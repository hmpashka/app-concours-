import CryptoKit
import Foundation
import TriPhotoCommun

// « Au bureau » › Envoyer un concours sur le NAS (demande HUGO 26/11/2026) : remplace les copier-coller et FileZilla
// pour mettre les concours sur le NAS quand HUGO le décide.
//
// Règles (validées par HUGO) :
// - fiable comme FileZilla : coupure réseau, NAS débranché, app quittée, Mac redémarré → on reprend à la photo où
//   l'on s'était arrêté. Chaque fichier est écrit sous un nom caché provisoire (« .NOM.part ») puis renommé : jamais
//   de photo à moitié copiée sur le NAS ;
// - chaque fichier est relu sur le NAS et comparé (empreinte SHA-256) à l'original ;
// - doublon = MÊME dossier, même nom, même contenu : pas renvoyé. La même photo dans un AUTRE dossier : on garde les
//   deux. Même dossier et même nom mais contenu différent : « À décider » (garder les deux, remplacer, ne pas envoyer) ;
// - rien n'est jamais effacé du Mac ni écrasé sur le NAS tout seul.

/// Un concours à envoyer sur le NAS.
public struct TacheEnvoi: Codable, Sendable, Identifiable, Equatable {
    public enum Etat: String, Codable, Sendable {
        case attente = "En attente", enCours = "En cours", fini = "Fini", arrete = "Arrêté"
    }

    public var id: String
    /// Dossier du concours sur le Mac.
    public var source: String
    /// Dossier de l'année sur le NAS (« /Volumes/hmphotographie/CONCOURS 2026 »).
    public var annee: String
    /// Nom du dossier créé dans l'année (le nom du dossier du concours).
    public var nom: String
    /// Fichier CSV d'attribution à joindre (posé à la racine du dossier du concours sur le NAS), nil : aucun.
    public var csv: String?
    public var verifier: Bool
    public var creeLe: Date
    public var finiLe: Date?
    public var etat: Etat
    /// Les photos du Mac sont parties à la Corbeille (« Libérer la place », au clic de HUGO).
    public var placeLiberee: Bool

    public init(source: URL, annee: URL, csv: URL? = nil, verifier: Bool = true) {
        id = UUID().uuidString
        self.source = source.path
        self.annee = annee.path
        nom = source.lastPathComponent
        self.csv = csv?.path
        self.verifier = verifier
        creeLe = Date()
        etat = .attente
        placeLiberee = false
    }

    public var urlSource: URL { URL(fileURLWithPath: source, isDirectory: true) }
    public var urlAnnee: URL { URL(fileURLWithPath: annee, isDirectory: true) }
    public var destination: URL { urlAnnee.appendingPathComponent(nom, isDirectory: true) }
}

/// Un fichier d'un envoi.
public struct FichierEnvoi: Codable, Sendable, Equatable, Identifiable {
    public enum Etat: String, Codable, Sendable {
        case aFaire, envoye, verifie, dejaLa, aDecider, erreur, ignore
    }
    public enum Choix: String, Codable, Sendable { case garderLesDeux, remplacer, nePasEnvoyer }

    /// Chemin dans le dossier du concours (« 04_CLUB 2/R3CR4410.JPG ») ; le CSV joint : son nom seul.
    public var chemin: String
    public var taille: Int64
    public var etat: Etat
    public var message = ""
    /// Nom donné sur le NAS quand ce n'est pas le même (« garder les deux » : « R3CR4410-2.JPG »).
    public var nomSurNAS: String?
    /// HUGO a choisi « remplacer » la photo différente du NAS.
    public var remplacer = false
    /// Le CSV joint (pris ailleurs que dans le dossier du concours).
    public var horsDossier: String?
    public var id: String { chemin }

    /// Dossier de premier niveau (l'épreuve), vide pour un fichier à la racine du concours.
    public var epreuve: String {
        let p = chemin.split(separator: "/")
        return p.count > 1 ? String(p[0]) : ""
    }
}

/// Où en est un envoi, en chiffres.
public struct BilanEnvoi: Sendable, Equatable {
    public struct Epreuve: Sendable, Equatable, Identifiable {
        public var nom: String
        public var total = 0, envoyes = 0, verifies = 0, aDecider = 0, erreurs = 0
        public var id: String { nom }
        public var fini: Bool { envoyes + aDecider + erreurs >= total }
    }
    public var total = 0, envoyes = 0, verifies = 0, dejaLa = 0, aDecider = 0, erreurs = 0, ignores = 0
    public var octetsTotal: Int64 = 0, octetsFaits: Int64 = 0
    public var epreuves: [Epreuve] = []

