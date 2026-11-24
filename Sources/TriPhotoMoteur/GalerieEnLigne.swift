import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import TriPhotoCommun
import UniformTypeIdentifiers

/// Réglages de l'envoi vers la galerie en ligne (comme un site dans FileZilla).
public struct ConfigGalerieEnLigne: Sendable {
    public enum Protocole: String, Codable, CaseIterable, Identifiable, Sendable {
        case ftp = "FTP"
        case ftpsExplicite = "FTP sur TLS explicite"
        case ftpsImplicite = "FTP sur TLS implicite"
        case sftp = "SFTP"
        public var id: String { rawValue }
        public var portParDefaut: Int {
            switch self {
            case .ftp, .ftpsExplicite: return 21
            case .ftpsImplicite: return 990
            case .sftp: return 22
            }
        }
    }

    public var protocole: Protocole
    public var hote: String
    public var port: Int              // 0 : port habituel du protocole
    public var identifiant: String
    public var motDePasse: String
    /// Dossier distant où vont TOUTES les photos (à plat). « /www/album » ou « album ».
    public var dossier: String
    /// Certificat du serveur non reconnu (FTP sur TLS) : l'accepter quand même, comme FileZilla le propose.
    public var accepterCertificat: Bool
    /// Envoi seulement la nuit (de `heureNuit` à `heureMatin`) ; sinon au fil de l'eau.
    public var laNuit: Bool
    public var heureNuit: Int
    public var heureMatin: Int
    /// Débit maximum en Ko/s (0 : sans limite).
    public var limiteKo: Int
    // La copie de la galerie
    public var cote: Int
    public var qualite: Int
    public var cube: FichierCube?
    /// Le .cube de la galerie est celui du serveur local : la copie du serveur peut servir si l'original manque.
    public var cubeDuServeur: Bool
    public var numero: Bool
    /// Auteur écrit dans les photos quand le boîtier n'a pas de photographe (photo de synchro).
    public var auteurParDefaut: String
    /// Photos reçues depuis ce jour (début du concours) : le journal garde aussi les anciens concours.
    public var depuis: Date
    /// Ce qui est déjà en ligne, pour ce concours (fichier JSON à côté du journal).
    public var fichierEtat: URL
    /// Régulateur réseau (console UniFi) : pause quand la ligne internet est chargée par les autres. nil : sans.
    public var unifi: ConfigUniFi?

    public init(protocole: Protocole, hote: String, port: Int, identifiant: String, motDePasse: String, dossier: String,
                accepterCertificat: Bool, laNuit: Bool, heureNuit: Int, heureMatin: Int, limiteKo: Int, cote: Int,
                qualite: Int, cube: FichierCube?, cubeDuServeur: Bool, numero: Bool, auteurParDefaut: String,
                depuis: Date, fichierEtat: URL, unifi: ConfigUniFi? = nil) {
        self.protocole = protocole
        self.hote = hote
        self.port = port
        self.identifiant = identifiant
        self.motDePasse = motDePasse
        self.dossier = dossier
        self.accepterCertificat = accepterCertificat
        self.laNuit = laNuit
        self.heureNuit = heureNuit
        self.heureMatin = heureMatin
        self.limiteKo = limiteKo
        self.cote = cote
        self.qualite = qualite
        self.cube = cube
        self.cubeDuServeur = cubeDuServeur
        self.numero = numero
        self.auteurParDefaut = auteurParDefaut
        self.depuis = depuis
        self.fichierEtat = fichierEtat
        self.unifi = unifi
    }

    var portReel: Int { port > 0 ? port : protocole.portParDefaut }

    /// Dans la plage de nuit ? (22 h → 7 h : de 22:00 à 06:59.)
    public func estLaNuit(_ d: Date = Date()) -> Bool {
        let h = Calendar.current.component(.hour, from: d)
        return heureNuit > heureMatin ? (h >= heureNuit || h < heureMatin) : (h >= heureNuit && h < heureMatin)
    }
}

