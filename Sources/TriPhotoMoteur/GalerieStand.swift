import CryptoKit
import Foundation

/// Réglages du rafraîchissement de la galerie du stand (le serveur local : administration Symfony / Sonata).
public struct ConfigGalerie: Sendable {
    /// « https://190.160.40.5 ». Vide : pas de rafraîchissement.
    public var adresse: String
    public var identifiant: String
    public var motDePasse: String
    /// Rafraîchissement au plus tard X minutes après la première copie en attente (envoi continu).
    public var minutes: Double
    /// …ou plus tôt, dès que plus rien n'a été copié depuis tant de secondes (fin d'une rafale).
    public var calmeSecondes: Double
    /// Empreinte du certificat du serveur (retenue à la 1re connexion, ensuite exigée).
    public var empreinte: String
    public var sauverEmpreinte: @Sendable (String) -> Void

    public init(adresse: String, identifiant: String, motDePasse: String, minutes: Double = 2, calmeSecondes: Double = 30,
                empreinte: String, sauverEmpreinte: @escaping @Sendable (String) -> Void) {
        self.adresse = adresse
        self.identifiant = identifiant
        self.motDePasse = motDePasse
        self.minutes = minutes
        self.calmeSecondes = calmeSecondes
        self.empreinte = empreinte
        self.sauverEmpreinte = sauverEmpreinte
    }
}

/// Essai de la galerie du stand depuis les réglages.
public enum EssaiGalerieStand {
    public static func tester(_ c: ConfigGalerie, fini: @escaping @Sendable (Bool, String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let g = GalerieStand(config: c, racine: URL(fileURLWithPath: "/"))
            let (ok, m) = g.tester()
            fini(ok, m)
        }
    }

    public static func chercherNouveauxDossiers(_ c: ConfigGalerie, fini: @escaping @Sendable (Bool, String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let g = GalerieStand(config: c, racine: URL(fileURLWithPath: "/"))
            let (ok, m) = g.chercherNouveauxDossiers()
            fini(ok, m)
        }
    }
}

public struct EtatGalerie: Sendable, Equatable {
    public var ok: Bool?
    public var message = ""
    public var le: Date?
    public var enAttente = 0
    public var prochain: Date?
    public init() {}
}

/// Rafraîchit la galerie du stand après des copies, comme la v00 (galerie.py) : jamais à chaque photo.
/// Les copies sont regroupées : un seul rafraîchissement quand plus rien n'a été copié depuis « calme » secondes,
/// et au plus tard X minutes après la première copie en attente (envoi continu). Seuls les dossiers touchés sont
/// rafraîchis ; un dossier neuf déclenche « Chercher les nouveaux dossiers ».
final class GalerieStand: NSObject, URLSessionDelegate, @unchecked Sendable {
    private var config: ConfigGalerie
    private let racine: URL
    private let verrou = NSLock()
    private var enAttente = 0
    private var premiere = Date.distantFuture
    private var derniere = Date.distantPast
    private var nouveauDossier = false
    private var dossiers: Set<String> = []
    private var enCours = false
    private var certificatRefuse = false
    private var _etat = EtatGalerie()
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral     // cookies gardés le temps de l'app seulement
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 200
        c.httpMaximumConnectionsPerHost = 1
        c.httpAdditionalHeaders = ["User-Agent": "TriPhoto"]
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    init(config: ConfigGalerie, racine: URL) {
        self.config = config
        self.racine = racine.standardizedFileURL
    }

    var etat: EtatGalerie {
        verrou.lock(); defer { verrou.unlock() }
        var e = _etat
        e.enAttente = enAttente
        e.prochain = enAttente > 0 ? min(premiere.addingTimeInterval(config.minutes * 60), derniere.addingTimeInterval(config.calmeSecondes)) : nil
        return e
    }

    /// Une copie vient d'être faite (ou retirée) dans ce dossier du serveur local.
    func copieFaite(dans dossier: URL, nouveau: Bool) {
        let nom = nomGalerie(dossier)
        verrou.lock(); defer { verrou.unlock() }
        let t = Date()
        if enAttente == 0 { premiere = t }
        enAttente += 1
        derniere = t
        if nouveau { nouveauDossier = true } else { dossiers.insert(nom) }
    }

    /// Appelé à chaque tour du moteur : rafraîchit si le moment est venu (hors du tri, sur un autre fil).
    func peutEtre() {
        verrou.lock()
        let t = Date()
        let pret = enAttente > 0 && !enCours
            && (t.timeIntervalSince(derniere) >= config.calmeSecondes || t.timeIntervalSince(premiere) >= config.minutes * 60)
        if pret { enCours = true }
        verrou.unlock()
        if pret { DispatchQueue.global(qos: .utility).async { self.rafraichir() } }
    }

    /// Bouton « Rafraîchir maintenant ».
    func maintenant() {
        verrou.lock()
        if enAttente == 0 { enAttente = 1; nouveauDossier = true; premiere = Date() }
        premiere = .distantPast
        verrou.unlock()
        peutEtre()
    }

