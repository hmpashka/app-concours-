// Essai du moteur photos, sans interface, sur une copie d'un dossier de photos.
//
//   swift run -c release essai-moteur <dossier de photos> [--cube fichier.cube] [--ffe fichier.xml]
//                                     [--cadence photos-par-minute] [--tampon] [--max N]
//                                     [--passages passages.json | --simuler-chrono [--erreurs N]]
//
// --simuler-chrono : fabrique un faux chrono d'après les codes des photos elles-mêmes (un passage par suite de
// photos du même code), pour essayer les propositions « À valider », les photos de code et les _00.
//
// Tout se passe dans un dossier d'essai temporaire (réception, import Lightroom, serveur) : le dossier de photos
// donné n'est jamais modifié. À la fin : vitesse, photos à renvoyer, erreurs, et vérification que les pixels des
// originaux envoyés à Lightroom sont identiques à ceux de départ (aucune recompression).
import CoreGraphics
import Foundation
import ImageIO
import TriPhotoCommun
import TriPhotoMoteur

setvbuf(stdout, nil, _IOLBF, 0)

func quitter(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
func option(_ nom: String) -> String? {
    guard let i = args.firstIndex(of: nom), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}
func drapeau(_ nom: String) -> Bool {
    guard let i = args.firstIndex(of: nom) else { return false }
    args.remove(at: i)
    return true
}

let cheminCube = option("--cube")
let cheminFFE = option("--ffe")
let cadence = option("--cadence").flatMap(Double.init)
let maxi = option("--max").flatMap(Int.init)
let avecTampon = drapeau("--tampon")
let cheminPassages = option("--passages")
let simulerChrono = drapeau("--simuler-chrono")
let erreursChrono = option("--erreurs").flatMap(Int.init) ?? 0   // 1 passage sur N avec un autre dossard
guard let source = args.first else {
    quitter("Usage : essai-moteur <dossier de photos> [--cube f.cube] [--ffe f.xml] [--cadence N] [--tampon] [--max N]")
}

let fm = FileManager.default
let sourceURL = URL(fileURLWithPath: (source as NSString).expandingTildeInPath, isDirectory: true)
var photos: [URL] = []
if let e = fm.enumerator(at: sourceURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
    for case let u as URL in e where ["jpg", "jpeg"].contains(u.pathExtension.lowercased()) { photos.append(u) }
}
photos.sort { $0.lastPathComponent < $1.lastPathComponent }
if let maxi { photos = Array(photos.prefix(maxi)) }
guard !photos.isEmpty else { quitter("Aucune photo JPEG dans \(sourceURL.path)") }

let horodatage = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
let essai = fm.temporaryDirectory.appendingPathComponent("essai-tri-photo-\(horodatage)", isDirectory: true)
let reception = essai.appendingPathComponent("reception", isDirectory: true)
let importLR = essai.appendingPathComponent("import-lightroom", isDirectory: true)
let tampon = essai.appendingPathComponent("tampon", isDirectory: true)
let serveur = essai.appendingPathComponent("serveur", isDirectory: true)
for d in [reception, importLR, tampon, serveur] { try! fm.createDirectory(at: d, withIntermediateDirectories: true) }

let cube = try cheminCube.map { try FichierCube(fichier: URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)) }
let concours = try cheminFFE.map { try LecteurFFE.lire(fichier: URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)) }

print("Essai du moteur : \(photos.count) photos, dossier d'essai \(essai.path)")
if let cube { print("  .cube : \(cube.taille)³") }
if let concours { print("  FFE : \(concours.format.rawValue), \(concours.epreuves.count) épreuves") }