/// L'état de la galerie en ligne, pour l'accueil, les réglages et la clôture.
public struct EtatGalerieEnLigne: Sendable, Equatable {
    public var ok: Bool?
    public var message = ""
    public var enLigne = 0
    public var aEnvoyer = 0
    public var aSupprimer = 0
    public var envoiEnCours = false
    public var attendLaNuit = false
    public var derniereReussite: Date?
    public var parMinute = 0.0
    public var pauseReseau = false
    public var reseau: EtatReseau?
    public init() {}
    public var aFaire: Int { aEnvoyer + aSupprimer }
}

/// Une photo qui doit être en ligne.
public struct PhotoEnLigne: Sendable, Hashable {
    public var nom: String            // nom du fichier en ligne (celui de la copie du serveur)
    public var signature: String      // change si la photo doit être renvoyée (recodée, refaite…)
    public var original: String
    public var copie: String
    public var copyright: String
    public var auteur: String
}

/// Tient la galerie en ligne à jour : toutes les photos dans un seul dossier, une photo qui existe déjà est remplacée,
/// une nouvelle est ajoutée, une photo retirée (supprimée dans Lightroom…) est supprimée en ligne. Seules les photos
/// envoyées par l'app sont supprimées : rien d'autre n'est jamais touché sur le serveur.
///
/// La copie de la galerie est faite au moment de l'envoi, depuis l'original (.cube, taille, numéro incrusté en haut
/// à gauche, seulement copyright et auteur). Les envois partent par lots, sur une seule connexion, avec les outils
/// du Mac (curl pour le FTP, sftp pour le SFTP), en priorité basse et au débit choisi.
public final class GalerieEnLigne: @unchecked Sendable {
    private let file = DispatchQueue(label: "tri-photo.galerie-en-ligne", qos: .utility)
    private let verrou = NSLock()
    private var config: ConfigGalerieEnLigne
    private var voulues: [String: PhotoEnLigne] = [:]
    private var envoyees: [String: String] = [:]           // nom → signature, ce qui est en ligne
    private var _etat = EtatGalerieEnLigne()
    private var enCours = false
    private var forcer = false
    private var reessayerApres = Date.distantPast
    private var echecs = 0
    private var activite: NSObjectProtocol?
    private var minuterie: DispatchSourceTimer?
    private var historique: [(Date, Int)] = []
    /// Rien n'est fait tant que le moteur n'a pas donné la liste complète (sinon tout paraîtrait « à supprimer »).
    private var listeRecue = false
    private var suppressionBloquee = 0
    private var reseau: ReseauUniFi?
    private var debitPropre = 0.0                          // Mbit/s envoyés par le dernier lot
    private var finDernierLot = Date.distantPast
    static let parLot = 20

    public init(config: ConfigGalerieEnLigne) {
        self.config = config
        self.reseau = config.unifi.flatMap { $0.adresse.isEmpty || $0.cle.isEmpty ? nil : ReseauUniFi(config: $0) }
        if let d = try? Data(contentsOf: config.fichierEtat),
           let e = try? JSONDecoder().decode([String: String].self, from: d) { envoyees = e }
        let t = DispatchSource.makeTimerSource(queue: file)
        t.schedule(deadline: .now() + 5, repeating: 20, leeway: .seconds(5))
        t.setEventHandler { [weak self] in self?.tour() }
        minuterie = t
        t.resume()
    }

    deinit { minuterie?.cancel() }

    public var etat: EtatGalerieEnLigne {
        verrou.lock(); defer { verrou.unlock() }
        return _etat
    }

    /// Nouveaux réglages (mot de passe changé, nuit…) sans perdre ce qui est déjà en ligne.
    public func regler(_ c: ConfigGalerieEnLigne) {
        file.async {
            let autreConcours = c.fichierEtat != self.config.fichierEtat
            self.config = c
            self.reseau = c.unifi.flatMap { $0.adresse.isEmpty || $0.cle.isEmpty ? nil : ReseauUniFi(config: $0) }
            if autreConcours {
                self.envoyees = (try? Data(contentsOf: c.fichierEtat))
                    .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
                self.voulues = [:]
                self.listeRecue = false
            }
            self.reessayerApres = .distantPast
            self.majEtat()
        }
    }

