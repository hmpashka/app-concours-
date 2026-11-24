import AppKit
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
    case reglages = "Réglages"
    var id: String { rawValue }
}

/// État général de l'app : écran affiché, panneaux, réglages du concours, fichier FFE chargé.
@MainActor
final class Etat: ObservableObject {
    @Published var ecran: Ecran = .reglages
    @Published var panneauGauche = true
    @Published var panneauDroit = true
    @Published var montrerEntrainement = false

    @Published var reglages: ReglagesConcours {
        didSet {
            guard reglages != oldValue else { return }
            Stockage.ecrire(reglages, nom: "reglages.json")
            if Etat.reglagesGalerie(reglages) != Etat.reglagesGalerie(oldValue) { galerieEnLigneChangee() }
            if reglages.accesDistance != oldValue.accesDistance || reglages.portAccesDistance != oldValue.portAccesDistance {
                reglerAccesDistance()
            }
        }
    }
    @Published private(set) var concours: Concours?
    @Published var erreurFFE: String?

    let raccourcis = Raccourcis()
    let moteur = Moteur()
    @Published var erreurDemarrage: String?
    let entrainement: Entrainement
    let capture = CaptureHorseComp()
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
    /// Clé API de la console UniFi (régulateur réseau) : dans le trousseau du Mac.
    @Published var cleUniFi: String = Trousseau.lire("unifi") {
        didSet { Trousseau.ecrire("unifi", cleUniFi); galerieEnLigneChangee() }
    }
    @Published var montrerTerrain = false
    @Published var cloture: GenreCloture?
    /// Engagés terrain quand le tri ne tourne pas (sinon : ceux du moteur, qui ajoute aussi ceux du chrono).
    @Published var terrainHorsTri: [EngageTerrain] = []
    @Published var messageAttribution = ""
    let serveur = ServeurPiste()
    let acces = AccesDistance()
    /// « Voir les photos de ce moment » (incident d'un iPhone) : la revue montre les photos autour de cette heure.
    @Published var momentRevue: (heure: Date, titre: String)?
    /// L'état en cours (pour les clics sur les notifications du Mac).
    static weak var courant: Etat?

    init() {
        reglages = Stockage.lire(ReglagesConcours.self, nom: "reglages.json") ?? ReglagesConcours()
        concours = Stockage.lire(Concours.self, nom: "concours.json")
        entrainement = Entrainement()
        capture.zones = { [weak self] in self?.reglages.zonesIncrustation ?? [:] }
        capture.concours = { [weak self] in self?.concours }
        capture.epreuveForcee = { [weak self] in self?.reglages.epreuveForcee ?? "" }
        if !reglages.dossierReception.isEmpty {
            entrainement.dossierCible = URL(fileURLWithPath: reglages.dossierReception)
        }
        let m = moteur
        serveur.resume = { m.resume }
        serveur.reglages = { [weak self] in self?.reglages ?? ReglagesConcours() }
        serveur.concours = { [weak self] in self?.concours }
        serveur.surMessages = { [weak self] in self?.ecran == .messages }
        serveur.alerteVue = { m.alerteVue(boitier: $0) }
        serveur.suivreEnDirect = { m.suivreEnDirect($0) }
        Etat.courant = self
        serveur.demarrer()
        terrainHorsTri = fichierTerrain.map { Moteur.engagesTerrain(fichier: $0) } ?? []
        acces.moteur = m
        acces.code = { [weak self] in self?.reglages.codeAccesDistance ?? "" }
        acces.etat = { [weak self] in self?.etatDistance() }
        reglerAccesDistance()
    }

    /// Sources du chrono vues aujourd'hui (pour relier les pistes des réglages à celles du chrono).
    func sourcesChrono(plus: String) -> [String] {
        var l = Set(moteur.resume.suivis.keys)
        if !plus.isEmpty { l.insert(plus) }
        return l.sorted()
    }

    /// Ouvre la synchro des boîtiers (photo du QR) avec ces choix pour le prochain boîtier.
    func demanderSynchro(nom: String, piste: String, photographe: String) {
        let source = ServeurPiste.source(pour: piste, reglages: reglages, sources: Array(moteur.resume.suivis.keys)) ?? ""
        moteur.ouvrirSynchro(DemandeSynchro(nom: nom, piste: piste, source: source, photographe: photographe))
    }

