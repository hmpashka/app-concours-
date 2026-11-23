import Combine
import Foundation
import TriPhotoCommun

/// Ce dont le moteur a besoin, figé au démarrage de la journée.
public struct ConfigMoteur {
    public var reception: URL
    public var importLightroom: URL
    public var tampon: URL?               // nil : pas de dossier tampon
    public var serveur: URL
    public var cote: Int
    public var qualite: Int
    public var cube: FichierCube?
    public var concours: Concours?
    public var tailleLot: Int
    public var silenceMinutes: Int
    public var retarderSiOccupe: Bool
    public var journal: URL        // fichier du journal (base SQLite)

    public init(reception: URL, importLightroom: URL, tampon: URL?, serveur: URL, cote: Int, qualite: Int,
                cube: FichierCube?, concours: Concours?, tailleLot: Int, silenceMinutes: Int,
                retarderSiOccupe: Bool, journal: URL) {
        self.reception = reception
        self.importLightroom = importLightroom
        self.tampon = tampon
        self.serveur = serveur
        self.cote = cote
        self.qualite = qualite
        self.cube = cube
        self.concours = concours
        self.tailleLot = tailleLot
        self.silenceMinutes = silenceMinutes
        self.retarderSiOccupe = retarderSiOccupe
        self.journal = journal
    }
}

/// Résumé affiché sur l'accueil, recalculé chaque seconde.
public struct ResumeMoteur {
    public struct Boitier: Identifiable {
        public var id: String { nom }
        public var nom: String
        public var photos: Int
        public var derniere: Date?
    }
    public struct Recente: Identifiable {
        public var id: Int64
        public var nom: String
        public var code: String
        public var boitier: String
        public var etat: EtatPhoto
    }

    public var recues = 0
    public var parMinute = 0.0
    public var enFile = 0
    public var retardSecondes = 0.0
    public var aRenvoyer: [FichePhoto] = []
    public var doublons: [FichePhoto] = []
    public var enErreur = 0
    public var derniereErreur = ""
    public var dansTampon = 0
    public var boitiers: [Boitier] = []
    public var recentes: [Recente] = []
    public var chargeLightroom = 0.0
    public var ouvriers = 3
    public var message = ""

    public init() {}
}

/// Le moteur photos (étape 1) : surveille le dossier de réception et, pour chaque photo :
/// contrôle → renommage → copie .cube vers le serveur local → IPTC dans l'original → import Lightroom.
///
/// Tout tourne en priorité basse (« utility », comme au test de vitesse), 1 à 3 photos à la fois selon le
/// travail de Lightroom. Le journal note chaque étape : après un plantage, on reprend là où on en était.
public final class Moteur: ObservableObject {
    public init() {}

    @Published public private(set) var actif = false
    @Published public private(set) var resume = ResumeMoteur()

    private let file = DispatchQueue(label: "tri-photo.moteur", qos: .utility)
    private let ouvriers: OperationQueue = {
        let q = OperationQueue()
        q.name = "tri-photo.ouvriers"
        q.qualityOfService = .utility
        q.maxConcurrentOperationCount = 3
        return q
    }()
    private let regulateur = Regulateur()

    // Tout ce qui suit n'est touché que depuis `file`.
    private var config: ConfigMoteur?
    private var journal: Journal?
    private var minuterie: DispatchSourceTimer?
    private var tailles: [String: UInt64] = [:]        // taille vue au tour précédent (fichier en cours d'arrivée ?)
    private var enCours: Set<String> = []
    private var reessayerApres: [String: Date] = [:]
    private var vuesEnAttente: [String: Date] = [:]    // première fois qu'une photo a été vue (pour le retard)
    private var charge = 0.0
    private var debutJournee = Calendar.current.startOfDay(for: Date())
    private var message = ""

    public static let dossierARenvoyer = "_À renvoyer"
    public static let dossierAAttribuer = "À attribuer"
    public static let dossierDoublons = "_Doublons"
    static let doublonAccepte = "Doublon accepté par HUGO"

    // MARK: - Démarrer / arrêter

    public func demarrer(_ c: ConfigMoteur) throws {
        let j = try Journal(fichier: c.journal)
        file.sync {
            self.config = c
            self.journal = j
            self.debutJournee = Calendar.current.startOfDay(for: Date())
            self.message = ""
            let t = DispatchSource.makeTimerSource(queue: file)
            t.schedule(deadline: .now(), repeating: 1.0, leeway: .milliseconds(200))
            t.setEventHandler { [weak self] in self?.tour() }
            self.minuterie = t
            t.resume()
        }
        DispatchQueue.main.async { self.actif = true }
    }

    /// Arrête la surveillance. Les photos en cours de traitement finissent proprement.
    public func arreter() {
        file.sync {
            minuterie?.cancel()
            minuterie = nil
            config = nil
        }
        DispatchQueue.main.async { self.actif = false }
    }