    /// La liste complète des photos qui doivent être en ligne (donnée par le moteur, toutes les minutes).
    public func synchroniser(_ photos: [PhotoEnLigne]) {
        file.async {
            var v: [String: PhotoEnLigne] = [:]
            for p in photos { v[p.nom] = p }
            self.voulues = v
            self.listeRecue = true
            self.majEtat()
        }
    }

    /// Envoyer tout de suite, même la nuit pas encore venue (clôture, bouton « Envoyer maintenant »).
    public func envoyerMaintenant() {
        file.async {
            self.forcer = true
            self.reessayerApres = .distantPast
            self.tour()
        }
    }

    /// Fabrique une copie de galerie (pour l'essai en ligne de commande).
    public static func essaiCopie(de url: URL, vers dest: URL, cote: Int, qualite: Int, cube: FichierCube?, numero: String?,
                                  copyright: String, auteur: String) throws {
        try TraitementPhoto.fabriquerCopieGalerie(de: url, vers: dest, cote: cote, qualite: qualite, cube: cube,
                                                  numero: numero, copyright: copyright, auteur: auteur)
    }

    /// Essai de la console UniFi (régulateur réseau) depuis les réglages.
    public static func testerUniFi(_ c: ConfigUniFi, fini: @escaping @Sendable (Bool, String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let r = ReseauUniFi(config: c)
            let (ok, message) = r.tester()
            fini(ok, message)
        }
    }

    /// Essai de connexion : liste le dossier distant (le crée s'il manque).
    public func tester(_ fini: @escaping @Sendable (Bool, String) -> Void) {
        file.async {
            do {
                try Transfert(config: self.config).tester()
                fini(true, "Connexion réussie : le dossier « \(self.config.dossier.isEmpty ? "/" : self.config.dossier) » est accessible.")
            } catch {
                fini(false, error.localizedDescription)
            }
        }
    }

    // MARK: - Travail

    private func aFaire() -> (envoyer: [PhotoEnLigne], supprimer: [String]) {
        let envoyer = voulues.values.filter { envoyees[$0.nom] != $0.signature }.sorted { $0.nom < $1.nom }
        var supprimer = envoyees.keys.filter { voulues[$0] == nil }.sorted()
        // Garde-fou : beaucoup de photos à supprimer d'un coup (journal changé, autre Mac…) : on ne supprime rien.
        if supprimer.count > 50 && Double(supprimer.count) > Double(envoyees.count) * 0.3 {
            suppressionBloquee = supprimer.count
            supprimer = []
        } else {
            suppressionBloquee = 0
        }
        return (envoyer, supprimer)
    }

    private func majEtat() {
        let (e, s) = aFaire()
        verrou.lock()
        _etat.enLigne = envoyees.count
        _etat.aEnvoyer = e.count
        _etat.aSupprimer = s.count
        _etat.envoiEnCours = enCours
        _etat.attendLaNuit = config.laNuit && !forcer && !config.estLaNuit() && !(e.isEmpty && s.isEmpty)
        let depuis = Date().addingTimeInterval(-300)
        historique.removeAll { $0.0 < depuis }
        _etat.parMinute = Double(historique.reduce(0) { $0 + $1.1 }) / 5
        _etat.reseau = reseau?.etat
        if suppressionBloquee > 0 {
            _etat.message = "\(suppressionBloquee) photos seraient à supprimer d'un coup de la galerie en ligne : rien n'est supprimé, par sécurité."
        }
        verrou.unlock()
        garderLeMacEveille(!(e.isEmpty && s.isEmpty))
    }

