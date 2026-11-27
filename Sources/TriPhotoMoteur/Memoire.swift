import Accelerate
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Une catégorie de la mémoire = un sous-dossier du dossier partagé.
public struct CategorieMemoire: Identifiable, Hashable, Sendable {
    /// « scène » : une seule par photo (bonne, floue, sol, code). « en plus » : s'ajoute à la scène (chute, meilleure…).
    public enum Genre: String, Sendable { case scene, enPlus }
    public var id: String { cle }
    public var cle: String
    public var nom: String
    public var genre: Genre
    public var exemples: Int
    public var prete: Bool { exemples >= Memoire.minimumExemples }
}

/// Un exemple : une petite vignette (360 px) dans le dossier de sa catégorie.
public struct ExempleMemoire: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public var url: URL
    public var categorie: String
    public var nom: String
    public var date: Date
    /// Encore dans iCloud (pas téléchargée sur ce Mac) : demandée, arrive en quelques secondes.
    public var dansLeNuage: Bool
}

/// La mémoire partagée entre les stands : un dossier iCloud Drive (« Tri-photo Mémoire ») avec un sous-dossier par
/// catégorie et, dedans, des vignettes de 360 px seulement (environ 25 Ko). Jamais remise à zéro : on ajoute et on
/// retire des exemples un par un (un exemple retiré part à la corbeille, on peut le remettre).
public final class Memoire: @unchecked Sendable {
    public static let minimumExemples = 20
    public static let base: [(String, String, CategorieMemoire.Genre)] = [
        ("bonne", "Bonne", .scene), ("floue", "Floue", .scene), ("sol", "Sol", .scene), ("code", "Photo de code", .scene),
        ("chute", "Chute", .enPlus), ("meilleure", "Meilleures", .enPlus), ("reseaux", "Réseaux sociaux", .enPlus),
    ]
    public static let cote = 360

