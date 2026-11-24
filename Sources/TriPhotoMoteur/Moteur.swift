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
    public var travailLightroom: URL?   // pour retrouver une photo déjà importée par Lightroom, et la suivre
    public var chrono: ConfigChrono?    // nil : pas de chrono, les photos partent avec le code du photographe
    /// Une photo en _00 (ou sans code) attend tant de minutes une photo de code ou le chrono avant de partir.
    public var attente00Minutes: Double
    /// Rafraîchissement de la galerie du stand (serveur local) par lots. nil : pas de rafraîchissement.
    public var galerie: ConfigGalerie?

    public init(reception: URL, importLightroom: URL, tampon: URL?, serveur: URL, cote: Int, qualite: Int,
                cube: FichierCube?, concours: Concours?, tailleLot: Int, silenceMinutes: Int,
                retarderSiOccupe: Bool, journal: URL, travailLightroom: URL? = nil, chrono: ConfigChrono? = nil,
                attente00Minutes: Double = 2, galerie: ConfigGalerie? = nil) {
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
        self.travailLightroom = travailLightroom
        self.chrono = chrono
        self.attente00Minutes = attente00Minutes
        self.galerie = galerie
    }
}

/// Résumé affiché sur l'accueil, recalculé chaque seconde.
public struct ResumeMoteur {
    public struct Boitier: Identifiable {
        public var id: String { nom }
        public var nom: String
        public var photos: Int
        public var derniere: Date?
        /// Photo de synchro : nom donné, piste, photographe, écart d'heure.
        public var synchro: BoitierSynchro?
        public var nomAffiche: String { synchro?.nomAffiche ?? nom }
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

    // Étape 2
    public var series: [SerieAValider] = []
    /// Photos mises de côté en attente de validation (les photos de code comptent pour une).
    public var aValider: Int { series.reduce(0) { $0 + ($1.genre == .photoCode ? 1 : $1.photos.count) } }
    public var enAttenteChrono = 0
    public var chrono: EtatChrono?
    public var enPiste: [EnPiste] = []
    public var passagesRecents: [Passage] = []
    public var sans00: [FichePhoto] = []
    public var photosParCode: [CodeCompte] = []
    public var epreuveCourbe = ""
    public var alertes: [String] = []

    // Étape 3 : app Piste
    /// Ce qui se passe sur chaque piste, par nom de piste du chrono (« source »).
    public var suivis: [String: SuiviPiste] = [:]
    /// Boîtier → piste du chrono (apprise sur les photos au bon code).
    public var boitierPiste: [String: String] = [:]
    public var alertesCode: [AlerteCodePiste] = []
    /// Photos parties par code aujourd'hui (« #12_03 » → 8).
    public var compteParCode: [String: Int] = [:]
    /// Photos renvoyées et bien arrivées ces 10 dernières minutes (nom d'origine).
    public var bienArrivees: [FichePhoto] = []
    /// Heure du chrono maintenant (horloge du Mac + écart).
    public var heureChrono: Double = 0
    /// Début du nom des photos d'un boîtier (« DERB ») → boîtier : retrouve le boîtier d'une photo illisible.
    public var prefixeBoitier: [String: String] = [:]

    // Photo de synchro (QR) et galerie du stand
    public var synchro = EtatSynchro()
    public var boitiersSynchro: [BoitierSynchro] = []
    /// Heure du chrono − heure du Mac (pour l'heure affichée dans le QR).
    public var ecartChrono: Double = 0
    public var galerie: EtatGalerie?

    public init() {}
}

/// Nombre de photos d'un code (courbe photos par cavalier).
public struct CodeCompte: Sendable {
    public var code: String
    public var photos: Int
}

/// Le lien avec le chrono, pour l'accueil.
public struct EtatChrono: Sendable {
    public var ok: Bool?
    public var erreur: String
    public var vu: Date?
    public var passages: Int
}

/// Ce qui est en piste en ce moment, piste par piste (d'après le chrono).
public struct EnPiste: Identifiable, Sendable {
    public var id: String { piste }
    public var piste: String
    public var passage: Passage
    public var termine: Bool
}

/// Une série « À valider » : photos qui se suivent, même boîtier, même code, même proposition.
/// Ou une photo de code, avec les photos d'avant parmi lesquelles choisir.
public struct SerieAValider: Identifiable, Sendable {
    public enum Genre: Sendable { case chrono, photoCode }
    public var id: String
    public var genre: Genre
    public var boitier: String
    public var photos: [FichePhoto]          // chrono : les photos de la série ; photo de code : les 15 d'avant
    public var photoCode: FichePhoto?
    public var code: String                  // code du photographe
    public var proposition: String
    public var raison: String
    public var confiance: Int
    public var preselection: Set<Int64>      // photos cochées d'office
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
    private var chrono: Chrono?
    private var enAttenteChrono: [String: Date] = [:]           // photos gardées en réception (chrono, _00)
    private var pisteDuBoitier: [String: String] = [:]          // apprise sur les photos conformes
    private var derniereSerie: [String: (cle: String, id: String, quand: Date)] = [:]
    private var suivi: SuiviLightroom?
    private var dernierSuivi = Date.distantPast
    private var dernierCalcul = Date.distantPast
    private var cache00: [FichePhoto] = []
    private var cacheCourbe: (String, [CodeCompte]) = ("", [])
    private var cacheCompte: [String: Int] = [:]
    private var cacheBienArrivees: [FichePhoto] = []
    private var nomsARenvoyer: [String: Int64] = [:]           // nom d'origine (minuscules) → photo mal arrivée
    private var alertesVues: [String: Double] = [:]            // boîtier → heure de la dernière photo quand vue
    private var direct = false                                  // des iPhone suivent les pistes
    private var prefixeBoitier: [String: String] = [:]
    private var demandeSynchro: DemandeSynchro?
    private var synchroDebut = Date.distantPast
    private var synchroJusqua = Date.distantPast
    private var dernierSynchro: BoitierSynchro?
    private var boitiersSynchro: [String: BoitierSynchro] = [:]
    private var galerie: GalerieStand?
    private var fichierSynchro: URL? { config.map { $0.journal.deletingLastPathComponent().appendingPathComponent("boitiers-synchro.json") } }