    /// Tant qu'il reste des photos à mettre en ligne, le Mac ne se met pas en veille tout seul (envois de nuit).
    private func garderLeMacEveille(_ oui: Bool) {
        if oui, activite == nil {
            activite = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .suddenTerminationDisabled],
                                                              reason: "Envoi des photos vers la galerie en ligne")
        } else if !oui, let a = activite {
            ProcessInfo.processInfo.endActivity(a)
            activite = nil
        }
    }

    private func tour() {
        guard listeRecue, !enCours, Date() >= reessayerApres, !config.hote.isEmpty else { majEtat(); return }
        let (envoyer, supprimer) = aFaire()
        if envoyer.isEmpty && supprimer.isEmpty { forcer = false; majEtat(); return }
        if config.laNuit && !forcer && !config.estLaNuit() { majEtat(); return }
        // Régulateur réseau : la ligne internet est chargée par les autres (stand, iPhone…) : on attend.
        let propre = Date().timeIntervalSince(finDernierLot) < 30 ? debitPropre : 0
        if let r = reseau, r.doitAttendre(propreMbit: propre) {
            verrou.lock()
            _etat.pauseReseau = true
            _etat.message = r.etat.message
            verrou.unlock()
            reessayerApres = Date().addingTimeInterval(15)
            majEtat()
            return
        }
        verrou.lock(); _etat.pauseReseau = false; verrou.unlock()
        enCours = true
        majEtat()
        defer { enCours = false; majEtat() }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tri-photo-galerie", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        do {
            let t = Transfert(config: config)
            // 1. Suppressions (rapides, un seul lot).
            if !supprimer.isEmpty {
                let lot = Array(supprimer.prefix(200))
                try t.supprimer(lot)
                for n in lot { envoyees[n] = nil }
                sauver()
            }
            // 2. Envois, par lots de 20 sur une seule connexion.
            var lot: [(PhotoEnLigne, URL)] = []
            var manquantes: [String] = []
            for p in envoyer.prefix(GalerieEnLigne.parLot) {
                let dest = tmp.appendingPathComponent(p.nom)
                do {
                    try fabriquer(p, vers: dest)
                    lot.append((p, dest))
                } catch {
                    manquantes.append(p.nom)
                }
            }
            if !lot.isEmpty {
                let debut = Date()
                let octets = lot.reduce(0.0) { somme, element in
                    let attributs = (try? FileManager.default.attributesOfItem(atPath: element.1.path)) ?? [:]
                    return somme + ((attributs[.size] as? NSNumber)?.doubleValue ?? 0)
                }
                try t.envoyer(lot.map { ($0.1, $0.0.nom) })
                let duree = max(0.5, Date().timeIntervalSince(debut))
                debitPropre = octets * 8 / duree / 1_000_000
                finDernierLot = Date()
                for (p, _) in lot { envoyees[p.nom] = p.signature }
                historique.append((Date(), lot.count))
                sauver()
            }
            for (_, url) in lot { try? FileManager.default.removeItem(at: url) }
            // Une photo dont l'original et la copie ont disparu : on ne la redemande plus.
            for n in manquantes { voulues[n] = nil }
            echecs = 0
            verrou.lock()
            _etat.ok = true
            _etat.derniereReussite = Date()
            let reste = aFaire()
            _etat.message = reste.envoyer.isEmpty && reste.supprimer.isEmpty
                ? "Galerie en ligne à jour (\(envoyees.count) photos)."
                : "Envoi en cours : encore \(reste.envoyer.count + reste.supprimer.count) photos."
            verrou.unlock()
            // Lot suivant tout de suite tant qu'il en reste.
            if !(aFaire().envoyer.isEmpty && aFaire().supprimer.isEmpty) {
                file.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.tour() }
            }
        } catch {
            echecs += 1
            reessayerApres = Date().addingTimeInterval(min(600, 30 * Double(echecs)))
            verrou.lock()
            _etat.ok = false
            _etat.message = "Galerie en ligne : \(error.localizedDescription) Nouvel essai dans \(Int(min(600, 30 * Double(echecs)) / 60) + 1) min."
            verrou.unlock()
        }
    }

    private func sauver() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        if let d = try? enc.encode(envoyees) { try? d.write(to: config.fichierEtat, options: .atomic) }
    }

    /// La copie de la galerie : depuis l'original si on l'a, sinon depuis la copie du serveur (même .cube).
    private func fabriquer(_ p: PhotoEnLigne, vers dest: URL) throws {
        let fm = FileManager.default
        let numero = config.numero ? (p.nom as NSString).deletingPathExtension : nil
        if !p.original.isEmpty, fm.fileExists(atPath: p.original) {
            try TraitementPhoto.fabriquerCopieGalerie(de: URL(fileURLWithPath: p.original), vers: dest, cote: config.cote,
                                                      qualite: config.qualite, cube: config.cube, numero: numero,
                                                      copyright: p.copyright, auteur: p.auteur)
        } else if config.cubeDuServeur, fm.fileExists(atPath: p.copie) {
            try TraitementPhoto.fabriquerCopieGalerie(de: URL(fileURLWithPath: p.copie), vers: dest, cote: config.cote,
                                                      qualite: config.qualite, cube: nil, numero: numero,
                                                      copyright: p.copyright, auteur: p.auteur)
        } else {
            throw TraitementPhoto.Erreur.illisible(p.nom)
        }
    }
}