    /// Ouvre la revue sur les photos prises autour d'une heure (incident).
    func voirMoment(_ heure: Date, titre: String) {
        momentRevue = (heure, titre)
        ecran = .revue
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
        } catch {
            erreurFFE = error.localizedDescription
        }
    }

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
            var cube: FichierCube?
            if !r.cubeServeur.isEmpty { cube = try FichierCube(fichier: URL(fileURLWithPath: r.cubeServeur)) }
            var chrono: ConfigChrono?
            if r.chronometrage == .captureHorseComp {
                chrono = ConfigChrono(adresse: "", codeRegie: "", codeTechnicien: "",
                                      apresArrivee: Double(r.finDeTourSecondes), latence: Double(r.latenceSecondes),
                                      attenteMaxMinutes: Double(r.attenteChronoMinutes), externe: true)
            } else if r.chronometrage == .hmTiming && (!r.adresseHM.isEmpty || !r.fichierPassagesEntrainement.isEmpty) {
                chrono = ConfigChrono(adresse: r.adresseHM, codeRegie: r.codeRegieHM, codeTechnicien: r.codeTechHM,
                                      apresArrivee: Double(r.finDeTourSecondes), latence: Double(r.latenceSecondes),
                                      attenteMaxMinutes: Double(r.attenteChronoMinutes),
                                      fichierPassages: r.fichierPassagesEntrainement.isEmpty ? nil
                                          : URL(fileURLWithPath: r.fichierPassagesEntrainement))
            }
            try moteur.demarrer(ConfigMoteur(reception: reception, importLightroom: importLR, tampon: tampon,
                                             serveur: serveur, cote: r.coteServeur, qualite: r.qualiteServeur,
                                             cube: cube, concours: concours, tailleLot: r.tailleLot,
                                             silenceMinutes: r.silenceBoitierMinutes,
                                             retarderSiOccupe: r.retarderSiLightroomOccupe,
                                             journal: Stockage.dossier.appendingPathComponent("journal.sqlite"),
                                             travailLightroom: r.dossierTravailLightroom.isEmpty ? nil
                                                 : URL(fileURLWithPath: r.dossierTravailLightroom, isDirectory: true),
                                             chrono: chrono, attente00Minutes: Double(r.attente00Minutes),
                                             galerie: r.urlGalerieStand.isEmpty ? nil : ConfigGalerie(
                                                 adresse: r.urlGalerieStand, identifiant: r.identifiantGalerieStand,
                                                 motDePasse: motDePasseGalerie, minutes: Double(r.minutesGalerieStand),
                                                 empreinte: r.empreinteGalerieStand,
                                                 sauverEmpreinte: { emp in
                                                     Task { @MainActor in Etat.courant?.reglages.empreinteGalerieStand = emp }
                                                 }),
                                             galerieEnLigne: configGalerieEnLigne(),
                                             fichierTerrain: fichierTerrain))
            if !fichierDebutExiste { creerFichierDebut(silencieux: true) }
            if chrono?.externe == true {
                let m = moteur
                capture.envoyer = { p, e in m.passagesExternes(p, erreur: e) }
                if !capture.ouverte && !r.urlIncrustation.isEmpty { capture.ouvrir(r.urlIncrustation) }
                m.passagesExternes(capture.passages)
            }
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
        switch reglages.chronometrage {
        case .hmTiming:
            let ok = !reglages.adresseHM.isEmpty || !reglages.fichierPassagesEntrainement.isEmpty
            v.append(.init(id: "Chronométrage", ok: ok, detail: ok ? "HM Timing · \(reglages.adresseHM.isEmpty ? "fichier d'entraînement" : reglages.adresseHM)"
                                                              : "Adresse de HM Timing à régler (sinon : codes du photographe gardés)"))
        case .captureHorseComp:
            let ok = !reglages.urlIncrustation.isEmpty && reglages.zonesIncrustation["dossard"] != nil
            v.append(.init(id: "Chronométrage", ok: ok, detail: ok ? "Capture Horse & Comp · zones réglées"
                                                              : "Capture Horse & Comp : adresse et zones à régler"))
        }
        return v
    }
}
