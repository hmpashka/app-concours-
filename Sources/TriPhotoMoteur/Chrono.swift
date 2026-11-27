import Foundation
import TriPhotoCommun

/// Un chrono du concours : un ordinateur HM Timing, ou une page d'incrustation Horse & Comp lue par l'app.
/// Un HM Timing peut chronométrer plusieurs pistes (ses « sources ») ; une page Horse & Comp, une seule piste.
public struct ConfigLienChrono: Sendable, Equatable {
    /// Identifiant stable (celui des réglages) : la capture Horse & Comp envoie ses passages avec.
    public var id: String
    /// Nom donné par HUGO (« HM Timing remorque »).
    public var nom: String
    /// Adresse de HM Timing (« http://192.168.1.20:8080 »).
    public var adresse: String
    public var codeRegie: String
    public var codeTechnicien: String
    /// Mode entraînement : passages lus dans un fichier JSON (même forme que la réponse de HM Timing).
    public var fichierPassages: URL?
    /// Vrai : les passages viennent de la capture Horse & Comp (envoyés par l'app), pas de HM Timing.
    public var externe: Bool
    /// Vrai : le nom des pistes est précédé du nom du chrono (plusieurs HM Timing : deux « Piste 1 » ne se mélangent pas).
    public var prefixer: Bool
    /// Nom de piste imposé (Horse & Comp : une seule piste, nommée comme le chrono).
    public var sourceFixe: String?

    public init(id: String, nom: String, adresse: String = "", codeRegie: String = "", codeTechnicien: String = "",
                fichierPassages: URL? = nil, externe: Bool = false, prefixer: Bool = false, sourceFixe: String? = nil) {
        self.id = id
        self.nom = nom
        self.adresse = adresse
        self.codeRegie = codeRegie
        self.codeTechnicien = codeTechnicien
        self.fichierPassages = fichierPassages
        self.externe = externe
        self.prefixer = prefixer
        self.sourceFixe = sourceFixe
    }

    /// Nom de piste tel que l'app le range (« HM Timing remorque · Piste 1 », ou « Piste 1 » s'il n'y a qu'un HM Timing).
    public func cle(_ source: String) -> String {
        if let s = sourceFixe, !s.isEmpty { return s }
        return prefixer ? ConfigLienChrono.cle(chrono: nom, source: source) : source
    }

    public static let separateur = " · "
    public static func cle(chrono: String, source: String) -> String { chrono + separateur + source }

    /// La partie « piste du chrono » d'une clé (« HM Timing remorque · Piste 1 » → « Piste 1 »).
    public static func brut(_ cle: String) -> String {
        guard let r = cle.range(of: separateur, options: .backwards) else { return cle }
        return String(cle[r.upperBound...])
    }
}

/// Réglages du lien avec les chronos, figés au démarrage de la journée.
public struct ConfigChrono: Sendable {
    /// Les chronos du concours (un ou plusieurs). Vide : pas de chrono.
    public var liens: [ConfigLienChrono]
    /// Fin de tour : la piste reste au couple tant de secondes après son arrivée.
    public var apresArrivee: Double
    /// Latence tolérée au changement de couple (secondes).
    public var latence: Double
    /// Attente maximale d'une information du chrono avant de laisser partir la photo avec son code (minutes).
    public var attenteMaxMinutes: Double

    public init(liens: [ConfigLienChrono], apresArrivee: Double = 15, latence: Double = 5, attenteMaxMinutes: Double = 3) {
        self.liens = liens
        self.apresArrivee = apresArrivee
        self.latence = latence
        self.attenteMaxMinutes = attenteMaxMinutes
    }

    /// Un seul chrono (outil d'essai, anciens réglages).
    public init(adresse: String, codeRegie: String, codeTechnicien: String, apresArrivee: Double = 15,
                latence: Double = 5, attenteMaxMinutes: Double = 3, fichierPassages: URL? = nil, externe: Bool = false) {
        self.init(liens: [ConfigLienChrono(id: "chrono", nom: externe ? "Horse & Comp" : "HM Timing", adresse: adresse,
                                           codeRegie: codeRegie, codeTechnicien: codeTechnicien,
                                           fichierPassages: fichierPassages, externe: externe)],
                  apresArrivee: apresArrivee, latence: latence, attenteMaxMinutes: attenteMaxMinutes)
    }
}

