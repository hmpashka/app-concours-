import AppKit
import Foundation
import TriPhotoCommun
import UniformTypeIdentifiers

/// Les écrans de l'app, dans l'ordre des onglets des maquettes.
enum Ecran: String, CaseIterable, Identifiable {
    case accueil = "Accueil"
    case aValider = "À valider"
    case revue = "Revue"
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
        didSet { if reglages != oldValue { Stockage.ecrire(reglages, nom: "reglages.json") } }
    }
    @Published private(set) var concours: Concours?
    @Published var erreurFFE: String?

    let raccourcis = Raccourcis()
    let entrainement: Entrainement

    init() {
        reglages = Stockage.lire(ReglagesConcours.self, nom: "reglages.json") ?? ReglagesConcours()
        concours = Stockage.lire(Concours.self, nom: "concours.json")
        entrainement = Entrainement()
        if !reglages.dossierReception.isEmpty {
            entrainement.dossierCible = URL(fileURLWithPath: reglages.dossierReception)
        }
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
        v.append(.init(id: "Chronométrage", ok: true, detail: reglages.chronometrage.rawValue))
        return v
    }
}
