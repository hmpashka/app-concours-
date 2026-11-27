import AppKit
import Combine
import Foundation
import TriPhotoCommun
import TriPhotoMoteur
import UniformTypeIdentifiers

/// Les écrans de l'app, dans l'ordre des onglets des maquettes.
enum Ecran: String, CaseIterable, Identifiable {
    case accueil = "Accueil"
    case aValider = "À valider"
    case revue = "Revue"
    case messages = "Messages"
    case memoire = "Mémoire"
    case commandes = "Commandes"
    case auBureau = "Au bureau"
    case reglages = "Réglages"
    var id: String { rawValue }
}

/// État général de l'app : écran affiché, panneaux, réglages du concours, fichier FFE chargé.
@MainActor
final class Etat: ObservableObject {
    @Published var ecran: Ecran = .reglages
    @Published var panneauGauche = true
    @Published var panneauDroit = true
    @Published var pleinEcran = false
    /// Photo où en était la Revue, pour y revenir après un tour dans un autre onglet (pas publié : rien à redessiner).
    var revuePhotoId: Int64?            // Revue : la photo seule sur fond noir (touche P)
    @Published var montrerEntrainement = false

    @Published var reglages: ReglagesConcours {
        didSet {
            guard reglages != oldValue else { return }
            Stockage.ecrire(reglages, nom: "reglages.json")
            if Etat.reglagesGalerie(reglages) != Etat.reglagesGalerie(oldValue) { galerieEnLigneChangee() }
            if reglages.accesDistance != oldValue.accesDistance || reglages.portAccesDistance != oldValue.portAccesDistance {
                reglerAccesDistance()
            }
            if reglages.dossierListings != oldValue.dossierListings {
                if retourListings { retourListings = false } else { changerDossierListings(depuis: oldValue) }
            }
            if reglages.dossierMemoire != oldValue.dossierMemoire {
                if retourMemoire { retourMemoire = false } else { changerDossierMemoire(depuis: oldValue) }
            }
        }
    }
    @Published private(set) var concours: Concours?
    @Published var erreurFFE: String?

    let raccourcis = Raccourcis()
    let moteur = Moteur()
    @Published var erreurDemarrage: String?
    let entrainement: Entrainement
    /// Une capture Horse & Comp par chrono Horse & Comp des réglages (page cachée, texte seulement).
    private(set) var captures: [String: CaptureHorseComp] = [:]
    /// Chrono Horse & Comp dont l'écran de capture est ouvert.
    @Published var captureChoisie = ""
    @Published var montrerCapture = false
    @Published var montrerSynchro = false
    /// Mot de passe de la galerie du stand : dans le trousseau du Mac, jamais dans reglages.json.
    @Published var motDePasseGalerie: String = Trousseau.lire("galerie-stand") {
        didSet { Trousseau.ecrire("galerie-stand", motDePasseGalerie) }
    }
    /// Mot de passe de la galerie en ligne (FTP / SFTP) : dans le trousseau du Mac.
    @Published var motDePasseGalerieEnLigne: String = Trousseau.lire("galerie-en-ligne") {
        didSet { Trousseau.ecrire("galerie-en-ligne", motDePasseGalerieEnLigne); galerieEnLigneChangee() }
    }
    @Published var montrerTerrain = false
    @Published var cloture: GenreCloture?
    /// Fenêtre « Commencer un nouveau concours » / « Rouvrir un concours rangé » (HUGO 26/11).
    @Published var nouveauConcours: DemandeNouveauConcours?
    /// Concours rangés sur ce Mac (pas finis ou finis), à rouvrir.
    @Published var concoursRanges: [ConcoursRange] = []
    /// Engagés terrain quand le tri ne tourne pas (sinon : ceux du moteur, qui ajoute aussi ceux du chrono).
    @Published var terrainHorsTri: [EngageTerrain] = []
    @Published var messageAttribution = ""
    let serveur = ServeurPiste()
    @Published var messageMemoire = ""
    /// Listings des concours et commandes de pack photo (dossier iCloud partagé entre les Mac).
    let archives: Archives
    /// Onglet « Au bureau » : archives des années passées, index, recherche, copies sur le Bureau.
    let bureau = EtatBureau()
    /// Ancien dossier de la mémoire, s'il y reste des vignettes pas encore téléchargées d'iCloud.
    @Published var ancienDossierMemoire: URL?
    /// Retour à l'ancien dossier de la mémoire après un choix refusé (rien à déplacer).
    var retourMemoire = false
    var retourListings = false
    /// La mémoire partagée (dossier iCloud des stands).
    @Published var memoire: Memoire
    let acces = AccesDistance()
    /// Loupedeck CT : pont local (ce Mac seulement) et ordres passés aux écrans Revue / À valider.
    let loupedeck = PontLoupedeck()
    let ordresLoupedeck = PassthroughSubject<OrdreLoupedeck, Never>()
    /// Tenus à jour par la Revue et « À valider » (pas @Published : rien à redessiner).
    var infoRevueLoupedeck: EtatLoupedeck.Revue?
    var infoSerieLoupedeck: EtatLoupedeck.Serie?
    var photoLoupedeck: Int64?
    @Published var etatAccesDistance = ""
    /// « Voir les photos de ce moment » (incident d'un iPhone) : la revue montre les photos autour de cette heure.
    @Published var momentRevue: (heure: Date, titre: String)?
    /// « Revoir » une série validée : la revue montre seulement ces photos (ids), pour les trier.
    @Published var photosRevue: (ids: [Int64], titre: String)?
    /// Les dernières séries validées ou refusées dans « À valider » (les plus récentes d'abord), pour les revoir.
    @Published var seriesValidees: [(ids: [Int64], titre: String, heure: Date)] = []
    /// L'état en cours (pour les clics sur les notifications du Mac).
    static weak var courant: Etat?