// MARK: - Transfert (curl pour le FTP, sftp pour le SFTP)

/// Parle au serveur avec les outils fournis avec macOS : /usr/bin/curl (FTP, FTP sur TLS) et /usr/bin/sftp (SFTP).
/// Le mot de passe ne passe jamais sur la ligne de commande (visible par les autres programmes) : curl le lit sur
/// son entrée, sftp le demande à un petit programme qui le lit dans son environnement.
struct Transfert {
    var config: ConfigGalerieEnLigne

    enum Erreur: Error, LocalizedError {
        case echec(String)
        var errorDescription: String? { if case .echec(let s) = self { return s }; return nil }
    }

    func tester() throws {
        if config.protocole == .sftp {
            try sftp(creerDossier() + ["ls -1 \(guillemets(dossierSFTP.isEmpty ? "." : dossierSFTP))"])
        } else {
            do {
                try curl(["url = \(guillemets(urlFTP(fichier: nil)))", "list-only", "output = \"/dev/null\""])
            } catch {
                // Dossier pas encore créé ? La connexion elle-même est-elle bonne ?
                guard !dossierPropre.isEmpty else { throw error }
                var racine = config
                racine.dossier = ""
                let essai = Transfert(config: racine)
                try essai.curl(["url = \(guillemets(essai.urlFTP(fichier: nil)))", "list-only", "output = \"/dev/null\""])
                throw Erreur.echec("connexion réussie, mais le dossier « \(config.dossier) » n'existe pas encore : il sera créé au premier envoi (si le serveur le permet).")
            }
        }
    }

    func envoyer(_ fichiers: [(URL, String)]) throws {
        if config.protocole == .sftp {
            try sftp(creerDossier() + fichiers.map { "put \(guillemets($0.0.path)) \(guillemets(cheminSFTP($0.1)))" })
        } else {
            var l = ["ftp-create-dirs"]
            for (local, nom) in fichiers {
                l.append("upload-file = \(guillemets(local.path))")
                l.append("url = \(guillemets(urlFTP(fichier: nom)))")
            }
            try curl(l)
        }
    }

    func supprimer(_ noms: [String]) throws {
        if config.protocole == .sftp {
            try sftp(noms.map { "-rm \(guillemets(cheminSFTP($0)))" })
        } else {
            // « * » devant : un fichier déjà absent n'arrête pas les autres.
            var l = noms.map { "quote = \(guillemets("*DELE " + cheminFTP($0)))" }
            l += ["url = \(guillemets(urlFTP(fichier: nil)))", "list-only", "output = \"/dev/null\""]
            try curl(l)
        }
    }

    // MARK: FTP

