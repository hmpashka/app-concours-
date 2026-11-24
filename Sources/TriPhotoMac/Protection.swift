import AppKit
import CommonCrypto
import CryptoKit
import Foundation
import IOKit
import TriPhotoMoteur

/// Protection antivol (maquette du 24/11).
///
/// Un petit fichier signé, « macs.json », est posé sur le site de HUGO (live.hmphotographie.fr) par FTP. Il dit
/// quels Mac sont autorisés et lesquels sont bloqués. Chaque Mac le relit au lancement puis toutes les heures.
/// - Signature : clé Ed25519. La clé privée voyage DANS le fichier, chiffrée par la phrase d'administration
///   choisie par HUGO (il est le seul à la taper). Sans elle, personne ne peut fabriquer un faux fichier.
/// - Un Mac bloqué l'est au prochain lancement (ou dans l'heure s'il a internet) : écran de blocage, mots de
///   passe du trousseau effacés.
/// - Sans internet, rien ne s'arrête. Après 30 jours sans nouvelles du site, l'app le demande au lancement, et
///   on peut continuer 5 fois avant qu'elle exige internet.
/// - Prévu pour des licences plus tard (champ « proprietaire » de chaque Mac).
@MainActor
final class Protection: ObservableObject {
    static let partagee = Protection()

    struct MacProtege: Codable, Equatable, Identifiable {
        var id: String
        var nom: String
        var etat: String              // « autorise » | « bloque »
        var activeLe: Date
        var proprietaire: String = "HM Photographie"
        var bloque: Bool { etat == "bloque" }
    }

    private struct Liste: Codable { var date: Date; var macs: [MacProtege] }

    private struct Fichier: Codable {
        var version = 1
        var cle: String               // clé publique (base64)
        var coffre: String            // clé privée chiffrée (AES-GCM, base64)
        var sel: String
        var contenu: String           // Liste en JSON (base64)
        var signature: String
    }

    struct Reglage: Codable, Equatable {
        var adresse = "https://live.hmphotographie.fr/groompix/macs.json"
        var protocole: ConfigGalerieEnLigne.Protocole = .ftp
        var hote = ""
        var port = 0
        var identifiant = ""
        var dossier = "/groompix"
        var accepterCertificat = false
    }

    private struct EtatLocal: Codable {
        var actif = false
        var clePubliqueSuivie = ""
        var derniereVerif: Date?
        var bloque = false
        var sursis = 5
    }

    @Published var reglage: Reglage { didSet { sauverReglage() } }
    @Published private(set) var macs: [MacProtege] = []
    @Published private(set) var bloque = false
    @Published private(set) var actif = false
    @Published private(set) var derniereVerif: Date?
    @Published var message = ""
    @Published var occupe = false
    /// Plus de 30 jours sans nouvelles du site : demande au lancement.
    @Published var demanderInternet = false
    @Published private(set) var sursis = 5

    private var local: EtatLocal { didSet { sauverLocal() } }
    private var minuterie: Timer?
    static let joursHorsLigne = 30.0

    var motDePasseSite: String {
        get { Trousseau.lire("protection-site") }
        set { Trousseau.ecrire("protection-site", newValue); objectWillChange.send() }
    }

    private init() {
        reglage = UserDefaults.standard.data(forKey: "protection-reglage")
            .flatMap { try? JSONDecoder().decode(Reglage.self, from: $0) } ?? Reglage()
        local = UserDefaults.standard.data(forKey: "protection-etat")
            .flatMap { try? JSONDecoder().decode(EtatLocal.self, from: $0) } ?? EtatLocal()
        bloque = local.bloque
        actif = local.actif
        derniereVerif = local.derniereVerif
        sursis = local.sursis
    }

    private func sauverReglage() {
        if let d = try? JSONEncoder().encode(reglage) { UserDefaults.standard.set(d, forKey: "protection-reglage") }
    }
    private func sauverLocal() {
        if let d = try? JSONEncoder().encode(local) { UserDefaults.standard.set(d, forKey: "protection-etat") }
        bloque = local.bloque
        actif = local.actif
        derniereVerif = local.derniereVerif
        sursis = local.sursis
    }

    // MARK: - Ce Mac

    /// Identifiant de ce Mac : empreinte de son numéro matériel (le numéro lui-même ne sort jamais du Mac).
    nonisolated static let idCeMac: String = {
        let s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(s) }
        let uuid = (IORegistryEntryCreateCFProperty(s, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String) ?? Host.current().localizedName ?? "inconnu"
        let h = SHA256.hash(data: Data(("groompix|" + uuid).utf8))
        return h.prefix(8).map { String(format: "%02x", $0) }.joined()
    }()

    static var nomCeMac: String { Host.current().localizedName ?? "Ce Mac" }

    var ceMac: MacProtege? { macs.first { $0.id == Protection.idCeMac } }

