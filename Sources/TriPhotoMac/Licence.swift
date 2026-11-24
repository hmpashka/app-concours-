import AppKit
import CryptoKit
import Foundation
import IOKit

/// Licence de Groom Pix (HUGO, 24/11) : même système que ses autres logiciels (HM TIMINGS, Gestovet, Atelier Piquage),
/// sur son site live.hmphotographie.fr. Page d'administration : /admin › Mes abonnés › Groom Pix.
///
/// - Un compte (mail + mot de passe) par client. Compte neuf : 48 h d'essai, puis HM Photographie l'active sur le site.
/// - Ce Mac se signale au lancement puis toutes les 5 minutes. Le site répond par une attestation signée (Ed25519,
///   même clé que HM TIMINGS) : l'app ne croit que ce qui est signé.
/// - Compte suspendu, Mac bloqué, essai ou abonnement fini, ou 6 jours sans contact : l'app se bloque. Jamais en plein
///   tri : si le tri tourne, le blocage attend que le tri s'arrête (ou le prochain lancement).
/// - Mac bloqué ou compte suspendu : les mots de passe enregistrés par l'app sont effacés de ce Mac.
/// - Après 4 jours sans contact : avertissement.
@MainActor
final class Licence: ObservableObject {
    static let partagee = Licence()

    nonisolated static let site = URL(string: "https://live.hmphotographie.fr")!
    nonisolated static let produit = "groompix"
    /// Clé publique des licences HM (la même que HM TIMINGS, serveur/licence.py).
    nonisolated static let clePublique = "e10bdabb55d9e13b6e7e94575cc044982e7ebc69d478a7b8482883f0b71bf876"
    static let joursMax = 6.0
    static let joursAvertissement = 4.0
    static let intervalleSignal: TimeInterval = 300

    /// Ce que dit la dernière attestation signée.
    struct Compte: Codable, Equatable {
        var id: String = ""
        var nom: String = ""
        var mail: String = ""
        var statut: String = ""                 // essai | actif | suspendu
        var fin: Double?                        // fin d'abonnement (secondes), nil = sans fin
        var essai_fin: Double?
        var poste_bloque: Bool = false
    }
    private struct Charge: Codable {
        var v: Int
        var produit: String
        var poste: String
        var emis: Double
        var compte: Compte
    }

    enum Verdict: Equatable {
        case aConnecter                         // pas de session : mail + mot de passe
        case ok
        case avertissement(jours: Int)          // 4 jours ou plus sans contact
        case bloque(raison: String, effacer: Bool)

        var bloquant: Bool { if case .bloque = self { return true }; return self == .aConnecter }
    }

    private struct EtatLocal: Codable {
        var signe = ""                          // dernière attestation reçue
        var contact: Double = 0                 // date (signée) du dernier contact
        var essaiDebut: Double = 0
        var effaces = false
    }

    @Published private(set) var compte: Compte?
    @Published private(set) var verdict: Verdict = .aConnecter
    @Published private(set) var dernierContact: Date?
    /// Blocage affiché (le tri en cours n'est jamais coupé).
    @Published private(set) var ecranBloque = false
    @Published var message = ""
    @Published var occupe = false

    private var local: EtatLocal { didSet { sauver() } }
    private var minuterie: Timer?
    private var dejaAffiche = false             // le premier verdict (au lancement) s'applique tout de suite
    var triActif: @MainActor () -> Bool = { false }

    private var jeton: String {
        get { Trousseau.lire("licence-session") }
        set { Trousseau.ecrire("licence-session", newValue) }
    }

    private init() {
        local = UserDefaults.standard.data(forKey: "licence-etat")
            .flatMap { try? JSONDecoder().decode(EtatLocal.self, from: $0) } ?? EtatLocal()
        lireAttestation()
        evaluer()
    }

    private func sauver() {
        if let d = try? JSONEncoder().encode(local) { UserDefaults.standard.set(d, forKey: "licence-etat") }
    }

    // MARK: - Ce Mac

    /// Identifiant de ce Mac : empreinte de son numéro matériel (le numéro lui-même ne sort jamais du Mac).
    nonisolated static let poste: String = {
        let s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(s) }
        let uuid = (IORegistryEntryCreateCFProperty(s, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String) ?? Host.current().localizedName ?? "inconnu"
        let h = SHA256.hash(data: Data(("groompix|" + uuid).utf8))
        return h.prefix(16).map { String(format: "%02x", $0) }.joined()
    }()

    static var nomCeMac: String { Host.current().localizedName ?? "Mac" }
    static var version: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev" }

    // MARK: - Lancement et signal

    func demarrer() {
        signaler()
        minuterie?.invalidate()
        minuterie = Timer.scheduledTimer(withTimeInterval: Licence.intervalleSignal, repeats: true) { _ in
            Task { @MainActor in Licence.partagee.signaler() }
        }
    }

    /// Le tri vient de s'arrêter (ou de démarrer) : un blocage en attente peut s'afficher.
    func triChange() { appliquer() }

    func signaler() {
        guard !jeton.isEmpty else { evaluer(); return }
        Task {
            let rep = await Licence.appeler("signal", ["jeton": jeton, "poste": Licence.poste,
                                                        "nom_poste": Licence.nomCeMac, "version": Licence.version])
            guard let rep else { evaluer(); return }               // pas d'internet : rien ne change
            if let s = rep["signe"] as? String, recevoir(s) {
                message = ""
            } else if (rep["statut"] as? String) == "non_connecte" {
                jeton = ""                                         // session fermée sur le site
                message = (rep["message"] as? String) ?? "Session fermée : reconnecte-toi."
            }
            evaluer()
        }
    }

