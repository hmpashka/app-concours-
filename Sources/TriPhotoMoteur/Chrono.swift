import Foundation
import TriPhotoCommun

/// Réglages du lien avec le chrono, figés au démarrage de la journée.
public struct ConfigChrono: Sendable {
    /// Adresse de HM Timing (« http://192.168.1.20:8080 »). Vide : pas de chrono (les photos partent avec leur code).
    public var adresse: String
    public var codeRegie: String
    public var codeTechnicien: String
    /// Fin de tour : la piste reste au couple tant de secondes après son arrivée.
    public var apresArrivee: Double
    /// Latence tolérée au changement de couple (secondes).
    public var latence: Double
    /// Attente maximale d'une information du chrono avant de laisser partir la photo avec son code (minutes).
    public var attenteMaxMinutes: Double
    /// Pour le mode entraînement : passages lus dans un fichier JSON (même forme que la réponse de HM Timing).
    public var fichierPassages: URL?

    public init(adresse: String, codeRegie: String, codeTechnicien: String, apresArrivee: Double = 15,
                latence: Double = 5, attenteMaxMinutes: Double = 3, fichierPassages: URL? = nil) {
        self.adresse = adresse
        self.codeRegie = codeRegie
        self.codeTechnicien = codeTechnicien
        self.apresArrivee = apresArrivee
        self.latence = latence
        self.attenteMaxMinutes = attenteMaxMinutes
        self.fichierPassages = fichierPassages
    }
}

/// Lien avec HM Timing : lui demande les passages gardés (`/api/flux/passages`), quelques Ko toutes les 8 s au plus,
/// et seulement quand des photos en ont besoin. Calcule aussi l'écart entre l'horloge de HM Timing et celle du Mac.
final class Chrono {
    let config: ConfigChrono
    private let session: URLSession
    private let verrou = NSLock()
    private var _passages: [Passage] = []
    private var _ecart: Double = 0          // horloge du chrono − horloge du Mac
    private var _ok: Bool?
    private var _erreur = ""
    private var _vu: Date?
    private var enCours = false
    private var dernierAppel = Date.distantPast

    init(config: ConfigChrono) {
        self.config = config
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 6
        c.timeoutIntervalForResource = 8
        c.waitsForConnectivity = false
        c.httpMaximumConnectionsPerHost = 1
        session = URLSession(configuration: c)
    }

    var passages: [Passage] { verrou.lock(); defer { verrou.unlock() }; return _passages }
    var ecart: Double { verrou.lock(); defer { verrou.unlock() }; return _ecart }
    /// nil : pas encore interrogé ; vrai : répond ; faux : ne répond pas.
    var ok: Bool? { verrou.lock(); defer { verrou.unlock() }; return _ok }
    var erreur: String { verrou.lock(); defer { verrou.unlock() }; return _erreur }
    var vu: Date? { verrou.lock(); defer { verrou.unlock() }; return _vu }

    /// Heure d'une photo (horloge de l'appareil) sur l'horloge du chrono.
    func heureChrono(_ prise: Date) -> Double { prise.timeIntervalSince1970 }

    /// Demande les passages si le dernier appel date de plus de 8 s. Ne bloque jamais.
    func actualiserSiBesoin(depuis: Date) {
        verrou.lock()
        guard !enCours, Date().timeIntervalSince(dernierAppel) >= 8 else { verrou.unlock(); return }
        enCours = true
        dernierAppel = Date()
        verrou.unlock()

        if let f = config.fichierPassages {
            let liste = Chrono.lire(fichier: f)
            terminer(passages: liste, ecart: 0, erreur: liste == nil ? "Fichier de passages illisible" : "")
            return
        }
        var base = config.adresse.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.hasPrefix("http") { base = "http://" + base }
        while base.hasSuffix("/") { base.removeLast() }
        guard var comp = URLComponents(string: base + "/api/flux/passages") else {
            terminer(passages: nil, ecart: 0, erreur: "Adresse de HM Timing invalide")
            return
        }
        comp.queryItems = [URLQueryItem(name: "limite", value: "1000"),
                           URLQueryItem(name: "depuis", value: String(Int(depuis.timeIntervalSince1970)))]
        guard let url = comp.url else {
            terminer(passages: nil, ecart: 0, erreur: "Adresse de HM Timing invalide")
            return
        }
        var req = URLRequest(url: url)
        req.setValue(config.codeRegie, forHTTPHeaderField: "X-Code")
        req.setValue(config.codeTechnicien, forHTTPHeaderField: "X-Tech")
        let t0 = Date().timeIntervalSince1970
        session.dataTask(with: req) { [weak self] data, rep, err in
            guard let self else { return }
            let t1 = Date().timeIntervalSince1970
            if let err {
                self.terminer(passages: nil, ecart: 0, erreur: "HM Timing ne répond pas : \(err.localizedDescription)")
                return
            }
            let statut = (rep as? HTTPURLResponse)?.statusCode ?? 0
            if statut == 403 {
                self.terminer(passages: nil, ecart: 0, erreur: "HM Timing refuse les codes de régie ou technicien")
                return
            }
            guard statut == 200, let data,
                  let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.terminer(passages: nil, ecart: 0, erreur: "HM Timing : réponse inattendue (\(statut))")
                return
            }
            let liste = (d["passages"] as? [[String: Any]] ?? []).compactMap(Passage.depuisHM)
            let ecart = (d["maintenant"] as? NSNumber).map { $0.doubleValue - (t0 + t1) / 2 } ?? 0
            self.terminer(passages: liste, ecart: ecart, erreur: "")
        }.resume()
    }

    private func terminer(passages: [Passage]?, ecart: Double, erreur: String) {
        verrou.lock()
        defer { verrou.unlock() }
        enCours = false
        if let passages {
            _passages = passages
            _ecart = ecart
            _ok = true
            _erreur = ""
            _vu = Date()
        } else {
            _ok = false
            _erreur = erreur
        }
    }

    /// Passages d'un fichier JSON : soit la réponse de HM Timing (`{"passages": [...]}`), soit une liste.
    static func lire(fichier: URL) -> [Passage]? {
        guard let data = try? Data(contentsOf: fichier), let j = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let liste = (j as? [String: Any])?["passages"] as? [[String: Any]] ?? (j as? [[String: Any]]) ?? []
        return liste.compactMap(Passage.depuisHM)
    }
}
