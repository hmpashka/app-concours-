import CryptoKit
import Foundation

/// Un UDM Pro (console UniFi) déjà connu de ce Mac : celui d'une remorque. Reconnu par l'adresse MAC du routeur
/// du réseau où le Mac est branché (elle ne change jamais, même si deux UDM ont la même adresse 192.168.1.1).
/// La clé API est dans le trousseau du Mac (« unifi-<adresse MAC> »), jamais ici.
public struct UDMConnu: Codable, Sendable, Equatable, Identifiable {
    public var mac: String
    public var nom: String
    /// Débit montant de la ligne internet de cette remorque, en Mbit/s (4G, fibre…).
    public var montantMbit: Int
    /// Empreinte du certificat de cette console (retenue à la 1re connexion, ensuite exigée).
    public var empreinte: String
    /// Dernière adresse où elle a été vue (« 192.168.1.1 »), pour information.
    public var derniereAdresse: String
    public var id: String { mac }

    public init(mac: String, nom: String, montantMbit: Int, empreinte: String = "", derniereAdresse: String = "") {
        self.mac = mac
        self.nom = nom
        self.montantMbit = montantMbit
        self.empreinte = empreinte
        self.derniereAdresse = derniereAdresse
    }
}

/// Le routeur du réseau où le Mac est branché en ce moment.
public struct RouteurVu: Sendable, Equatable {
    public var adresse: String          // « 192.168.1.1 »
    /// Identifiant de la console : son adresse MAC (« 74:ac:b9:12:4f:0a »), ou, si macOS cache la table du réseau
    /// à l'app, l'empreinte de son certificat (« certificat 3fa94c… »), propre à chaque UDM. Vide : routeur muet
    /// (accès au réseau local pas autorisé à Groom Pix, ou pas une console).
    public var mac: String
    public init(adresse: String, mac: String) {
        self.adresse = adresse
        self.mac = mac
    }
}

/// Trouve le routeur du réseau actuel (passerelle par défaut, puis son adresse MAC), sans rien régler.
public enum DetectionUDM {
    /// nil : pas de réseau, ou routeur introuvable. Quelques millisecondes (outils du système, sans réseau).
    public static func routeurActuel() -> RouteurVu? {
        guard let ip = passerelle() else { return nil }
        if let mac = macDe(ip) { return RouteurVu(adresse: ip, mac: mac) }
        // Pas encore dans la table du Mac (aucun échange récent avec le routeur) : un ping, puis on relit.
        _ = lancer("/sbin/ping", ["-c", "1", "-t", "1", "-n", ip])
        if let mac = macDe(ip) { return RouteurVu(adresse: ip, mac: mac) }
        // macOS cache la table à l'app (signature de développement) : le certificat de la console l'identifie aussi.
        if let e = empreinteCertificat(ip) { return RouteurVu(adresse: ip, mac: "certificat " + e.prefix(16)) }
        return RouteurVu(adresse: ip, mac: "")
    }

    /// Empreinte SHA-256 du certificat HTTPS du routeur (aucune donnée envoyée). nil : pas de réponse.
    public static func empreinteCertificat(_ adresse: String) -> String? {
        guard let url = URL(string: "https://\(adresse)/") else { return nil }
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 4
        c.timeoutIntervalForResource = 6
        let d = SansVerification()
        let s = URLSession(configuration: c, delegate: d, delegateQueue: nil)
        let fini = DispatchSemaphore(value: 0)
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        s.dataTask(with: req) { _, _, _ in fini.signal() }.resume()
        _ = fini.wait(timeout: .now() + 7)
        s.invalidateAndCancel()
        return d.empreinte
    }

    /// « gateway: 192.168.1.1 » dans `route -n get default` (IPv4 seulement). Avec un VPN allumé, la route par défaut
    /// passe par le tunnel (sans passerelle) : on prend alors la route par défaut du câble ou du wifi (`netstat -rn`).
    static func passerelle() -> String? {
        if let t = lancer("/sbin/route", ["-n", "get", "default"]) {
            for l in t.split(separator: "\n") {
                let l = l.trimmingCharacters(in: .whitespaces)
                guard l.hasPrefix("gateway:") else { continue }
                let ip = l.dropFirst("gateway:".count).trimmingCharacters(in: .whitespaces)
                if estIPv4(ip) { return ip }
            }
        }
        return lancer("/usr/sbin/netstat", ["-rn", "-f", "inet"]).flatMap(passerelleDansTable)
    }