    /// Nom du dossier côté galerie : son chemin sous le dossier du serveur local (« 08 Amateur 2 GP/À attribuer »).
    func nomGalerie(_ dossier: URL) -> String {
        let d = dossier.standardizedFileURL.pathComponents, r = racine.pathComponents
        guard d.count > r.count, Array(d.prefix(r.count)) == r else { return racine.lastPathComponent }
        return d.dropFirst(r.count).joined(separator: "/")
    }

    // MARK: - Rafraîchir

    private func rafraichir() {
        verrou.lock()
        let n = enAttente, nouveau = nouveauDossier, liste = dossiers
        enAttente = 0; nouveauDossier = false; dossiers = []
        verrou.unlock()
        var faits: [String] = []
        do {
            if !(try connecte()) { try seConnecter() }
            if nouveau {
                _ = try requete("/admin/app/dossier/scan", delai: 180)
                faits.append("nouveaux dossiers")
            }
            for nom in liste.sorted() {
                guard let lien = try lienMiseAJour(nom) else {
                    throw GalerieStand.erreur("dossier « \(nom) » introuvable dans la galerie")
                }
                let (st, _, _) = try requete(lien, delai: 180)
                if st >= 400 { throw GalerieStand.erreur("la galerie répond \(st) pour « \(nom) »") }
                faits.append(nom)
            }
            finir(ok: true, message: "Galerie rafraîchie (\(faits.isEmpty ? "rien à faire" : faits.joined(separator: ", "))) pour \(n) photo\(n > 1 ? "s" : "")")
        } catch {
            // on réessaiera dans une minute environ, avec tout ce qui restait
            verrou.lock()
            enAttente += n
            nouveauDossier = nouveauDossier || nouveau
            dossiers.formUnion(liste)
            premiere = Date().addingTimeInterval(60 - config.minutes * 60)
            derniere = Date().addingTimeInterval(60)
            verrou.unlock()
            verrou.lock()
            let cert = certificatRefuse
            certificatRefuse = false
            verrou.unlock()
            finir(ok: false, message: "Galerie non rafraîchie : " + (cert
                ? "le certificat du serveur a changé, connexion refusée (efface l'empreinte dans les réglages si c'est voulu)"
                : error.localizedDescription))
        }
    }

    private func finir(ok: Bool, message: String) {
        verrou.lock()
        enCours = false
        _etat.ok = ok
        _etat.message = message
        _etat.le = Date()
        verrou.unlock()
    }

    /// Seule la racine du serveur compte : « smb://190.160.40.5 » (partage collé par erreur), « 190.160.40.5 »,
    /// « https://190.160.40.5/admin/app/dossier/list » (page copiée du navigateur) → « https://190.160.40.5 ».
    static func adresseWeb(_ adresse: String) -> String {
        var a = adresse.trimmingCharacters(in: .whitespacesAndNewlines)
        let schema = a.lowercased().hasPrefix("http://") ? "http://" : "https://"
        if let r = a.range(of: "://") { a = String(a[r.upperBound...]) }
        a = String(a.split(separator: "/").first ?? Substring(a))
        return schema + a
    }

    /// Bouton « Rafraîchir maintenant » sans tri en cours : connexion, puis « Chercher les nouveaux dossiers ».
    func chercherNouveauxDossiers() -> (Bool, String) {
        do {
            if !(try connecte()) { try seConnecter() }
            let (st, _, _) = try requete("/admin/app/dossier/scan", delai: 180)
            if st >= 400 { return (false, "La galerie répond \(st) à « Chercher les nouveaux dossiers ».") }
            return (true, "Galerie rafraîchie (nouveaux dossiers cherchés).")
        } catch {
            return tester()
        }
    }

