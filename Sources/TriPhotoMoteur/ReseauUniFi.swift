import CryptoKit
import Foundation

/// Réglages du régulateur réseau : la console UniFi (UDM Pro) et le débit montant de la ligne internet.
public struct ConfigUniFi: Sendable {
    /// Adresse de la console (« 192.168.1.1 »).
    public var adresse: String
    /// Clé API créée dans UniFi Network (Paramètres › Plan de contrôle › Intégrations). Gardée dans le trousseau.
    public var cle: String
    /// Débit montant de la ligne internet du concours, en Mbit/s (4G, fibre…).
    public var montantMbit: Double
    /// La galerie se met en pause quand les AUTRES (stand, iPhone, visiteurs…) utilisent plus de ce pourcentage.
    public var seuil: Double
    /// Empreinte du certificat de la console (retenue à la 1re connexion, ensuite exigée).
    public var empreinte: String
    public var sauverEmpreinte: @Sendable (String) -> Void

    public init(adresse: String, cle: String, montantMbit: Double, seuil: Double = 0.7, empreinte: String,
                sauverEmpreinte: @escaping @Sendable (String) -> Void) {
        self.adresse = adresse
        self.cle = cle
        self.montantMbit = montantMbit
        self.seuil = seuil
        self.empreinte = empreinte
        self.sauverEmpreinte = sauverEmpreinte
    }
}

/// Ce que le régulateur voit de la ligne internet.
public struct EtatReseau: Sendable, Equatable {
    public var ok: Bool?
    public var message = ""
    public var montantMbit = 0.0          // envoi total sur internet en ce moment
    public var descendantMbit = 0.0
    public var autresMbit = 0.0           // sans la galerie
    public var sature = false
    public var le: Date?
    public init() {}
}

/// Lit le débit de la ligne internet sur la console UniFi (API « Integration » de UniFi Network : sites, appareils,
/// statistiques de la passerelle). Une requête toutes les 15 s au plus, seulement quand la galerie a du travail.
final class ReseauUniFi: NSObject, URLSessionDelegate, @unchecked Sendable {
    private var config: ConfigUniFi
    private let verrou = NSLock()
    private var site = ""
    private var passerelle = ""
    private var _etat = EtatReseau()
    private var derniere = Date.distantPast
    private var calmeDepuis: Date?
    private var certificatRefuse = false
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 8
        c.timeoutIntervalForResource = 15
        c.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    init(config: ConfigUniFi) { self.config = config }

    var etat: EtatReseau { verrou.lock(); defer { verrou.unlock() }; return _etat }

    /// La galerie doit-elle attendre ? `propreMbit` : ce que la galerie envoie elle-même en ce moment.
    /// Pause dès que les autres dépassent le seuil ; reprise quand ils sont repassés 15 points dessous depuis 30 s.
    func doitAttendre(propreMbit: Double) -> Bool {
        if Date().timeIntervalSince(derniere) >= 15 { mesurer(propreMbit: propreMbit) }
        verrou.lock(); defer { verrou.unlock() }
        return _etat.sature
    }

    private func mesurer(propreMbit: Double) {
        derniere = Date()
        do {
            if site.isEmpty { site = try premierSite() }
            if passerelle.isEmpty { passerelle = try trouverPasserelle() }
            let s = try json("/sites/\(site)/devices/\(passerelle)/statistics/latest")
            let uplink = s["uplink"] as? [String: Any] ?? [:]
            let tx = (uplink["txRateBps"] as? NSNumber)?.doubleValue ?? 0
            let rx = (uplink["rxRateBps"] as? NSNumber)?.doubleValue ?? 0
            let montant = tx / 1_000_000
            let autres = max(0, montant - propreMbit)
            let limite = config.montantMbit * config.seuil
            verrou.lock()
            var sature = _etat.sature
            if config.montantMbit > 0 {
                if autres > limite {
                    sature = true
                    calmeDepuis = nil
                } else if autres < config.montantMbit * max(0.05, config.seuil - 0.15) {
                    if calmeDepuis == nil { calmeDepuis = Date() }
                    if let c = calmeDepuis, Date().timeIntervalSince(c) >= 30 { sature = false }
                } else {
                    calmeDepuis = nil
                }
            }
            var e = EtatReseau()
            e.ok = true
            e.message = sature ? String(format: "Ligne internet chargée (%.1f Mbit/s par les autres) : galerie en pause.", autres)
                               : String(format: "Ligne internet : %.1f Mbit/s envoyés, %.1f reçus.", montant, rx / 1_000_000)
            e.montantMbit = montant
            e.descendantMbit = rx / 1_000_000
            e.autresMbit = autres
            e.sature = sature
            e.le = Date()
            _etat = e
            verrou.unlock()
        } catch {
            // Console injoignable : la galerie n'est pas bloquée pour autant (débit maximum des réglages).
            verrou.lock()
            _etat.ok = false
            _etat.sature = false
            _etat.message = "Console UniFi : \(error.localizedDescription)"
            site = certificatRefuse ? site : ""
            passerelle = ""
            verrou.unlock()
        }
    }