    /// Connexion (compte existant) ou création (nouveau compte, avec le nom du stand).
    func connecter(mail: String, motDePasse: String, creerAvecNom nom: String?) {
        occupe = true
        message = ""
        var corps: [String: Any] = ["mail": mail, "mot_de_passe": motDePasse, "poste": Licence.poste,
                                    "nom_poste": Licence.nomCeMac, "version": Licence.version]
        if let nom {
            corps["nom"] = nom
            if local.essaiDebut > 0 { corps["essai_debut"] = Int(local.essaiDebut) }
        }
        Task {
            defer { occupe = false }
            guard let rep = await Licence.appeler(nom == nil ? "compte/connexion" : "compte/creer", corps) else {
                message = "Le site live.hmphotographie.fr ne répond pas : vérifie la connexion internet."
                return
            }
            guard (rep["ok"] as? Bool) == true, let j = rep["jeton"] as? String, let s = rep["signe"] as? String, recevoir(s) else {
                message = (rep["message"] as? String) ?? (rep["erreur"] as? String) ?? "Le site a refusé la demande."
                return
            }
            jeton = j
            if local.essaiDebut == 0 { local.essaiDebut = Date().timeIntervalSince1970 }
            evaluer()
        }
    }

    func deconnecter() {
        let j = jeton
        jeton = ""
        local.signe = ""
        compte = nil
        evaluer()
        guard !j.isEmpty else { return }
        Task { _ = await Licence.appeler("deconnexion", ["jeton": j, "poste": Licence.poste]) }
    }

    // MARK: - Attestation signée

    /// Vérifie et garde une attestation. Faux si la signature, le logiciel ou le Mac ne correspondent pas.
    private func recevoir(_ signe: String) -> Bool {
        guard let c = Licence.verifier(signe) else { message = "Réponse du site non signée : ignorée."; return false }
        local.signe = signe
        local.contact = max(local.contact, c.emis)
        lireAttestation()
        return true
    }

    private func lireAttestation() {
        if let c = Licence.verifier(local.signe) {
            compte = c.compte
            dernierContact = Date(timeIntervalSince1970: local.contact)
        } else {
            compte = nil
        }
    }

    nonisolated private static func verifier(_ signe: String) -> Charge? {
        let p = signe.split(separator: ".")
        guard p.count == 2, let json = deb64url(String(p[0])), let sig = deb64url(String(p[1])),
              let brut = Data(hex: clePublique), let cle = try? Curve25519.Signing.PublicKey(rawRepresentation: brut),
              cle.isValidSignature(sig, for: json),
              let c = try? JSONDecoder().decode(Charge.self, from: json),
              c.v == 1, c.produit == produit, c.poste == poste else { return nil }
        return c
    }

    nonisolated private static func deb64url(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }

    // MARK: - Verdict

    private func evaluer() {
        let maintenant = Date().timeIntervalSince1970
        let jours = (maintenant - local.contact) / 86400
        var v: Verdict
        if jeton.isEmpty || compte == nil {
            v = .aConnecter
        } else if let c = compte, c.poste_bloque {
            v = .bloque(raison: "Ce Mac a été bloqué par son propriétaire.", effacer: true)
        } else if let c = compte, c.statut == "suspendu" {
            v = .bloque(raison: "La licence de ce compte est suspendue.", effacer: true)
        } else if let c = compte, c.statut == "essai", let f = c.essai_fin, f < maintenant {
            v = .bloque(raison: "L'essai de 48 h est terminé : HM Photographie doit activer le compte.", effacer: false)
        } else if let c = compte, c.statut == "actif", let f = c.fin, f < maintenant {
            v = .bloque(raison: "L'abonnement est terminé depuis le \(Date(timeIntervalSince1970: f).formatted(date: .long, time: .omitted)).", effacer: false)
        } else if jours > Licence.joursMax {
            v = .bloque(raison: "Groom Pix n'a pas pu joindre live.hmphotographie.fr depuis plus de \(Int(Licence.joursMax)) jours. Connecte ce Mac à internet : il se débloque tout seul.", effacer: false)
        } else if jours >= Licence.joursAvertissement {
            v = .avertissement(jours: Int(jours))
        } else {
            v = .ok
        }
        verdict = v
        appliquer()
    }

    private func appliquer() {
        let bloquant = verdict.bloquant
        if !bloquant {
            ecranBloque = false
        } else if !dejaAffiche || !triActif() {
            ecranBloque = true                    // au lancement, ou tri arrêté : tout de suite
        }
        dejaAffiche = true
        if case .bloque(_, true) = verdict, ecranBloque, !local.effaces {
            for c in ["galerie-stand", "galerie-en-ligne", "unifi", "protection-site"] { Trousseau.ecrire(c, "") }
            local.effaces = true
        } else if case .ok = verdict {
            local.effaces = false
        }
    }

    // MARK: - Réseau

    nonisolated private static func appeler(_ route: String, _ corps: [String: Any]) async -> [String: Any]? {
        let url = site.appendingPathComponent("api/\(produit)/\(route)")
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: corps)
        guard let res = try? await URLSession.shared.data(for: r), res.1 is HTTPURLResponse else { return nil }
        return ((try? JSONSerialization.jsonObject(with: res.0)) as? [String: Any]) ?? [:]
    }
}

private extension Data {
    init?(hex: String) {
        var d = Data(capacity: hex.count / 2)
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let b = UInt8(hex[i..<j], radix: 16) else { return nil }
            d.append(b)
            i = j
        }
        self = d
    }
}