    /// iCloud Drive › Tri-photo Mémoire (à partager depuis le Finder avec les autres Mac des stands).
    public static var dossierParDefaut: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Tri-photo Mémoire", isDirectory: true)
    }

    public let dossier: URL
    private let verrou = NSLock()
    private var _version = 0

    public init(dossier: URL) {
        self.dossier = dossier
    }

    /// Change à chaque ajout ou retrait fait sur ce Mac (les ajouts des autres stands sont vus à la relecture).
    public var version: Int { verrou.lock(); defer { verrou.unlock() }; return _version }
    private func changee() { verrou.lock(); _version += 1; verrou.unlock() }

    public func creer() {
        let fm = FileManager.default
        // iCloud Drive coupé sur ce Mac : on ne fabrique pas un faux dossier iCloud
        guard fm.fileExists(atPath: dossier.deletingLastPathComponent().path) else { return }
        for (cle, _, _) in Memoire.base {
            try? fm.createDirectory(at: dossier.appendingPathComponent(cle, isDirectory: true), withIntermediateDirectories: true)
        }
    }

    public var accessible: Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: dossier.path, isDirectory: &d) && d.boolValue
    }

    public static func nom(de cle: String) -> String { base.first { $0.0 == cle }?.1 ?? cle }
    public static func genre(de cle: String) -> CategorieMemoire.Genre {
        base.first { $0.0 == cle }?.2 ?? .enPlus
    }

    /// Les catégories : celles de base d'abord, puis celles créées par HUGO (sous-dossiers en plus).
    public func categories() -> [CategorieMemoire] {
        let fm = FileManager.default
        let dossiers = ((try? fm.contentsOfDirectory(at: dossier, includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
        let autres = dossiers.filter { d in !Memoire.base.contains { $0.0 == d } }.sorted()
        return (Memoire.base.map(\.0) + autres).map { cle in
            CategorieMemoire(cle: cle, nom: Memoire.nom(de: cle), genre: Memoire.genre(de: cle), exemples: compter(cle))
        }
    }

    private func compter(_ cle: String) -> Int {
        let l = (try? FileManager.default.contentsOfDirectory(atPath: dossier.appendingPathComponent(cle).path)) ?? []
        return l.filter { Memoire.estVignette($0) }.count
    }

    static func estVignette(_ nom: String) -> Bool {
        let n = nom.lowercased()
        return n.hasSuffix(".jpg") || (n.hasPrefix(".") && n.hasSuffix(".jpg.icloud"))
    }

    /// Les exemples d'une catégorie, les plus récents d'abord. Ceux encore dans iCloud sont demandés au passage.
    public func exemples(_ cle: String) -> [ExempleMemoire] {
        let fm = FileManager.default
        let d = dossier.appendingPathComponent(cle, isDirectory: true)
        let fichiers = (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: [.contentModificationDateKey], options: [])) ?? []
        var l: [ExempleMemoire] = []
        for u in fichiers where Memoire.estVignette(u.lastPathComponent) {
            var nom = u.lastPathComponent
            var url = u
            let nuage = nom.hasPrefix(".") && nom.lowercased().hasSuffix(".icloud")
            if nuage {
                nom = String(nom.dropFirst().dropLast(".icloud".count))
                url = d.appendingPathComponent(nom)
                try? fm.startDownloadingUbiquitousItem(at: url)
            }
            let date = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            l.append(ExempleMemoire(url: url, categorie: cle, nom: nom, date: date, dansLeNuage: nuage))
        }
        return l.sorted { $0.date > $1.date }
    }

    /// Nom d'un exemple : la date et le nom de la photo (« 2026-11-24_IMG_4410-32.jpg »), sans doublon possible.
    public static func nomExemple(photo: String, date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let base = (photo as NSString).deletingPathExtension
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(f.string(from: date))_\(base).jpg"
    }

    /// Ajoute un exemple : vignette de 360 px fabriquée depuis la photo (l'original n'est que lu).
    @discardableResult
    public func ajouter(photo: URL, categorie: String, nom: String? = nil) throws -> URL {
        let fm = FileManager.default
        let d = dossier.appendingPathComponent(categorie, isDirectory: true)
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        let cible = d.appendingPathComponent(nom ?? Memoire.nomExemple(photo: photo.lastPathComponent))
        if fm.fileExists(atPath: cible.path) { return cible }
        guard let im = Memoire.image(photo, cote: Memoire.cote) else {
            throw NSError(domain: "Memoire", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photo illisible : \(photo.lastPathComponent)"])
        }
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw NSError(domain: "Memoire", code: 2, userInfo: [NSLocalizedDescriptionKey: "Vignette impossible"])
        }
        CGImageDestinationAddImage(dest, im, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "Memoire", code: 2, userInfo: [NSLocalizedDescriptionKey: "Vignette impossible"])
        }
        try fm.moveItem(at: tmp, to: cible)
        changee()
        return cible
    }

    /// Remet en vraies vignettes les exemples trop gros (des photos entières copiées dans le dossier à la main :
    /// 4 à 7 Mo au lieu de 25 Ko, lentes à télécharger sur chaque Mac). Chaque grosse photo est remplacée par sa
    /// vignette de 360 px, sous le même nom ; la photo entière part à la Corbeille (on peut l'y reprendre).
    /// Celles encore dans iCloud sont demandées et seront allégées la fois suivante.
    public func alleger(limite: Int = 300_000) -> (allegees: Int, enAttente: Int) {
        let fm = FileManager.default
        var allegees = 0, enAttente = 0
        let dossiers = ((try? fm.contentsOfDirectory(at: dossier, includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        for d in dossiers {
            let fichiers = (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: [.fileSizeKey], options: [])) ?? []
            for u in fichiers {
                let nom = u.lastPathComponent
                if nom.hasPrefix(".") && nom.lowercased().hasSuffix(".jpg.icloud") {
                    // encore dans le nuage : on ne sait pas sa taille avant de l'avoir
                    continue
                }
                guard nom.lowercased().hasSuffix(".jpg"),
                      let taille = try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize, taille > limite else { continue }
                guard let im = Memoire.image(u, cote: Memoire.cote) else { enAttente += 1; continue }
                let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
                CGImageDestinationAddImage(dest, im, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
                guard CGImageDestinationFinalize(dest) else { continue }
                do {
                    try fm.trashItem(at: u, resultingItemURL: nil)
                    try fm.moveItem(at: tmp, to: u)
                    allegees += 1
                } catch {
                    try? fm.removeItem(at: tmp)
                }
            }
        }
        if allegees > 0 { changee() }
        return (allegees, enAttente)
    }

    /// Nombre d'exemples trop gros (déjà sur ce Mac) : pour proposer « Alléger ».
    public func tropGros(limite: Int = 300_000) -> Int {
        let fm = FileManager.default
        var n = 0
        let dossiers = ((try? fm.contentsOfDirectory(at: dossier, includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles])) ?? [])
        for d in dossiers {
            for u in (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: [.fileSizeKey], options: [])) ?? []
            where u.lastPathComponent.lowercased().hasSuffix(".jpg") && !u.lastPathComponent.hasPrefix(".") {
                if let t = try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize, t > limite { n += 1 }
            }
        }
        return n
    }

    /// Retire un exemple : il part à la corbeille (renvoie où, pour pouvoir l'y reprendre).
    @discardableResult
    public func retirer(_ e: ExempleMemoire) -> URL? {
        var dans: NSURL?
        try? FileManager.default.trashItem(at: e.url, resultingItemURL: &dans)
        changee()
        return dans as URL?
    }

    /// Retire l'exemple tiré de cette photo, s'il existe (photo déclassée dans la revue).
    public func retirer(photo: String, categorie: String) {
        let d = dossier.appendingPathComponent(categorie, isDirectory: true)
        let base = "_" + (photo as NSString).deletingPathExtension + ".jpg"
        let l = (try? FileManager.default.contentsOfDirectory(atPath: d.path)) ?? []
        for n in l where n.hasSuffix(base) && n.count == base.count + 10 {
            try? FileManager.default.trashItem(at: d.appendingPathComponent(n), resultingItemURL: nil)
            changee()
        }
    }

    /// Remet un exemple retiré (bouton « Annuler »).
    public func remettre(_ corbeille: URL, dans e: ExempleMemoire) {
        try? FileManager.default.moveItem(at: corbeille, to: e.url)
        changee()
    }

    public func deplacer(_ e: ExempleMemoire, vers categorie: String) {
        let d = dossier.appendingPathComponent(categorie, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let cible = d.appendingPathComponent(e.nom)
        if FileManager.default.fileExists(atPath: cible.path) { retirer(e); return }
        try? FileManager.default.moveItem(at: e.url, to: cible)
        changee()
    }

    /// Nouvelle catégorie : un sous-dossier. Elle sert aux détections dès qu'elle a 20 exemples.
    @discardableResult
    public func creerCategorie(_ nom: String) -> String? {
        let n = nom.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        guard !n.isEmpty, !n.hasPrefix(".") else { return nil }
        try? FileManager.default.createDirectory(at: dossier.appendingPathComponent(n, isDirectory: true), withIntermediateDirectories: true)
        changee()
        return n
    }

    /// Image réduite d'une photo (orientation appliquée), sans jamais la modifier.
    public static func image(_ url: URL, cote: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: cote,
                                     kCGImageSourceShouldCacheImmediately: false]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}

/// Ce que la mémoire reconnaît sur une photo.
public struct Reconnu: Sendable, Equatable {
    /// Scène la plus probable (« bonne », « floue », « sol », « code »), vide si pas assez sûr.
    public var scene = ""
    public var confiance = 0
    /// Catégories « en plus » reconnues (chute, réseaux sociaux, catégories de HUGO).
    public var enPlus: [String] = []
    /// Ressemblance aux « meilleures » (0 à 1), -1 si cette catégorie n'a pas encore 20 exemples.
    public var belle = -1.0

    /// Pour le journal : « floue », « bonne|chute », ou « - » quand rien n'est sûr.
    public var texte: String {
        let l = (scene.isEmpty ? [] : [scene]) + enPlus
        return l.isEmpty ? "-" : l.joined(separator: "|")
    }
}

/// Reconnaissance par ressemblance : chaque photo est résumée par une « empreinte » (Vision, Apple), comparée à
/// celles des exemples de la mémoire. Les 7 exemples les plus proches votent. Rien n'est appris en dehors des
/// exemples : retirer un exemple suffit à corriger. Empreintes des exemples gardées sur ce Mac (pas dans iCloud).
final class Reconnaissance {
    private let memoire: Memoire
    private let cache: URL
    private var exemples: [(cle: String, v: [Float])] = []
    private var comptes: [String: Int] = [:]
    private var signature = ""
    private var derniereLecture = Date.distantPast
    private var versionLue = -1

    init(memoire: Memoire, cache: URL) {
        self.memoire = memoire
        self.cache = cache
    }

    /// Au moins une catégorie « scène » face à une autre, ou une catégorie « en plus », a ses 20 exemples.
    var prete: Bool {
        let scenes = comptes.filter { Memoire.genre(de: $0.key) == .scene && $0.value >= Memoire.minimumExemples }
        let plus = comptes.filter { Memoire.genre(de: $0.key) == .enPlus && $0.value >= Memoire.minimumExemples }
        return scenes.count >= 2 || (!plus.isEmpty && (comptes["bonne"] ?? 0) >= Memoire.minimumExemples)
    }

    /// Relit la mémoire (toutes les 2 minutes, ou tout de suite après un changement fait sur ce Mac).
    /// Renvoie vrai si elle a changé.
    @discardableResult
    func actualiser(forcer: Bool = false) -> Bool {
        guard forcer || memoire.version != versionLue || Date().timeIntervalSince(derniereLecture) > 120 else { return false }
        derniereLecture = Date()
        versionLue = memoire.version
        var l: [(cle: String, v: [Float])] = []
        var c: [String: Int] = [:]
        var sig: [String] = []
        for cat in memoire.categories() {
            let ex = memoire.exemples(cat.cle).filter { !$0.dansLeNuage }
            c[cat.cle] = ex.count
            for e in ex {
                if let v = empreinteExemple(e) { l.append((cat.cle, v)) }
            }
            sig.append("\(cat.cle):\(ex.count):\(ex.first?.nom ?? "")")
        }
        let s = sig.joined(separator: ",")
        let change = s != signature
        exemples = l
        comptes = c
        signature = s
        return change
    }

    private func empreinteExemple(_ e: ExempleMemoire) -> [Float]? {
        let f = cache.appendingPathComponent(e.categorie, isDirectory: true).appendingPathComponent(e.nom + ".fp")
        if let d = try? Data(contentsOf: f), !d.isEmpty {
            return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
        guard let im = Memoire.image(e.url, cote: 384), let v = Reconnaissance.empreinte(im) else { return nil }
        try? FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? v.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: f, options: .atomic)
        return v
    }

    /// Empreinte Vision d'une image (quelques dizaines de millisecondes sur une image de 384 px).
    static func empreinte(_ im: CGImage) -> [Float]? {
        let r = VNGenerateImageFeaturePrintRequest()
        r.imageCropAndScaleOption = .scaleFill
        do {
            try VNImageRequestHandler(cgImage: im, options: [:]).perform([r])
        } catch {
            return nil
        }
        guard let o = r.results?.first as? VNFeaturePrintObservation, o.elementType == .float else { return nil }
        return o.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(o.elementCount)) }
    }

    /// Qualité du meilleur visage (0 à 1 : net, de face, yeux ouverts), -1 sans visage. Pour les remises des prix.
    static func qualiteVisage(_ im: CGImage) -> Double {
        let r = VNDetectFaceCaptureQualityRequest()
        do {
            try VNImageRequestHandler(cgImage: im, options: [:]).perform([r])
        } catch {
            return -1
        }
        let q = (r.results ?? []).compactMap { o -> Double? in
            guard let x = o.faceCaptureQuality else { return nil }
            return Double("\(x)")
        }
        return q.max() ?? -1
    }

    func reconnaitre(_ v: [Float]) -> Reconnu {
        var r = Reconnu()
        guard !exemples.isEmpty else { return r }
        // distances à tous les exemples (vectoriel, très rapide même pour des milliers d'exemples)
        var d: [(cle: String, d: Float)] = []
        d.reserveCapacity(exemples.count)
        for e in exemples where e.v.count == v.count {
            var x: Float = 0
            vDSP_distancesq(v, 1, e.v, 1, &x, vDSP_Length(v.count))
            d.append((e.cle, x.squareRoot()))
        }
        func vote(_ cles: Set<String>, k: Int = 7) -> [String: Double] {
            let proches = d.filter { cles.contains($0.cle) }.sorted { $0.d < $1.d }.prefix(k)
            var p: [String: Double] = [:]
            for x in proches { p[x.cle, default: 0] += 1 / Double(max(x.d, 0.001)) }
            let t = p.values.reduce(0, +)
            return t > 0 ? p.mapValues { $0 / t } : [:]
        }
        let pretes = Set(comptes.filter { $0.value >= Memoire.minimumExemples }.map(\.key))
        // scène : une seule, parmi les catégories de scène qui ont leurs 20 exemples
        let scenes = pretes.filter { Memoire.genre(de: $0) == .scene }
        if scenes.count >= 2, let m = vote(scenes).max(by: { $0.value < $1.value }), m.value >= 0.6 {
            r.scene = m.key
            r.confiance = Int((m.value * 100).rounded())
        }
        // en plus : chaque catégorie face aux photos « bonne » (les photos ordinaires)
        guard pretes.contains("bonne") else { return r }
        for cle in pretes where Memoire.genre(de: cle) == .enPlus {
            let part = vote([cle, "bonne"])[cle] ?? 0
            if cle == "meilleure" { r.belle = part }
            if part >= 0.7 && cle != "meilleure" { r.enPlus.append(cle) }
        }
        r.enPlus.sort()
        return r
    }
}