    public static let dossierARenvoyer = "_À renvoyer"
    public static let dossierAAttribuer = "À attribuer"
    public static let dossierDoublons = "_Doublons"
    public static let dossierAValider = "_À valider"
    public static let dossierPhotosCode = "_Photos de code"
    public static let dossierSynchro = "_Synchro"
    static let doublonAccepte = "Doublon accepté par HUGO"
    static let codeGarde = "Code du photographe gardé par HUGO"
    static let pasPhotoCode = "Pas une photo de code (HUGO)"
    static let sansChrono = "Partie sans vérification du chrono"
    public static let bienArrivee = "Renvoyée : bien arrivée"

    // MARK: - Démarrer / arrêter

    public func demarrer(_ c: ConfigMoteur) throws {
        let j = try Journal(fichier: c.journal)
        file.sync {
            self.config = c
            self.journal = j
            self.debutJournee = Calendar.current.startOfDay(for: Date())
            self.message = ""
            self.chrono = c.chrono.map { Chrono(config: $0) }
            self.suivi = c.travailLightroom.map { SuiviLightroom(dossier: $0) }
            self.galerie = c.galerie.flatMap { $0.adresse.isEmpty ? nil : GalerieStand(config: $0, racine: c.serveur) }
            self.chargerSynchro()
            self.enAttenteChrono = [:]
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
        for k in enAttenteChrono.keys where !chemins.contains(k) && !enCours.contains(k) { enAttenteChrono[k] = nil }
        for (url, taille) in presentes {
            let chemin = url.path
            if enCours.contains(chemin) { continue }
            if let r = reessayerApres[chemin], r > maintenant { continue }
            if vuesEnAttente[chemin] == nil && enAttenteChrono[chemin] == nil { vuesEnAttente[chemin] = maintenant }
            // Prête quand sa taille n'a pas bougé depuis le tour précédent (le boîtier a fini de l'écrire).
            defer { tailles[chemin] = taille }
            guard taille > 0, tailles[chemin] == taille else { continue }
            enCours.insert(chemin)
            ouvriers.addOperation { [weak self] in self?.traiter(url, config: c) }
        }

        // Chrono : les passages, seulement quand des photos en ont besoin (quelques Ko toutes les 8 s au plus).
        // Des iPhone suivent les pistes : passages demandés toutes les 8 s même sans photo.
        if let ch = chrono, !presentes.isEmpty || !enAttenteChrono.isEmpty || ch.ok == nil || direct
            || maintenant.timeIntervalSince(ch.vu ?? .distantPast) > 60 {
            ch.actualiserSiBesoin(depuis: maintenant.addingTimeInterval(-4 * 3600))
        }

        // Dossier tampon : faut-il envoyer le lot à Lightroom ?
        if let tampon = c.tampon { verifierTampon(tampon: tampon, config: c, journal: j, maintenant: maintenant) }

        // Dossier de travail de Lightroom : suppressions et codes changés (toutes les 15 s).
        if let s = suivi, maintenant.timeIntervalSince(dernierSuivi) >= 15 {
            dernierSuivi = maintenant
            s.examiner { [weak self] constat in self?.file.async { self?.appliquer(constat) } }
        }

        galerie?.peutEtre()
        publier(journal: j, maintenant: maintenant)
    }

    /// JPEG du dossier de réception (sous-dossiers compris, sauf « _À renvoyer »), avec leur taille.
    private static func lister(_ dossier: URL) -> [(URL, UInt64)] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: dossier, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var l: [(URL, UInt64)] = []
        for case let url as URL in e {
            if [dossierARenvoyer, dossierDoublons, dossierAValider, dossierPhotosCode, dossierSynchro].contains(url.lastPathComponent) {
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

            let prefixe = Moteur.prefixe(fiche.origine)
            if !prefixe.isEmpty, !infos.boitier.isEmpty {
                let bt = infos.boitier
                // plusieurs boîtiers au même début de nom (« IMG_ ») : « * », la photo illisible est montrée à toutes les pistes
                file.sync {
                    if let avant = prefixeBoitier[prefixe] { if avant != bt { prefixeBoitier[prefixe] = "*" } }
                    else { prefixeBoitier[prefixe] = bt }
                }
            }

            // 1a. Photo de synchro : pendant que la fenêtre du QR est ouverte, une photo du QR règle l'heure du
            //     boîtier, lui donne son nom, sa piste et son photographe. Elle n'est jamais envoyée.
            if let session = file.sync(execute: { () -> (debut: Date, demande: DemandeSynchro)? in
                   guard let d = demandeSynchro, Date() < synchroJusqua else { return nil }
                   return (synchroDebut, d)
               }), let qr = Synchro.lireQR(url), qr >= session.debut.timeIntervalSince1970 - 5, let prise = fiche.prise {
                let demande = session.demande
                let cote = c.reception.appendingPathComponent(Moteur.dossierSynchro, isDirectory: true)
                try mettreDeCote(url, dans: cote, fiche: &fiche)
                let b = fiche.boitier
                let avant = file.sync { boitiersSynchro[b] }
                let s = BoitierSynchro(boitier: b, nom: demande.nom.isEmpty ? (avant?.nom ?? "") : demande.nom,
                                       piste: demande.piste, source: demande.source, photographe: demande.photographe,
                                       ecart: (prise.timeIntervalSince1970 - qr), le: Date(), photo: fiche.origine)
                fiche.etat = .synchro
                fiche.erreur = "Photo de synchro : \(s.nomAffiche), \(s.ecartTexte)"
                fiche.noter("synchro", s.ecartTexte)
                file.sync { enregistrerSynchro(s) }
                terminer(fiche, chemin: chemin)
                return
            }

            // 1b. Photo renvoyée par le photographe (elle était mal arrivée) : l'ancienne, abîmée, va à la corbeille
            //     et sort de la liste « à renvoyer » de l'iPhone.
            let cleNom = fiche.origine.lowercased()
            let idFiche = fiche.id
            if let ancien = file.sync(execute: { nomsARenvoyer[cleNom] }), ancien != idFiche,
               var vieille = file.sync(execute: { journal?.fiche(id: ancien) }), vieille.etat == .aRenvoyer {
                try? FileManager.default.trashItem(at: URL(fileURLWithPath: vieille.chemin), resultingItemURL: nil)
                vieille.etat = .retiree
                vieille.erreur = Moteur.bienArrivee
                let v = vieille
                file.sync {
                    journal?.mettreAJour(v)
                    nomsARenvoyer[cleNom] = nil
                    cacheBienArrivees.insert(v, at: 0)
                }
            }

            // 2. Code du photographe (Copyright). Un code validé par HUGO prend le pas.
            let codePhotographe = CodePassage.lire(infos.copyright)
            fiche.code = codePhotographe?.texte ?? ""
            if fiche.historique.isEmpty { fiche.noter("boîtier", fiche.code.isEmpty ? "sans code (code d'origine)" : "\(fiche.code) (code d'origine)") }

            // 2b. Photo de code (ciel, plafond) ? Elle n'est jamais envoyée : elle sert à recoder les photos d'avant.
            if fiche.nettete == 0, let a = Analyse.analyser(url) {
                fiche.nettete = a.nettete
                fiche.scene = a.scene.rawValue
            }
            if fiche.codeFinal.isEmpty, fiche.scene == Analyse.Scene.code.rawValue, !fiche.a(Moteur.pasPhotoCode),
               codePhotographe != nil {
                let cote = c.reception.appendingPathComponent(Moteur.dossierPhotosCode, isDirectory: true)
                try mettreDeCote(url, dans: cote, fiche: &fiche)
                fiche.etat = .photoCode
                fiche.serie = "code-\(fiche.id)"
                fiche.raison = "Photo de code \(fiche.code) : choisir les photos d'avant qu'elle concerne"
                terminer(fiche, chemin: chemin)
                return
            }

            // 2c. Chrono : le code est-il celui du couple en piste ? Sinon, proposition « À valider ».
            if fiche.codeFinal.isEmpty, !fiche.a(Moteur.codeGarde) {
                let attendu = Date().timeIntervalSince(fiche.recue)
                let sans = codePhotographe == nil || codePhotographe?.special == .inconnu
                var garderEnReception = false
                if let ch = file.sync(execute: { chrono }), let prise = fiche.prise {
                    if ch.ok == true {
                        let b0 = fiche.boitier
                        let piste = file.sync { pisteDuBoitier[b0] }
                        let d = Attribution.decider(code: codePhotographe, t: ch.heureChrono(prise, boitier: b0), passages: ch.passages,
                                                    apres: ch.config.apresArrivee, latence: ch.config.latence, piste: piste)
                        switch d {
                        case .conforme:
                            if case .trouve(let places) = Attribution.placer(t: ch.heureChrono(prise, boitier: b0), passages: ch.passages,
                                                                              apres: ch.config.apresArrivee),
                               let p = places.first(where: { $0.passage.code == codePhotographe }) {
                                let b = fiche.boitier
                                file.sync { pisteDuBoitier[b] = p.passage.source }
                            }
                        case .garder:
                            garderEnReception = sans && attendu < c.attente00Minutes * 60
                        case .attendre:
                            garderEnReception = attendu < ch.config.attenteMaxMinutes * 60
                            if !garderEnReception { fiche.marquer(Moteur.sansChrono) }
                        case .proposer(let propose, let raison, let confiance, _):
                            let cote = c.reception.appendingPathComponent(Moteur.dossierAValider, isDirectory: true)
                            try mettreDeCote(url, dans: cote, fiche: &fiche)
                            fiche.etat = .aValider
                            fiche.proposition = propose.texte
                            fiche.raison = raison
                            fiche.confiance = confiance
                            let f0 = fiche
                            fiche.serie = file.sync { serie(pour: f0) }
                            fiche.noter("proposition", "\(propose.texte) · en attente")
                            terminer(fiche, chemin: chemin)
                            return
                        }
                    } else {
                        // chrono pas encore joint, ou injoignable : on attend un peu, puis la photo part avec son code
                        garderEnReception = attendu < ch.config.attenteMaxMinutes * 60
                        if !garderEnReception { fiche.marquer(Moteur.sansChrono) }
                    }
                } else if sans {
                    // pas de chrono : une photo en _00 attend un peu une photo de code du même boîtier
                    garderEnReception = attendu < c.attente00Minutes * 60
                }
                if garderEnReception {
                    let f = fiche
                    file.sync {
                        journal?.mettreAJour(f)
                        enCours.remove(chemin)
                        tailles[chemin] = nil
                        vuesEnAttente[chemin] = nil
                        if enAttenteChrono[chemin] == nil { enAttenteChrono[chemin] = Date() }
                        reessayerApres[chemin] = Date().addingTimeInterval(8)
                    }
                    return
                }
            }
            let code = fiche.codeFinal.isEmpty ? codePhotographe : CodePassage.lire(fiche.codeFinal)
            if let code, let couple = c.concours?.couple(pour: code) {
                fiche.cavalier = couple.cavalier
                fiche.cheval = couple.cheval
            }
            let dossierServeur = Moteur.dossierServeur(pour: code, config: c)
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
            let dossierNeuf = !FileManager.default.fileExists(atPath: dossierServeur.path)
            try TraitementPhoto.fabriquerCopie(de: url, vers: copie, cote: c.cote, qualite: c.qualite, cube: c.cube,
                                               copyright: code?.texte ?? infos.copyright, priseEXIF: infos.priseEXIF)
            fiche.copie = copie.path
            fiche.etat = .copiee
            galerie?.copieFaite(dans: dossierServeur, nouveau: dossierNeuf)
            let enregistrer = fiche
            file.sync { journal?.mettreAJour(enregistrer) }

            // 5. IPTC écrit dans l'original (sans recompression), déposé dans le tampon ou l'import Lightroom.
            //    Code validé par HUGO : il remplace le Copyright ; le code d'origine reste dans Job Identifier.
            let final = destination.appendingPathComponent(fiche.nom)
            try TraitementPhoto.copierAvecIPTC(de: url, vers: final, motsCles: Moteur.motsCles(fiche, code: code, config: c),
                                               codeOrigine: fiche.code,
                                               copyright: fiche.codeFinal.isEmpty ? nil : fiche.codeFinal)
            fiche.serie = ""
            enAttenteFini(chemin)

            // L'original n'est retiré de la réception qu'une fois sa copie complète vérifiée à destination.
            let tailleFinale = (try? FileManager.default.attributesOfItem(atPath: final.path)[.size] as? UInt64) ?? 0
            guard tailleFinale > 0 else { throw TraitementPhoto.Erreur.ecriture(final.path) }
            try FileManager.default.removeItem(at: url)
            fiche.chemin = final.path
            fiche.etat = c.tampon == nil ? .envoyee : .tampon
            fiche.erreur = fiche.a(Moteur.sansChrono) ? Moteur.sansChrono : ""
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
            enAttenteChrono[chemin] = nil
        }
    }

    private func enAttenteFini(_ chemin: String) { file.sync { enAttenteChrono[chemin] = nil } }

    /// Met une photo de côté dans un sous-dossier de la réception (rien n'est envoyé tant que HUGO n'a pas choisi).
    private func mettreDeCote(_ url: URL, dans cote: URL, fiche: inout FichePhoto) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: cote, withIntermediateDirectories: true)
        let dest = cote.appendingPathComponent(Renommage.libre(fiche.origine) { fm.fileExists(atPath: cote.appendingPathComponent($0).path) })
        try fm.moveItem(at: url, to: dest)
        fiche.chemin = dest.path
    }