    /// Rafraîchissement de la galerie du stand (serveur local). nil : pas d'adresse.
    func configGalerieStand() -> ConfigGalerie? {
        let r = reglages
        guard !r.urlGalerieStand.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return ConfigGalerie(adresse: r.urlGalerieStand, identifiant: r.identifiantGalerieStand,
                             motDePasse: motDePasseGalerie,
                             // 0 = « en direct » (HUGO 26/11) : toutes les 30 s pendant une rafale, 10 s après la dernière photo
                             minutes: r.minutesGalerieStand == 0 ? 0.5 : Double(r.minutesGalerieStand),
                             calmeSecondes: r.minutesGalerieStand == 0 ? 10 : 30,
                             empreinte: r.empreinteGalerieStand,
                             sauverEmpreinte: { emp in
                                 Task { @MainActor in Etat.courant?.reglages.empreinteGalerieStand = emp }
                             })
    }

    init() {
        let r = Stockage.lire(ReglagesConcours.self, nom: "reglages.json") ?? ReglagesConcours()
        reglages = r
        memoire = Memoire(dossier: Etat.dossierMemoire(r))
        archives = Archives(dossier: Etat.dossierListings(r))
        concours = Stockage.lire(Concours.self, nom: "concours.json")
        concoursRanges = ConcoursRange.tous()
        entrainement = Entrainement()
        if !reglages.dossierReception.isEmpty {
            entrainement.dossierCible = URL(fileURLWithPath: reglages.dossierReception)
        }
        let m = moteur
        bureau.concoursEnCours = { m.actif }
        serveur.resume = { m.resume }
        serveur.reglages = { [weak self] in self?.reglages ?? ReglagesConcours() }
        serveur.concours = { [weak self] in self?.concours }
        serveur.surMessages = { [weak self] in self?.ecran == .messages }
        serveur.alerteVue = { m.alerteVue(boitier: $0) }
        serveur.chercherClients = { [weak self] t in self?.chercherClients(t) ?? [] }
        serveur.commandesDuConcours = { [weak self] in
            guard let self else { return [] }
            self.archives.relire(forcer: false)          // les commandes prises sur les autres Mac (toutes les 20 s)
            return self.archives.commandes(concours: self.idConcours)
        }
        serveur.enregistrerCommande = { [weak self] k in self?.archives.enregistrer(k) }
        serveur.suivreEnDirect = { m.suivreEnDirect($0) }
        Etat.courant = self
        StandsUniFi.partages.demarrer()        // l'UDM de la remorque où le Mac est branché
        Notifieur.partage.surveiller(m) { [weak self] in self?.reglages.silenceBoitierMinutes ?? 5 }
        serveur.demarrer()
        terrainHorsTri = fichierTerrain.map { Moteur.engagesTerrain(fichier: $0) } ?? []
        acces.moteur = m
        acces.surEtat = { t in Task { @MainActor in Etat.courant?.etatAccesDistance = t } }
        acces.code = { [weak self] in self?.reglages.codeAccesDistance ?? "" }
        acces.etat = { [weak self] in self?.etatDistance() }
        reglerAccesDistance()
        brancherLoupedeck()
    }