/// L'état d'un chrono, pour l'accueil (un voyant par chrono).
public struct EtatLienChrono: Sendable, Identifiable {
    public var id: String
    public var nom: String
    public var externe: Bool
    /// nil : pas encore joint ; vrai : répond ; faux : ne répond pas.
    public var ok: Bool?
    public var erreur: String
    public var vu: Date?
    public var passages: Int
    /// Pistes vues dans ce chrono, telles que le chrono les nomme (sans le nom du chrono).
    public var sources: [String]
}

/// Lien avec UN chrono : HM Timing (`/api/flux/passages`, quelques Ko toutes les 8 s au plus, seulement quand des
/// photos en ont besoin) ou capture Horse & Comp (passages envoyés par l'app). Calcule l'écart entre l'horloge de
/// ce HM Timing et celle du Mac.
final class LienChrono {
    let config: ConfigLienChrono
    private let session: URLSession
    private let verrou = NSLock()
    private var _passages: [Passage] = []   // heure de CE chrono, pistes déjà nommées par `config.cle`
    private var _sources: [String] = []
    private var _ecart: Double = 0          // horloge de ce chrono − horloge du Mac
    private var _ok: Bool?
    private var _erreur = ""
    private var _vu: Date?
    private var enCours = false
    private var dernierAppel = Date.distantPast
    /// Prévient le chrono commun qu'il faut refaire la liste réunie.
    var change: (() -> Void)?

    init(config: ConfigLienChrono) {
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
    var ok: Bool? { verrou.lock(); defer { verrou.unlock() }; return _ok }
    var erreur: String { verrou.lock(); defer { verrou.unlock() }; return _erreur }
    var vu: Date? { verrou.lock(); defer { verrou.unlock() }; return _vu }

    var etat: EtatLienChrono {
        verrou.lock(); defer { verrou.unlock() }
        return EtatLienChrono(id: config.id, nom: config.nom, externe: config.externe, ok: _ok, erreur: _erreur,
                              vu: _vu, passages: _passages.count, sources: _sources)
    }

    /// Cette piste (clé de l'app) vient-elle de ce chrono ?
    func donne(_ cle: String) -> Bool {
        if let s = config.sourceFixe, !s.isEmpty { return s == cle }
        verrou.lock(); defer { verrou.unlock() }
        return _sources.contains { config.cle($0) == cle }
    }

    /// Demande les passages si le dernier appel date de plus de 8 s. Ne bloque jamais.
    func actualiserSiBesoin(depuis: Date) {
        if config.externe { return }        // la capture Horse & Comp envoie ses passages elle-même
        verrou.lock()
        guard !enCours, Date().timeIntervalSince(dernierAppel) >= 8 else { verrou.unlock(); return }
        enCours = true
        dernierAppel = Date()
        verrou.unlock()

        if let f = config.fichierPassages {
            let liste = Chrono.lire(fichier: f)
            terminer(passages: liste, ecart: 0, erreur: liste == nil ? "fichier de passages illisible" : "")
            return
        }
        var base = config.adresse.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.hasPrefix("http") { base = "http://" + base }
        while base.hasSuffix("/") { base.removeLast() }
        guard !config.adresse.trimmingCharacters(in: .whitespaces).isEmpty,
              var comp = URLComponents(string: base + "/api/flux/passages") else {
            terminer(passages: nil, ecart: 0, erreur: "adresse invalide")
            return
        }
        comp.queryItems = [URLQueryItem(name: "limite", value: "1000"),
                           URLQueryItem(name: "depuis", value: String(Int(depuis.timeIntervalSince1970)))]
        guard let url = comp.url else {
            terminer(passages: nil, ecart: 0, erreur: "adresse invalide")
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
                self.terminer(passages: nil, ecart: 0, erreur: "ne répond pas : \(err.localizedDescription)")
                return
            }
            let statut = (rep as? HTTPURLResponse)?.statusCode ?? 0
            if statut == 403 {
                self.terminer(passages: nil, ecart: 0, erreur: "refuse les codes de régie ou technicien")
                return
            }
            guard statut == 200, let data,
                  let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.terminer(passages: nil, ecart: 0, erreur: "réponse inattendue (\(statut))")
                return
            }
            let liste = (d["passages"] as? [[String: Any]] ?? []).compactMap(Passage.depuisHM)
            let ecart = (d["maintenant"] as? NSNumber).map { $0.doubleValue - (t0 + t1) / 2 } ?? 0
            self.terminer(passages: liste, ecart: ecart, erreur: "")
        }.resume()
    }

    /// Passages venus de la capture Horse & Comp (heure du Mac : pas d'écart d'horloge).
    func recevoir(_ passages: [Passage], erreur: String) {
        if erreur.isEmpty || !passages.isEmpty {
            terminer(passages: passages, ecart: 0, erreur: "")
            if !erreur.isEmpty { verrou.lock(); _erreur = erreur; verrou.unlock() }
        } else {
            terminer(passages: nil, ecart: 0, erreur: erreur)
        }
    }

    private func terminer(passages: [Passage]?, ecart: Double, erreur: String) {
        verrou.lock()
        enCours = false
        if let passages {
            var srcs: [String] = []
            _passages = passages.map { p in
                if !srcs.contains(p.source) { srcs.append(p.source) }
                var q = p
                q.source = config.cle(p.source)
                return q
            }
            if let s = config.sourceFixe, !s.isEmpty { srcs = [s] }
            _sources = srcs.sorted()
            _ecart = ecart
            _ok = true
            _erreur = ""
            _vu = Date()
        } else {
            _ok = false
            _erreur = erreur
        }
        verrou.unlock()
        change?()
    }
}