    /// Série « À valider » : les photos qui se suivent sur un boîtier avec le même code et la même proposition.
    /// Appelé depuis `file`.
    private func serie(pour f: FichePhoto) -> String {
        let cle = "\(f.code)>\(f.proposition)"
        let maintenant = Date()
        if let d = derniereSerie[f.boitier], d.cle == cle, maintenant.timeIntervalSince(d.quand) < 120 {
            derniereSerie[f.boitier] = (cle, d.id, maintenant)
            return d.id
        }
        let id = "chrono-\(f.id)"
        derniereSerie[f.boitier] = (cle, id, maintenant)
        return id
    }

    /// Dossier de l'épreuve sur le serveur local (« À attribuer » pour _00 ou sans code).
    static func dossierServeur(pour code: CodePassage?, config c: ConfigMoteur) -> URL {
        var d = c.serveur
        if let code {
            let ep = c.concours?.epreuve(numero: code.epreuve)
            d.appendPathComponent(ep?.nomDossier ?? NomDossier.pourEpreuve(numero: code.epreuve, nom: ""), isDirectory: true)
            if code.special == .inconnu { d.appendPathComponent(dossierAAttribuer, isDirectory: true) }
        } else {
            d.appendPathComponent(dossierAAttribuer, isDirectory: true)
        }
        return d
    }

