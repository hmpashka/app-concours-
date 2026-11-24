import AppKit
import Foundation
import TriPhotoCommun
import TriPhotoMoteur

/// Étape 5 : mémoire partagée, remises des prix (Google Drive), collections dynamiques Lightroom.
extension Etat {
    nonisolated static func dossierMemoire(_ r: ReglagesConcours) -> URL {
        r.dossierMemoire.isEmpty ? Memoire.dossierParDefaut : URL(fileURLWithPath: r.dossierMemoire, isDirectory: true)
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