    /// Pistes vues aujourd'hui dans un chrono, telles qu'il les nomme (pour relier les pistes des réglages aux siennes).
    func sourcesChrono(_ c: ReglagesConcours.ChronoConcours?, plus: String) -> [String] {
        var l = Set<String>()
        if let c, let e = moteur.resume.chrono?.liens.first(where: { $0.id == c.id.uuidString }) {
            l.formUnion(e.sources)
        } else if c == nil {
            l.formUnion(moteur.resume.suivis.keys.map(ConfigLienChrono.brut))
        }
        if !plus.isEmpty { l.insert(plus) }
        return l.sorted()
    }

    /// La capture Horse & Comp d'un chrono (créée à la première demande).
    func capture(pour id: String) -> CaptureHorseComp {
        if let c = captures[id] { return c }
        let c = CaptureHorseComp(id: id)
        c.zones = { [weak self] in self?.reglages.chrono(id: id)?.zones ?? [:] }
        c.concours = { [weak self] in self?.concours }
        c.epreuveForcee = { [weak self] in self?.reglages.chrono(id: id)?.epreuveForcee ?? "" }
        captures[id] = c
        return c
    }

    /// Les chronos en quelques mots (sous-titre, clôture, accès à distance).
    var texteChronos: String {
        let prets = reglages.chronos.filter(\.pret)
        if prets.isEmpty { return reglages.fichierPassagesEntrainement.isEmpty ? "Sans chrono" : "Entraînement" }
        if prets.count == 1 { return prets[0].genre == .horseComp ? "Capture Horse & Comp" : "HM Timing" }
        return "\(prets.count) chronos"
    }

    /// Ouvre la synchro des boîtiers (photo du QR) avec ces choix pour le prochain boîtier.
    func demanderSynchro(nom: String, piste: String, photographe: String) {
        let source = ServeurPiste.source(pour: piste, reglages: reglages, sources: Array(moteur.resume.suivis.keys)) ?? ""
        moteur.ouvrirSynchro(DemandeSynchro(nom: nom, piste: piste, source: source, photographe: photographe))
    }

    /// Ouvre la revue sur les photos prises autour d'une heure (incident).
    func voirMoment(_ heure: Date, titre: String) {
        photosRevue = nil
        momentRevue = (heure, titre)
        ecran = .revue
    }

    /// Ouvre la revue sur ces photos seulement (série validée).
    func voirPhotos(_ ids: [Int64], titre: String) {
        momentRevue = nil
        photosRevue = (ids, titre)
        ecran = .revue
    }

    /// Note une série validée pour pouvoir la revoir ensuite (20 dernières).
    func noterSerieValidee(_ ids: [Int64], titre: String) {
        guard !ids.isEmpty else { return }
        seriesValidees.insert((ids, titre, Date()), at: 0)
        if seriesValidees.count > 20 { seriesValidees.removeLast(seriesValidees.count - 20) }
    }

    // MARK: - Panneaux

    func basculerTousLesPanneaux() {
        let afficher = !(panneauGauche || panneauDroit)
        panneauGauche = afficher
        panneauDroit = afficher
    }

    // MARK: - Fichier FFE

    /// Ouvre le sélecteur de fichier puis charge le fichier FFE choisi.
    func choisirFichierFFE() {
        let p = NSOpenPanel()
        p.title = "Fichier FFE du concours"
        p.message = "Choisis le fichier du SIF (conc….xml) ou de FFE Compet."
        p.allowedContentTypes = [.xml]
        p.allowsMultipleSelection = false
        if p.runModal() == .OK, let url = p.url { chargerFFE(url) }
    }

    func chargerFFE(_ url: URL) {
        do {
            let c = try LecteurFFE.lire(fichier: url)
            concours = c
            erreurFFE = nil
            reglages.cheminFFE = url.path
            if reglages.nomConcours.isEmpty { reglages.nomConcours = c.nom.capitalized }
            Stockage.ecrire(c, nom: "concours.json")
            garderListing()
        } catch {
            erreurFFE = error.localizedDescription
        }
    }

    /// Concours rangé (plus de fichier FFE) ou rouvert (son fichier FFE lu relu).
    func remplacerConcours(_ c: Concours?) { concours = c }

    /// Recharge le même fichier (après une mise à jour du SIF par exemple).
    func rechargerFFE() {
        guard !reglages.cheminFFE.isEmpty else { return choisirFichierFFE() }
        chargerFFE(URL(fileURLWithPath: reglages.cheminFFE))
    }

