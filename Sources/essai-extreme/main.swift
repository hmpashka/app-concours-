// Essais extrêmes du moteur photos, sans interface : ce qui peut arriver un dimanche de rush.
//
//   swift run -c release essai-extreme <dossier de photos> [--cube fichier.cube]
//
// Chaque essai tourne dans son propre dossier temporaire (réception, import Lightroom, serveur) : le dossier de
// photos donné n'est jamais modifié. À la fin de chaque essai, on vérifie qu'aucune photo n'est perdue ni envoyée
// deux fois, que les originaux gardent leurs pixels, et qu'aucun fichier à moitié écrit ne traîne.
import CoreGraphics
import Foundation
import ImageIO
import TriPhotoCommun
import TriPhotoMoteur

setvbuf(stdout, nil, _IOLBF, 0)

var args = Array(CommandLine.arguments.dropFirst())
func option(_ nom: String) -> String? {
    guard let i = args.firstIndex(of: nom), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}
let cheminCube = option("--cube")
guard let source = args.first else {
    print("Usage : essai-extreme <dossier de photos> [--cube f.cube]")
    exit(1)
}
let fm = FileManager.default
let sourceURL = URL(fileURLWithPath: (source as NSString).expandingTildeInPath, isDirectory: true)
var sources: [URL] = []
if let e = fm.enumerator(at: sourceURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
    for case let u as URL in e where ["jpg", "jpeg"].contains(u.pathExtension.lowercased()) { sources.append(u) }
}
sources.sort { $0.lastPathComponent < $1.lastPathComponent }
guard sources.count >= 40 else { print("Il faut au moins 40 photos JPEG dans \(sourceURL.path)"); exit(1) }
let cube = cheminCube.flatMap { try? FichierCube(fichier: URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)) }

// MARK: - Outils

struct Bac {
    let racine, reception, importLR, serveur, tampon, travail: URL
}

func nouveauBac(_ nom: String) -> Bac {
    let r = fm.temporaryDirectory.appendingPathComponent("essai-extreme-\(nom)-\(UUID().uuidString.prefix(6))", isDirectory: true)
    let b = Bac(racine: r, reception: r.appendingPathComponent("reception"), importLR: r.appendingPathComponent("import"),
                serveur: r.appendingPathComponent("serveur"), tampon: r.appendingPathComponent("tampon"),
                travail: r.appendingPathComponent("travail-lightroom"))
    for d in [b.reception, b.importLR, b.serveur, b.tampon, b.travail] { try? fm.createDirectory(at: d, withIntermediateDirectories: true) }
    return b
}

func config(_ b: Bac, tampon: Bool = false) -> ConfigMoteur {
    ConfigMoteur(reception: b.reception, importLightroom: b.importLR, tampon: tampon ? b.tampon : nil, serveur: b.serveur,
                 cote: 1500, qualite: 56, cube: cube, concours: nil, tailleLot: 10, silenceMinutes: 1, retarderSiOccupe: false,
                 journal: b.racine.appendingPathComponent("journal.sqlite"), travailLightroom: b.travail, attente00Minutes: 0)
}

/// Dépose une photo dans la réception comme un boîtier : copie cachée puis renommage.
func deposer(_ u: URL, nom: String? = nil, dans d: URL) {
    let n = nom ?? u.lastPathComponent
    let prov = d.appendingPathComponent(".\(n).part")
    try? fm.copyItem(at: u, to: prov)
    try? fm.moveItem(at: prov, to: d.appendingPathComponent(n))
}