    public init(_ fichiers: [FichierEnvoi]) {
        var parEpreuve: [String: Epreuve] = [:]
        var ordre: [String] = []
        for f in fichiers {
            total += 1
            octetsTotal += f.taille
            let ep = f.epreuve.isEmpty ? "(à la racine du concours)" : f.epreuve
            if parEpreuve[ep] == nil { parEpreuve[ep] = Epreuve(nom: ep); ordre.append(ep) }
            parEpreuve[ep]!.total += 1
            switch f.etat {
            case .envoye: envoyes += 1; octetsFaits += f.taille; parEpreuve[ep]!.envoyes += 1
            case .verifie: envoyes += 1; verifies += 1; octetsFaits += f.taille
                parEpreuve[ep]!.envoyes += 1; parEpreuve[ep]!.verifies += 1
            case .dejaLa: dejaLa += 1; envoyes += 1; verifies += 1; octetsFaits += f.taille
                parEpreuve[ep]!.envoyes += 1; parEpreuve[ep]!.verifies += 1
            case .aDecider: aDecider += 1; parEpreuve[ep]!.aDecider += 1
            case .erreur: erreurs += 1; parEpreuve[ep]!.erreurs += 1
            case .ignore: ignores += 1; envoyes += 1; parEpreuve[ep]!.envoyes += 1
            case .aFaire: break
            }
        }
        epreuves = ordre.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.compactMap { parEpreuve[$0] }
    }

    public var resteAFaire: Int { total - envoyes - aDecider - erreurs }
    /// Tout est sur le NAS et vérifié : on peut libérer la place sur le Mac.
    public var toutVerifie: Bool { total > 0 && verifies == total }
}

/// L'envoi en tâche de fond : un concours après l'autre, un fichier à la fois.
public final class EnvoyeurNAS: @unchecked Sendable {
    public enum Reseau: Equatable, Sendable {
        case ok
        case coupe(depuis: Date, prochainEssai: Date)
        case attenteNuit
        case pause
    }

    public struct Avancee: Sendable {
        public var tache: TacheEnvoi
        public var fichier: String
        public var reseau: Reseau
        public var debit: Double             // octets par seconde (moyenne récente)
    }

    /// Où ranger l'état des envois (Application Support › Tri-photo › Au bureau › Envois).
    public let dossier: URL
    /// Appelé depuis le fil d'envoi (au plus 4 fois par seconde, et à chaque fin de fichier important).
    public var surAvancee: ((Avancee) -> Void)?
    /// Appelé quand un concours est fini (pour mettre l'index des archives à jour).
    public var surFin: ((TacheEnvoi) -> Void)?

    private let verrou = NSRecursiveLock()
    private var _taches: [TacheEnvoi] = []
    private var _fichiers: [String: [FichierEnvoi]] = [:]
    private var enMarche = false
    private var _pause = false
    private var _arret = false
    private var _debitMax: Double = 30_000_000
    private var _seulementLaNuit = false
    /// Attente entre deux essais quand le réseau est coupé (secondes).
    public var attenteReseau: TimeInterval = 30

    public init(dossier: URL) {
        self.dossier = dossier
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let d = try? Data(contentsOf: dossier.appendingPathComponent("envois.json")),
           let t = try? dec.decode([TacheEnvoi].self, from: d) {
            _taches = t
            for x in t {
                if let d = try? Data(contentsOf: fichierEtat(x.id)), let f = try? dec.decode([FichierEnvoi].self, from: d) {
                    _fichiers[x.id] = f
                }
            }
        }
        // un envoi « en cours » quand l'app s'est arrêtée reprendra au prochain lancement
        for i in _taches.indices where _taches[i].etat == .enCours { _taches[i].etat = .attente }
    }

    private func fichierEtat(_ id: String) -> URL { dossier.appendingPathComponent("envoi-\(id).json") }

    // MARK: - Réglages et commandes (depuis l'écran)