    /// Mots-clés IPTC : cavalier, cheval, épreuve, et CHUTE si HUGO l'a marquée.
    static func motsCles(_ f: FichePhoto, code: CodePassage?, config c: ConfigMoteur) -> [String] {
        var m: [String] = []
        if let code, let couple = c.concours?.couple(pour: code) {
            m += [couple.cavalier, couple.cheval].filter { !$0.isEmpty }
        }
        if let code, let ep = c.concours?.epreuve(numero: code.epreuve) { m.append("Épreuve \(ep.nomDossier)") }
        if f.chute { m.append("CHUTE") }
        return m
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
        nomsARenvoyer = Dictionary(r.aRenvoyer.map { ($0.origine.lowercased(), $0.id) }, uniquingKeysWith: { a, _ in a })
        r.doublons = j.fiches(etat: .doublon, limite: 500).filter { FileManager.default.fileExists(atPath: $0.chemin) }
        r.enErreur = compte[.erreur] ?? 0
        r.dansTampon = compte[.tampon] ?? 0
        r.boitiers = j.boitiers(depuis: debutJournee).filter { !$0.nom.isEmpty }
            .map { ResumeMoteur.Boitier(nom: $0.nom, photos: $0.photos, derniere: $0.derniere, synchro: boitiersSynchro[$0.nom]) }
        var es = EtatSynchro()
        es.ouverte = demandeSynchro != nil && maintenant < synchroJusqua
        es.jusqua = es.ouverte ? synchroJusqua : nil
        es.dernier = dernierSynchro
        r.synchro = es
        r.boitiersSynchro = boitiersSynchro.values.sorted { $0.le > $1.le }
        r.ecartChrono = chrono?.ecart ?? 0
        r.galerie = galerie?.etat
        r.recentes = j.dernieres(12).map { ResumeMoteur.Recente(id: $0.id, nom: $0.nom, code: $0.codeRetenu, boitier: $0.boitier, etat: $0.etat) }
        r.chargeLightroom = charge
        r.ouvriers = ouvriers.maxConcurrentOperationCount
        r.message = message

        // Étape 2 : séries à valider, photos de code, chrono, _00, courbe.
        r.enAttenteChrono = enAttenteChrono.count
        var series: [String: SerieAValider] = [:]
        var ordre: [String] = []
        // Séries : photos d'un même boîtier qui se suivent (moins d'une minute d'écart à la prise de vue), avec le
        // même code et la même proposition. Calculées ici, sur l'heure de prise de vue : l'ordre de traitement
        // (plusieurs photos à la fois) ne coupe plus une série en morceaux.
        let enAttente = j.fiches(etat: .aValider, limite: 2000)
            .filter { FileManager.default.fileExists(atPath: $0.chemin) }
            .sorted { ($0.boitier, $0.prise ?? $0.recue) < ($1.boitier, $1.prise ?? $1.recue) }
        var courante: String?
        var precedente: FichePhoto?
        for f in enAttente {
            let meme = precedente.map { p in
                p.boitier == f.boitier && p.code == f.code && p.proposition == f.proposition
                    && (f.prise ?? f.recue).timeIntervalSince(p.prise ?? p.recue) < 60
            } ?? false
            if !meme || courante == nil {
                let id = "chrono-\(f.id)"
                courante = id
                ordre.append(id)
                series[id] = SerieAValider(id: id, genre: .chrono, boitier: f.boitier, photos: [], photoCode: nil,
                                           code: f.code, proposition: f.proposition, raison: f.raison,
                                           confiance: f.confiance, preselection: [])
            }
            if let id = courante {
                series[id]?.photos.append(f)
                series[id]?.preselection.insert(f.id)
                // lecture d'abord dans une variable : lire et modifier « series » dans la même ligne est refusé
                let confiance = series[id]?.confiance ?? 100
                series[id]?.confiance = min(confiance, f.confiance)
            }
            precedente = f
        }
        for pc in j.fiches(etat: .photoCode, limite: 200) where !pc.serie.isEmpty {
            guard let prise = pc.prise else { continue }
            let avant = j.precedentes(boitier: pc.boitier, avant: prise, n: 15)
            // cochées d'office : en remontant depuis la photo de code, les photos en _00 ou sans code, puis celles
            // qui portent l'ancien code juste avant (le photographe a oublié de changer son code)
            var coches: Set<Int64> = []
            for f in avant.reversed() {
                let k = CodePassage.lire(f.codeRetenu)
                if k == nil || k?.special == .inconnu { coches.insert(f.id) } else { break }
            }
            ordre.append(pc.serie)
            series[pc.serie] = SerieAValider(id: pc.serie, genre: .photoCode, boitier: pc.boitier, photos: avant, photoCode: pc,
                                             code: "", proposition: pc.code, raison: pc.raison, confiance: coches.isEmpty ? 60 : 90,
                                             preselection: coches)
        }
        r.series = ordre.compactMap { series[$0] }
        if let ch = chrono {
            r.chrono = EtatChrono(ok: ch.ok, erreur: ch.erreur, vu: ch.vu, passages: ch.passages.count)
            let ps = ch.passages
            var parPiste: [String: Passage] = [:]
            for p in ps where (parPiste[p.source]?.debut ?? -1) < p.debut { parPiste[p.source] = p }
            let t = maintenant.timeIntervalSince1970 + ch.ecart
            r.enPiste = parPiste.map { EnPiste(piste: $0.key, passage: $0.value, termine: ($0.value.fin ?? .infinity) + 60 < t) }
                .sorted { $0.piste < $1.piste }
            r.passagesRecents = Array(ps.sorted { $0.debut > $1.debut }.prefix(40))
        }
        if maintenant.timeIntervalSince(dernierCalcul) >= 10 {
            dernierCalcul = maintenant
            cache00 = j.fiches00(depuis: debutJournee)
            let derniere = j.dernieres(30).compactMap { CodePassage.lire($0.codeRetenu) }.first { $0.special == nil }
            if let e = derniere?.epreuve { cacheCourbe = (e, j.photosParCode(epreuve: e, depuis: debutJournee).map { CodeCompte(code: $0.code, photos: $0.photos) }) }
        }
        r.sans00 = cache00
        r.epreuveCourbe = cacheCourbe.0
        r.photosParCode = cacheCourbe.1
        // alerte : beaucoup de _00 sur un boîtier (30 dernières photos)
        var parBoitier: [String: (Int, Int)] = [:]
        for f in j.dernieres(150) where f.etat == .envoyee || f.etat == .tampon {
            let k = CodePassage.lire(f.codeRetenu)
            let v = parBoitier[f.boitier] ?? (0, 0)
            if v.0 < 30 { parBoitier[f.boitier] = (v.0 + 1, v.1 + ((k == nil || k?.special == .inconnu) ? 1 : 0)) }
        }
        for (b, v) in parBoitier where v.0 >= 10 && Double(v.1) / Double(v.0) > 0.4 {
            r.alertes.append("\(b) : \(v.1) photos sur \(v.0) en _00 ou sans code.")
        }
        publierPistes(&r, journal: j, maintenant: maintenant)
        // boîtier qui travaille sans photo de synchro (son heure n'est pas vérifiée)
        if chrono != nil {
            for b in r.boitiers where b.synchro == nil && b.photos >= 5 && maintenant.timeIntervalSince(b.derniere ?? .distantPast) < 1800 {
                r.alertes.append("\(b.nom) : pas de photo de synchro (heure du boîtier non vérifiée).")
            }
        }
        if let g = r.galerie, g.ok == false { r.alertes.append(g.message) }
        DispatchQueue.main.async { self.resume = r }
    }

