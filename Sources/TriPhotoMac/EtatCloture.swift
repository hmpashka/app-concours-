import AppKit
import Foundation
import TriPhotoCommun
import TriPhotoMoteur

/// Clôture du soir (chaque jour) ou clôture finale (le dernier jour).
enum GenreCloture: String, Identifiable {
    case journee = "Clôturer la journée"
    case finale = "Clôturer le concours"
    var id: String { rawValue }
}

/// Étape 4 : galerie en ligne, engagés terrain, fichiers d'attribution, clôture.
extension Etat {
    // MARK: - Galerie en ligne

    /// Ce qui compte pour l'envoi vers la galerie en ligne (un changement règle le moteur à nouveau).
    static func reglagesGalerie(_ r: ReglagesConcours) -> String {
        [r.adresseFTPGalerie, r.protocoleGalerie.rawValue, "\(r.portGalerie)", r.identifiantGalerie, r.dossierGalerie,
         "\(r.accepterCertificatGalerie)", "\(r.galerieLaNuit)", "\(r.heureNuitGalerie)", "\(r.heureMatinGalerie)",
         "\(r.limiteKoGalerie)", r.auteurGalerie, "\(r.coteGalerie)", "\(r.qualiteGalerie)", "\(r.numeroIncruste)",
         "\(r.cubeGalerieIdentique)", r.cubeGalerie, r.cubeServeur, r.adresseUniFi, "\(r.montantMbitLigne)",
         "\(r.seuilUniFi)"].joined(separator: "|")
    }