    public var debitMax: Double {
        get { verrou.lock(); defer { verrou.unlock() }; return _debitMax }
        set { verrou.lock(); _debitMax = newValue; verrou.unlock() }
    }
    public var seulementLaNuit: Bool {
        get { verrou.lock(); defer { verrou.unlock() }; return _seulementLaNuit }
        set { verrou.lock(); _seulementLaNuit = newValue; verrou.unlock() }
    }
    public var enPause: Bool {
        get { verrou.lock(); defer { verrou.unlock() }; return _pause }
        set { verrou.lock(); _pause = newValue; verrou.unlock() }
    }
    public var occupe: Bool { verrou.lock(); defer { verrou.unlock() }; return enMarche }

    public var taches: [TacheEnvoi] { verrou.lock(); defer { verrou.unlock() }; return _taches }
    public func fichiers(_ id: String) -> [FichierEnvoi] { verrou.lock(); defer { verrou.unlock() }; return _fichiers[id] ?? [] }

    private func garder() {
        verrou.lock(); defer { verrou.unlock() }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(_taches) { try? d.write(to: dossier.appendingPathComponent("envois.json"), options: .atomic) }
    }

    private func garderFichiers(_ id: String) {
        verrou.lock(); defer { verrou.unlock() }
        if let d = try? JSONEncoder().encode(_fichiers[id] ?? []) { try? d.write(to: fichierEtat(id), options: .atomic) }
    }

    private func modifierTache(_ id: String, _ m: (inout TacheEnvoi) -> Void) {
        verrou.lock()
        if let i = _taches.firstIndex(where: { $0.id == id }) { m(&_taches[i]) }
        verrou.unlock()
        garder()
    }

    private func modifierFichier(_ id: String, _ chemin: String, _ m: (inout FichierEnvoi) -> Void) {
        verrou.lock()
        if let i = _fichiers[id]?.firstIndex(where: { $0.chemin == chemin }) { m(&_fichiers[id]![i]) }
        verrou.unlock()
    }

    /// Ajoute des concours à la file (un concours déjà dans la file, pas encore fini, n'est pas ajouté deux fois).
    public func ajouter(_ t: [TacheEnvoi]) {
        verrou.lock()
        for x in t where !_taches.contains(where: { $0.source == x.source && $0.annee == x.annee && $0.etat != .fini }) {
            _taches.append(x)
        }
        verrou.unlock()
        garder()
        lancer()
    }

    /// Reprend un envoi arrêté ou fini (refait la liste : seules les photos nouvelles partent).
    public func reprendre(_ id: String) {
        modifierTache(id) { $0.etat = .attente }
        lancer()
    }

    /// Arrête un envoi (ce qui est envoyé reste ; on pourra le reprendre).
    public func arreter(_ id: String) {
        verrou.lock()
        if let i = _taches.firstIndex(where: { $0.id == id }), _taches[i].etat != .fini {
            if _taches[i].etat == .enCours { _arret = true }      // le fil s'arrête au prochain morceau
            _taches[i].etat = .arrete
        }
        verrou.unlock()
        garder()
    }

    /// Retire un envoi de l'historique (rien n'est effacé, ni sur le Mac ni sur le NAS).
    public func oublier(_ id: String) {
        verrou.lock()
        _taches.removeAll { $0.id == id && $0.etat != .enCours }
        _fichiers[id] = nil
        verrou.unlock()
        try? FileManager.default.removeItem(at: fichierEtat(id))
        garder()
    }

    /// Le choix de HUGO pour une photo « À décider ».
    public func decider(_ id: String, chemin: String, _ choix: FichierEnvoi.Choix) {
        modifierFichier(id, chemin) { f in
            switch choix {
            case .garderLesDeux: f.etat = .aFaire; f.remplacer = false; f.nomSurNAS = nil; f.message = "garder les deux"
            case .remplacer: f.etat = .aFaire; f.remplacer = true; f.message = "remplacer"
            case .nePasEnvoyer: f.etat = .ignore; f.message = "pas envoyée (choix)"
            }
        }
        garderFichiers(id)
        if choix != .nePasEnvoyer {
            verrou.lock()
            if let i = _taches.firstIndex(where: { $0.id == id }), _taches[i].etat == .fini { _taches[i].etat = .attente }
            verrou.unlock()
            garder()
            lancer()
        }
    }