func jpegs(_ d: URL, recursif: Bool = false) -> [URL] {
    var l: [URL] = []
    if recursif, let e = fm.enumerator(at: d, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
        for case let u as URL in e where ["jpg", "jpeg"].contains(u.pathExtension.lowercased()) { l.append(u) }
    } else {
        l = ((try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") && ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
    }
    return l
}

func fichiersPart(_ d: URL) -> Int {
    var n = 0
    if let e = fm.enumerator(atPath: d.path) { for case let p as String in e where p.hasSuffix(".part") { n += 1 } }
    return n
}

/// Attend qu'une condition soit vraie (en faisant tourner la boucle principale), au plus `secondes`.
@discardableResult
func attendre(_ secondes: Double, _ condition: () -> Bool) -> Bool {
    let t0 = Date()
    while Date().timeIntervalSince(t0) < secondes {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    }
    return condition()
}

func pixels(_ u: URL) -> Data? {
    guard let s = CGImageSourceCreateWithURL(u as CFURL, nil), let im = CGImageSourceCreateImageAtIndex(s, 0, nil),
          let data = im.dataProvider?.data else { return nil }
    return data as Data
}

/// Les pixels de chaque photo envoyée sont-ils ceux d'une des photos de départ ? (10 au plus, c'est lent)
func pixelsIntacts(_ envoyees: [URL], depart: [URL]) -> (ok: Int, ko: Int) {
    let parNom = Dictionary(depart.map { ($0.deletingPathExtension().lastPathComponent, $0) }, uniquingKeysWith: { a, _ in a })
    var ok = 0, ko = 0
    for u in envoyees.prefix(10) {
        var base = u.deletingPathExtension().lastPathComponent
        while parNom[base] == nil, let i = base.lastIndex(of: "-") { base = String(base[..<i]) }
        guard let o = parNom[base] else { continue }
        if let a = pixels(o), a == pixels(u) { ok += 1 } else { ko += 1 }
    }
    return (ok, ko)
}

var resultats: [(String, Bool, String)] = []
func noter(_ nom: String, _ ok: Bool, _ detail: String) {
    resultats.append((nom, ok, detail))
    print("\(ok ? "OK   " : "ÉCHEC") \(nom) : \(detail)")
}

/// Fin d'un essai : tout est parti une seule fois, rien d'abîmé.
func bilan(_ nom: String, _ b: Bac, _ m: Moteur, attendues: Int, depart: [URL], aRenvoyer: Int = 0, doublons: Int = 0, tampon: Bool = false) {
    let envoyees = jpegs(b.importLR) + (tampon ? jpegs(b.tampon) : []) + jpegs(b.travail, recursif: true)
    let copies = jpegs(b.serveur, recursif: true).count
    let restantes = jpegs(b.reception).count
    let r = m.resume
    let px = pixelsIntacts(envoyees, depart: depart)
    let noms = envoyees.map { $0.lastPathComponent.lowercased() }
    let enDouble = noms.count - Set(noms).count
    var problemes: [String] = []
    if envoyees.count != attendues { problemes.append("\(envoyees.count) envoyées au lieu de \(attendues)") }
    if copies != attendues { problemes.append("\(copies) copies serveur au lieu de \(attendues)") }
    if restantes > 0 { problemes.append("\(restantes) restées dans la réception") }
    if r.aRenvoyer.count != aRenvoyer { problemes.append("\(r.aRenvoyer.count) à renvoyer au lieu de \(aRenvoyer)") }
    if r.doublons.count != doublons { problemes.append("\(r.doublons.count) doublons au lieu de \(doublons)") }
    if r.enErreur > 0 { problemes.append("\(r.enErreur) en erreur (\(r.message))") }
    if enDouble > 0 { problemes.append("\(enDouble) envoyées deux fois") }
    if px.ko > 0 { problemes.append("\(px.ko) originaux aux pixels changés") }
    let part = fichiersPart(b.racine)
    if part > 0 { problemes.append("\(part) fichiers .part restés") }
    noter(nom, problemes.isEmpty, problemes.isEmpty
          ? "\(envoyees.count) envoyées, \(copies) copies, \(r.aRenvoyer.count) à renvoyer, \(r.doublons.count) doublons, pixels \(px.ok)/\(px.ok + px.ko) identiques"
          : problemes.joined(separator: " · "))
}

func lot(_ debut: Int, _ n: Int) -> [URL] { Array(sources[debut..<min(debut + n, sources.count)]) }

func fini(_ b: Bac, _ m: Moteur, _ n: Int, tampon: Bool = false, secondes: Double = 240) -> Bool {
    attendre(secondes) {
        let r = m.resume
        return jpegs(b.reception).isEmpty && (jpegs(b.importLR).count + (tampon ? jpegs(b.tampon).count : 0)
                                                + jpegs(b.travail, recursif: true).count + r.aRenvoyer.count + r.doublons.count) >= n
    }
}

print("Essais extrêmes : \(sources.count) photos de départ\(cube != nil ? ", avec .cube" : "")")
let t0 = Date()

// MARK: 1. Rafale : 300 photos d'un coup

do {
    let b = nouveauBac("rafale")
    let m = Moteur()
    try! m.demarrer(config(b))
    let l = lot(0, 300)
    DispatchQueue.global().async { for u in l { deposer(u, dans: b.reception) } }
    let debut = Date()
    _ = fini(b, m, l.count, secondes: 600)
    let d = Date().timeIntervalSince(debut)
    m.arreter()
    bilan("1. Rafale de \(l.count) photos d'un coup (\(Int(Double(l.count) / max(d, 1) * 60)) photos/min)", b, m, attendues: l.count, depart: l)
}

// MARK: 2. Photos abîmées : coupée en deux, vide, pas un JPEG

do {
    let b = nouveauBac("abimees")
    let m = Moteur()
    try! m.demarrer(config(b))
    let l = lot(0, 10)
    for u in l { deposer(u, dans: b.reception) }
    let d = try! Data(contentsOf: sources[10])
    try! d.prefix(d.count / 2).write(to: b.reception.appendingPathComponent("COUPEE_0001.JPG"))
    try! Data().write(to: b.reception.appendingPathComponent("VIDE_0002.JPG"))
    try! Data("ceci n'est pas une photo".utf8).write(to: b.reception.appendingPathComponent("TEXTE_0003.JPG"))
    print("     (essai 2 : attente de 90 s pour le fichier vide…)")
    _ = attendre(150) { m.resume.aRenvoyer.count >= 3 && jpegs(b.reception).isEmpty }
    m.arreter()
    bilan("2. Photos abîmées (coupée, vide, pas un JPEG) parmi 10 bonnes", b, m, attendues: 10, depart: l, aRenvoyer: 3)
}

// MARK: 3. Transfert lent : la photo arrive par morceaux avec des pauses de 3 s

do {
    let b = nouveauBac("lent")
    let m = Moteur()
    try! m.demarrer(config(b))
    let l = lot(20, 3)
    for u in l {
        let d = try! Data(contentsOf: u)
        let dest = b.reception.appendingPathComponent(u.lastPathComponent)
        fm.createFile(atPath: dest.path, contents: nil)
        let h = try! FileHandle(forWritingTo: dest)
        let morceau = max(1, d.count / 4)
        var i = 0
        while i < d.count {
            h.write(d.subdata(in: i..<min(i + morceau, d.count)))
            i += morceau
            RunLoop.main.run(until: Date().addingTimeInterval(3))     // le boîtier hésite 3 s
        }
        try? h.close()
    }
    _ = fini(b, m, l.count)
    m.arreter()
    bilan("3. Transfert lent (4 morceaux, 3 s de pause entre chaque)", b, m, attendues: l.count, depart: l)
}

// MARK: 4. Serveur local débranché en plein tri, puis rebranché

do {
    let b = nouveauBac("serveur")
    let m = Moteur()
    try! m.demarrer(config(b))
    let l = lot(30, 40)
    DispatchQueue.global().async { for u in l { deposer(u, dans: b.reception); Thread.sleep(forTimeInterval: 0.1) } }
    _ = attendre(30) { jpegs(b.importLR).count >= 5 }
    let cache = b.racine.appendingPathComponent("serveur-debranche")
    try? fm.moveItem(at: b.serveur, to: cache)
    _ = attendre(20) { m.resume.enErreur > 0 }
    let erreursVues = m.resume.enErreur
    try? fm.moveItem(at: cache, to: b.serveur)
    _ = fini(b, m, l.count, secondes: 180)
    _ = attendre(30) { m.resume.enErreur == 0 }
    m.arreter()
    bilan("4. Serveur débranché puis rebranché (\(erreursVues) photos en attente pendant la coupure)", b, m, attendues: l.count, depart: l)
}

// MARK: 5. Reprise après plantage : dépôt pour Lightroom fait, retrait de la réception impossible

do {
    let b = nouveauBac("plantage")
    let m = Moteur()
    try! m.demarrer(config(b))
    let l = lot(80, 8)
    for u in l { deposer(u, dans: b.reception) }
    // Réception verrouillée : le moteur dépose les photos pour Lightroom mais ne peut pas les retirer de la réception,
    // comme un plantage juste entre les deux. Il réessaie toutes les 15 s.
    try? fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: b.reception.path)
    _ = attendre(40) { jpegs(b.importLR).count >= l.count }
    RunLoop.main.run(until: Date().addingTimeInterval(20))          // au moins un nouvel essai
    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: b.reception.path)
    _ = fini(b, m, l.count)
    _ = attendre(40) { m.resume.enErreur == 0 && jpegs(b.reception).isEmpty }
    m.arreter()
    bilan("5. Reprise après une coupure entre le dépôt Lightroom et le retrait (aucun faux doublon)", b, m, attendues: l.count, depart: l)
}