    // MARK: - Un tour (chaque seconde)

    private func tour() {
        guard let c = config, let j = journal else { return }
        let maintenant = Date()

        // Régulateur : Lightroom travaille-t-il ?
        charge = regulateur.chargeLightroom()
        let retard = vuesEnAttente.values.min().map { maintenant.timeIntervalSince($0) } ?? 0
        ouvriers.maxConcurrentOperationCount = RegleRegulateur.ouvriers(chargeLightroom: charge, fileEnRetard: retard > 30)

        // Nouvelles photos complètes dans le dossier de réception.
        let presentes = Moteur.lister(c.reception)
        let chemins = Set(presentes.map { $0.0.path })
        for k in vuesEnAttente.keys where !chemins.contains(k) && !enCours.contains(k) {
            vuesEnAttente[k] = nil      // photo retirée à la main du dossier de réception
            tailles[k] = nil
        }
        for (url, taille) in presentes {
            let chemin = url.path
            if enCours.contains(chemin) { continue }
            if let r = reessayerApres[chemin], r > maintenant { continue }
            if vuesEnAttente[chemin] == nil { vuesEnAttente[chemin] = maintenant }
            // Prête quand sa taille n'a pas bougé depuis le tour précédent (le boîtier a fini de l'écrire).
            defer { tailles[chemin] = taille }
            guard taille > 0, tailles[chemin] == taille else { continue }
            enCours.insert(chemin)
            ouvriers.addOperation { [weak self] in self?.traiter(url, config: c) }
        }

        // Dossier tampon : faut-il envoyer le lot à Lightroom ?
        if let tampon = c.tampon { verifierTampon(tampon: tampon, config: c, journal: j, maintenant: maintenant) }

        publier(journal: j, maintenant: maintenant)
    }

    /// JPEG du dossier de réception (sous-dossiers compris, sauf « _À renvoyer »), avec leur taille.
    private static func lister(_ dossier: URL) -> [(URL, UInt64)] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: dossier, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var l: [(URL, UInt64)] = []
        for case let url as URL in e {
            if url.lastPathComponent == dossierARenvoyer || url.lastPathComponent == dossierDoublons {
                e.skipDescendants()
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard ext == "jpg" || ext == "jpeg" else { continue }
            let taille = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            l.append((url, UInt64(taille)))
        }
        return l
    }

    // MARK: - Une photo