    /// « Libérer la place sur le Mac » : seulement si tout est sur le NAS et vérifié. Le dossier du concours part à
    /// la Corbeille du Mac (on peut l'y reprendre).
    public func libererLaPlace(_ id: String) throws {
        guard let t = taches.first(where: { $0.id == id }) else { return }
        guard BilanEnvoi(fichiers(id)).toutVerifie else {
            throw NSError(domain: "EnvoiNAS", code: 2, userInfo: [NSLocalizedDescriptionKey: "Tout n'est pas encore vérifié sur le NAS."])
        }
        try FileManager.default.trashItem(at: t.urlSource, resultingItemURL: nil)
        modifierTache(id) { $0.placeLiberee = true }
    }

    // MARK: - Le fil d'envoi

    public func lancer() {
        verrou.lock()
        let demarrer = !enMarche
        if demarrer { enMarche = true; _arret = false }
        verrou.unlock()
        guard demarrer else { return }
        let t = Thread { [weak self] in self?.boucle() }
        t.qualityOfService = .utility
        t.name = "Envoi sur le NAS"
        t.start()
    }

    private func prochaine() -> TacheEnvoi? {
        verrou.lock(); defer { verrou.unlock() }
        _arret = false
        guard let i = _taches.firstIndex(where: { $0.etat == .attente }) else { enMarche = false; return nil }
        _taches[i].etat = .enCours
        return _taches[i]
    }

    private var arretDemande: Bool { verrou.lock(); defer { verrou.unlock() }; return _arret }

    private func boucle() {
        while let t = prochaine() {
            garder()
            envoyer(t)
        }
    }

    /// Fait l'envoi dans le fil appelant (outil d'essai, tests).
    public func envoyerIci(_ id: String) {
        verrou.lock()
        guard let i = _taches.firstIndex(where: { $0.id == id }) else { verrou.unlock(); return }
        _taches[i].etat = .enCours
        let t = _taches[i]
        verrou.unlock()
        envoyer(t)
    }

    private var dernierSignal = Date.distantPast
    private var octetsRecents: [(Date, Int)] = []
    private func signaler(_ t: TacheEnvoi, _ fichier: String, _ r: Reseau, forcer: Bool = false) {
        guard forcer || Date().timeIntervalSince(dernierSignal) > 0.25 else { return }
        dernierSignal = Date()
        let maintenant = Date()
        octetsRecents.removeAll { maintenant.timeIntervalSince($0.0) > 5 }
        let debit = Double(octetsRecents.reduce(0) { $0 + $1.1 }) / 5
        let actuelle = taches.first { $0.id == t.id } ?? t
        surAvancee?(Avancee(tache: actuelle, fichier: fichier, reseau: r, debit: debit))
    }

    /// Pause et « seulement la nuit ». Rend faux si on doit arrêter.
    private func attendreSiBesoin(_ t: TacheEnvoi) -> Bool {
        while !arretDemande {
            if enPause { signaler(t, "", .pause, forcer: true); Thread.sleep(forTimeInterval: 1); continue }
            if seulementLaNuit {
                let h = Calendar.current.component(.hour, from: Date())
                if !(h >= 22 || h < 7) { signaler(t, "", .attenteNuit, forcer: true); Thread.sleep(forTimeInterval: 30); continue }
            }
            return true
        }
        return false
    }

    private enum Arret: Error { case demande }

    private func envoyer(_ t: TacheEnvoi) {
        let fm = FileManager.default
        // 1. La liste des fichiers du concours (sur le Mac), fusionnée avec ce qui est déjà fait.
        var liste: [FichierEnvoi] = []
        let deja = Dictionary(fichiers(t.id).map { ($0.chemin, $0) }, uniquingKeysWith: { a, _ in a })
        if let e = fm.enumerator(at: t.urlSource, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                 options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            let base = t.urlSource.standardizedFileURL.path
            for case let u as URL in e {
                guard let v = try? u.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), v.isRegularFile == true else { continue }
                var rel = u.standardizedFileURL.path
                if rel.hasPrefix(base) { rel = String(rel.dropFirst(base.count)) }
                while rel.hasPrefix("/") { rel.removeFirst() }
                let taille = Int64(v.fileSize ?? 0)
                if var f = deja[rel] {
                    // fichier changé sur le Mac depuis l'envoi : il repart
                    if f.taille != taille, f.etat != .aDecider { f = FichierEnvoi(chemin: rel, taille: taille, etat: .aFaire) }
                    else if f.etat == .erreur { f.etat = .aFaire; f.message = "" }
                    liste.append(f)
                } else {
                    liste.append(FichierEnvoi(chemin: rel, taille: taille, etat: .aFaire))
                }
            }
        }
        if let csv = t.csv {
            let u = URL(fileURLWithPath: csv)
            let nom = u.lastPathComponent
            if !liste.contains(where: { $0.chemin == nom }) {
                let taille = Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                var f = deja[nom] ?? FichierEnvoi(chemin: nom, taille: taille, etat: .aFaire)
                if f.etat == .erreur { f.etat = .aFaire }
                f.horsDossier = csv
                liste.append(f)
            }
        }
        liste.sort { $0.chemin.localizedStandardCompare($1.chemin) == .orderedAscending }
        verrou.lock(); _fichiers[t.id] = liste; verrou.unlock()
        garderFichiers(t.id)
        signaler(t, "", .ok, forcer: true)