    // MARK: - Vérification (lancement, puis toutes les heures)

    func demarrer() {
        if actif, let d = local.derniereVerif, Date().timeIntervalSince(d) > Protection.joursHorsLigne * 86400 {
            demanderInternet = true
        }
        verifier()
        minuterie?.invalidate()
        minuterie = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in Protection.partagee.verifier() }
        }
    }

    /// Lit le fichier du site. Sans réponse (pas d'internet) : rien ne change, l'app continue.
    func verifier() {
        guard actif, let url = URL(string: reglage.adresse) else { return }
        Task {
            guard let f = try? await Protection.telecharger(url) else { return }
            guard let liste = verifierSignature(f) else {
                message = "Le fichier du site n'a pas la bonne signature : ignoré."
                return
            }
            macs = liste.macs
            var l = local
            l.derniereVerif = Date()
            l.sursis = 5
            demanderInternet = false
            if let moi = liste.macs.first(where: { $0.id == Protection.idCeMac }) {
                if moi.bloque && !l.bloque {
                    l.bloque = true
                    Protection.effacerMotsDePasse()
                } else if !moi.bloque && l.bloque {
                    l.bloque = false                      // débloqué par HUGO
                }
            }
            local = l
        }
    }

    /// « Continuer quand même » (sans internet depuis plus de 30 jours).
    func continuerSansInternet() {
        guard local.sursis > 0 else { return }
        local.sursis -= 1
        demanderInternet = false
    }

    private func verifierSignature(_ f: Fichier) -> Liste? {
        guard f.cle == local.clePubliqueSuivie,
              let cle = Data(base64Encoded: f.cle).flatMap({ try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }),
              let contenu = Data(base64Encoded: f.contenu), let sig = Data(base64Encoded: f.signature),
              cle.isValidSignature(sig, for: contenu) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Liste.self, from: contenu)
    }

    nonisolated private static func telecharger(_ url: URL) async throws -> Fichier? {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        r.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (d, rep) = try await URLSession.shared.data(for: r)
        if let h = rep as? HTTPURLResponse, h.statusCode == 404 { return nil }
        guard let h = rep as? HTTPURLResponse, h.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Fichier.self, from: d)
    }

    /// Mac bloqué : les mots de passe enregistrés par l'app sont effacés de ce Mac.
    private static func effacerMotsDePasse() {
        for c in ["galerie-stand", "galerie-en-ligne", "unifi", "protection-site"] { Trousseau.ecrire(c, "") }
    }

    // MARK: - Administration (phrase tapée par HUGO)

    /// Active la protection sur ce Mac. Premier Mac : crée la clé avec cette phrase. Les suivants : même phrase.
    func activer(phrase: String) {
        modifier(phrase: phrase, creerSiAbsent: true) { liste in
            if let i = liste.macs.firstIndex(where: { $0.id == Protection.idCeMac }) {
                liste.macs[i].etat = "autorise"
            } else {
                liste.macs.append(MacProtege(id: Protection.idCeMac, nom: Protection.nomCeMac, etat: "autorise", activeLe: Date()))
            }
            return "Protection active sur « \(Protection.nomCeMac) »."
        }
    }

    func bloquer(_ m: MacProtege, oui: Bool, phrase: String) {
        modifier(phrase: phrase) { liste in
            guard let i = liste.macs.firstIndex(where: { $0.id == m.id }) else { return "Mac introuvable." }
            liste.macs[i].etat = oui ? "bloque" : "autorise"
            return oui ? "« \(m.nom) » est bloqué : il le sera dès qu'il verra le site." : "« \(m.nom) » est débloqué."
        }
    }

    func renommer(_ m: MacProtege, en nom: String, phrase: String) {
        let n = nom.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        modifier(phrase: phrase) { liste in
            guard let i = liste.macs.firstIndex(where: { $0.id == m.id }) else { return "Mac introuvable." }
            liste.macs[i].nom = n
            return "Renommé en « \(n) »."
        }
    }

    func retirer(_ m: MacProtege, phrase: String) {
        modifier(phrase: phrase) { liste in
            liste.macs.removeAll { $0.id == m.id }
            return "« \(m.nom) » retiré de la liste."
        }
    }

    /// Relit le fichier, ouvre le coffre avec la phrase, applique le changement, signe et redépose le fichier.
    private func modifier(phrase: String, creerSiAbsent: Bool = false, _ changer: @escaping (inout Liste) -> String) {
        guard let url = URL(string: reglage.adresse) else { message = "Adresse du fichier incorrecte."; return }
        guard !reglage.hote.isEmpty else { message = "Remplis d'abord la connexion au site (FTP)."; return }
        guard phrase.count >= 8 else { message = "La phrase d'administration doit faire au moins 8 caractères."; return }
        occupe = true
        message = "Connexion au site…"
        let config = configFTP()
        Task {
            defer { occupe = false }
            do {
                let ancien = try await Protection.telecharger(url)
                var cle: Curve25519.Signing.PrivateKey
                var sel: Data
                var liste: Liste
                if let f = ancien {
                    guard let s = Data(base64Encoded: f.sel), let coffre = Data(base64Encoded: f.coffre),
                          let k = Protection.ouvrir(coffre, phrase: phrase, sel: s),
                          k.publicKey.rawRepresentation.base64EncodedString() == f.cle else {
                        message = "Phrase d'administration incorrecte : rien n'a changé."
                        return
                    }
                    if !local.clePubliqueSuivie.isEmpty && local.clePubliqueSuivie != f.cle {
                        message = "Le fichier du site a une autre clé que celle de ce Mac : rien n'a changé."
                        return
                    }
                    cle = k
                    sel = s
                    let dec = JSONDecoder()
                    dec.dateDecodingStrategy = .iso8601
                    liste = (Data(base64Encoded: f.contenu).flatMap { try? dec.decode(Liste.self, from: $0) }) ?? Liste(date: Date(), macs: [])
                } else {
                    guard creerSiAbsent else { message = "Pas encore de fichier sur le site : active d'abord ce Mac."; return }
                    cle = Curve25519.Signing.PrivateKey()
                    sel = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
                    liste = Liste(date: Date(), macs: [])
                }
                let texte = changer(&liste)
                liste.date = Date()
                let enc = JSONEncoder()
                enc.dateEncodingStrategy = .iso8601
                enc.outputFormatting = [.sortedKeys]
                let contenu = try enc.encode(liste)
                let f = Fichier(cle: cle.publicKey.rawRepresentation.base64EncodedString(),
                                coffre: try Protection.fermer(cle, phrase: phrase, sel: sel).base64EncodedString(),
                                sel: sel.base64EncodedString(), contenu: contenu.base64EncodedString(),
                                signature: try cle.signature(for: contenu).base64EncodedString())
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("macs.json")
                try JSONEncoder().encode(f).write(to: tmp, options: .atomic)
                try await Task.detached { try GalerieEnLigne.deposer(tmp, nom: "macs.json", config: config) }.value
                try? FileManager.default.removeItem(at: tmp)
                var l = local
                l.actif = true
                l.clePubliqueSuivie = f.cle
                l.derniereVerif = Date()
                local = l
                macs = liste.macs
                message = texte
            } catch {
                message = "Site : \(error.localizedDescription)"
            }
        }
    }

    func testerConnexion() {
        occupe = true
        message = "Test de la connexion au site…"
        let c = configFTP()
        Task {
            defer { occupe = false }
            do {
                try await Task.detached { try GalerieEnLigne.testerConnexion(c) }.value
                message = "Connexion au site réussie."
            } catch {
                message = "Connexion : \(error.localizedDescription)"
            }
        }
    }

    private func configFTP() -> ConfigGalerieEnLigne {
        ConfigGalerieEnLigne(protocole: reglage.protocole, hote: reglage.hote, port: reglage.port, identifiant: reglage.identifiant,
                             motDePasse: motDePasseSite, dossier: reglage.dossier, accepterCertificat: reglage.accepterCertificat,
                             laNuit: false, heureNuit: 22, heureMatin: 7, limiteKo: 0, cote: 0, qualite: 0, cube: nil,
                             cubeDuServeur: false, numero: false, auteurParDefaut: "", depuis: Date(),
                             fichierEtat: FileManager.default.temporaryDirectory.appendingPathComponent("protection-etat.json"))
    }

    // MARK: - Coffre (clé privée chiffrée par la phrase)

    nonisolated private static func deriver(_ phrase: String, sel: Data) -> SymmetricKey {
        var cle = [UInt8](repeating: 0, count: 32)
        let p = Array(phrase.utf8)
        _ = sel.withUnsafeBytes { s in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), phrase, p.count,
                                 s.bindMemory(to: UInt8.self).baseAddress, sel.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 200_000, &cle, cle.count)
        }
        return SymmetricKey(data: cle)
    }

    nonisolated private static func fermer(_ k: Curve25519.Signing.PrivateKey, phrase: String, sel: Data) throws -> Data {
        guard let d = try AES.GCM.seal(k.rawRepresentation, using: deriver(phrase, sel: sel)).combined else {
            throw URLError(.cannotCreateFile)
        }
        return d
    }

    nonisolated private static func ouvrir(_ coffre: Data, phrase: String, sel: Data) -> Curve25519.Signing.PrivateKey? {
        guard let boite = try? AES.GCM.SealedBox(combined: coffre),
              let brut = try? AES.GCM.open(boite, using: deriver(phrase, sel: sel)) else { return nil }
        return try? Curve25519.Signing.PrivateKey(rawRepresentation: brut)
    }
}
