import AppKit
import Foundation
import TriPhotoCommun
import TriPhotoMoteur

/// Listings des concours et commandes de pack photo, gardés dans un dossier iCloud partagé entre les Mac
/// (« Tri-photo Listings ») : un fichier par concours dans « Listings », un fichier par commande dans
/// « Commandes/<concours> » (deux Mac qui prennent chacun une commande ne se gênent jamais). Rien n'est jamais
/// effacé : une commande supprimée part à la corbeille.
@MainActor
final class Archives: ObservableObject {
    @Published private(set) var listings: [ListingConcours] = []
    @Published private(set) var commandes: [Commande] = []
    @Published var message = ""
    private(set) var dossier: URL
    private var derniereLecture = Date.distantPast

    static var dossierParDefaut: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Tri-photo Listings", isDirectory: true)
    }

    init(dossier: URL) {
        self.dossier = dossier
        relire()
    }

    private var dossierListings: URL { dossier.appendingPathComponent("Listings", isDirectory: true) }
    private var dossierCommandes: URL { dossier.appendingPathComponent("Commandes", isDirectory: true) }

    func changerDossier(_ d: URL) {
        dossier = d
        relire()
    }

    /// Relit tout (au plus toutes les 20 s, sauf `forcer`) : les autres Mac ajoutent aussi des commandes.
    func relire(forcer: Bool = true) {
        guard forcer || Date().timeIntervalSince(derniereLecture) > 20 else { return }
        derniereLecture = Date()
        let fm = FileManager.default
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        func fichiers(_ d: URL, recursif: Bool) -> [URL] {
            if recursif {
                guard let e = fm.enumerator(at: d, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
                return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }
            }
            return ((try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
                .filter { $0.pathExtension == "json" }
        }
        // fichiers encore dans iCloud : on les demande (ils seront lus à la prochaine relecture)
        for d in [dossierListings, dossierCommandes] {
            if let e = fm.enumerator(at: d, includingPropertiesForKeys: nil, options: []) {
                for case let u as URL in e where u.lastPathComponent.hasSuffix(".json.icloud") {
                    let vrai = u.deletingLastPathComponent().appendingPathComponent(String(u.lastPathComponent.dropFirst().dropLast(7)))
                    try? fm.startDownloadingUbiquitousItem(at: vrai)
                }
            }
        }
        listings = fichiers(dossierListings, recursif: false).compactMap { u in
            (try? Data(contentsOf: u)).flatMap { try? dec.decode(ListingConcours.self, from: $0) }
        }
        .sorted { (FichierEngages.dateDepuisFR($0.fin) ?? $0.majLe) > (FichierEngages.dateDepuisFR($1.fin) ?? $1.majLe) }
        commandes = fichiers(dossierCommandes, recursif: true).compactMap { u in
            (try? Data(contentsOf: u)).flatMap { try? dec.decode(Commande.self, from: $0) }
        }
        .sorted { $0.creeeLe > $1.creeeLe }
    }

    private func ecrire<T: Encodable>(_ v: T, vers url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try enc.encode(v).write(to: url, options: .atomic)
    }

    private static func nomFichier(_ id: String) -> String {
        NomDossier.nettoyer(id).replacingOccurrences(of: "/", with: "-") + ".json"
    }

    // MARK: - Listings

    func listing(_ id: String) -> ListingConcours? { listings.first { $0.id == id } }

    /// Garde (ou met à jour) le listing d'un concours. Son tarif, s'il existait, est gardé.
    func garder(_ l: ListingConcours) {
        var n = l
        if let ancien = listing(l.id) { n.tarif = ancien.tarif }
        n.majLe = Date()
        do {
            try ecrire(n, vers: dossierListings.appendingPathComponent(Archives.nomFichier(n.id)))
            relire()
        } catch {
            message = "Listing de « \(l.nom) » : \(error.localizedDescription)"
        }
    }

    func changerTarif(_ id: String, _ t: TarifConcours) {
        guard var l = listing(id), l.tarif != t else { return }
        l.tarif = t
        l.majLe = Date()
        try? ecrire(l, vers: dossierListings.appendingPathComponent(Archives.nomFichier(l.id)))
        relire()
    }

    /// Ajoute un ancien concours depuis son fichier FFE (SIF ou FFE Compet).
    func importer(fichierFFE url: URL) {
        do {
            let c = try LecteurFFE.lire(fichier: url)
            let e = try LecteurEngagesFFE.lire(fichier: url)
            let id = c.numero.isEmpty ? NomDossier.nettoyer(c.nom) : c.numero
            garder(ListingConcours.depuis(e, id: id, nom: c.nom.capitalized))
            message = "« \(c.nom.capitalized) » ajouté : \(e.reduce(0) { $0 + $1.engages.count }) couples."
        } catch {
            message = "\(url.lastPathComponent) : \(error.localizedDescription)"
        }
    }

    // MARK: - Commandes

    private func fichier(_ k: Commande) -> URL {
        dossierCommandes.appendingPathComponent(NomDossier.nettoyer(k.concours), isDirectory: true)
            .appendingPathComponent(k.id + ".json")
    }

    func enregistrer(_ k: Commande) {
        var n = k
        n.majLe = Date()
        do {
            try ecrire(n, vers: fichier(n))
            if let i = commandes.firstIndex(where: { $0.id == n.id }) { commandes[i] = n } else { commandes.insert(n, at: 0) }
        } catch {
            message = "Commande de \(k.client) : \(error.localizedDescription)"
        }
    }

    /// À la corbeille (on peut l'y reprendre).
    func supprimer(_ k: Commande) {
        try? FileManager.default.trashItem(at: fichier(k), resultingItemURL: nil)
        commandes.removeAll { $0.id == k.id }
    }

    func commandes(concours: String) -> [Commande] { commandes.filter { $0.concours == concours } }
}
