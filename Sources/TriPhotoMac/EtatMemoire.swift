import AppKit
import Foundation
import TriPhotoCommun
import TriPhotoMoteur

/// Étape 5 : mémoire partagée, remises des prix (Google Drive), collections dynamiques Lightroom.
extension Etat {
    nonisolated static func dossierMemoire(_ r: ReglagesConcours) -> URL {
        r.dossierMemoire.isEmpty ? Memoire.dossierParDefaut : URL(fileURLWithPath: r.dossierMemoire, isDirectory: true)
    }

    /// Nouvel emplacement de la mémoire : tout ce qu'il y a dans l'ancien dossier y est déplacé (en arrière-plan).
    func changerDossierMemoire(depuis ancien: ReglagesConcours) {
        let avant = memoire
        let pa = Etat.dossierMemoire(ancien).standardizedFileURL.path + "/"
        let pb = Etat.dossierMemoire(reglages).standardizedFileURL.path + "/"
        if pa.hasPrefix(pb) || pb.hasPrefix(pa) {
            messageMemoire = "Dossier refusé : il ne doit être ni dans la mémoire actuelle, ni au-dessus d'elle. La mémoire n'a pas bougé."
            retourMemoire = true
            reglages.dossierMemoire = ancien.dossierMemoire
            return
        }
        let neuve = Memoire(dossier: Etat.dossierMemoire(reglages))
        memoire = neuve
        moteur.reglerMemoire(reglages.detectionsActives ? neuve : nil)
        messageMemoire = "Déplacement de la mémoire en cours…"
        DispatchQueue.global(qos: .utility).async {
            let r = avant.toutDeplacer(vers: neuve.dossier)
            neuve.creer()
            Task { @MainActor in
                if r.deplaces < 0 {
                    Etat.courant?.messageMemoire = "Rien n'a bougé : choisis un dossier qui n'est ni dans la mémoire actuelle, ni au-dessus d'elle."
                    return
                }
                let s = r.deplaces > 1 ? "s" : ""
                var t = "Mémoire déplacée : \(r.deplaces) fichier\(s) dans « \(neuve.dossier.lastPathComponent) »."
                if r.restes > 0 {
                    t += " \(r.restes) vignette\(r.restes > 1 ? "s" : "") encore dans iCloud, restée\(r.restes > 1 ? "s" : "") dans l'ancien dossier : bouton « Finir le déplacement » quand elles seront téléchargées."
                }
                Etat.courant?.messageMemoire = t
                Etat.courant?.ancienDossierMemoire = r.restes > 0 ? avant.dossier : nil
            }
        }
    }

    /// Reprend le déplacement des vignettes restées dans l'ancien dossier (elles étaient encore dans iCloud).
    func finirDeplacementMemoire() {
        guard let a = ancienDossierMemoire else { return }
        let neuve = memoire
        DispatchQueue.global(qos: .utility).async {
            let r = Memoire(dossier: a).toutDeplacer(vers: neuve.dossier)
            Task { @MainActor in
                Etat.courant?.messageMemoire = r.restes > 0
                    ? "\(r.deplaces) déplacés, \(r.restes) encore dans iCloud : réessaie dans un moment."
                    : "Déplacement fini (\(r.deplaces) fichiers)."
                Etat.courant?.ancienDossierMemoire = r.restes > 0 ? a : nil
            }
        }
    }

    /// Remises des prix : nil si l'option est coupée ou sans dossier Google Drive.
    func configRemises() -> ConfigRemises? {
        let r = reglages
        guard r.remisesActives, !r.dossierRemises.isEmpty else { return nil }
        return ConfigRemises(dossier: URL(fileURLWithPath: r.dossierRemises, isDirectory: true), photos: max(1, r.photosParRemise),
                             attenteMinutes: Double(max(1, r.attenteRemiseMinutes)), depuis: debutConcours,
                             fichierEtat: Stockage.dossier.appendingPathComponent("remises-\(cleConcours).json"))
    }

    /// Un classement de la revue enrichit la mémoire (ou retire l'exemple si HUGO enlève le classement).
    /// La vignette est faite depuis l'original sur ce Mac (pas de réseau), sinon depuis la copie du serveur.
    func noterDansLaMemoire(_ f: FichePhoto, categorie: String, ajouter: Bool) {
        let m = memoire
        DispatchQueue.global(qos: .utility).async {
            guard ajouter else { return m.retirer(photo: f.nom, categorie: categorie) }
            let source = [f.chemin, f.copie].first { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) }
            guard let source else { return }
            m.creer()
            _ = try? m.ajouter(photo: URL(fileURLWithPath: source), categorie: categorie,
                               nom: Memoire.nomExemple(photo: f.nom, date: f.prise ?? f.recue))
        }
    }

    /// Collections dynamiques Lightroom, une par épreuve, à côté des fichiers d'attribution.
    @discardableResult
    func creerCollectionsLightroom() -> URL? {
        do {
            let dossier = dossierAttribution.appendingPathComponent("Collections Lightroom \(NomDossier.nettoyer(nomConcoursFichier))",
                                                                    isDirectory: true)
            let n = try CollectionsLightroom.ecrire(try epreuvesEngages(), dans: dossier)
            messageAttribution = "\(n) collections dynamiques écrites. Dans Lightroom : clic droit sur « Collections » › Importer des paramètres de collection dynamique."
            return dossier
        } catch {
            messageAttribution = "Collections Lightroom : \(error.localizedDescription)"
            return nil
        }
    }
}