    private func premierSite() throws -> String {
        let r = try json("/sites")
        guard let l = r["data"] as? [[String: Any]], let id = l.first?["id"] as? String else {
            throw ReseauUniFi.erreur("aucun site trouvé")
        }
        return id
    }

    /// La passerelle (l'UDM Pro elle-même) : l'appareil qui a la fonction « gateway », sinon un modèle UDM / UXG.
    private func trouverPasserelle() throws -> String {
        let r = try json("/sites/\(site)/devices?limit=200")
        let l = r["data"] as? [[String: Any]] ?? []
        func est(_ d: [String: Any]) -> Bool {
            let f = (d["features"] as? [String] ?? []).map { $0.lowercased() }
            let m = ((d["model"] as? String ?? "") + " " + (d["name"] as? String ?? "")).uppercased()
            return f.contains("gateway") || m.contains("UDM") || m.contains("UXG") || m.contains("DREAM") || m.contains("UCG")
        }
        guard let d = l.first(where: est) ?? l.first, let id = d["id"] as? String else {
            throw ReseauUniFi.erreur("passerelle introuvable")
        }
        return id
    }

    private func json(_ chemin: String) throws -> [String: Any] {
        var h = config.adresse.trimmingCharacters(in: .whitespaces)
        for p in ["https://", "http://"] where h.lowercased().hasPrefix(p) { h = String(h.dropFirst(p.count)) }
        h = String(h.split(separator: "/").first ?? Substring(h))
        guard let url = URL(string: "https://\(h)/proxy/network/integration/v1\(chemin)") else { throw ReseauUniFi.erreur("adresse invalide") }
        var req = URLRequest(url: url)
        req.setValue(config.cle, forHTTPHeaderField: "X-API-KEY")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let fini = DispatchSemaphore(value: 0)
        final class Reponse: @unchecked Sendable { var data: Data?; var code = 0; var erreur: Error? }
        let rep = Reponse()
        session.dataTask(with: req) { d, r, e in
            rep.data = d
            rep.code = (r as? HTTPURLResponse)?.statusCode ?? 0
            rep.erreur = e
            fini.signal()
        }.resume()
        if fini.wait(timeout: .now() + 16) == .timedOut { throw ReseauUniFi.erreur("pas de réponse") }
        if certificatRefuse { throw ReseauUniFi.erreur("le certificat de la console a changé, connexion refusée") }
        if let e = rep.erreur { throw ReseauUniFi.erreur(e.localizedDescription) }
        if rep.code == 401 || rep.code == 403 { throw ReseauUniFi.erreur("clé API refusée") }
        guard rep.code == 200, let d = rep.data, let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            throw ReseauUniFi.erreur("réponse inattendue (\(rep.code))")
        }
        return o
    }

    private static func erreur(_ t: String) -> NSError {
        NSError(domain: "UniFi", code: 1, userInfo: [NSLocalizedDescriptionKey: t])
    }

    /// Certificat auto-signé de la console : accepté la 1re fois (empreinte retenue), ensuite exigé.
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let confiance = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let chaine = SecTrustCopyCertificateChain(confiance) as? [SecCertificate], let cert = chaine.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let emp = SHA256.hash(data: SecCertificateCopyData(cert) as Data).map { String(format: "%02x", $0) }.joined()
        verrou.lock()
        let attendue = config.empreinte
        if attendue.isEmpty { config.empreinte = emp }
        verrou.unlock()
        if attendue.isEmpty {
            config.sauverEmpreinte(emp)
        } else if attendue != emp {
            verrou.lock(); certificatRefuse = true; verrou.unlock()
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        verrou.lock(); certificatRefuse = false; verrou.unlock()
        completionHandler(.useCredential, URLCredential(trust: confiance))
    }

    /// Essai depuis les réglages : la console répond-elle, et que voit-elle sur la ligne ?
    func tester() -> (Bool, String) {
        derniere = .distantPast
        mesurer(propreMbit: 0)
        let e = etat
        return (e.ok == true, e.ok == true ? String(format: "Console UniFi jointe : %.1f Mbit/s envoyés, %.1f reçus en ce moment.",
                                                    e.montantMbit, e.descendantMbit) : e.message)
    }
}