    private var dossierPropre: String {
        config.dossier.trimmingCharacters(in: .whitespaces).split(separator: "/").joined(separator: "/")
    }
    private var absolu: Bool { config.dossier.trimmingCharacters(in: .whitespaces).hasPrefix("/") }

    private func urlFTP(fichier: String?) -> String {
        let schema = config.protocole == .ftpsImplicite ? "ftps" : "ftp"
        var chemin = dossierPropre.split(separator: "/").map { encoder(String($0)) }.joined(separator: "/")
        if absolu { chemin = "%2F" + chemin }
        var u = "\(schema)://\(config.hote):\(config.portReel)/"
        if !chemin.isEmpty { u += chemin + "/" }
        if let f = fichier { u += encoder(f) }
        return u
    }

    /// Chemin pour les commandes FTP brutes (DELE), envoyées avant d'entrer dans le dossier.
    private func cheminFTP(_ nom: String) -> String {
        let d = dossierPropre
        return (absolu ? "/" : "") + (d.isEmpty ? nom : d + "/" + nom)
    }

    private func encoder(_ s: String) -> String {
        var permis = CharacterSet.urlPathAllowed
        permis.remove(charactersIn: "/;?#%")
        return s.addingPercentEncoding(withAllowedCharacters: permis) ?? s
    }

    private func curl(_ lignes: [String]) throws {
        var conf = ["silent", "show-error", "fail", "connect-timeout = 20", "retry = 2",
                    "user = \(guillemets(config.identifiant + ":" + config.motDePasse))"]
        if config.protocole == .ftpsExplicite { conf.append("ssl-reqd") }
        if config.protocole != .ftp && config.accepterCertificat { conf.append("insecure") }
        if config.limiteKo > 0 { conf.append("limit-rate = \(config.limiteKo)K") }
        conf += lignes
        let sortie = try Transfert.lancer("/usr/bin/curl", ["-K", "-"], entree: conf.joined(separator: "\n") + "\n",
                                          env: [:], delai: 900)
        if sortie.code != 0 { throw Erreur.echec(Transfert.expliquerCurl(sortie.code, sortie.texte)) }
    }

    static func expliquerCurl(_ code: Int32, _ texte: String) -> String {
        switch code {
        case 6: return "serveur introuvable (adresse ?)."
        case 7, 28: return "le serveur ne répond pas (adresse, port, réseau ?)."
        case 9: return "dossier distant refusé ou introuvable."
        case 35, 60: return "connexion sécurisée refusée (protocole ou certificat ?)."
        case 64: return "le serveur n'accepte pas le FTP sur TLS : choisis « FTP »."
        case 67: return "identifiant ou mot de passe refusé."
        case 25: return "envoi refusé par le serveur (droits ou disque plein ?)."
        default:
            let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "erreur \(code) du transfert." : t + "."
        }
    }

    // MARK: SFTP

    private var dossierSFTP: String { (absolu ? "/" : "") + dossierPropre }
    private func cheminSFTP(_ nom: String) -> String { dossierSFTP.isEmpty ? nom : dossierSFTP + "/" + nom }

    /// « -mkdir a », « -mkdir a/b »… (un « - » devant : déjà là, ce n'est pas une erreur).
    private func creerDossier() -> [String] {
        var l: [String] = []
        var courant = absolu ? "/" : ""
        for morceau in dossierPropre.split(separator: "/") {
            courant += (courant.isEmpty || courant == "/" ? "" : "/") + morceau
            l.append("-mkdir \(guillemets(courant))")
        }
        return l
    }