    private func traiter(_ url: URL, config c: ConfigMoteur) {
        let chemin = url.path
        var fiche = file.sync { journal?.fiche(chemin: chemin) } ?? FichePhoto(
            origine: url.lastPathComponent, nom: url.lastPathComponent, boitier: "", prise: nil, code: "",
            etat: .recue, chemin: chemin, copie: "", erreur: "", recue: Date(), maj: Date())
        if fiche.id == 0 { fiche.id = file.sync { journal?.ajouter(fiche) ?? 0 } }

        do {
            // 1. Contrôle : photo mal transférée → mise de côté, à redemander au boîtier (nom d'origine).
            guard let infos = TraitementPhoto.infos(url), !TraitementPhoto.estAbimee(url) else {
                let cote = c.reception.appendingPathComponent(Moteur.dossierARenvoyer, isDirectory: true)
                try FileManager.default.createDirectory(at: cote, withIntermediateDirectories: true)
                let dest = cote.appendingPathComponent(Renommage.libre(fiche.origine) {
                    FileManager.default.fileExists(atPath: cote.appendingPathComponent($0).path)
                })
                try FileManager.default.moveItem(at: url, to: dest)
                fiche.etat = .aRenvoyer
                fiche.chemin = dest.path
                fiche.erreur = "Mal transférée"
                terminer(fiche, chemin: chemin)
                return
            }
            fiche.boitier = infos.boitier
            fiche.prise = infos.prise

            // 2. Code du photographe (Copyright) et dossier de l'épreuve sur le serveur local.
            let code = CodePassage.lire(infos.copyright)
            fiche.code = code?.texte ?? ""
            var dossierServeur = c.serveur
            if let code {
                let ep = c.concours?.epreuve(numero: code.epreuve)
                dossierServeur.appendPathComponent(ep?.nomDossier ?? NomDossier.pourEpreuve(numero: code.epreuve, nom: ""),
                                                   isDirectory: true)
                if code.special == .inconnu { dossierServeur.appendPathComponent(Moteur.dossierAAttribuer, isDirectory: true) }
            } else {
                dossierServeur.appendPathComponent(Moteur.dossierAAttribuer, isDirectory: true)
            }
            guard FileManager.default.fileExists(atPath: c.serveur.path) else {
                throw TraitementPhoto.Erreur.ecriture("serveur local introuvable (\(c.serveur.path))")
            }

            // 3. Renommage (une seule fois) : nom d'origine + -minute de prise de vue.
            //    Normalement aucun doublon n'est possible : s'il y en a un, la photo est mise de côté et
            //    n'entre pas dans Lightroom tant que HUGO n'a pas décidé (garder sous un autre nom, ou jeter).
            let destination = c.tampon ?? c.importLightroom
            if fiche.erreur != Moteur.doublonAccepte {
                let nom = Renommage.nom(origine: fiche.origine, priseEXIF: infos.priseEXIF,
                                        secours: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate)
                let id = fiche.id
                let pris = file.sync { journal?.nomDejaUtilise(nom, sauf: id) ?? false }
                    || FileManager.default.fileExists(atPath: destination.appendingPathComponent(nom).path)
                    || FileManager.default.fileExists(atPath: c.importLightroom.appendingPathComponent(nom).path)
                if pris {
                    let cote = c.reception.appendingPathComponent(Moteur.dossierDoublons, isDirectory: true)
                    try FileManager.default.createDirectory(at: cote, withIntermediateDirectories: true)
                    let dest = cote.appendingPathComponent(Renommage.libre(fiche.origine) {
                        FileManager.default.fileExists(atPath: cote.appendingPathComponent($0).path)
                    })
                    try FileManager.default.moveItem(at: url, to: dest)
                    fiche.nom = nom
                    fiche.code = code?.texte ?? ""
                    fiche.etat = .doublon
                    fiche.chemin = dest.path
                    fiche.erreur = "Même nom qu'une photo déjà reçue : \(nom)"
                    terminer(fiche, chemin: chemin)
                    return
                }
                fiche.nom = nom
            }

            // 4. Copie compressée avec le .cube vers le serveur local.
            let copie = dossierServeur.appendingPathComponent(fiche.nom)
            try TraitementPhoto.fabriquerCopie(de: url, vers: copie, cote: c.cote, qualite: c.qualite, cube: c.cube,
                                               copyright: code?.texte ?? infos.copyright, priseEXIF: infos.priseEXIF)
            fiche.copie = copie.path
            fiche.etat = .copiee
            let enregistrer = fiche
            file.sync { journal?.mettreAJour(enregistrer) }

            // 5. IPTC écrit dans l'original (sans recompression), déposé dans le tampon ou l'import Lightroom.
            var motsCles: [String] = []
            if let code, let couple = c.concours?.couple(pour: code) {
                motsCles += [couple.cavalier, couple.cheval].filter { !$0.isEmpty }
            }
            if let code, let ep = c.concours?.epreuve(numero: code.epreuve) {
                motsCles.append("Épreuve \(ep.nomDossier)")
            }
            let final = destination.appendingPathComponent(fiche.nom)
            try TraitementPhoto.copierAvecIPTC(de: url, vers: final, motsCles: motsCles, codeOrigine: code?.texte ?? "")

            // L'original n'est retiré de la réception qu'une fois sa copie complète vérifiée à destination.
            let tailleFinale = (try? FileManager.default.attributesOfItem(atPath: final.path)[.size] as? UInt64) ?? 0
            guard tailleFinale > 0 else { throw TraitementPhoto.Erreur.ecriture(final.path) }
            try FileManager.default.removeItem(at: url)
            fiche.chemin = final.path
            fiche.etat = c.tampon == nil ? .envoyee : .tampon
            fiche.erreur = ""
            terminer(fiche, chemin: chemin)
        } catch {
            fiche.etat = .erreur
            let texte = error.localizedDescription
            if fiche.erreur != Moteur.doublonAccepte { fiche.erreur = texte }   // un doublon accepté le reste
            let f = fiche
            file.sync {
                journal?.mettreAJour(f)
                message = texte
                reessayerApres[chemin] = Date().addingTimeInterval(15)
                enCours.remove(chemin)
                tailles[chemin] = nil
            }
        }
    }

    private func terminer(_ f: FichePhoto, chemin: String) {
        file.sync {
            journal?.mettreAJour(f)
            enCours.remove(chemin)
            tailles[chemin] = nil
            vuesEnAttente[chemin] = nil
            reessayerApres[chemin] = nil
        }
    }

    // MARK: - Dossier tampon