    // MARK: - Pistes (app Piste sur les iPhone)

    private func publierPistes(_ r: inout ResumeMoteur, journal j: Journal, maintenant: Date) {
        if maintenant.timeIntervalSince(dernierCalcul) < 1 {       // recalculé en même temps que la courbe (10 s)
            cacheCompte = j.compteParCode(depuis: debutJournee)
            cacheBienArrivees = j.fiches(etat: .retiree, majDepuis: maintenant.addingTimeInterval(-600))
                .filter { $0.erreur == Moteur.bienArrivee }
        }
        r.compteParCode = cacheCompte
        r.bienArrivees = cacheBienArrivees.filter { maintenant.timeIntervalSince($0.maj) < 600 }
        r.boitierPiste = pisteDuBoitier
        r.prefixeBoitier = prefixeBoitier
        guard let ch = chrono else { return }
        let t = maintenant.timeIntervalSince1970 + ch.ecart
        r.heureChrono = t
        let ps = ch.passages
        for source in Set(ps.map(\.source)) {
            r.suivis[source] = SuiviPiste.calculer(source: source, passages: ps, concours: config?.concours, maintenant: t)
        }
        // dernières photos de chaque boîtier (code du photographe, tel que réglé sur le boîtier)
        var photos: [String: [(code: String, prise: Double)]] = [:]
        var derniere: [String: Double] = [:]
        for f in j.dernieres(150) where ![.aRenvoyer, .doublon, .ecartee].contains(f.etat) {
            guard let p = f.prise, !f.boitier.isEmpty else { continue }
            let h = ch.heureChrono(p, boitier: f.boitier)
            photos[f.boitier, default: []].append((code: f.code, prise: h))
            derniere[f.boitier] = max(derniere[f.boitier] ?? 0, h)
        }
        for (b, l) in photos {
            guard let source = pisteDuBoitier[b], let s = r.suivis[source],
                  let a = SuiviPiste.alerteCode(boitier: b, photos: l, suivi: s) else { continue }
            if let vue = alertesVues[b], (derniere[b] ?? 0) <= vue { continue }    // « c'est changé » : on attend la photo suivante
            r.alertesCode.append(a)
            r.alertes.append("\(b) (\(source)) : photos encore en \(a.ancien), l'épreuve \(s.epreuve) a commencé.")
        }
        // couple sans aucune photo alors que le boîtier de la piste travaille
        for (source, s) in r.suivis {
            guard let p = s.precedent, let fin = p.fin ?? s.enPiste?.debut, fin + 60 < t, t - fin < 900,
                  p.code.special == nil, (cacheCompte[p.code.texte] ?? 0) == 0 else { continue }
            let actif = pisteDuBoitier.contains { $0.value == source && t - (derniere[$0.key] ?? 0) < 600 }
            if actif { r.alertes.append("\(source) : aucune photo de \(p.code.texte) (\(p.cavalier)).") }
        }
    }

    /// « DERB1340-35.JPG » → « DERB », « IMG_8812.JPG » → « IMG_ ».
    public static func prefixe(_ nom: String) -> String {
        String(nom.prefix { !$0.isNumber }).uppercased()
    }

    /// Des iPhone suivent les pistes : le chrono est interrogé toutes les 8 s, même sans photo à vérifier.
    public func suivreEnDirect(_ actif: Bool) { file.async { [weak self] in self?.direct = actif } }