        // 2. Un fichier à la fois.
        var depuisSauvegarde = 0
        for f0 in liste where f0.etat == .aFaire {
            guard attendreSiBesoin(t) else { break }
            var essais = 0
            while true {
                guard attendreSiBesoin(t) else { break }
                do {
                    try envoyerUn(t, f0)
                    break
                } catch Arret.demande {
                    break
                } catch {
                    // NAS injoignable : on attend et on réessaie le même fichier, sans fin (comme FileZilla)
                    if !fm.fileExists(atPath: t.annee) {
                        let depuis = Date()
                        while !fm.fileExists(atPath: t.annee) && !arretDemande {
                            signaler(t, f0.chemin, .coupe(depuis: depuis, prochainEssai: Date().addingTimeInterval(attenteReseau)), forcer: true)
                            Thread.sleep(forTimeInterval: attenteReseau)
                        }
                        continue
                    }
                    essais += 1
                    if essais >= 3 {
                        modifierFichier(t.id, f0.chemin) { $0.etat = .erreur; $0.message = error.localizedDescription }
                        break
                    }
                    Thread.sleep(forTimeInterval: 2)
                }
            }
            if arretDemande { break }
            depuisSauvegarde += 1
            if depuisSauvegarde >= 10 { garderFichiers(t.id); depuisSauvegarde = 0 }
            signaler(t, f0.chemin, .ok)
        }
        garderFichiers(t.id)