/// Faux chrono : un passage par suite de photos qui portent le même code (heure de prise de vue).
func fauxChrono(_ photos: [URL]) -> URL {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy:MM:dd HH:mm:ss"
    var vues: [(Double, CodePassage)] = []
    for p in photos {
        guard let s = CGImageSourceCreateWithURL(p as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any] else { continue }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        guard let t = (exif[kCGImagePropertyExifDateTimeOriginal] as? String).flatMap(f.date(from:)),
              let c = CodePassage.lire(tiff[kCGImagePropertyTIFFCopyright] as? String), c.special == nil else { continue }
        vues.append((t.timeIntervalSince1970, c))
    }
    vues.sort { $0.0 < $1.0 }
    var passages: [[String: Any]] = []
    var i = 0
    while i < vues.count {
        var k = i
        while k + 1 < vues.count && vues[k + 1].1 == vues[i].1 && vues[k + 1].0 - vues[k].0 < 300 { k += 1 }
        // --erreurs N : un passage sur N porte un autre dossard, comme si le photographe s'était trompé de code
        let faux = erreursChrono > 0 && passages.count % erreursChrono == erreursChrono - 1
        let dossard = faux ? String((Int(vues[i].1.dossard) ?? 0) + 100) : vues[i].1.dossard
        passages.append(["source": "piste1", "epreuve": vues[i].1.epreuve, "dossard": dossard,
                         "entree": vues[i].0 - 3, "depart": vues[i].0 - 1, "fin": vues[k].0 + 1])
        i = k + 1
    }
    let url = essai.appendingPathComponent("passages-simules.json")
    let data = try! JSONSerialization.data(withJSONObject: ["passages": passages], options: [.prettyPrinted])
    try! data.write(to: url)
    print("  Faux chrono : \(passages.count) passages (\(url.lastPathComponent))")
    return url
}

var chrono: ConfigChrono?
if let cheminPassages {
    chrono = ConfigChrono(adresse: "", codeRegie: "", codeTechnicien: "", attenteMaxMinutes: 0.2,
                          fichierPassages: URL(fileURLWithPath: (cheminPassages as NSString).expandingTildeInPath))
} else if simulerChrono {
    chrono = ConfigChrono(adresse: "", codeRegie: "", codeTechnicien: "", attenteMaxMinutes: 0.2, fichierPassages: fauxChrono(photos))
}

let moteur = Moteur()
try moteur.demarrer(ConfigMoteur(reception: reception, importLightroom: importLR, tampon: avecTampon ? tampon : nil,
                                 serveur: serveur, cote: 1500, qualite: 56, cube: cube, concours: concours,
                                 tailleLot: 20, silenceMinutes: 1, retarderSiOccupe: true,
                                 journal: essai.appendingPathComponent("journal.sqlite"),
                                 chrono: chrono, attente00Minutes: 0.2))

// Les photos arrivent dans la réception (copie, puis renommage : jamais de fichier à moitié écrit).
let debut = Date()
DispatchQueue.global(qos: .userInitiated).async {
    for p in photos {
        let prov = reception.appendingPathComponent(".\(p.lastPathComponent).part")
        try? fm.copyItem(at: p, to: prov)
        try? fm.moveItem(at: prov, to: reception.appendingPathComponent(p.lastPathComponent))
        if let cadence, cadence > 0 { Thread.sleep(forTimeInterval: 60 / cadence) }
    }
}

func nombre(_ d: URL) -> Int {
    ((try? fm.contentsOfDirectory(atPath: d.path)) ?? []).filter { !$0.hasPrefix(".") && $0.lowercased().hasSuffix("jpg") }.count
}