    // MARK: - Modèles de concours

    func enregistrerModele(nom: String) {
        let n = NomDossier.nettoyer(nom)
        guard !n.isEmpty else { return }
        var modele = reglages
        modele.cheminFFE = ""          // le fichier FFE change à chaque concours
        modele.nomConcours = ""
        Stockage.ecrire(modele, vers: Stockage.dossierModeles.appendingPathComponent(n + ".json"))
    }

    func chargerModele(nom: String) {
        let url = Stockage.dossierModeles.appendingPathComponent(nom + ".json")
        guard let data = try? Data(contentsOf: url),
              var m = try? JSONDecoder().decode(ReglagesConcours.self, from: data) else { return }
        m.cheminFFE = reglages.cheminFFE
        m.nomConcours = reglages.nomConcours
        reglages = m
    }

    // MARK: - Journée (moteur photos)

    /// Démarre le tri : vérifie les dossiers, lit le .cube, puis lance le moteur et ouvre l'accueil.
    func demarrerJournee() {
        let r = reglages
        func dossier(_ chemin: String, _ nom: String) throws -> URL {
            var estDossier: ObjCBool = false
            guard !chemin.isEmpty, FileManager.default.fileExists(atPath: chemin, isDirectory: &estDossier),
                  estDossier.boolValue else {
                throw NSError(domain: "TriPhoto", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(nom) : dossier introuvable."])
            }
            return URL(fileURLWithPath: chemin, isDirectory: true)
        }
        do {
            let reception = try dossier(r.dossierReception, "Dossier de réception")
            let importLR = try dossier(r.dossierImportLightroom, "Import Lightroom")
            let serveur = try dossier(r.dossierServeurLocal, "Serveur local")
            var tampon: URL?
            if r.tamponActif { tampon = try dossier(r.dossierTampon, "Dossier tampon") }
            if Set([reception, importLR, serveur].map(\.standardizedFileURL)).count < 3 {
                throw NSError(domain: "TriPhoto", code: 2, userInfo: [NSLocalizedDescriptionKey:
                    "La réception, l'import Lightroom et le serveur local doivent être trois dossiers différents."])
            }
            if let t = tampon?.standardizedFileURL, [reception, importLR, serveur].map(\.standardizedFileURL).contains(t) {
                throw NSError(domain: "TriPhoto", code: 2, userInfo: [NSLocalizedDescriptionKey:
                    "Le dossier tampon doit être un dossier à part (ni la réception, ni l'import Lightroom, ni le serveur local)."])
            }
            var cube: FichierCube?
            if !r.cubeServeur.isEmpty { cube = try FichierCube(fichier: URL(fileURLWithPath: r.cubeServeur)) }
            // Les chronos : chaque HM Timing réglé, chaque Horse & Comp ; le mode entraînement remplace les HM Timing.
            var liens: [ConfigLienChrono] = []
            if !r.fichierPassagesEntrainement.isEmpty {
                liens.append(ConfigLienChrono(id: "entrainement", nom: "Entraînement",
                                              fichierPassages: URL(fileURLWithPath: r.fichierPassagesEntrainement)))
            } else {
                liens += r.chronos.filter { $0.genre == .hmTiming && $0.pret }.map(r.lien)
            }
            let horseComp = r.chronos.filter { $0.genre == .horseComp && $0.pret }
            liens += horseComp.map(r.lien)
            let chrono: ConfigChrono? = liens.isEmpty ? nil
                : ConfigChrono(liens: liens, apresArrivee: Double(r.finDeTourSecondes), latence: Double(r.latenceSecondes),
                               attenteMaxMinutes: Double(r.attenteChronoMinutes))
            try moteur.demarrer(ConfigMoteur(reception: reception, importLightroom: importLR, tampon: tampon,
                                             serveur: serveur, cote: r.coteServeur, qualite: r.qualiteServeur,
                                             cube: cube, concours: concours, tailleLot: r.tailleLot,
                                             silenceMinutes: r.silenceBoitierMinutes,
                                             retarderSiOccupe: r.retarderSiLightroomOccupe,
                                             journal: Stockage.dossier.appendingPathComponent("journal.sqlite"),
                                             travailLightroom: r.dossierTravailLightroom.isEmpty ? nil
                                                 : URL(fileURLWithPath: r.dossierTravailLightroom, isDirectory: true),
                                             chrono: chrono, attente00Minutes: Double(r.attente00Minutes),
                                             galerie: configGalerieStand(),
                                             galerieEnLigne: configGalerieEnLigne(),
                                             fichierTerrain: fichierTerrain,
                                             memoire: r.detectionsActives ? memoire : nil,
                                             remises: configRemises(),
                                             sauvegarde: r.sauvegardeActive && !r.dossierSauvegarde.isEmpty
                                                 ? URL(fileURLWithPath: r.dossierSauvegarde, isDirectory: true) : nil,
                                             rushAuto: r.rushAutoPhotos, ouvriersMax: r.photosEnMemeTemps))
            if !fichierDebutExiste { creerFichierDebut(silencieux: true) } else { ecrireListingTexte() }
            garderListing()
            let m = moteur
            for c in horseComp {
                let id = c.id.uuidString
                let cap = capture(pour: id)
                cap.envoyer = { p, e in m.passagesExternes(lien: id, p, erreur: e) }
                if !cap.ouverte { cap.ouvrir(c.urlIncrustation) }
                m.passagesExternes(lien: id, cap.passages)
            }
            // captures de chronos retirés des réglages : fermées
            for (id, cap) in captures where !horseComp.contains(where: { $0.id.uuidString == id }) && cap.ouverte { cap.fermer() }
            erreurDemarrage = nil
            ecran = .accueil
        } catch {
            erreurDemarrage = error.localizedDescription
        }
    }

    func arreterJournee() { moteur.arreter() }

    // MARK: - Prêt à démarrer ?

    struct Verification: Identifiable {
        let id: String
        let ok: Bool
        let detail: String
    }

    var verifications: [Verification] {
        let fm = FileManager.default
        func dossierOK(_ chemin: String) -> Bool {
            var estDossier: ObjCBool = false
            return !chemin.isEmpty && fm.fileExists(atPath: chemin, isDirectory: &estDossier) && estDossier.boolValue
        }
        var v: [Verification] = []
        if let c = concours {
            v.append(.init(id: "Fichier FFE", ok: true,
                           detail: "\(c.format.rawValue) · \(c.epreuves.count) épreuves · \(c.nombreEngages) engagés"))
        } else {
            v.append(.init(id: "Fichier FFE", ok: false, detail: "À charger"))
        }
        let dossiers: [(String, String)] = [
            ("Dossier de réception", reglages.dossierReception),
            ("Import Lightroom", reglages.dossierImportLightroom),
            ("Travail Lightroom", reglages.dossierTravailLightroom),
            ("Serveur local", reglages.dossierServeurLocal),
        ]
        for (nom, chemin) in dossiers {
            let ok = dossierOK(chemin)
            v.append(.init(id: nom, ok: ok, detail: ok ? "Trouvé" : (chemin.isEmpty ? "À choisir" : "Introuvable (disque ou serveur absent ?)")))
        }
        if reglages.tamponActif {
            let ok = dossierOK(reglages.dossierTampon)
            v.append(.init(id: "Dossier tampon", ok: ok, detail: ok ? "Trouvé" : "À choisir"))
        }
        let cubeOK = !reglages.cubeServeur.isEmpty && fm.isReadableFile(atPath: reglages.cubeServeur)
        v.append(.init(id: "Fichier .cube", ok: cubeOK, detail: cubeOK ? (reglages.cubeServeur as NSString).lastPathComponent : "À choisir"))
        if reglages.chronos.isEmpty {
            v.append(.init(id: "Chronométrage", ok: false, detail: "Aucun chrono : les codes du photographe sont gardés"))
        }
        for c in reglages.chronos {
            let id = reglages.chronos.count > 1 ? "Chrono « \(c.nom) »" : "Chronométrage"
            switch c.genre {
            case .hmTiming:
                let entrainement = !reglages.fichierPassagesEntrainement.isEmpty
                let ok = c.pret || entrainement
                v.append(.init(id: id, ok: ok, detail: ok ? "HM Timing · \(entrainement ? "fichier d'entraînement" : c.adresse)"
                                                  : "Adresse de HM Timing à régler (sinon : codes du photographe gardés)"))
            case .horseComp:
                let ok = c.pret && c.zones["dossard"] != nil
                v.append(.init(id: id, ok: ok, detail: ok ? "Capture Horse & Comp · zones réglées"
                                                  : "Capture Horse & Comp : adresse et zones à régler"))
            }
        }
        return v
    }
}
