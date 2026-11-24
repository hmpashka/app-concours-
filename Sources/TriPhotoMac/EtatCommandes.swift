import Foundation
import TriPhotoCommun
import TriPhotoMoteur

/// Commandes de pack photo : listing du concours gardé, recherche des clients (Mac et iPhone), photos par couple.
extension Etat {
    nonisolated static func dossierListings(_ r: ReglagesConcours) -> URL {
        r.dossierListings.isEmpty ? Archives.dossierParDefaut : URL(fileURLWithPath: r.dossierListings, isDirectory: true)
    }

    /// Identifiant du concours en cours dans les listings : son numéro FFE, sinon son nom.
    var idConcours: String {
        if let n = concours?.numero, !n.isEmpty { return n }
        return NomDossier.nettoyer(concours?.nom ?? reglages.nomConcours)
    }

    /// Garde le listing du concours en cours (au chargement du fichier FFE, au démarrage, à la clôture).
    func garderListing() {
        guard let c = concours, let e = try? epreuvesEngages() else { return }
        archives.garder(ListingConcours.depuis(e, terrain: engagesTerrain, id: idConcours,
                                               nom: reglages.nomConcours.isEmpty ? c.nom.capitalized : reglages.nomConcours))
    }

    /// Recherche d'un client dans tous les listings gardés, avec le nombre de photos pour le concours en cours.
    func chercherClients(_ texte: String) -> [ClientTrouve] {
        archives.relire(forcer: false)
        var photos: [String: Int] = [:]
        if moteur.actif {
            for f in moteur.photosDuConcours(depuis: debutConcours) {
                if let k = CodePassage.lire(f.codeRetenu) { photos[k.texte, default: 0] += 1 }
            }
        }
        return Commandes.chercher(texte, dans: archives.listings, concoursEnCours: idConcours, photos: photos)
    }

    /// Nouvel emplacement des listings et commandes : tout le contenu de l'ancien dossier y est déplacé.
    func changerDossierListings(depuis ancien: ReglagesConcours) {
        let a = Etat.dossierListings(ancien), b = Etat.dossierListings(reglages)
        let pa = a.standardizedFileURL.path + "/", pb = b.standardizedFileURL.path + "/"
        if pa.hasPrefix(pb) || pb.hasPrefix(pa) {
            archives.message = "Dossier refusé : il ne doit être ni dans l'ancien, ni au-dessus. Rien n'a bougé."
            retourListings = true
            reglages.dossierListings = ancien.dossierListings
            return
        }
        archives.changerDossier(b)
        archives.message = "Déplacement des listings et commandes en cours…"
        DispatchQueue.global(qos: .utility).async {
            // même déplacement que la mémoire : tout passe, rien n'est doublé, un dossier dans l'autre est refusé
            let r = Memoire(dossier: a).toutDeplacer(vers: b)
            Task { @MainActor in
                guard let e = Etat.courant else { return }
                e.archives.relire()
                e.archives.message = r.deplaces < 0
                    ? "Rien n'a bougé : le nouveau dossier ne doit être ni dans l'ancien, ni au-dessus."
                    : "\(r.deplaces) fichiers déplacés" + (r.restes > 0 ? ", \(r.restes) encore dans iCloud (refais le choix plus tard)." : ".")
            }
        }
    }
}