var dernierAffichage = Date.distantPast
var fin: Date?
while true {
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    let r = moteur.resume
    let codes = r.series.filter { $0.genre == .photoCode }.count
    let faites = nombre(importLR) + (avecTampon ? nombre(tampon) : 0) + r.aRenvoyer.count + r.doublons.count + r.aValider + codes
    if Date().timeIntervalSince(dernierAffichage) >= 5 {
        dernierAffichage = Date()
        print(String(format: "  %4ld / %ld  · %5.0f photos/min · file %ld · Lightroom %3.0f %% · ouvriers %ld",
                     faites, photos.count, Double(faites) / max(Date().timeIntervalSince(debut), 1) * 60,
                     r.enFile, r.chargeLightroom * 100, r.ouvriers))
    }
    if faites >= photos.count && fin == nil { fin = Date() }
    if let f = fin, !avecTampon || nombre(tampon) == 0 || Date().timeIntervalSince(f) > 150 { break }
    if Date().timeIntervalSince(debut) > Double(photos.count) * 2 + 120 { print("  Arrêt : trop long."); break }
}
let duree = (fin ?? Date()).timeIntervalSince(debut)
moteur.arreter()
RunLoop.main.run(until: Date().addingTimeInterval(1))

// Vérifications.
let r = moteur.resume
let envoyes = ((try? fm.contentsOfDirectory(at: importLR, includingPropertiesForKeys: nil)) ?? [])
    .filter { $0.pathExtension.lowercased() == "jpg" || $0.pathExtension.lowercased() == "jpeg" }
var copies = 0
if let e = fm.enumerator(atPath: serveur.path) { for case let p as String in e where p.lowercased().hasSuffix("jpg") { copies += 1 } }

/// Pixels décodés d'un JPEG, pour vérifier que l'original n'a pas été recompressé.
func pixels(_ u: URL) -> Data? {
    guard let s = CGImageSourceCreateWithURL(u as CFURL, nil), let im = CGImageSourceCreateImageAtIndex(s, 0, nil),
          let data = im.dataProvider?.data else { return nil }
    return data as Data
}
var identiques = 0, differents = 0, motsCles = 0
let parNomOrigine = Dictionary(photos.map { ($0.deletingPathExtension().lastPathComponent, $0) }, uniquingKeysWith: { a, _ in a })
for u in envoyes.prefix(30) {
    // IMG_4410-32.JPG ← IMG_4410.JPG (et DERB1340-35.JPG gardé tel quel)
    var base = u.deletingPathExtension().lastPathComponent
    if parNomOrigine[base] == nil, let i = base.lastIndex(of: "-") { base = String(base[..<i]) }
    guard let origine = parNomOrigine[base] else { continue }
    let a = pixels(origine), b = pixels(u)
    if a != nil && a == b { identiques += 1 } else { differents += 1 }
    if let s = CGImageSourceCreateWithURL(u as CFURL, nil),
       let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any],
       let iptc = p[kCGImagePropertyIPTCDictionary] as? [CFString: Any], iptc[kCGImagePropertyIPTCKeywords] != nil {
        motsCles += 1
    }
}

print("")
print("Résultat")
print(String(format: "  %ld photos en %.0f s : %.0f photos par minute", photos.count, duree, Double(photos.count) / max(duree, 1) * 60))
print("  Envoyées à l'import Lightroom : \(envoyes.count)")
print("  Copies .cube sur le serveur : \(copies)")
print("  À renvoyer (mal transférées) : \(r.aRenvoyer.count)")
print("  Doublons mis de côté : \(r.doublons.count)")
print("  À valider (propositions du chrono) : \(r.aValider) photos en \(r.series.filter { $0.genre == .chrono }.count) séries")
print("  Photos de code détectées : \(r.series.filter { $0.genre == .photoCode }.count)")
for s in r.series.prefix(8) {
    print("    · \(s.genre == .photoCode ? "photo de code" : "\(s.photos.count) photos") \(s.code) → \(s.proposition) (\(s.confiance) %) : \(s.raison)")
}
print("  En erreur : \(r.enErreur)\(r.message.isEmpty ? "" : " (dernier message : \(r.message))")")
print("  Originaux vérifiés (30 max) : \(identiques) pixels identiques, \(differents) différents")
print("  Avec mots-clés IPTC : \(motsCles) (seulement si le code correspond au fichier FFE)")
print("  Dossier d'essai gardé pour regarder : \(essai.path)")
exit(differents == 0 && r.enErreur == 0 ? 0 : 2)
