import Foundation
import TriPhotoCommun
import TriPhotoMoteur

// Essai de l'onglet « Au bureau » sur un vrai dossier d'archives, sans rien y écrire :
//   swift run -c release essai-bureau <dossier d'une année> [--chercher "julie martin"] [--index <dossier>] [--douce]
// Mesure la vitesse de l'indexation, ce qui est lu sur le disque, la place prise par l'index et les vignettes,
// puis fait une recherche. L'index d'essai est rangé dans un dossier temporaire (sauf --index).

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("Usage : essai-bureau <dossier d'une année> [--chercher \"texte\"] [--index <dossier>] [--douce] [--csv <dossier des CSV>]")
    exit(1)
}
func valeur(_ nom: String) -> String? {
    guard let i = args.firstIndex(of: nom), i + 1 < args.count else { return nil }
    return args[i + 1]
}
let racine = URL(fileURLWithPath: args[1], isDirectory: true)
let dossierIndex = valeur("--index").map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? FileManager.default.temporaryDirectory.appendingPathComponent("essai-bureau-\(UUID().uuidString)", isDirectory: true)
let index = try IndexArchives(dossier: dossierIndex)
let indexeur = IndexeurArchives(index: index)
indexeur.pauseEntrePhotos = args.contains("--douce") ? 0.02 : 0
if let c = valeur("--csv") { indexeur.dossierCSV = URL(fileURLWithPath: c, isDirectory: true) }
let archive = ArchiveAnnee(id: "essai", annee: ArchiveAnnee.anneeDevinee(racine.lastPathComponent), chemin: racine.path)

print("Archive : \(racine.path)")
print("Index   : \(dossierIndex.path)")
var dernier = Date()
indexeur.surProgression = { _, p in
    guard Date().timeIntervalSince(dernier) > 2 || p.etape == .fini else { return }
    dernier = Date()
    print("  \(p.etape.rawValue) · \(p.trouvees) photos vues · \(p.lues)/\(p.aLire) lues · \(p.erreurs) erreurs")
}
let t0 = Date()
let p = indexeur.indexerIci(archive)
let duree = Date().timeIntervalSince(t0)
let (tIndex, tVignettes) = index.taillesSurLeMac()
let n = index.compte(archive: "essai")
print("""

Fini en \(String(format: "%.1f", duree)) s : \(p.lues) photos lues (\(String(format: "%.0f", Double(p.lues) / max(duree, 0.001) * 60))/min), \(p.erreurs) erreurs, \(p.dansICloud) laissées dans iCloud.
Index : \(n.photos) photos, \(n.concours) concours.
Place : fiches \(ByteCountFormatter.string(fromByteCount: tIndex, countStyle: .file)), vignettes \(ByteCountFormatter.string(fromByteCount: tVignettes, countStyle: .file)).
""")
// ce qu'une photo coûte à lire : mesuré sur les 20 premières
var lus = 0, totaux: Int64 = 0, k = 0
if let e = FileManager.default.enumerator(at: racine, includingPropertiesForKeys: [.fileSizeKey]) {
    for case let u as URL in e where LecturePhoto.extensions.contains(u.pathExtension.lowercased()) {
        let (l, _) = LecturePhoto.lire(u)
        if l.octetsLus > 0 { lus += l.octetsLus; totaux += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        k += 1
        if k >= 20 { break }
    }
}
if totaux > 0 {
    print("Lu sur le disque : \(ByteCountFormatter.string(fromByteCount: Int64(lus), countStyle: .file)) pour \(ByteCountFormatter.string(fromByteCount: totaux, countStyle: .file)) de photos (\(String(format: "%.1f", Double(lus) * 100 / Double(totaux))) %).")
}
if let t = valeur("--chercher") {
    let t1 = Date()
    let r = index.chercher(RechercheArchives(texte: t))
    print("\nRecherche « \(t) » : \(r.total) photos en \(String(format: "%.3f", Date().timeIntervalSince(t1))) s")
    for ph in r.photos.prefix(10) {
        print("  \(ph.chemin) · \(ph.code) · \(ph.motsCles.joined(separator: ", ")) · \(ph.copyright)")
    }
}
// une photo au hasard, pour voir ce qui a été lu
if let ph = index.chercher(RechercheArchives()).photos.first {
    print("\nExemple : \(ph.chemin)\n  concours « \(ph.concours) » · épreuve « \(ph.epreuve) » · code \(ph.code) · mots-clés \(ph.motsCles) · copyright « \(ph.copyright) » · vignette \(ph.vignette)")
}