    private func sftp(_ commandes: [String]) throws {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tri-photo")
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        let demande = base.appendingPathComponent("demande-mot-de-passe.sh")
        if !fm.fileExists(atPath: demande.path) {
            try "#!/bin/sh\nprintf '%s\\n' \"$TRIPHOTO_MDP\"\n".write(to: demande, atomically: true, encoding: .utf8)
        }
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: demande.path)
        let lot = fm.temporaryDirectory.appendingPathComponent("tri-photo-sftp-\(UUID().uuidString).txt")
        try commandes.joined(separator: "\n").appending("\n").write(to: lot, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: lot) }
        // BatchMode=no AVANT -b, sinon sftp interdit toute demande de mot de passe.
        var args = ["-o", "BatchMode=no", "-o", "StrictHostKeyChecking=accept-new",
                    "-o", "UserKnownHostsFile=\(base.appendingPathComponent("galerie-serveurs-connus").path)",
                    "-o", "PreferredAuthentications=password,keyboard-interactive",
                    "-o", "NumberOfPasswordPrompts=1", "-o", "ConnectTimeout=20",
                    "-P", "\(config.portReel)"]
        if config.limiteKo > 0 { args += ["-l", "\(config.limiteKo * 8)"] }
        args += ["-b", lot.path, "\(config.identifiant)@\(config.hote)"]
        let sortie = try Transfert.lancer("/usr/bin/sftp", args, entree: nil,
                                          env: ["SSH_ASKPASS": demande.path, "SSH_ASKPASS_REQUIRE": "force",
                                                "DISPLAY": ":0", "TRIPHOTO_MDP": config.motDePasse], delai: 900)
        if sortie.code != 0 {
            let t = sortie.texte.lowercased()
            if t.contains("permission denied") { throw Erreur.echec("identifiant ou mot de passe refusé.") }
            if t.contains("host key verification failed") || t.contains("remote host identification has changed") {
                throw Erreur.echec("la clé du serveur SFTP a changé : vérifie que c'est bien ton serveur.")
            }
            if t.contains("could not resolve") { throw Erreur.echec("serveur introuvable (adresse ?).") }
            if t.contains("timed out") || t.contains("connection refused") {
                throw Erreur.echec("le serveur ne répond pas (adresse, port, réseau ?).")
            }
            let derniere = sortie.texte.split(separator: "\n").last.map(String.init) ?? "erreur \(sortie.code)"
            throw Erreur.echec(derniere + ".")
        }
    }

    // MARK: Outils

    /// Entre guillemets pour la configuration de curl et les lots de sftp (\ et " protégés).
    private func guillemets(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Lance un outil en priorité basse et attend sa fin (au plus `delai` secondes).
    static func lancer(_ outil: String, _ args: [String], entree: String?, env: [String: String],
                       delai: TimeInterval) throws -> (code: Int32, texte: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: outil)
        p.arguments = args
        var e = ProcessInfo.processInfo.environment
        for (k, v) in env { e[k] = v }
        p.environment = e
        p.qualityOfService = .utility
        let erreurs = Pipe()
        p.standardError = erreurs
        p.standardOutput = FileHandle.nullDevice
        let tuyau = Pipe()
        p.standardInput = entree == nil ? FileHandle.nullDevice : tuyau
        let fini = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in fini.signal() }
        let lu = Lu()
        let groupe = DispatchGroup()
        groupe.enter()
        DispatchQueue.global(qos: .utility).async {
            lu.donnees = erreurs.fileHandleForReading.readDataToEndOfFile()
            groupe.leave()
        }
        try p.run()
        if let entree {
            tuyau.fileHandleForWriting.write(Data(entree.utf8))
            try? tuyau.fileHandleForWriting.close()
        }
        if fini.wait(timeout: .now() + delai) == .timedOut {
            p.terminate()
            _ = fini.wait(timeout: .now() + 5)
            throw Erreur.echec("transfert trop long, arrêté.")
        }
        _ = groupe.wait(timeout: .now() + 5)
        return (p.terminationStatus, String(decoding: lu.donnees, as: UTF8.self))
    }

    private final class Lu: @unchecked Sendable { var donnees = Data() }
}

// MARK: - La copie de la galerie