    /// « C'est changé » touché sur l'iPhone : l'alerte ne revient que si la photo suivante a encore l'ancien code.
    public func alerteVue(boitier: String) {
        file.async { [weak self] in
            guard let self, let j = self.journal, let ch = self.chrono else { return }
            let h = j.dernieres(150).filter { $0.boitier == boitier }.compactMap(\.prise).map { ch.heureChrono($0, boitier: boitier) }.max() ?? 0
            self.alertesVues[boitier] = h
        }
    }

    /// Photos prises autour d'une heure (bouton INCIDENT d'un iPhone), tous boîtiers.
    public func photosAutour(_ heure: Date, secondes: Double = 60) -> [FichePhoto] {
        file.sync {
            (journal?.dernieres(3000) ?? []).filter {
                guard let p = $0.prise else { return false }
                return abs(p.timeIntervalSince(heure)) <= secondes && ![.aRenvoyer, .doublon, .ecartee, .photoCode].contains($0.etat)
            }.sorted { ($0.prise ?? .distantPast) < ($1.prise ?? .distantPast) }
        }
    }

    // MARK: - Photo de synchro (QR)

    /// Ouvre la synchro : pendant `minutes`, une photo du QR règle le boîtier qui l'a prise, avec ces choix.
    public func ouvrirSynchro(_ d: DemandeSynchro, minutes: Double = 10) {
        file.async { [weak self] in
            guard let self else { return }
            if self.demandeSynchro == nil || Date() >= self.synchroJusqua { self.synchroDebut = Date() }
            self.demandeSynchro = d
            self.synchroJusqua = Date().addingTimeInterval(minutes * 60)
        }
    }

    public func fermerSynchro() {
        file.async { [weak self] in
            self?.demandeSynchro = nil
            self?.synchroJusqua = .distantPast
        }
    }

    /// Change le nom, la piste ou le photographe d'un boîtier déjà synchronisé (sans refaire la photo).
    public func modifierBoitier(_ s: BoitierSynchro) {
        file.async { [weak self] in
            guard let self, self.boitiersSynchro[s.boitier] != nil else { return }
            self.enregistrerSynchro(s, nouveau: false)
        }
    }

    /// Oublie la synchro d'un boîtier (son heure n'est plus corrigée).
    public func oublierBoitier(_ boitier: String) {
        file.async { [weak self] in
            guard let self else { return }
            self.boitiersSynchro[boitier] = nil
            self.sauverSynchro()
        }
    }

    private func enregistrerSynchro(_ s: BoitierSynchro, nouveau: Bool = true) {
        boitiersSynchro[s.boitier] = s
        if !s.source.isEmpty { pisteDuBoitier[s.boitier] = s.source }
        if nouveau {
            dernierSynchro = s
            // le nom est propre à chaque boîtier : le suivant devra en recevoir un autre (piste et photographe restent)
            demandeSynchro?.nom = ""
        }
        sauverSynchro()
    }

    private func sauverSynchro() {
        chrono?.regler(ecarts: boitiersSynchro.mapValues(\.ecart))
        guard let f = fichierSynchro else { return }
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? e.encode(Array(boitiersSynchro.values)) { try? d.write(to: f, options: .atomic) }
    }

    private func chargerSynchro() {
        guard let f = fichierSynchro, let d = try? Data(contentsOf: f) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        guard let l = try? dec.decode([BoitierSynchro].self, from: d) else { return }
        boitiersSynchro = Dictionary(l.map { ($0.boitier, $0) }, uniquingKeysWith: { a, _ in a })
        for s in l where !s.source.isEmpty { pisteDuBoitier[s.boitier] = s.source }
        chrono?.regler(ecarts: boitiersSynchro.mapValues(\.ecart))
    }

    /// Galerie du stand : rafraîchir tout de suite (bouton).
    public func rafraichirGalerie() { file.async { [weak self] in self?.galerie?.maintenant() } }

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

    /// La photo déjà reçue sous le même nom qu'un doublon (pour les montrer côte à côte).
    public func premiere(pour doublon: FichePhoto) -> FichePhoto? {
        file.sync { journal?.fiche(nom: doublon.nom, sauf: doublon.id) }
    }