// MARK: 6. Arrêt brutal puis redémarrage sur le même journal

do {
    let b = nouveauBac("redemarrage")
    var m = Moteur()
    try! m.demarrer(config(b))
    let l = lot(90, 60)
    for u in l { deposer(u, dans: b.reception) }
    _ = attendre(30) { jpegs(b.importLR).count >= 10 }
    m.arreter()
    RunLoop.main.run(until: Date().addingTimeInterval(5))      // les photos en cours finissent proprement
    m = Moteur()                                               // nouvelle app, même journal
    try! m.demarrer(config(b))
    _ = fini(b, m, l.count)
    m.arreter()
    bilan("6. Arrêt en plein tri puis redémarrage", b, m, attendues: l.count, depart: l)
}

// MARK: 7. Doublons : la même photo renvoyée deux fois, et deux boîtiers aux mêmes noms

do {
    let b = nouveauBac("doublons")
    let m = Moteur()
    try! m.demarrer(config(b))
    let l = lot(150, 10)
    for u in l { deposer(u, dans: b.reception) }
    _ = fini(b, m, l.count)
    for u in l.prefix(3) { deposer(u, dans: b.reception) }       // renvoyées
    _ = attendre(60) { m.resume.doublons.count >= 3 }
    m.arreter()
    bilan("7. Trois photos reçues deux fois (mises de côté en doublon, rien envoyé en double)", b, m, attendues: l.count, depart: l, doublons: 3)
}