extension Memoire {
    /// Essai sans l'app (essai-moteur --memoire) : ce que la mémoire reconnaît sur ces photos, avec le temps passé.
    public func essai(_ photos: [URL], cache: URL) -> (prete: Bool, comptes: [String: Int], resultats: [(URL, Reconnu, Double, Double)]) {
        let r = Reconnaissance(memoire: self, cache: cache)
        r.actualiser(forcer: true)
        var l: [(URL, Reconnu, Double, Double)] = []
        for u in photos {
            let t0 = Date()
            var res = Reconnu()
            if let im = Memoire.image(u, cote: 384), let v = Reconnaissance.empreinte(im) { res = r.reconnaitre(v) }
            let visage = Memoire.image(u, cote: 1024).map(Reconnaissance.qualiteVisage) ?? -1
            l.append((u, res, visage, Date().timeIntervalSince(t0)))
        }
        return (r.prete, Dictionary(uniqueKeysWithValues: categories().map { ($0.cle, $0.exemples) }), l)
    }
}

extension Memoire {
    /// Change d'emplacement : tout le contenu (catégories, vignettes, fichiers ajoutés à la main) va dans le nouveau
    /// dossier. Un exemple qui y existe déjà n'est pas doublé. Les vignettes encore dans iCloud (pas téléchargées)
    /// sont demandées et restent dans l'ancien dossier : il suffit de refaire le déplacement plus tard.
    /// Renvoie (déplacés, restés).
    public func toutDeplacer(vers nouveau: URL) -> (deplaces: Int, restes: Int) {
        let fm = FileManager.default
        guard dossier.standardizedFileURL != nouveau.standardizedFileURL,
              fm.fileExists(atPath: dossier.path) else { return (0, 0) }
        // un dossier dans l'autre : on refuse (on déplacerait la mémoire dans elle-même)
        let a = dossier.standardizedFileURL.path + "/", b = nouveau.standardizedFileURL.path + "/"
        if a.hasPrefix(b) || b.hasPrefix(a) { return (-1, 0) }
        try? fm.createDirectory(at: nouveau, withIntermediateDirectories: true)
        var deplaces = 0, restes = 0
        func deplacer(_ source: URL, _ cible: URL) {
            let contenu = (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? []
            for u in contenu {
                let nom = u.lastPathComponent
                if nom == ".DS_Store" { continue }
                if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    let d = cible.appendingPathComponent(nom, isDirectory: true)
                    try? fm.createDirectory(at: d, withIntermediateDirectories: true)
                    deplacer(u, d)
                    try? fm.removeItem(at: u.appendingPathComponent(".DS_Store"))
                    if ((try? fm.contentsOfDirectory(atPath: u.path)) ?? ["?"]).isEmpty { try? fm.removeItem(at: u) }
                    continue
                }
                if nom.hasPrefix(".") && nom.hasSuffix(".icloud") {
                    // pas encore sur ce Mac : on la demande, elle partira au prochain déplacement
                    try? fm.startDownloadingUbiquitousItem(at: source.appendingPathComponent(String(nom.dropFirst().dropLast(7))))
                    restes += 1
                    continue
                }
                let c = cible.appendingPathComponent(nom)
                if fm.fileExists(atPath: c.path) {
                    try? fm.trashItem(at: u, resultingItemURL: nil)     // déjà là-bas : pas de doublon
                    deplaces += 1
                } else if (try? fm.moveItem(at: u, to: c)) != nil {
                    deplaces += 1
                } else if (try? fm.copyItem(at: u, to: c)) != nil {
                    try? fm.removeItem(at: u)
                    deplaces += 1
                } else {
                    restes += 1
                }
            }
        }
        deplacer(dossier, nouveau)
        try? fm.removeItem(at: dossier.appendingPathComponent(".DS_Store"))
        if restes == 0, ((try? fm.contentsOfDirectory(atPath: dossier.path)) ?? ["?"]).isEmpty { try? fm.removeItem(at: dossier) }
        return (deplaces, restes)
    }
}