    /// Remplacer la première photo par le doublon (le dernier reçu) : nouvelle copie .cube sur le serveur, et
    /// l'original remplacé là où il est (import Lightroom, tampon ou dossier de travail de Lightroom). L'ancien
    /// original va à la corbeille du Mac : tout reste récupérable.
    public func remplacerPremiere(par doublon: FichePhoto) {
        file.async { [weak self] in
            guard let self, let c = self.config, let j = self.journal else { return }
            let fm = FileManager.default
            let nouvelle = URL(fileURLWithPath: doublon.chemin)
            guard fm.fileExists(atPath: nouvelle.path), var premiere = j.fiche(nom: doublon.nom, sauf: doublon.id) else {
                self.message = "Remplacement impossible : photo introuvable."
                return
            }
            // Où est l'original de la première ? Là où on l'a déposé, sinon dans le dossier de travail de Lightroom.
            var cible: URL? = fm.fileExists(atPath: premiere.chemin) ? URL(fileURLWithPath: premiere.chemin) : nil
            if cible == nil, let travail = c.travailLightroom,
               let e = fm.enumerator(at: travail, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for case let u as URL in e where u.lastPathComponent.caseInsensitiveCompare(premiere.nom) == .orderedSame {
                    cible = u
                    break
                }
            }
            guard let cible else {
                self.message = "Remplacement impossible : l'original de \(premiere.nom) n'a pas été retrouvé."
                return
            }
            do {
                guard let infos = TraitementPhoto.infos(nouvelle) else { throw TraitementPhoto.Erreur.illisible(nouvelle.lastPathComponent) }
                let code = CodePassage.lire(infos.copyright)
                if !premiere.copie.isEmpty {
                    try TraitementPhoto.fabriquerCopie(de: nouvelle, vers: URL(fileURLWithPath: premiere.copie), cote: c.cote,
                                                       qualite: c.qualite, cube: c.cube,
                                                       copyright: code?.texte ?? infos.copyright, priseEXIF: infos.priseEXIF)
                }
                var motsCles: [String] = []
                if let code, let couple = c.concours?.couple(pour: code) {
                    motsCles += [couple.cavalier, couple.cheval].filter { !$0.isEmpty }
                }
                if let code, let ep = c.concours?.epreuve(numero: code.epreuve) { motsCles.append("Épreuve \(ep.nomDossier)") }
                // la nouvelle version est d'abord écrite à côté, puis l'ancienne part à la corbeille
                let provisoire = cible.deletingLastPathComponent().appendingPathComponent(".remplacement-\(cible.lastPathComponent)")
                try TraitementPhoto.copierAvecIPTC(de: nouvelle, vers: provisoire, motsCles: motsCles, codeOrigine: code?.texte ?? "")
                try fm.trashItem(at: cible, resultingItemURL: nil)
                try fm.moveItem(at: provisoire, to: cible)
                try fm.removeItem(at: nouvelle)
                premiere.erreur = "Remplacée par le doublon \(doublon.origine)"
                premiere.chemin = cible.path
                j.mettreAJour(premiere)
                var d = doublon
                d.etat = .ecartee
                d.erreur = "A remplacé la première photo \(premiere.nom)"
                j.mettreAJour(d)
                self.message = "\(premiere.nom) remplacée par le dernier reçu. Dans Lightroom, si l'aperçu n'a pas changé : clic droit > Mettre à jour l'aperçu."
            } catch {
                self.message = "Remplacement : \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Capture Horse & Comp

    /// Les passages lus sur la page d'incrustation de Horses & Competitions (capture), envoyés par l'app.
    public func passagesExternes(_ passages: [Passage], erreur: String = "") {
        file.async { [weak self] in
            guard let ch = self?.chrono, ch.config.externe else { return }
            ch.recevoir(passages, erreur: erreur)
        }
    }

    // MARK: - Codes : décisions de HUGO (« À valider », photos de code, revue)

    /// Applique un code à des photos, où qu'elles en soient :
    /// - mises de côté « À valider » ou gardées en réception : le code est retenu, elles repartent dans le tri ;
    /// - déjà envoyées : la copie du serveur est refaite dans le bon dossier et les métadonnées de l'original
    ///   (Copyright, mots-clés) sont réécrites là où il est, sans toucher l'image. Le code d'origine reste dans
    ///   Job Identifier.
    public func appliquer(code texte: String, a ids: [Int64], qui: String = "HUGO") {
        guard let code = CodePassage.lire(texte) else { return }
        file.async { [weak self] in self?.appliquerSurFile(code: code, ids: ids, qui: qui, essai: 0) }
    }

    private func appliquerSurFile(code: CodePassage, ids: [Int64], qui: String, essai: Int) {
        guard let c = config, let j = journal else { return }
        var plusTard: [Int64] = []
        for id in ids {
            guard var f = j.fiche(id: id) else { continue }
            if enCours.contains(f.chemin) { plusTard.append(id); continue }    // en plein traitement : juste après
            switch f.etat {
            case .aValider, .recue, .erreur:
                f.codeFinal = code.texte
                f.noter(qui, "\(code.texte) · validé")
                f.serie = ""
                if f.etat == .aValider { remettreEnReception(&f, config: c) }
                f.etat = .recue
                j.mettreAJour(f)
                reessayerApres[f.chemin] = nil
            case .copiee, .tampon, .envoyee:
                let id = f.id
                let travail = c.travailLightroom
                ouvriers.addOperation { [weak self] in self?.recoder(id: id, code: code, qui: qui, config: c, travail: travail) }
            default:
                continue
            }
        }
        if !plusTard.isEmpty && essai < 20 {
            file.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.appliquerSurFile(code: code, ids: plusTard, qui: qui, essai: essai + 1)
            }
        }
        message = "Code \(code.texte) appliqué à \(ids.count - plusTard.count) photo\(ids.count - plusTard.count > 1 ? "s" : "")."
    }

    /// Refuser une proposition : la photo part avec le code du photographe, sans redemander au chrono.
    public func garderCodePhotographe(_ ids: [Int64]) {
        file.async { [weak self] in
            guard let self, let c = self.config, let j = self.journal else { return }
            for id in ids {
                guard var f = j.fiche(id: id), f.etat == .aValider else { continue }
                f.marquer(Moteur.codeGarde)
                f.noter("HUGO", "proposition \(f.proposition) refusée, \(f.code.isEmpty ? "sans code" : f.code) gardé")
                f.serie = ""
                self.remettreEnReception(&f, config: c)
                f.etat = .recue
                j.mettreAJour(f)
            }
        }
    }

    /// Photo de code utilisée : son code est appliqué aux photos choisies, et elle sort de « À valider ».
    /// Elle-même n'est jamais envoyée (elle reste dans « _Photos de code » de la réception).
    public func utiliserPhotoCode(_ photoCode: FichePhoto, pour ids: [Int64]) {
        if !ids.isEmpty { appliquer(code: photoCode.code, a: ids, qui: "photo de code") }
        file.async { [weak self] in
            guard let j = self?.journal, var f = j.fiche(id: photoCode.id) else { return }
            f.serie = ""
            f.noter("HUGO", ids.isEmpty ? "photo de code ignorée" : "photo de code appliquée à \(ids.count) photos")
            j.mettreAJour(f)
        }
    }

    /// « Ce n'est pas une photo de code » : elle repart dans le tri comme une photo normale.
    public func pasUnePhotoDeCode(_ photoCode: FichePhoto) {
        file.async { [weak self] in
            guard let self, let c = self.config, let j = self.journal, var f = j.fiche(id: photoCode.id), f.etat == .photoCode else { return }
            f.marquer(Moteur.pasPhotoCode)
            f.serie = ""
            self.remettreEnReception(&f, config: c)
            f.etat = .recue
            j.mettreAJour(f)
        }
    }

    /// Marquer (ou non) une chute : mot-clé CHUTE dans l'original.
    public func marquerChute(_ id: Int64, _ chute: Bool) {
        file.async { [weak self] in
            guard let self, let c = self.config, let j = self.journal, var f = j.fiche(id: id) else { return }
            f.chute = chute
            j.mettreAJour(f)
            guard [.copiee, .tampon, .envoyee].contains(f.etat) else { return }    // pas encore parti : écrit au départ
            let travail = c.travailLightroom
            self.ouvriers.addOperation { [weak self] in self?.reecrireOriginal(id: id, config: c, travail: travail) }
        }
    }

    /// Classement de la revue (bonne, floue, sol, code) : noté pour la mémoire (étape 5), rien n'est retiré.
    public func classer(_ id: Int64, _ classe: String) {
        file.async { [weak self] in
            guard let j = self?.journal, var f = j.fiche(id: id) else { return }
            f.classe = f.classe == classe ? "" : classe
            j.mettreAJour(f)
        }
    }

    /// Photos pour l'écran de revue (lecture seule, depuis n'importe quel fil).
    public func photosRevue(epreuve: String?) -> [FichePhoto] {
        file.sync { journal?.fichesRevue(epreuve: epreuve) ?? [] }
    }

    public func fiche(id: Int64) -> FichePhoto? { file.sync { journal?.fiche(id: id) } }

    /// Remet une photo mise de côté dans la réception (elle y est reprise au tour suivant). Appelé depuis `file`.
    private func remettreEnReception(_ f: inout FichePhoto, config c: ConfigMoteur) {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: f.chemin)
        guard fm.fileExists(atPath: source.path), source.deletingLastPathComponent().standardizedFileURL != c.reception.standardizedFileURL
        else { return }
        let retour = c.reception.appendingPathComponent(Renommage.libre(f.origine) { fm.fileExists(atPath: c.reception.appendingPathComponent($0).path) })
        do {
            try fm.moveItem(at: source, to: retour)
            f.chemin = retour.path
        } catch {
            message = "Remise en réception : \(error.localizedDescription)"
        }
    }

    /// Où est l'original d'une photo envoyée : là où on l'a déposé, sinon dans le dossier de travail de Lightroom.
    private static func trouverOriginal(_ f: FichePhoto, travail: URL?) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: f.chemin) { return URL(fileURLWithPath: f.chemin) }
        guard let travail, let e = fm.enumerator(at: travail, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        for case let u as URL in e where u.lastPathComponent.caseInsensitiveCompare(f.nom) == .orderedSame { return u }
        return nil
    }