    /// Premier jour du concours (fichier FFE), sinon aujourd'hui moins les jours du concours.
    var debutConcours: Date {
        let jours = (concours?.epreuves ?? []).compactMap { FichierEngages.dateISO($0.date) }
        if let d = jours.min() { return Calendar.current.startOfDay(for: d) }
        let aujourdhui = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: -(max(1, reglages.nombreJours) - 1), to: aujourdhui) ?? aujourdhui
    }

    /// Dernier jour du concours (fichier FFE), sinon le premier jour plus les jours du concours.
    var finConcours: Date {
        let jours = (concours?.epreuves ?? []).compactMap { FichierEngages.dateISO($0.date) }
        if let d = jours.max() { return Calendar.current.startOfDay(for: d) }
        return Calendar.current.date(byAdding: .day, value: max(1, reglages.nombreJours) - 1, to: debutConcours) ?? debutConcours
    }

    var cleConcours: String {
        let n = concours?.numero ?? ""
        return NomDossier.nettoyer(n.isEmpty ? (reglages.nomConcours.isEmpty ? "concours" : reglages.nomConcours) : n)
    }

    var fichierTerrain: URL? { Stockage.dossier.appendingPathComponent("engages-terrain-\(cleConcours).json") }

    /// Réglages de la galerie en ligne pour le moteur ; nil si l'adresse n'est pas remplie.
    func configGalerieEnLigne() -> ConfigGalerieEnLigne? {
        let r = reglages
        let hote = r.adresseFTPGalerie.trimmingCharacters(in: .whitespaces)
        guard !hote.isEmpty else { return nil }
        let chemin = r.cubeGalerieIdentique ? r.cubeServeur : r.cubeGalerie
        let cube = chemin.isEmpty ? nil : try? FichierCube(fichier: URL(fileURLWithPath: chemin))
        return ConfigGalerieEnLigne(protocole: r.protocoleGalerie, hote: Etat.hoteSeul(hote), port: r.portGalerie,
                                    identifiant: r.identifiantGalerie, motDePasse: motDePasseGalerieEnLigne,
                                    dossier: r.dossierGalerie, accepterCertificat: r.accepterCertificatGalerie,
                                    laNuit: r.galerieLaNuit, heureNuit: r.heureNuitGalerie, heureMatin: r.heureMatinGalerie,
                                    limiteKo: r.limiteKoGalerie, cote: r.coteGalerie, qualite: r.qualiteGalerie, cube: cube,
                                    cubeDuServeur: r.cubeGalerieIdentique, numero: r.numeroIncruste,
                                    auteurParDefaut: r.auteurGalerie, depuis: debutConcours,
                                    fichierEtat: Stockage.dossier.appendingPathComponent("galerie-en-ligne-\(cleConcours).json"),
                                    unifi: configUniFi())
    }

    /// Régulateur réseau : nil sans adresse ou sans clé API.
    func configUniFi() -> ConfigUniFi? {
        let r = reglages
        guard !r.adresseUniFi.trimmingCharacters(in: .whitespaces).isEmpty, !cleUniFi.isEmpty else { return nil }
        return ConfigUniFi(adresse: r.adresseUniFi, cle: cleUniFi, montantMbit: Double(r.montantMbitLigne),
                           seuil: Double(r.seuilUniFi) / 100, empreinte: r.empreinteUniFi,
                           sauverEmpreinte: { emp in Task { @MainActor in Etat.courant?.reglages.empreinteUniFi = emp } })
    }

    /// « ftp://ftp.site.fr/ » ou « sftp://site.fr » collés depuis FileZilla → « ftp.site.fr ».
    static func hoteSeul(_ s: String) -> String {
        var h = s
        for p in ["sftp://", "ftps://", "ftp://"] where h.lowercased().hasPrefix(p) { h = String(h.dropFirst(p.count)) }
        return String(h.split(separator: "/").first ?? Substring(h))
    }

    func galerieEnLigneChangee() {
        guard moteur.actif, let g = configGalerieEnLigne() else { return }
        moteur.reglerGalerieEnLigne(g)
    }

    // MARK: - Engagés terrain

    /// Les engagés terrain du concours : ceux du moteur pendant le tri (il ajoute ceux vus par le chrono).
    var engagesTerrain: [EngageTerrain] { moteur.actif ? moteur.resume.engagesTerrain : terrainHorsTri }

    func enregistrerEngageTerrain(_ e: EngageTerrain) {
        if moteur.actif {
            moteur.enregistrerEngageTerrain(e)
        } else {
            if let i = terrainHorsTri.firstIndex(where: { $0.id == e.id }) { terrainHorsTri[i] = e } else { terrainHorsTri.append(e) }
            sauverTerrainHorsTri()
        }
        mettreAJourFichierFinBientot()
    }

    /// Engagé terrain ajouté, corrigé ou retiré pendant le concours (HUGO 24/11) : le fichier de fin est réécrit tout
    /// de suite, sans attendre la clôture (le moteur met une seconde à prendre le changement en compte).
    private func mettreAJourFichierFinBientot() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.creerFichierFin(enDirect: true) }
    }

    func retirerEngageTerrain(_ e: EngageTerrain) {
        if moteur.actif {
            moteur.retirerEngageTerrain(id: e.id)
        } else {
            terrainHorsTri.removeAll { $0.id == e.id }
            sauverTerrainHorsTri()
        }
        mettreAJourFichierFinBientot()
    }

    private func sauverTerrainHorsTri() {
        guard let u = fichierTerrain else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(terrainHorsTri) { try? d.write(to: u, options: .atomic) }
    }

    // MARK: - Fichiers d'attribution

    /// Dossier des fichiers créés pour un concours (HUGO 24/11 : tout groupé, début et fin ensemble) :
    /// un sous-dossier au nom du concours (« 26-11-29_LAMOTTE INDOOR ») dans celui des réglages, sinon dans le
    /// dossier « Clôtures » de l'app. Fichier du début, fichier de fin, statistiques et collections Lightroom y vont.
    var dossierAttribution: URL {
        let racine = reglages.dossierClotures.isEmpty ? Stockage.dossier.appendingPathComponent("Clôtures", isDirectory: true)
                                                      : URL(fileURLWithPath: reglages.dossierClotures, isDirectory: true)
        let nom = (FichierEngages.nomFichier(concours: nomConcoursFichier, dernierJour: finConcours) as NSString).deletingPathExtension
        let d = nom.isEmpty ? racine : racine.appendingPathComponent(nom, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    var nomConcoursFichier: String { reglages.nomConcours.isEmpty ? (concours?.nom ?? "") : reglages.nomConcours }

    var fichierDebut: URL {
        dossierAttribution.appendingPathComponent(FichierEngages.nomFichier(concours: nomConcoursFichier, dernierJour: finConcours))
    }

    var fichierFin: URL {
        dossierAttribution.appendingPathComponent(FichierEngages.nomFichier(concours: nomConcoursFichier, dernierJour: finConcours,
                                                                            suffixe: " fin"))
    }

    var fichierDebutExiste: Bool { FileManager.default.fileExists(atPath: fichierDebut.path) }

    func epreuvesEngages() throws -> [EpreuveEngages] {
        guard !reglages.cheminFFE.isEmpty else {
            throw NSError(domain: "TriPhoto", code: 3, userInfo: [NSLocalizedDescriptionKey: "Charge d'abord le fichier FFE."])
        }
        return try LecteurEngagesFFE.lire(fichier: URL(fileURLWithPath: reglages.cheminFFE))
    }

    /// Fichier d'attribution de début de concours (d'après le fichier FFE). Un fichier déjà là est remplacé
    /// seulement à la demande (bouton) ; l'ancien part à la corbeille, donc rien n'est perdu.
    @discardableResult
    func creerFichierDebut(silencieux: Bool = false) -> URL? {
        do {
            let texte = FichierEngages.debut(try epreuvesEngages())
            let url = fichierDebut
            try ecrireEnGardantLAncien(texte, vers: url)
            messageAttribution = "Fichier de début écrit : \(url.lastPathComponent)"
            return url
        } catch {
            if !silencieux { messageAttribution = "Fichier de début : \(error.localizedDescription)" }
            return nil
        }
    }

    /// Fichier d'attribution de fin (format HMV), avec les engagés terrain.
    @discardableResult
    func creerFichierFin(enDirect: Bool = false) -> URL? {
        do {
            let texte = FichierEngages.cloture(try epreuvesEngages(), terrain: engagesTerrain)
            let url = fichierFin
            if enDirect {       // mise à jour pendant le concours : remplacé sur place, sans remplir la Corbeille
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(texte.utf8).write(to: url, options: .atomic)
            } else {
                try ecrireEnGardantLAncien(texte, vers: url)
            }
            messageAttribution = "Fichier de fin écrit : \(url.lastPathComponent) (\(engagesTerrain.count) engagés terrain)"
            garderListing()
            return url
        } catch {
            messageAttribution = "Fichier de fin : \(error.localizedDescription)"
            return nil
        }
    }

    private func ecrireEnGardantLAncien(_ texte: String, vers url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) { try? fm.trashItem(at: url, resultingItemURL: nil) }
        try Data(texte.utf8).write(to: url, options: .atomic)
    }

    func montrerDansLeFinder(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    // MARK: - Statistiques de fin de concours

    /// Petit bilan texte : photos par jour, par épreuve, par photographe.
    func statistiques() -> String {
        let photos = moteur.photosDuConcours(depuis: debutConcours)
        let jour = DateFormatter()
        jour.locale = Locale(identifier: "fr_FR")
        jour.dateFormat = "EEEE d MMMM"
        var parJour: [String: Int] = [:]
        var parEpreuve: [String: Int] = [:]
        var parBoitier: [String: Int] = [:]
        for f in photos {
            parJour[jour.string(from: f.recue), default: 0] += 1
            let code = CodePassage.lire(f.codeRetenu)
            let ep = code.flatMap { concours?.epreuve(numero: $0.epreuve)?.nomDossier } ?? (code == nil ? "Sans code" : "Épreuve \(code!.epreuve)")
            parEpreuve[ep, default: 0] += 1
            parBoitier[f.boitier.isEmpty ? "Inconnu" : f.boitier, default: 0] += 1
        }
        var l = ["\(nomConcoursFichier) : \(photos.count) photos", ""]
        l.append("Par jour")
        l += parJour.sorted { $0.key < $1.key }.map { "  \($0.key) : \($0.value)" }
        l.append("")
        l.append("Par épreuve")
        l += parEpreuve.sorted { $0.key < $1.key }.map { "  \($0.key) : \($0.value)" }
        l.append("")
        l.append("Par boîtier")
        l += parBoitier.sorted { $0.value > $1.value }.map { "  \($0.key) : \($0.value)" }
        l.append("")
        l.append("Engagés terrain : \(engagesTerrain.count)")
        return l.joined(separator: "\n")
    }

    func ecrireStatistiques() -> URL? {
        let url = dossierAttribution.appendingPathComponent(
            (fichierFin.deletingPathExtension().lastPathComponent.replacingOccurrences(of: " fin", with: "")) + " statistiques.txt")
        do {
            try ecrireEnGardantLAncien(statistiques(), vers: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Accès à distance

    func reglerAccesDistance() {
        if reglages.accesDistance && reglages.codeAccesDistance.count >= 4 {
            acces.demarrer(port: reglages.portAccesDistance)
        } else {
            acces.arreter()
        }
    }

    /// Ce que voit la page à distance (tableau de bord, en lecture seule).
    func etatDistance() -> EtatDistance {
        let r = moteur.resume
        let chrono: String
        if let c = r.chrono {
            chrono = c.ok == true ? "\(reglages.chronometrage.rawValue) OK" : "\(reglages.chronometrage.rawValue) : \(c.erreur)"
        } else {
            chrono = "Sans chrono"
        }
        var galerie = ""
        if let g = r.galerieEnLigne {
            galerie = g.aFaire == 0 ? "\(g.enLigne) en ligne" : (g.attendLaNuit ? "\(g.aFaire) pour la nuit" : "\(g.aFaire) à envoyer")
        }
        return EtatDistance(
            concours: reglages.nomConcours.isEmpty ? (concours?.nom ?? "") : reglages.nomConcours,
            actif: moteur.actif, recues: r.recues, parMinute: r.parMinute, enFile: r.enFile, retardSecondes: r.retardSecondes,
            aValider: r.aValider, aRenvoyer: r.aRenvoyer.count, dansTampon: r.dansTampon, enErreur: r.enErreur,
            chrono: chrono, galerie: galerie,
            boitiers: r.boitiers.map { .init(nom: $0.nomAffiche, photos: $0.photos, derniere: $0.derniere?.timeIntervalSince1970) },
            pistes: r.enPiste.map { .init(piste: $0.piste, epreuve: $0.passage.epreuve, dossard: $0.passage.dossard,
                                          cavalier: $0.passage.cavalier, cheval: $0.passage.cheval, termine: $0.termine) },
            alertes: r.alertes,
            epreuves: (concours?.epreuves ?? []).map { .init(numero: $0.numero, nom: $0.nomDossier) },
            heure: Date().timeIntervalSince1970)
    }
}