    /// Bouton « Tester la connexion » : le serveur répond-il, l'identifiant est-il accepté, la liste des dossiers
    /// se lit-elle ? Ne rafraîchit rien.
    func tester() -> (Bool, String) {
        let web = GalerieStand.adresseWeb(config.adresse)
        do {
            if !(try connecte()) { try seConnecter() }
            let (st, _, page) = try requete("/admin/app/dossier/list?per_page=250")
            guard st == 200 else { return (false, "Connecté, mais la liste des dossiers répond \(st).") }
            let n = GalerieStand.tous(#"/admin/app/dossier/(\d+)/"#, page).count
            let detail = n > 0 ? " Dossiers vus dans la galerie." : ""
            let note = web == config.adresse.trimmingCharacters(in: .whitespacesAndNewlines) ? "" : " (adresse utilisée : \(web))"
            return (true, "Connexion réussie : identifiant et mot de passe acceptés.\(detail)\(note)")
        } catch {
            verrou.lock(); let cert = certificatRefuse; certificatRefuse = false; verrou.unlock()
            if cert { return (false, "Le certificat du serveur a changé : connexion refusée (« Oublier le certificat » si c'est voulu).") }
            let e = error as NSError
            if e.domain == NSURLErrorDomain {
                switch e.code {
                case NSURLErrorCannotConnectToHost, NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorNotConnectedToInternet,
                     NSURLErrorNetworkConnectionLost:
                    return (false, "Le serveur ne répond pas à \(web) : est-il allumé, et ce Mac est-il sur le réseau du stand ?")
                default: break
                }
            }
            return (false, error.localizedDescription)
        }
    }

    private static func erreur(_ t: String) -> NSError {
        NSError(domain: "Galerie", code: 1, userInfo: [NSLocalizedDescriptionKey: t])
    }

    private func connecte() throws -> Bool {
        let (st, url, _) = try requete("/admin/dashboard")
        return st == 200 && !url.lowercased().contains("login")
    }

    private func seConnecter() throws {
        let (_, _, page) = try requete("/admin/login")
        let jeton = GalerieStand.premier(#"name="_csrf_token"\s+value="([^"]*)""#, page)
            ?? GalerieStand.premier(#"value="([^"]*)"\s+name="_csrf_token""#, page) ?? ""
        let (_, url, _) = try requete("/admin/login_check", formulaire: [
            "_username": config.identifiant, "_password": config.motDePasse, "_csrf_token": jeton, "_remember_me": "on"])
        _ = url
        if !(try connecte()) { throw GalerieStand.erreur("identifiant ou mot de passe de la galerie refusé") }
    }

    /// Lien « Rafraichir le dossier » de la ligne du dossier (son jeton change à chaque affichage de la liste).
    private func lienMiseAJour(_ nom: String) throws -> String? {
        let (_, _, page) = try requete("/admin/app/dossier/list?per_page=250")
        let lignes = try NSRegularExpression(pattern: #"<tr[^>]*>(.*?)</tr>"#, options: [.dotMatchesLineSeparators])
        let ns = page as NSString
        for m in lignes.matches(in: page, range: NSRange(location: 0, length: ns.length)) {
            let ligne = ns.substring(with: m.range(at: 1))
            guard let lien = GalerieStand.premier(#"href="([^"]*/admin/app/dossier/update\?[^"]*)""#, ligne) else { continue }
            let cellules = GalerieStand.tous(#"<td[^>]*>(.*?)</td>"#, ligne).map {
                $0.replacingOccurrences(of: #"<[^>]+>|\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            if cellules.contains(where: { !$0.isEmpty && ($0 == nom || $0.hasSuffix("/" + nom) || $0.hasSuffix("/" + nom + "/")) }) {
                return lien.replacingOccurrences(of: "&amp;", with: "&")
            }
        }
        return nil
    }

    // MARK: - HTTP

    /// Requête (GET, ou POST d'un formulaire). Rend le statut, l'adresse finale (après redirections) et la page.
    private func requete(_ chemin: String, formulaire: [String: String]? = nil, delai: TimeInterval = 30) throws -> (Int, String, String) {
        var base = GalerieStand.adresseWeb(config.adresse)
        while base.hasSuffix("/") { base.removeLast() }
        let complet = chemin.hasPrefix("http") ? chemin : base + chemin
        guard let url = URL(string: complet) else { throw GalerieStand.erreur("adresse de la galerie invalide") }
        var r = URLRequest(url: url, timeoutInterval: delai)
        if let formulaire {
            r.httpMethod = "POST"
            r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            // Tout ce qui n'est pas lettre, chiffre ou « -._~ » est encodé (mot de passe avec & = + # …).
            var permis = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)..<Unicode.Scalar(128)))
            permis.insert(charactersIn: "-._~")
            func enc(_ t: String) -> String { t.addingPercentEncoding(withAllowedCharacters: permis) ?? t }
            r.httpBody = formulaire.map { enc($0.key) + "=" + enc($0.value) }.joined(separator: "&").data(using: .utf8)
        }
        let fini = DispatchSemaphore(value: 0)
        var sortie: (Int, String, String)?
        var echec: Error?
        session.dataTask(with: r) { data, rep, err in
            if let err { echec = err } else {
                let h = rep as? HTTPURLResponse
                sortie = (h?.statusCode ?? 0, h?.url?.absoluteString ?? "",
                          String(decoding: (data ?? Data()).prefix(2_000_000), as: UTF8.self))
            }
            fini.signal()
        }.resume()
        fini.wait()
        if let echec { throw echec }
        return sortie ?? (0, "", "")
    }

    /// Certificat auto-signé du serveur du stand : accepté la 1re fois (son empreinte est retenue), ensuite exigé.
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
        completionHandler(.useCredential, URLCredential(trust: confiance))
    }

    private static func premier(_ motif: String, _ texte: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: motif, options: [.dotMatchesLineSeparators]) else { return nil }
        let ns = texte as NSString
        guard let m = re.firstMatch(in: texte, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static func tous(_ motif: String, _ texte: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: motif, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = texte as NSString
        return re.matches(in: texte, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }
}