// MARK: 8. Noms bizarres : espaces, accents, très long, .JPEG en majuscules, sous-dossiers

do {
    let b = nouveauBac("noms")
    let m = Moteur()
    try! m.demarrer(config(b))
    let l = lot(160, 6)
    let noms = ["photo avec espaces.jpg", "Écuyère été ç.JPG", String(repeating: "L", count: 180) + ".jpg",
                "MAJUSCULES.JPEG", "point.dans.le.nom.jpg", "sous-dossier"]
    for (u, n) in zip(l, noms) {
        if n == "sous-dossier" {
            let sd = b.reception.appendingPathComponent("carte SD/DCIM", isDirectory: true)
            try? fm.createDirectory(at: sd, withIntermediateDirectories: true)
            deposer(u, nom: "DANS_SOUS_DOSSIER.JPG", dans: sd)
        } else {
            deposer(u, nom: n, dans: b.reception)
        }
    }
    _ = attendre(90) { jpegs(b.importLR).count >= l.count }
    m.arreter()
    let reste = jpegs(b.reception, recursif: true).count
    let envoyees = jpegs(b.importLR).count
    noter("8. Noms bizarres et sous-dossiers", envoyees == l.count && reste == 0 && m.resume.enErreur == 0,
          "\(envoyees)/\(l.count) envoyées, \(reste) restées, \(m.resume.enErreur) en erreur \(m.resume.message)")
}

// MARK: 9. Pause en plein rush : rien ne part, puis tout repart

do {
    let b = nouveauBac("pause")
    let m = Moteur()
    try! m.demarrer(config(b))
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    m.mettreEnPause(true)
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    let l = lot(170, 20)
    for u in l { deposer(u, dans: b.reception) }
    RunLoop.main.run(until: Date().addingTimeInterval(8))
    let pendant = jpegs(b.importLR).count + jpegs(b.serveur, recursif: true).count
    m.mettreEnPause(false)
    _ = fini(b, m, l.count)
    m.arreter()
    if pendant > 0 { noter("9. Pause", false, "\(pendant) fichiers sont partis pendant la pause") }
    bilan("9. Pause pendant 8 s puis reprise", b, m, attendues: l.count, depart: l)
}