/// Les chronos du concours, réunis : un ou plusieurs HM Timing, une ou plusieurs captures Horse & Comp.
/// Tous les passages sont remis sur UNE horloge, celle du premier chrono qui répond (« heure du chrono » : c'est
/// elle que montre le QR de synchro des boîtiers). Chaque piste garde son nom, les pistes ne se mélangent pas.
final class Chrono {
    let config: ConfigChrono
    let liens: [LienChrono]
    private let verrou = NSLock()
    private var _reunis: [Passage]?
    private var _ecartsBoitiers: [String: Double] = [:]

    init(config: ConfigChrono) {
        self.config = config
        liens = config.liens.map { LienChrono(config: $0) }
        for l in liens { l.change = { [weak self] in self?.invalider() } }
    }

    private func invalider() { verrou.lock(); _reunis = nil; verrou.unlock() }

    /// Le chrono de référence pour l'heure : le premier HM Timing qui a répondu (sinon le premier chrono).
    private var reference: LienChrono? {
        liens.first { !$0.config.externe && $0.ok == true } ?? liens.first { $0.ok == true } ?? liens.first
    }

    /// Horloge de référence − horloge du Mac.
    var ecart: Double { reference?.ecart ?? 0 }

    /// Tous les passages, sur l'horloge de référence.
    var passages: [Passage] {
        verrou.lock()
        if let r = _reunis { verrou.unlock(); return r }
        verrou.unlock()
        let ref = ecart
        var tous: [Passage] = []
        for l in liens {
            let decale = ref - l.ecart          // heure de ce chrono → heure de référence
            if abs(decale) < 0.001 {
                tous += l.passages
            } else {
                tous += l.passages.map { p in
                    var q = p
                    q.entree = p.entree.map { $0 + decale }
                    q.depart = p.depart + decale
                    q.fin = p.fin.map { $0 + decale }
                    q.remplaceA = p.remplaceA.map { $0 + decale }
                    return q
                }
            }
        }
        if liens.count > 1 { tous.sort { $0.debut < $1.debut } }
        verrou.lock(); _reunis = tous; verrou.unlock()
        return tous
    }