    /// Première ligne « default  192.168.1.254  UGScg  en0 » dont la passerelle est une adresse IPv4
    /// (les lignes du VPN « default  link#40  UCSIg  utun12 » sont sautées).
    static func passerelleDansTable(_ table: String) -> String? {
        for l in table.split(separator: "\n") {
            let c = l.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard c.count >= 2, c[0] == "default", estIPv4(c[1]) else { continue }
            if let i = c.last, i.hasPrefix("utun") || i.hasPrefix("ipsec") || i.hasPrefix("ppp") { continue }
            return c[1]
        }
        return nil
    }

    static func estIPv4(_ ip: String) -> Bool {
        let p = ip.split(separator: ".", omittingEmptySubsequences: false)
        return p.count == 4 && p.allSatisfy { UInt8($0) != nil }
    }

    /// « ? (192.168.1.1) at 74:ac:b9:12:4f:a on en0 ifscope [ethernet] » dans `arp -n 192.168.1.1`.
    static func macDe(_ ip: String) -> String? {
        guard let t = lancer("/usr/sbin/arp", ["-n", ip]),
              let r = t.range(of: " at ") else { return nil }
        let brut = t[r.upperBound...].split(separator: " ").first.map(String.init) ?? ""
        return normaliser(brut)
    }

    /// « 74:ac:b9:2:4f:a » → « 74:ac:b9:02:4f:0a » ; nil si ce n'est pas une adresse MAC.
    public static func normaliser(_ brut: String) -> String? {
        let p = brut.lowercased().split(separator: ":", omittingEmptySubsequences: false)
        guard p.count == 6, p.allSatisfy({ !$0.isEmpty && $0.count <= 2 && UInt8($0, radix: 16) != nil }) else { return nil }
        let mac = p.map { $0.count == 1 ? "0" + $0 : String($0) }.joined(separator: ":")
        return mac == "ff:ff:ff:ff:ff:ff" || mac == "00:00:00:00:00:00" ? nil : mac
    }

    private static func lancer(_ outil: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: outil)
        p.arguments = args
        let sortie = Pipe()
        p.standardOutput = sortie
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let d = sortie.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(decoding: d, as: UTF8.self) : nil
    }

    /// Ce routeur est-il une console UniFi ? Lit seulement la page d'accueil (« UniFi OS »), sans clé ni mot de passe,
    /// pour ne pas proposer d'ajouter la box du bureau ou d'un hôtel. nil : pas de réponse (réseau pas prêt,
    /// accès au réseau local pas encore autorisé…), à réessayer.
    public static func estUniFi(_ adresse: String, fini: @escaping @Sendable (Bool?) -> Void) {
        guard let url = URL(string: "https://\(adresse)/") else { fini(false); return }
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 5
        c.timeoutIntervalForResource = 8
        let s = URLSession(configuration: c, delegate: SansVerification(), delegateQueue: nil)
        s.dataTask(with: url) { d, r, e in
            if e != nil || r == nil { fini(nil); s.finishTasksAndInvalidate(); return }
            let corps = String(decoding: (d ?? Data()).prefix(200_000), as: UTF8.self).lowercased()
            let entetes = ((r as? HTTPURLResponse)?.allHeaderFields ?? [:]).map { "\($0.key) \($0.value)" }
                .joined(separator: " ").lowercased()
            fini(corps.contains("unifi") || entetes.contains("unifi"))
            s.finishTasksAndInvalidate()
        }.resume()
    }

    /// Certificat auto-signé de la console : accepté pour ce seul coup d'œil (rien de secret n'est envoyé).
    private final class SansVerification: NSObject, URLSessionDelegate, @unchecked Sendable {
        private let verrou = NSLock()
        private var _empreinte: String?
        var empreinte: String? { verrou.lock(); defer { verrou.unlock() }; return _empreinte }
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if let t = challenge.protectionSpace.serverTrust {
                if let chaine = SecTrustCopyCertificateChain(t) as? [SecCertificate], let cert = chaine.first {
                    let e = SHA256.hash(data: SecCertificateCopyData(cert) as Data).map { String(format: "%02x", $0) }.joined()
                    verrou.lock(); _empreinte = e; verrou.unlock()
                }
                completionHandler(.useCredential, URLCredential(trust: t))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }
}