        // 3. Fin du concours (ou arrêt).
        let bilan = BilanEnvoi(fichiers(t.id))
        if arretDemande || taches.first(where: { $0.id == t.id })?.etat == .arrete {
            modifierTache(t.id) { $0.etat = .arrete }
        } else if bilan.resteAFaire == 0 {
            modifierTache(t.id) { $0.etat = .fini; $0.finiLe = Date() }
            if let fin = taches.first(where: { $0.id == t.id }) { surFin?(fin) }
        } else {
            // des photos « À décider » ont été tranchées pendant l'envoi : un tour de plus
            modifierTache(t.id) { $0.etat = .attente }
        }
        signaler(t, "", .ok, forcer: true)
    }

    /// Envoie un fichier (ou constate qu'il est déjà là). Lance une erreur si le disque ou le réseau ne répond pas.
    private func envoyerUn(_ t: TacheEnvoi, _ f: FichierEnvoi) throws {
        let fm = FileManager.default
        let source = f.horsDossier.map { URL(fileURLWithPath: $0) } ?? t.urlSource.appendingPathComponent(f.chemin)
        guard fm.fileExists(atPath: source.path) else {
            modifierFichier(t.id, f.chemin) { $0.etat = .erreur; $0.message = "plus sur le Mac" }
            return
        }
        guard fm.fileExists(atPath: t.annee) else { throw CocoaError(.fileNoSuchFile) }
        let dossierCible = t.destination.appendingPathComponent((f.chemin as NSString).deletingLastPathComponent, isDirectory: true)
        try fm.createDirectory(at: dossierCible, withIntermediateDirectories: true)
        var nomFinal = f.nomSurNAS ?? (f.chemin as NSString).lastPathComponent
        var cible = dossierCible.appendingPathComponent(nomFinal)

        if fm.fileExists(atPath: cible.path) && !f.remplacer {
            if f.message == "garder les deux" && f.nomSurNAS == nil {
                // « garder les deux » : un nom libre « NOM-2.JPG »
                let base = (nomFinal as NSString).deletingPathExtension, ext = (nomFinal as NSString).pathExtension
                var n = 2
                repeat {
                    nomFinal = ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)"
                    cible = dossierCible.appendingPathComponent(nomFinal)
                    n += 1
                } while fm.fileExists(atPath: cible.path)
                modifierFichier(t.id, f.chemin) { $0.nomSurNAS = nomFinal }
            } else {
                // même dossier, même nom : même contenu → doublon, rien à faire ; sinon c'est HUGO qui décide
                let tailleNAS = (try? fm.attributesOfItem(atPath: cible.path)[.size] as? Int64) ?? -1
                if tailleNAS == f.taille, try EnvoyeurNAS.empreinte(source) == EnvoyeurNAS.empreinte(cible, controle: { !self.arretDemande }) {
                    modifierFichier(t.id, f.chemin) { $0.etat = .dejaLa; $0.message = "" }
                } else {
                    modifierFichier(t.id, f.chemin) { $0.etat = .aDecider; $0.message = "même nom sur le NAS, photo différente" }
                }
                return
            }
        }

        // copie dans un fichier caché provisoire, puis renommage : jamais de fichier à moitié copié sur le NAS
        let part = dossierCible.appendingPathComponent("." + nomFinal + ".part")
        if fm.fileExists(atPath: part.path) { try fm.removeItem(at: part) }       // reste d'un envoi coupé : il est à nous
        let hSource = try copier(source, vers: part, t: t, nomFichier: f.chemin)
        if f.remplacer && fm.fileExists(atPath: cible.path) {
            _ = try fm.replaceItemAt(cible, withItemAt: part)
        } else {
            try fm.moveItem(at: part, to: cible)
        }
        modifierFichier(t.id, f.chemin) { $0.etat = .envoye; $0.message = "" }
        if t.verifier {
            let hNAS = try EnvoyeurNAS.empreinte(cible, controle: { !self.arretDemande })
            if hNAS == hSource {
                modifierFichier(t.id, f.chemin) { $0.etat = .verifie }
            } else {
                try? fm.removeItem(at: cible)                // c'est notre copie, ratée : on la refait
                modifierFichier(t.id, f.chemin) { $0.etat = .aFaire }
                throw NSError(domain: "EnvoiNAS", code: 3, userInfo: [NSLocalizedDescriptionKey: "Copie différente de l'original"])
            }
        }
    }

    /// Copie par morceaux (pause, arrêt et débit doux possibles) et rend l'empreinte de l'original.
    private func copier(_ source: URL, vers part: URL, t: TacheEnvoi, nomFichier: String) throws -> SHA256.Digest {
        let fm = FileManager.default
        guard fm.createFile(atPath: part.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let lire = try FileHandle(forReadingFrom: source)
        defer { try? lire.close() }
        let ecrire = try FileHandle(forWritingTo: part)
        var ferme = false
        defer { if !ferme { try? ecrire.close() } }
        var h = SHA256()
        let debut = Date()
        var total = 0
        while true {
            if arretDemande { try? ecrire.close(); ferme = true; try? fm.removeItem(at: part); throw Arret.demande }
            while enPause && !arretDemande { Thread.sleep(forTimeInterval: 0.5) }
            guard let morceau = try lire.read(upToCount: 1 << 20), !morceau.isEmpty else { break }
            h.update(data: morceau)
            try ecrire.write(contentsOf: morceau)
            total += morceau.count
            verrou.lock(); octetsRecents.append((Date(), morceau.count)); verrou.unlock()
            let max = debitMax
            if max > 0 {
                let avance = Double(total) / max - Date().timeIntervalSince(debut)
                if avance > 0 { Thread.sleep(forTimeInterval: min(avance, 2)) }
            }
            signaler(t, nomFichier, .ok)
        }
        try ecrire.synchronize()
        try ecrire.close()
        ferme = true
        return h.finalize()
    }

    /// Empreinte SHA-256 d'un fichier, lu par morceaux.
    static func empreinte(_ u: URL, controle: () -> Bool = { true }) throws -> SHA256.Digest {
        let fh = try FileHandle(forReadingFrom: u)
        defer { try? fh.close() }
        var h = SHA256()
        while let m = try fh.read(upToCount: 1 << 20), !m.isEmpty {
            guard controle() else { throw Arret.demande }
            h.update(data: m)
        }
        return h.finalize()
    }
}