    private func verifierTampon(tampon: URL, config c: ConfigMoteur, journal j: Journal, maintenant: Date) {
        let enAttente = j.fiches(etat: .tampon)
        var derniere: [String: Date] = [:]
        for f in enAttente { derniere[f.boitier] = max(derniere[f.boitier] ?? .distantPast, f.recue) }
        let decision = RegleTampon.decider(enAttente: enAttente.count, tailleLot: c.tailleLot,
                                           derniereParBoitier: derniere, premiereEnAttente: enAttente.map(\.recue).min(),
                                           maintenant: maintenant, silenceMinutes: c.silenceMinutes,
                                           lightroomOccupe: RegleRegulateur.lightroomOccupe(chargeLightroom: charge),
                                           retarderSiOccupe: c.retarderSiOccupe)
        guard case .envoyer(let raison) = decision else { return }
        let fm = FileManager.default
        var envoyees = 0
        for var f in enAttente {
            let source = URL(fileURLWithPath: f.chemin)
            guard fm.fileExists(atPath: source.path) else { continue }
            let nom = Renommage.libre(f.nom) { fm.fileExists(atPath: c.importLightroom.appendingPathComponent($0).path) }
            let dest = c.importLightroom.appendingPathComponent(nom)
            do {
                try fm.moveItem(at: source, to: dest)
                f.nom = nom
                f.chemin = dest.path
                f.etat = .envoyee
                j.mettreAJour(f)
                envoyees += 1
            } catch {
                message = "Tampon : \(error.localizedDescription)"
            }
        }
        if envoyees > 0 { message = "Lot de \(envoyees) photos envoyé à Lightroom : \(raison)." }
    }

    // MARK: - Accueil

    private func publier(journal j: Journal, maintenant: Date) {
        var r = ResumeMoteur()
        let compte = j.compter(depuis: debutJournee)
        r.recues = compte.values.reduce(0, +)
        r.parMinute = Double(j.terminees(depuis: maintenant.addingTimeInterval(-300))) / 5
        r.enFile = vuesEnAttente.count
        r.retardSecondes = vuesEnAttente.values.min().map { maintenant.timeIntervalSince($0) } ?? 0
        // à renvoyer : tant que le fichier abîmé est encore dans « _À renvoyer » (HUGO le supprime une fois renvoyé)
        r.aRenvoyer = j.fiches(etat: .aRenvoyer, limite: 500).filter { FileManager.default.fileExists(atPath: $0.chemin) }
        r.doublons = j.fiches(etat: .doublon, limite: 500).filter { FileManager.default.fileExists(atPath: $0.chemin) }
        r.enErreur = compte[.erreur] ?? 0
        r.dansTampon = compte[.tampon] ?? 0
        r.boitiers = j.boitiers(depuis: debutJournee).filter { !$0.nom.isEmpty }
            .map { ResumeMoteur.Boitier(nom: $0.nom, photos: $0.photos, derniere: $0.derniere) }
        r.recentes = j.dernieres(12).map { ResumeMoteur.Recente(id: $0.id, nom: $0.nom, code: $0.code, boitier: $0.boitier, etat: $0.etat) }
        r.chargeLightroom = charge
        r.ouvriers = ouvriers.maxConcurrentOperationCount
        r.message = message
        DispatchQueue.main.async { self.resume = r }
    }

    // MARK: - Doublons (décision de HUGO)

    /// Garder la photo : elle repart dans le tri sous un nom libre (« DERB1340-35-2.JPG »).
    public func garderDoublon(_ f: FichePhoto) {
        file.async { [weak self] in
            guard let self, let c = self.config, let j = self.journal else { return }
            let fm = FileManager.default
            let source = URL(fileURLWithPath: f.chemin)
            guard fm.fileExists(atPath: source.path) else { return }
            let destination = c.tampon ?? c.importLightroom
            let nom = Renommage.libre(f.nom) { n in
                j.nomDejaUtilise(n, sauf: f.id) || fm.fileExists(atPath: destination.appendingPathComponent(n).path)
                    || fm.fileExists(atPath: c.importLightroom.appendingPathComponent(n).path)
            }
            let retour = c.reception.appendingPathComponent(Renommage.libre(f.origine) {
                fm.fileExists(atPath: c.reception.appendingPathComponent($0).path)
            })
            do {
                try fm.moveItem(at: source, to: retour)
                var g = f
                g.nom = nom
                g.chemin = retour.path
                g.etat = .recue
                g.erreur = Moteur.doublonAccepte
                j.mettreAJour(g)
                self.message = "Doublon gardé : il part sous le nom \(nom)."
            } catch {
                self.message = "Doublon : \(error.localizedDescription)"
            }
        }
    }

    /// Jeter la photo : elle va à la corbeille du Mac (récupérable), rien n'est envoyé.
    public func jeterDoublon(_ f: FichePhoto) {
        file.async { [weak self] in
            guard let self, let j = self.journal else { return }
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: f.chemin), resultingItemURL: nil)
                var g = f
                g.etat = .ecartee
                g.erreur = "Mise à la corbeille par HUGO"
                j.mettreAJour(g)
                self.message = "Doublon \(f.origine) mis à la corbeille."
            } catch {
                self.message = "Doublon : \(error.localizedDescription)"
            }
        }
    }
}