extension TraitementPhoto {
    /// Copie pour la galerie en ligne : redressée, côté le plus long = cote, .cube, sRGB, numéro de la photo
    /// incrusté en haut à gauche, et seulement le copyright (le code) et l'auteur. L'original n'est pas touché.
    static func fabriquerCopieGalerie(de url: URL, vers final: URL, cote: Int, qualite: Int, cube: FichierCube?,
                                      numero: String?, copyright: String, auteur: String) throws {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw Erreur.illisible(url.lastPathComponent) }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: cote,
                                     kCGImageSourceShouldCacheImmediately: false]
        guard let petite = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        else { throw Erreur.illisible(url.lastPathComponent) }
        var image = CIImage(cgImage: petite)
        if let cube {
            let filtre = CIFilter(name: "CIColorCubeWithColorSpace")!
            filtre.setValue(cube.taille, forKey: "inputCubeDimension")
            filtre.setValue(cube.valeurs.withUnsafeBufferPointer { Data(buffer: $0) }, forKey: "inputCubeData")
            filtre.setValue(srgb, forKey: "inputColorSpace")
            filtre.setValue(image, forKey: kCIInputImageKey)
            if let sortie = filtre.outputImage { image = sortie }
        }
        guard var rendu = contexte.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: srgb)
        else { throw Erreur.ecriture("rendu de \(url.lastPathComponent)") }
        if let numero, !numero.isEmpty, let avecNumero = incruster(numero, sur: rendu) { rendu = avecNumero }

        var tiff: [CFString: Any] = [:]
        var iptc: [CFString: Any] = [:]
        if !copyright.isEmpty {
            tiff[kCGImagePropertyTIFFCopyright] = copyright
            iptc[kCGImagePropertyIPTCCopyrightNotice] = copyright
        }
        if !auteur.isEmpty {
            tiff[kCGImagePropertyTIFFArtist] = auteur
            iptc[kCGImagePropertyIPTCByline] = [auteur]
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: Double(qualite) / 100,
                                      kCGImagePropertyTIFFDictionary: tiff,
                                      kCGImagePropertyIPTCDictionary: iptc]
        try ecrireSansJamaisDemiFichier(final) { provisoire in
            guard let dest = CGImageDestinationCreateWithURL(provisoire as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
            else { throw Erreur.ecriture(provisoire.path) }
            CGImageDestinationAddImage(dest, rendu, props as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw Erreur.ecriture(final.path) }
        }
    }

    /// Le numéro en blanc sur un cartouche sombre, en haut à gauche (hauteur ≈ 3,5 % de l'image).
    static func incruster(_ texte: String, sur image: CGImage) -> CGImage? {
        let l = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: l, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: l, height: h))
        let taille = max(14, CGFloat(min(l, h)) * 0.045)
        let police = CTFontCreateWithName("Helvetica-Bold" as CFString, taille, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): police,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        ]
        let ligne = CTLineCreateWithAttributedString(NSAttributedString(string: texte, attributes: attrs))
        let largeur = CTLineGetTypographicBounds(ligne, nil, nil, nil)
        let marge = taille * 0.5
        let cadre = CGRect(x: marge, y: CGFloat(h) - marge - taille * 1.5, width: CGFloat(largeur) + taille, height: taille * 1.5)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
        ctx.addPath(CGPath(roundedRect: cadre, cornerWidth: taille * 0.25, cornerHeight: taille * 0.25, transform: nil))
        ctx.fillPath()
        ctx.textPosition = CGPoint(x: cadre.minX + taille * 0.5, y: cadre.minY + taille * 0.42)
        CTLineDraw(ligne, ctx)
        return ctx.makeImage()
    }
}

extension GalerieEnLigne {
    /// Dépose un seul fichier par la connexion choisie (FTP, FTP sur TLS, SFTP), dans `config.dossier`.
    /// Dépôt d’un fichier isolé par la même connexion.
    public static func deposer(_ local: URL, nom: String, config: ConfigGalerieEnLigne) throws {
        try Transfert(config: config).envoyer([(local, nom)])
    }

    /// Essaie la connexion (même test que « Tester la connexion » de la galerie).
    public static func testerConnexion(_ config: ConfigGalerieEnLigne) throws {
        try Transfert(config: config).tester()
    }
}