/// Réglages du régulateur réseau : les UDM connus de ce Mac, leurs clés, et le seuil de pause.
public struct ConfigUniFi: Sendable {
    public var udms: [UDMConnu]
    /// Clé API de chaque UDM (adresse MAC → clé), lue dans le trousseau par l'app.
    public var cles: [String: String]
    /// La galerie se met en pause quand les AUTRES (stand, iPhone, visiteurs…) utilisent plus de ce pourcentage.
    public var seuil: Double
    /// Empreinte du certificat retenue à la 1re connexion d'un UDM (adresse MAC, empreinte).
    public var sauverEmpreinte: @Sendable (String, String) -> Void

    public init(udms: [UDMConnu], cles: [String: String], seuil: Double = 0.7,
                sauverEmpreinte: @escaping @Sendable (String, String) -> Void) {
        self.udms = udms
        self.cles = cles
        self.seuil = seuil
        self.sauverEmpreinte = sauverEmpreinte
    }
}

/// La console à interroger : l'UDM connu du réseau actuel, ou celui qu'on essaie depuis les réglages.
public struct CibleUniFi: Sendable {
    public var mac: String
    public var nom: String
    public var adresse: String
    public var cle: String
    public var montantMbit: Double
    public var empreinte: String
    public init(mac: String, nom: String, adresse: String, cle: String, montantMbit: Double, empreinte: String) {
        self.mac = mac
        self.nom = nom
        self.adresse = adresse
        self.cle = cle
        self.montantMbit = montantMbit
        self.empreinte = empreinte
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
    /// Nom de l'UDM du réseau actuel (« Remorque A »), vide hors réseau connu.
    public var nomUDM = ""
    public init() {}
}

/// Lit le débit de la ligne internet sur la console UniFi (API « Integration » de UniFi Network : sites, appareils,
/// statistiques de la passerelle). Une requête toutes les 15 s au plus, seulement quand la galerie a du travail.
final class ReseauUniFi: NSObject, URLSessionDelegate, @unchecked Sendable {
    private var config: ConfigUniFi
    /// Pour l'essai depuis les réglages : cette console-là, sans chercher le routeur.
    private let forcee: CibleUniFi?
    private let verrou = NSLock()
    private var cible: CibleUniFi?
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

    init(config: ConfigUniFi, forcee: CibleUniFi? = nil) {
        self.config = config
        self.forcee = forcee
    }

    var etat: EtatReseau { verrou.lock(); defer { verrou.unlock() }; return _etat }

    /// Empreinte retenue pendant l'essai (pour enregistrer un nouvel UDM avec elle).
    var empreinteVue: String { verrou.lock(); defer { verrou.unlock() }; return cible?.empreinte ?? "" }

    /// La galerie doit-elle attendre ? `propreMbit` : ce que la galerie envoie elle-même en ce moment.
    /// Pause dès que les autres dépassent le seuil ; reprise quand ils sont repassés 15 points dessous depuis 30 s.
    func doitAttendre(propreMbit: Double) -> Bool {
        if Date().timeIntervalSince(derniere) >= 15 { mesurer(propreMbit: propreMbit) }
        verrou.lock(); defer { verrou.unlock() }
        return _etat.sature
    }

    /// L'UDM connu du réseau où le Mac est branché (nil : bureau, autre wifi, UDM pas encore ajouté).
    private func cibleActuelle() -> CibleUniFi? {
        if let forcee { return forcee }
        guard let r = DetectionUDM.routeurActuel(), !r.mac.isEmpty,
              let u = config.udms.first(where: { $0.mac == r.mac }),
              let cle = config.cles[u.mac], !cle.isEmpty else { return nil }
        return CibleUniFi(mac: u.mac, nom: u.nom, adresse: r.adresse, cle: cle, montantMbit: Double(u.montantMbit),
                          empreinte: u.empreinte)
    }