    /// nil : aucun chrono encore joint ; vrai : au moins un répond ; faux : aucun ne répond.
    var ok: Bool? {
        let oks = liens.map(\.ok)
        if oks.contains(true) { return true }
        if oks.contains(where: { $0 == nil }) { return nil }
        return liens.isEmpty ? nil : false
    }

    /// L'état du chrono qui donne cette piste (clé de l'app). Piste inconnue : l'état de l'ensemble.
    func okPour(piste: String?) -> Bool? {
        if let piste, let l = liens.first(where: { $0.donne(piste) }) { return l.ok }
        if liens.count == 1 { return liens[0].ok }
        return ok
    }

    var erreur: String {
        let e = liens.filter { !$0.erreur.isEmpty }.map { liens.count > 1 ? "\($0.config.nom) : \($0.erreur)" : $0.erreur }
        if liens.count == 1, let l = liens.first, !l.erreur.isEmpty, !l.config.externe { return "HM Timing \(l.erreur)" }
        return e.joined(separator: " · ")
    }

    /// Le plus ancien « vu » : un chrono pas vu depuis longtemps fait redemander les passages.
    var vu: Date? {
        let vus = liens.map(\.vu)
        if vus.contains(where: { $0 == nil }) { return nil }
        return vus.compactMap { $0 }.min()
    }

    var etats: [EtatLienChrono] { liens.map(\.etat) }

    /// Écarts d'heure des boîtiers synchronisés (photo du QR) : heure du boîtier − heure du chrono.
    func regler(ecarts: [String: Double]) { verrou.lock(); _ecartsBoitiers = ecarts; verrou.unlock() }

    /// Heure d'une photo (horloge de l'appareil) sur l'horloge du chrono, corrigée de l'écart du boîtier.
    func heureChrono(_ prise: Date, boitier: String = "") -> Double {
        verrou.lock(); defer { verrou.unlock() }
        return prise.timeIntervalSince1970 - (_ecartsBoitiers[boitier] ?? 0)
    }

    /// Demande les passages à chaque HM Timing (chacun au plus toutes les 8 s). Ne bloque jamais.
    func actualiserSiBesoin(depuis: Date) {
        for l in liens { l.actualiserSiBesoin(depuis: depuis) }
    }

    /// Passages d'une capture Horse & Comp.
    func recevoir(lien: String, _ passages: [Passage], erreur: String) {
        guard let l = liens.first(where: { $0.config.id == lien && $0.config.externe })
                ?? (liens.filter(\.config.externe).count == 1 && lien.isEmpty ? liens.first(where: \.config.externe) : nil)
        else { return }
        l.recevoir(passages, erreur: erreur)
    }

    /// Passages d'un fichier JSON : soit la réponse de HM Timing (`{"passages": [...]}`), soit une liste.
    static func lire(fichier: URL) -> [Passage]? {
        guard let data = try? Data(contentsOf: fichier), let j = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let liste = (j as? [String: Any])?["passages"] as? [[String: Any]] ?? (j as? [[String: Any]]) ?? []
        return liste.compactMap(Passage.depuisHM)
    }
}

/// Bouton « Tester » des réglages : interroge une fois un HM Timing, sans démarrer le tri.
public enum TestChrono {
    /// Rend un texte court : « répond · pistes vues : Piste 1, Piste 2 » ou la raison de l'échec.
    public static func tester(_ config: ConfigLienChrono, fin: @escaping @Sendable (Bool, String) -> Void) {
        var c = config
        c.prefixer = false
        let lien = LienChrono(config: c)
        lien.change = { [lien] in
            let e = lien.etat
            if e.ok == true {
                fin(true, "répond · " + (e.sources.isEmpty ? "aucun passage pour l'instant" : "pistes vues : " + e.sources.joined(separator: ", ")))
            } else {
                fin(false, e.erreur)
            }
            lien.change = nil
        }
        lien.actualiserSiBesoin(depuis: Date().addingTimeInterval(-12 * 3600))
    }
}