    /// Change le code d'une photo déjà envoyée (tourne sur un ouvrier, priorité basse).
    private func recoder(id: Int64, code: CodePassage, qui: String, config c: ConfigMoteur, travail: URL?) {
        guard var f = file.sync(execute: { journal?.fiche(id: id) }) else { return }
        guard let original = Moteur.trouverOriginal(f, travail: travail) else {
            file.sync { message = "Recodage impossible : l'original de \(f.nom) est introuvable." }
            return
        }
        do {
            let ancienne = f.copie
            f.codeFinal = code.texte
            if let couple = c.concours?.couple(pour: code) { f.cavalier = couple.cavalier; f.cheval = couple.cheval } else { f.cavalier = ""; f.cheval = "" }
            let nouvelle = Moteur.dossierServeur(pour: code, config: c).appendingPathComponent(f.nom)
            let dossierNeuf = !FileManager.default.fileExists(atPath: nouvelle.deletingLastPathComponent().path)
            if let infos = TraitementPhoto.infos(original) {
                try TraitementPhoto.fabriquerCopie(de: original, vers: nouvelle, cote: c.cote, qualite: c.qualite, cube: c.cube,
                                                   copyright: code.texte, priseEXIF: infos.priseEXIF)
            }
            if !ancienne.isEmpty, ancienne != nouvelle.path {
                try? FileManager.default.removeItem(atPath: ancienne)
                galerie?.copieFaite(dans: URL(fileURLWithPath: ancienne).deletingLastPathComponent(), nouveau: false)
            }
            galerie?.copieFaite(dans: nouvelle.deletingLastPathComponent(), nouveau: dossierNeuf)
            f.copie = nouvelle.path
            try TraitementPhoto.reecrireMetadonnees(original, motsCles: Moteur.motsCles(f, code: code, config: c),
                                                    codeOrigine: f.code, copyright: code.texte)
            f.chemin = original.path
            f.noter(qui, "\(code.texte) · appliqué (copie du serveur refaite)")
            let g = f
            file.sync { journal?.mettreAJour(g) }
        } catch {
            file.sync { message = "Recodage de \(f.nom) : \(error.localizedDescription)" }
        }
    }

    /// Réécrit les métadonnées de l'original (après CHUTE).
    private func reecrireOriginal(id: Int64, config c: ConfigMoteur, travail: URL?) {
        guard let f = file.sync(execute: { journal?.fiche(id: id) }), let original = Moteur.trouverOriginal(f, travail: travail) else { return }
        let code = CodePassage.lire(f.codeRetenu)
        do {
            try TraitementPhoto.reecrireMetadonnees(original, motsCles: Moteur.motsCles(f, code: code, config: c), codeOrigine: f.code,
                                                    copyright: f.codeFinal.isEmpty ? nil : f.codeFinal)
        } catch {
            file.sync { message = "Mot-clé CHUTE sur \(f.nom) : \(error.localizedDescription)" }
        }
    }

    // MARK: - Suivi du dossier de travail de Lightroom

    /// Ce que le suivi a vu : appliqué sur `file`.
    private func appliquer(_ constat: SuiviLightroom.Constat) {
        guard let c = config, let j = journal else { return }
        for (nom, url) in constat.vues {
            guard var f = j.ficheEnvoyee(nom: nom), f.chemin != url.path else { continue }
            f.chemin = url.path               // rangée par Lightroom dans son dossier de travail
            j.mettreAJour(f)
        }
        for (nom, url) in constat.modifiees {
            guard let f = j.ficheEnvoyee(nom: nom), let infos = TraitementPhoto.infos(url),
                  let nouveau = CodePassage.lire(infos.copyright), nouveau != CodePassage.lire(f.codeRetenu) else { continue }
            // code changé dans Lightroom : copie refaite dans le bon dossier, mots-clés mis à jour
            let id = f.id
            let travail = c.travailLightroom
            ouvriers.addOperation { [weak self] in self?.recoder(id: id, code: nouveau, qui: "Lightroom", config: c, travail: travail) }
        }
        if constat.disparues.count > 20 {
            message = "\(constat.disparues.count) photos ont disparu d'un coup du dossier de travail de Lightroom : rien n'a été retiré du serveur (disque débranché, dossier renommé ?)."
            return
        }
        var retirees = 0
        for nom in constat.disparues {
            guard var f = j.ficheEnvoyee(nom: nom) else { continue }
            if !f.copie.isEmpty {
                try? FileManager.default.removeItem(atPath: f.copie)
                galerie?.copieFaite(dans: URL(fileURLWithPath: f.copie).deletingLastPathComponent(), nouveau: false)
            }
            f.etat = .retiree
            f.noter("Lightroom", "supprimée dans Lightroom : copie retirée du serveur")
            j.mettreAJour(f)
            retirees += 1
        }
        if retirees > 0 { message = "\(retirees) photo\(retirees > 1 ? "s" : "") supprimée\(retirees > 1 ? "s" : "") dans Lightroom : copie retirée du serveur local." }
    }
}