    private func mesurer(propreMbit: Double) {
        derniere = Date()
        guard let nouvelle = cibleActuelle() else {
            // Pas d'UDM connu ici : régulateur en pause, la galerie envoie normalement (débit maximum des réglages).
            verrou.lock()
            cible = nil
            site = ""
            passerelle = ""
            certificatRefuse = false
            calmeDepuis = nil
            var e = EtatReseau()
            e.message = "Aucun UDM connu sur ce réseau : régulateur en pause."
            _etat = e
            verrou.unlock()
            return
        }
        verrou.lock()
        if cible?.mac != nouvelle.mac {
            // Autre remorque (ou 1re mesure) : on repart de zéro avec la console de ce réseau.
            site = ""
            passerelle = ""
            certificatRefuse = false
            calmeDepuis = nil
            _etat = EtatReseau()
            cible = nouvelle
        } else {
            let emp = cible?.empreinte ?? ""
            cible = nouvelle
            if nouvelle.empreinte.isEmpty { cible?.empreinte = emp }
            cible?.adresse = nouvelle.adresse
        }
        let c = cible ?? nouvelle
        verrou.unlock()
        do {
            if site.isEmpty { site = try premierSite() }
            if passerelle.isEmpty { passerelle = try trouverPasserelle() }
            let s = try json("/sites/\(site)/devices/\(passerelle)/statistics/latest")
            let uplink = s["uplink"] as? [String: Any] ?? [:]
            let tx = (uplink["txRateBps"] as? NSNumber)?.doubleValue ?? 0
            let rx = (uplink["rxRateBps"] as? NSNumber)?.doubleValue ?? 0
            let montant = tx / 1_000_000
            let autres = max(0, montant - propreMbit)
            let limite = c.montantMbit * config.seuil
            verrou.lock()
            var sature = _etat.sature
            if c.montantMbit > 0 {
                if autres > limite {
                    sature = true
                    calmeDepuis = nil
                } else if autres < c.montantMbit * max(0.05, config.seuil - 0.15) {
                    if calmeDepuis == nil { calmeDepuis = Date() }
                    if let d = calmeDepuis, Date().timeIntervalSince(d) >= 30 { sature = false }
                } else {
                    calmeDepuis = nil
                }
            }
            var e = EtatReseau()
            e.ok = true
            e.nomUDM = c.nom
            e.message = sature ? String(format: "%@ : ligne internet chargée (%.1f Mbit/s par les autres), galerie en pause.", c.nom, autres)
                               : String(format: "%@ : %.1f Mbit/s envoyés, %.1f reçus.", c.nom, montant, rx / 1_000_000)
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
            _etat.nomUDM = c.nom
            _etat.message = "\(c.nom) : \(error.localizedDescription)"
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
        verrou.lock()
        let c = cible
        verrou.unlock()
        guard let c else { throw ReseauUniFi.erreur("aucun UDM connu sur ce réseau") }
        var h = c.adresse.trimmingCharacters(in: .whitespaces)
        for p in ["https://", "http://"] where h.lowercased().hasPrefix(p) { h = String(h.dropFirst(p.count)) }
        h = String(h.split(separator: "/").first ?? Substring(h))
        guard let url = URL(string: "https://\(h)/proxy/network/integration/v1\(chemin)") else { throw ReseauUniFi.erreur("adresse invalide") }
        var req = URLRequest(url: url)
        req.setValue(c.cle, forHTTPHeaderField: "X-API-KEY")
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

    /// Certificat auto-signé de la console : accepté la 1re fois (empreinte retenue pour CET UDM), ensuite exigé.
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
        let attendue = cible?.empreinte ?? ""
        let mac = cible?.mac ?? ""
        if attendue.isEmpty { cible?.empreinte = emp }
        if let i = config.udms.firstIndex(where: { $0.mac == mac }), attendue.isEmpty { config.udms[i].empreinte = emp }
        verrou.unlock()
        if attendue.isEmpty {
            if forcee == nil, !mac.isEmpty { config.sauverEmpreinte(mac, emp) }
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
        return (e.ok == true, e.ok == true ? String(format: "Console jointe : %.1f Mbit/s envoyés, %.1f reçus en ce moment.",
                                                    e.montantMbit, e.descendantMbit) : e.message)
    }
}