// MARK: 10. Supprimer depuis l'app puis annuler (⌘Z)

do {
    let b = nouveauBac("suppression")
    let m = Moteur()
    try! m.demarrer(config(b))
    let l = lot(190, 8)
    for u in l { deposer(u, dans: b.reception) }
    _ = fini(b, m, l.count)
    let ids = m.photosRevue(epreuve: nil).prefix(3).map(\.id)
    m.supprimer(Array(ids))
    _ = attendre(20) { jpegs(b.importLR).count == l.count - ids.count }
    let apres = (jpegs(b.importLR).count, jpegs(b.serveur, recursif: true).count)
    m.annulerSuppression(Array(ids))
    _ = attendre(30) { jpegs(b.importLR).count == l.count && jpegs(b.serveur, recursif: true).count == l.count }
    m.arreter()
    if apres.0 != l.count - ids.count || apres.1 != l.count - ids.count {
        noter("10. Suppression", false, "après suppression : \(apres.0) originaux, \(apres.1) copies (attendu \(l.count - ids.count))")
    }
    bilan("10. Supprimer 3 photos puis annuler", b, m, attendues: l.count, depart: l)
}

// MARK: 11. Dossier tampon : lot, puis vidage forcé (clôture), suppression + annulation dans le tampon

do {
    let b = nouveauBac("tampon")
    let m = Moteur()
    try! m.demarrer(config(b, tampon: true))
    let l = lot(200, 7)                                         // moins qu'un lot de 10 : reste au tampon
    for u in l { deposer(u, dans: b.reception) }
    _ = attendre(60) { jpegs(b.tampon).count >= l.count }
    let ids = m.photosRevue(epreuve: nil).prefix(2).map(\.id)
    m.supprimer(Array(ids))
    _ = attendre(20) { jpegs(b.tampon).count == l.count - ids.count }
    m.annulerSuppression(Array(ids))
    _ = attendre(20) { jpegs(b.tampon).count == l.count }
    m.viderTampon()
    _ = attendre(30) { jpegs(b.importLR).count == l.count }
    m.arreter()
    bilan("11. Tampon : suppression annulée puis vidage à la clôture", b, m, attendues: l.count, depart: l)
}

// MARK: 12. Lightroom supprime des photos de son dossier de travail

do {
    let b = nouveauBac("lightroom")
    let m = Moteur()
    try! m.demarrer(config(b))
    let l = lot(210, 6)
    for u in l { deposer(u, dans: b.reception) }
    _ = fini(b, m, l.count)
    // Lightroom importe : il range les photos dans son dossier de travail
    let jour = b.travail.appendingPathComponent("2026/2026-11-29", isDirectory: true)
    try? fm.createDirectory(at: jour, withIntermediateDirectories: true)
    for u in jpegs(b.importLR) { try? fm.moveItem(at: u, to: jour.appendingPathComponent(u.lastPathComponent)) }
    RunLoop.main.run(until: Date().addingTimeInterval(20))
    // HUGO supprime 2 photos dans Lightroom
    for u in jpegs(jour).prefix(2) { try? fm.removeItem(at: u) }
    _ = attendre(60) { jpegs(b.serveur, recursif: true).count == l.count - 2 }
    m.arreter()
    let copies = jpegs(b.serveur, recursif: true).count
    noter("12. Suppression dans Lightroom → copie retirée du serveur", copies == l.count - 2,
          "\(copies) copies sur le serveur (attendu \(l.count - 2))")
}

// MARK: Bilan

print("")
let echecs = resultats.filter { !$0.1 }
print("Bilan : \(resultats.count - echecs.count)/\(resultats.count) essais réussis en \(Int(Date().timeIntervalSince(t0))) s")
for e in echecs { print("  ÉCHEC \(e.0) : \(e.2)") }
exit(echecs.isEmpty ? 0 : 2)
