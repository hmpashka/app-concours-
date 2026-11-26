import CoreGraphics
import Foundation
import ImageIO
import SQLite3
import TriPhotoCommun
import UniformTypeIdentifiers

// « Au bureau » (demande HUGO 26/11/2026) : retrouver vite une photo dans les archives des années passées
// (disques réseau, un dossier par année › dossiers concours › sous-dossiers), sans passer par un catalogue
// Lightroom trop lourd.
//
// Règles :
// - Les archives ne sont JAMAIS modifiées, déplacées ni effacées : on lit, on copie, c'est tout.
// - Lecture légère : seulement le début de chaque photo (256 Ko au lieu de 10 Mo), où se trouvent la date,
//   les mots-clés, le copyright et la petite vignette déjà rangée dans le JPEG.
// - Priorité basse, une photo à la fois, en pause pendant un concours ; reprend où elle s'était arrêtée
//   (une photo déjà lue, de même taille et même date, n'est jamais relue).
// - L'index reste sur le Mac : on cherche même quand le disque est débranché.

/// Une archive : le dossier d'une année.
public struct ArchiveAnnee: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: String
    /// « 2025 » (ce que HUGO voit ; tiré du nom du dossier quand c'est possible).
    public var annee: String
    /// Dossier racine sur ce Mac (« /Volumes/Archives/2025 »).
    public var chemin: String
    /// Adresse pour rebrancher le disque réseau (« smb://NAS-HM/Archives »), vide pour un disque local ou USB.
    public var remontage: String
    /// Nom du disque (« Archives », « ARCHIVES 2024 »).
    public var nomDisque: String

    public init(id: String = UUID().uuidString, annee: String, chemin: String, remontage: String = "", nomDisque: String = "") {
        self.id = id
        self.annee = annee
        self.chemin = chemin
        self.remontage = remontage
        self.nomDisque = nomDisque
    }

    public var url: URL { URL(fileURLWithPath: chemin, isDirectory: true) }

    /// Le disque est-il branché ? (Un disque réseau débranché : son dossier n'existe plus dans /Volumes.)
    public var present: Bool {
        var dossier: ObjCBool = false
        return FileManager.default.fileExists(atPath: chemin, isDirectory: &dossier) && dossier.boolValue
    }

    /// Année devinée d'après le nom du dossier (« Archives 2025 » → « 2025 »), sinon l'année en cours.
    public static func anneeDevinee(_ nom: String) -> String {
        if let r = nom.range(of: #"(19|20)\d\d"#, options: .regularExpression) { return String(nom[r]) }
        return String(Calendar.current.component(.year, from: Date()))
    }
}

/// Une photo des archives, telle que l'index la connaît.
public struct PhotoArchive: Identifiable, Sendable, Hashable {
    public var id: Int64
    public var archive: String
    /// Chemin depuis la racine de l'archive (« 26-11-24_LAMOTTE INDOOR/12 Pro 2 GP/DERB1340-35.JPG »).
    public var chemin: String
    public var nom: String
    public var taille: Int64
    public var prise: Date?
    /// Premier dossier sous l'année (le concours).
    public var concours: String
    /// Sous-dossiers entre le concours et la photo (« 12 Pro 2 GP »).
    public var epreuve: String
    /// Code « #12_45 » lu dans le copyright (ou l'identifiant de la tâche), vide sinon.
    public var code: String
    public var motsCles: [String]
    public var copyright: String
    public var vignette: Bool

    public init(id: Int64, archive: String, chemin: String, nom: String, taille: Int64, prise: Date?, concours: String,
                epreuve: String, code: String, motsCles: [String], copyright: String, vignette: Bool) {
        self.id = id
        self.archive = archive
        self.chemin = chemin
        self.nom = nom
        self.taille = taille
        self.prise = prise
        self.concours = concours
        self.epreuve = epreuve
        self.code = code
        self.motsCles = motsCles
        self.copyright = copyright
        self.vignette = vignette
    }

    /// Le fichier d'origine, dans l'archive donnée.
    public func url(dans a: ArchiveAnnee) -> URL { a.url.appendingPathComponent(chemin) }
}

/// Ce que l'on cherche.
public struct RechercheArchives: Equatable, Sendable {
    public enum Champ: String, CaseIterable, Identifiable, Sendable {
        case partout = "Partout"
        case motsCles = "Mots-clés"
        case nomFichier = "Nom de fichier"
        case copyright = "Copyright"
        case concours = "Concours"
        case epreuve = "Épreuve"
        public var id: String { rawValue }
        var colonne: String {
            switch self {
            case .partout: return "(n_tout || ' ' || n_csv)"
            case .motsCles: return "(n_mots || ' ' || n_csv)"
            case .nomFichier: return "n_nom"
            case .copyright: return "n_copyright"
            case .concours: return "n_concours"
            case .epreuve: return "n_epreuve"
            }
        }
    }

    public var texte = ""
    public var champ: Champ = .partout
    /// Une seule année (id de l'archive), nil : toutes.
    public var archive: String?
    /// Un seul concours (nom exact du dossier), nil : tous.
    public var concours: String?
    /// Numéro d'épreuve (« 12 ») ou bout du nom du sous-dossier, vide : toutes.
    public var epreuve = ""
    public var du: Date?
    public var au: Date?
    public var limite = 3000

    public init(texte: String = "", champ: Champ = .partout) {
        self.texte = texte
        self.champ = champ
    }

    public var vide: Bool {
        IndexArchives.normaliser(texte).isEmpty && concours == nil && epreuve.trimmingCharacters(in: .whitespaces).isEmpty
            && du == nil && au == nil
    }
}

/// L'index des archives : une base SQLite sur ce Mac (environ 1 Ko par photo).
/// Utilisable depuis plusieurs fils (verrou) : l'indexation écrit pendant que l'écran cherche.
public final class IndexArchives: @unchecked Sendable {
    private var db: OpaquePointer?
    private let verrou = NSRecursiveLock()
    private static let transitoire = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public let fichier: URL
    /// Dossier des vignettes (240 px, environ 10 Ko chacune) : « <dossier>/Vignettes/<archive>/<id / 1000>/<id>.jpg ».
    public let dossierVignettes: URL

    /// `dossier` : où ranger l'index et les vignettes (Application Support › Tri-photo › Au bureau).
    public init(dossier: URL) throws {
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        fichier = dossier.appendingPathComponent("index-archives.sqlite")
        dossierVignettes = dossier.appendingPathComponent("Vignettes", isDirectory: true)
        if sqlite3_open(fichier.path, &db) != SQLITE_OK {
            throw NSError(domain: "IndexArchives", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Index des archives illisible : \(fichier.path)"])
        }
        executer("PRAGMA journal_mode=WAL")
        executer("PRAGMA synchronous=NORMAL")
        executer("""
        CREATE TABLE IF NOT EXISTS photos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            archive TEXT NOT NULL, chemin TEXT NOT NULL, dossier TEXT NOT NULL, nom TEXT NOT NULL,
            taille INTEGER NOT NULL, modif REAL NOT NULL, prise REAL,
            concours TEXT NOT NULL, epreuve TEXT NOT NULL, num TEXT NOT NULL, code TEXT NOT NULL,
            mots TEXT NOT NULL, copyright TEXT NOT NULL, vignette INTEGER NOT NULL, passe INTEGER NOT NULL,
            n_tout TEXT NOT NULL, n_nom TEXT NOT NULL, n_concours TEXT NOT NULL, n_epreuve TEXT NOT NULL,
            n_mots TEXT NOT NULL, n_copyright TEXT NOT NULL,
            mots_csv TEXT NOT NULL DEFAULT '', n_csv TEXT NOT NULL DEFAULT '',
            UNIQUE(archive, chemin))
        """)
        // cavalier et cheval tirés du fichier d'attribution du concours (photos d'archives sans mots-clés)
        executer("ALTER TABLE photos ADD COLUMN mots_csv TEXT NOT NULL DEFAULT ''")
        executer("ALTER TABLE photos ADD COLUMN n_csv TEXT NOT NULL DEFAULT ''")
        executer("CREATE TABLE IF NOT EXISTS csv (archive TEXT NOT NULL, concours TEXT NOT NULL, signature TEXT NOT NULL, PRIMARY KEY(archive, concours))")
        executer("CREATE INDEX IF NOT EXISTS photos_dossier ON photos(archive, dossier)")
        executer("CREATE INDEX IF NOT EXISTS photos_prise ON photos(prise)")
        executer("CREATE INDEX IF NOT EXISTS photos_concours ON photos(archive, concours)")
        executer("CREATE TABLE IF NOT EXISTS passes (archive TEXT PRIMARY KEY, passe INTEGER NOT NULL, fin REAL)")
        executer("""
        CREATE TABLE IF NOT EXISTS attente (
            id INTEGER PRIMARY KEY AUTOINCREMENT, photo INTEGER NOT NULL, destination TEXT NOT NULL, demandee REAL NOT NULL)
        """)
    }

    deinit { sqlite3_close(db) }

    // MARK: - Outils SQLite

    @discardableResult
    private func executer(_ sql: String) -> Bool {
        verrou.lock(); defer { verrou.unlock() }
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private enum Valeur {
        case t(String), i(Int64), r(Double), nul
    }

    private func lier(_ st: OpaquePointer?, _ valeurs: [Valeur]) {
        for (k, v) in valeurs.enumerated() {
            let i = Int32(k + 1)
            switch v {
            case .t(let s): sqlite3_bind_text(st, i, s, -1, IndexArchives.transitoire)
            case .i(let n): sqlite3_bind_int64(st, i, n)
            case .r(let d): sqlite3_bind_double(st, i, d)
            case .nul: sqlite3_bind_null(st, i)
            }
        }
    }

    /// Lance une requête et lit chaque ligne (sous le verrou).
    private func lignes(_ sql: String, _ valeurs: [Valeur] = [], _ ligne: (OpaquePointer?) -> Void) {
        verrou.lock(); defer { verrou.unlock() }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(st) }
        lier(st, valeurs)
        while sqlite3_step(st) == SQLITE_ROW { ligne(st) }
    }

    @discardableResult
    private func modifier(_ sql: String, _ valeurs: [Valeur] = []) -> Bool {
        verrou.lock(); defer { verrou.unlock() }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(st) }
        lier(st, valeurs)
        return sqlite3_step(st) == SQLITE_DONE
    }

    private static func texte(_ st: OpaquePointer?, _ i: Int32) -> String {
        guard let c = sqlite3_column_text(st, i) else { return "" }
        return String(cString: c)
    }

    func debut() { executer("BEGIN") }
    func fin() { executer("COMMIT") }

    // MARK: - Texte cherchable

    /// Minuscules, sans accents, ponctuation en espaces (sauf # et _ des codes) : « Julie MARTIN, Quaprice d'Or »
    /// → « julie martin quaprice d or ».
    public static func normaliser(_ s: String) -> String {
        let plie = s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
        var r = ""
        r.reserveCapacity(plie.count)
        var espace = true
        let car = Array(plie)
        for (k, c) in car.enumerated() {
            // « _ » gardé seulement dans un code (« 12_45 ») ; « 16_CLUB » ou « 01_PREPA » : deux mots
            let codeSouligne = c == "_" && k > 0 && k + 1 < car.count && car[k - 1].isNumber && car[k + 1].isNumber
            if c.isLetter || c.isNumber || c == "#" || codeSouligne {
                r.append(c)
                espace = false
            } else if !espace {
                r.append(" ")
                espace = true
            }
        }
        return r.trimmingCharacters(in: .whitespaces)
    }

    /// Concours et épreuve d'après le chemin : 1er dossier = concours, les suivants = épreuve.
    public static func decouper(_ chemin: String) -> (concours: String, epreuve: String, dossier: String) {
        var parts = chemin.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return ("", "", "") }
        parts.removeLast()                               // le nom du fichier
        let dossier = parts.joined(separator: "/")
        guard let c = parts.first else { return ("", "", "") }
        return (c, parts.dropFirst().joined(separator: " › "), dossier)
    }

    /// Numéro d'épreuve : celui du code (« #12_45 » → « 12 »), sinon les chiffres au début du sous-dossier.
    static func numeroEpreuve(code: String, epreuve: String) -> String {
        if let c = CodePassage.lire(code) { return c.epreuve }
        if let r = epreuve.range(of: #"^\s*0*(\d+[A-Za-z]?)\b"#, options: .regularExpression) {
            return CodePassage.cle(String(epreuve[r]))
        }
        return ""
    }

    // MARK: - Écriture (indexation)

    /// Les photos déjà connues d'un dossier : nom de fichier → (id, taille, date de modification).
    func connues(archive: String, dossier: String) -> [String: (Int64, Int64, Double)] {
        var r: [String: (Int64, Int64, Double)] = [:]
        lignes("SELECT nom, id, taille, modif FROM photos WHERE archive = ? AND dossier = ?", [.t(archive), .t(dossier)]) { st in
            r[IndexArchives.texte(st, 0)] = (sqlite3_column_int64(st, 1), sqlite3_column_int64(st, 2), sqlite3_column_double(st, 3))
        }
        return r
    }

    /// Note que ces photos sont toujours là (passe en cours).
    func vues(_ ids: [Int64], passe: Int64) {
        for paquet in stride(from: 0, to: ids.count, by: 500) {
            let l = ids[paquet..<min(paquet + 500, ids.count)].map(String.init).joined(separator: ",")
            modifier("UPDATE photos SET passe = ? WHERE id IN (\(l))", [.i(passe)])
        }
    }

    /// Ajoute ou met à jour une photo. Rend son id (gardé d'une lecture à l'autre : la vignette garde son nom).
    @discardableResult
    func enregistrer(archive: String, chemin: String, taille: Int64, modif: Double, lu: LecturePhoto, vignette: Bool,
                     passe: Int64, csv: [String: [String]] = [:]) -> Int64? {
        let (concours, epreuve, dossier) = IndexArchives.decouper(chemin)
        let nom = (chemin as NSString).lastPathComponent
        let num = IndexArchives.numeroEpreuve(code: lu.code, epreuve: epreuve)
        let mots = lu.motsCles.joined(separator: "\n")
        let n = IndexArchives.normaliser
        let codeCourt = lu.code.replacingOccurrences(of: "#", with: "")
        let tout = n([nom, concours, epreuve, lu.code, codeCourt, mots.replacingOccurrences(of: "\n", with: " "), lu.copyright]
            .joined(separator: " "))
        let motsCSV = (lu.code.isEmpty ? nil : csv[lu.code]) ?? []
        let ok = modifier("""
        INSERT INTO photos (archive, chemin, dossier, nom, taille, modif, prise, concours, epreuve, num, code, mots,
            copyright, vignette, passe, n_tout, n_nom, n_concours, n_epreuve, n_mots, n_copyright, mots_csv, n_csv)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(archive, chemin) DO UPDATE SET dossier = excluded.dossier, nom = excluded.nom,
            taille = excluded.taille, modif = excluded.modif, prise = excluded.prise, concours = excluded.concours,
            epreuve = excluded.epreuve, num = excluded.num, code = excluded.code, mots = excluded.mots,
            copyright = excluded.copyright, vignette = excluded.vignette, passe = excluded.passe,
            n_tout = excluded.n_tout, n_nom = excluded.n_nom, n_concours = excluded.n_concours,
            n_epreuve = excluded.n_epreuve, n_mots = excluded.n_mots, n_copyright = excluded.n_copyright,
            mots_csv = excluded.mots_csv, n_csv = excluded.n_csv
        """, [.t(archive), .t(chemin), .t(dossier), .t(nom), .i(taille), .r(modif),
              lu.prise.map { Valeur.r($0.timeIntervalSince1970) } ?? Valeur.nul, .t(concours), .t(epreuve), .t(num), .t(lu.code),
              .t(mots), .t(lu.copyright), .i(vignette ? 1 : 0), .i(passe), .t(tout), .t(n(nom)), .t(n(concours)),
              .t(n(epreuve)), .t(n(mots)), .t(n(lu.copyright)), .t(motsCSV.joined(separator: "\n")),
              .t(n(motsCSV.joined(separator: " ")))])
        guard ok else { return nil }
        var id: Int64?
        lignes("SELECT id FROM photos WHERE archive = ? AND chemin = ?", [.t(archive), .t(chemin)]) { id = sqlite3_column_int64($0, 0) }
        return id
    }

    func marquerVignette(_ id: Int64) { modifier("UPDATE photos SET vignette = 1 WHERE id = ?", [.i(id)]) }

    func passe(archive: String) -> Int64 {
        var p: Int64 = 0
        lignes("SELECT passe FROM passes WHERE archive = ?", [.t(archive)]) { p = sqlite3_column_int64($0, 0) }
        return p
    }

    func finirPasse(archive: String, passe: Int64) {
        modifier("INSERT INTO passes (archive, passe, fin) VALUES (?,?,?) ON CONFLICT(archive) DO UPDATE SET passe = excluded.passe, fin = excluded.fin",
                 [.t(archive), .i(passe), .r(Date().timeIntervalSince1970)])
    }

    /// Fin de la dernière vérification complète d'une archive.
    public func derniereVerification(archive: String) -> Date? {
        var d: Date?
        lignes("SELECT fin FROM passes WHERE archive = ?", [.t(archive)]) { st in
            if sqlite3_column_type(st, 0) != SQLITE_NULL { d = Date(timeIntervalSince1970: sqlite3_column_double(st, 0)) }
        }
        return d
    }

    /// Photos plus vues pendant une passe complète (effacées ou déplacées sur le disque) : retirées de l'index.
    func retirerAbsentes(archive: String, passe: Int64) -> [Int64] {
        var ids: [Int64] = []
        lignes("SELECT id FROM photos WHERE archive = ? AND passe < ?", [.t(archive), .i(passe)]) { ids.append(sqlite3_column_int64($0, 0)) }
        modifier("DELETE FROM photos WHERE archive = ? AND passe < ?", [.t(archive), .i(passe)])
        return ids
    }

    /// Oublie une archive (l'index seulement : le disque n'est jamais touché).
    public func oublier(archive: String) {
        modifier("DELETE FROM photos WHERE archive = ?", [.t(archive)])
        modifier("DELETE FROM passes WHERE archive = ?", [.t(archive)])
        try? FileManager.default.removeItem(at: dossierVignettes.appendingPathComponent(archive, isDirectory: true))
    }

    // MARK: - Lecture (recherche)

    private static let colonnes = "id, archive, chemin, nom, taille, prise, concours, epreuve, code, mots, copyright, vignette, mots_csv"

    private static func photo(_ st: OpaquePointer?) -> PhotoArchive {
        var mots = texte(st, 9).components(separatedBy: "\n").filter { !$0.isEmpty }
        for m in texte(st, 12).components(separatedBy: "\n") where !m.isEmpty && !mots.contains(where: { $0.lowercased() == m.lowercased() }) {
            mots.append(m)
        }
        return PhotoArchive(
            id: sqlite3_column_int64(st, 0), archive: texte(st, 1), chemin: texte(st, 2), nom: texte(st, 3),
            taille: sqlite3_column_int64(st, 4),
            prise: sqlite3_column_type(st, 5) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(st, 5)),
            concours: texte(st, 6), epreuve: texte(st, 7), code: texte(st, 8),
            motsCles: mots, copyright: texte(st, 10),
            vignette: sqlite3_column_int(st, 11) != 0)
    }

    /// Cherche : chaque mot tapé doit se trouver (dans le champ choisi), dans n'importe quel ordre.
    /// Rend les photos (au plus `limite`, de la plus ancienne à la plus récente) et le nombre total trouvé.
    public func chercher(_ r: RechercheArchives) -> (photos: [PhotoArchive], total: Int) {
        var conditions: [String] = []
        var valeurs: [Valeur] = []
        // Chaque mot tapé doit être le DÉBUT d'un mot (« 70 » trouve « PREPA 70 », pas « R3CR2870 ») ;
        // dans les noms de fichier, n'importe quel bout suffit.
        let debutDeMot = r.champ != .nomFichier
        for mot in IndexArchives.normaliser(r.texte).split(separator: " ") {
            let echappe = mot.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            if debutDeMot {
                conditions.append("(' ' || \(r.champ.colonne)) LIKE ? ESCAPE '\\'")
                valeurs.append(.t("% \(echappe)%"))
            } else {
                conditions.append("\(r.champ.colonne) LIKE ? ESCAPE '\\'")
                valeurs.append(.t("%\(echappe)%"))
            }
        }
        if let a = r.archive { conditions.append("archive = ?"); valeurs.append(.t(a)) }
        if let c = r.concours { conditions.append("concours = ?"); valeurs.append(.t(c)) }
        let ep = r.epreuve.trimmingCharacters(in: .whitespaces)
        if !ep.isEmpty {
            let echappe = IndexArchives.normaliser(ep).replacingOccurrences(of: "_", with: "\\_")
            conditions.append("(num = ? OR n_epreuve LIKE ? ESCAPE '\\')")
            valeurs.append(.t(CodePassage.cle(ep)))
            valeurs.append(.t("%\(echappe)%"))
        }
        if let d = r.du { conditions.append("prise >= ?"); valeurs.append(.r(Calendar.current.startOfDay(for: d).timeIntervalSince1970)) }
        if let d = r.au {
            let fin = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: d)) ?? d
            conditions.append("prise < ?")
            valeurs.append(.r(fin.timeIntervalSince1970))
        }
        let ou = conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")
        var total = 0
        lignes("SELECT COUNT(*) FROM photos" + ou, valeurs) { total = Int(sqlite3_column_int64($0, 0)) }
        var photos: [PhotoArchive] = []
        photos.reserveCapacity(min(total, r.limite))
        lignes("SELECT \(IndexArchives.colonnes) FROM photos\(ou) ORDER BY prise IS NULL, prise, chemin LIMIT \(r.limite)", valeurs) {
            photos.append(IndexArchives.photo($0))
        }
        return (photos, total)
    }

    public func photo(id: Int64) -> PhotoArchive? {
        var p: PhotoArchive?
        lignes("SELECT \(IndexArchives.colonnes) FROM photos WHERE id = ?", [.i(id)]) { p = IndexArchives.photo($0) }
        return p
    }

    /// Les concours d'une archive (ou de toutes), dans l'ordre des dossiers.
    public func concours(archive: String?) -> [String] {
        var r: [String] = []
        if let archive {
            lignes("SELECT DISTINCT concours FROM photos WHERE archive = ? AND concours <> '' ORDER BY concours", [.t(archive)]) {
                r.append(IndexArchives.texte($0, 0))
            }
        } else {
            lignes("SELECT DISTINCT concours FROM photos WHERE concours <> '' ORDER BY concours") { r.append(IndexArchives.texte($0, 0)) }
        }
        return r
    }

    /// Nombre de photos et de concours d'une archive.
    public func compte(archive: String) -> (photos: Int, concours: Int) {
        var p = 0, c = 0
        lignes("SELECT COUNT(*), COUNT(DISTINCT NULLIF(concours, '')) FROM photos WHERE archive = ?", [.t(archive)]) {
            p = Int(sqlite3_column_int64($0, 0)); c = Int(sqlite3_column_int64($0, 1))
        }
        return (p, c)
    }

    /// Place prise sur le Mac : l'index, et les vignettes (compté au plus une fois par minute : c'est long).
    public func taillesSurLeMac() -> (index: Int64, vignettes: Int64) {
        let fm = FileManager.default
        func taille(_ u: URL) -> Int64 { (try? fm.attributesOfItem(atPath: u.path)[.size] as? Int64) ?? 0 }
        let index = taille(fichier) + taille(URL(fileURLWithPath: fichier.path + "-wal"))
        var v: Int64 = 0
        if let e = fm.enumerator(at: dossierVignettes, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let u as URL in e { v += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
        return (index, v)
    }

    // MARK: - Vignettes

    public func urlVignette(_ p: PhotoArchive) -> URL { urlVignette(archive: p.archive, id: p.id) }

    func urlVignette(archive: String, id: Int64) -> URL {
        dossierVignettes.appendingPathComponent(archive, isDirectory: true)
            .appendingPathComponent(String(id / 1000), isDirectory: true)
            .appendingPathComponent("\(id).jpg")
    }

    func ecrireVignette(_ image: CGImage, archive: String, id: Int64) -> Bool {
        let u = urlVignette(archive: archive, id: id)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let d = CGImageDestinationCreateWithURL(u as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(d, image, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
        return CGImageDestinationFinalize(d)
    }

    /// La vignette d'une photo. Si la photo n'en avait pas de toute prête et que son disque est branché, elle est
    /// faite maintenant d'après l'original (lu en entier, une seule fois) et gardée. nil : rien de possible.
    public func vignette(_ p: PhotoArchive, archive: ArchiveAnnee?) -> URL? {
        let u = urlVignette(p)
        if FileManager.default.fileExists(atPath: u.path) { return u }
        guard let a = archive, a.present,
              let src = CGImageSourceCreateWithURL(p.url(dans: a) as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let im = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: LecturePhoto.coteVignette,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceShouldCacheImmediately: false,
              ] as CFDictionary),
              ecrireVignette(im, archive: p.archive, id: p.id)
        else { return nil }
        marquerVignette(p.id)
        return u
    }

    // MARK: - Copies en attente d'un disque débranché

    public func mettreEnAttente(_ p: PhotoArchive, destination: URL) {
        modifier("INSERT INTO attente (photo, destination, demandee) VALUES (?,?,?)",
                 [.i(p.id), .t(destination.path), .r(Date().timeIntervalSince1970)])
    }

    public func enAttente() -> [(cle: Int64, photo: PhotoArchive, destination: URL)] {
        var l: [(Int64, Int64, String)] = []
        lignes("SELECT id, photo, destination FROM attente ORDER BY id") {
            l.append((sqlite3_column_int64($0, 0), sqlite3_column_int64($0, 1), IndexArchives.texte($0, 2)))
        }
        return l.compactMap { (cle, id, d) in
            guard let p = photo(id: id) else { retirerAttente(cle); return nil }
            return (cle, p, URL(fileURLWithPath: d, isDirectory: true))
        }
    }

    public func retirerAttente(_ cle: Int64) { modifier("DELETE FROM attente WHERE id = ?", [.i(cle)]) }

    // MARK: - Pour les essais

    /// Ajoute une photo sans lire de fichier (tests).
    @discardableResult
    public func ajouterPourEssai(archive: String, chemin: String, prise: Date? = nil, motsCles: [String] = [],
                                 copyright: String = "") -> Int64? {
        var lu = LecturePhoto()
        lu.prise = prise
        lu.motsCles = motsCles
        lu.copyright = copyright
        lu.code = LecturePhoto.codeDans(copyright)
        return enregistrer(archive: archive, chemin: chemin, taille: 1, modif: 0, lu: lu, vignette: false, passe: 1)
    }
}

// MARK: - Lecture légère d'une photo

/// Ce que l'on garde d'une photo : lu au début du fichier seulement.
public struct LecturePhoto: Sendable {
    public var prise: Date?
    public var motsCles: [String] = []
    public var copyright = ""
    public var code = ""
    /// Octets vraiment lus sur le disque (pour l'essai : combien on économise).
    public var octetsLus = 0

    public init() {}

    static let coteVignette = 240
    /// Ce qu'on lit d'une photo JPEG : l'en-tête (EXIF, IPTC, XMP et la petite vignette du boîtier).
    static let octetsEnTete = 256 * 1024
    public static let extensions: Set<String> = ["jpg", "jpeg", "heic", "tif", "tiff", "png", "dng", "cr2", "cr3", "nef",
                                                 "nrw", "arw", "raf", "orf", "rw2", "pef", "srw"]
    static let enTeteSeulement: Set<String> = ["jpg", "jpeg"]

    /// « #12_45 » s'il y a un code dans le texte (seulement avec un # : un copyright « 2024-25 » n'est pas un code).
    static func codeDans(_ s: String) -> String {
        guard s.contains("#"), let c = CodePassage.lire(String(s[s.range(of: "#")!.lowerBound...])) else { return "" }
        return c.texte
    }

    private static let formatEXIF: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f
    }()

    /// Valeurs texte d'une balise XMP (simple, liste ou texte en plusieurs langues).
    static func textesXMP(_ m: CGImageMetadata, _ chemin: String) -> [String] {
        guard let tag = CGImageMetadataCopyTagWithPath(m, nil, chemin as CFString),
              let v = CGImageMetadataTagCopyValue(tag) else { return [] }
        if let s = v as? String { return [s] }
        if let l = v as? [AnyObject] {
            return l.compactMap { o -> String? in
                if let s = o as? String { return s }
                if CFGetTypeID(o) == CGImageMetadataTagGetTypeID() {
                    return CGImageMetadataTagCopyValue(unsafeBitCast(o, to: CGImageMetadataTag.self)) as? String
                }
                return nil
            }
        }
        return []
    }

    /// Lit une photo des archives. `xmp` : le fichier .xmp à côté (photos RAW retouchées dans Lightroom), s'il existe.
    /// Rend aussi la petite vignette déjà rangée dans la photo (nil s'il n'y en a pas : elle sera faite plus tard,
    /// seulement si on la regarde).
    public static func lire(_ url: URL, xmp: URL? = nil) -> (LecturePhoto, CGImage?) {
        var lu = LecturePhoto()
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        var src: CGImageSource?
        if enTeteSeulement.contains(url.pathExtension.lowercased()),
           let fh = try? FileHandle(forReadingFrom: url) {
            let data = (try? fh.read(upToCount: octetsEnTete)) ?? Data()
            try? fh.close()
            lu.octetsLus = data.count
            src = CGImageSourceCreateWithData(data as CFData, options)
            // en-tête trop gros (rare) : on relira le fichier normalement
            if let s = src, CGImageSourceCopyPropertiesAtIndex(s, 0, nil) == nil { src = nil }
        }
        if src == nil {
            src = CGImageSourceCreateWithURL(url as CFURL, options)
            lu.octetsLus = -1                        // inconnu : ImageIO lit ce dont il a besoin
        }
        guard let src else { return (lu, nil) }
        let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let iptc = p[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
        if let s = (exif[kCGImagePropertyExifDateTimeOriginal] as? String) ?? (tiff[kCGImagePropertyTIFFDateTime] as? String) {
            lu.prise = formatEXIF.date(from: s)
        }
        var mots = (iptc[kCGImagePropertyIPTCKeywords] as? [String]) ?? []
        var droits = (tiff[kCGImagePropertyTIFFCopyright] as? String) ?? (iptc[kCGImagePropertyIPTCCopyrightNotice] as? String) ?? ""
        var metas: [CGImageMetadata] = []
        if let m = CGImageSourceCopyMetadataAtIndex(src, 0, nil) { metas.append(m) }
        if let xmp, let d = try? Data(contentsOf: xmp), let m = CGImageMetadataCreateFromXMPData(d as CFData) {
            metas.insert(m, at: 0)                   // le .xmp de Lightroom est le plus à jour
        }
        for m in metas {
            mots += textesXMP(m, "dc:subject")
            if droits.isEmpty { droits = textesXMP(m, "dc:rights").first ?? "" }
        }
        var vus = Set<String>()
        lu.motsCles = mots.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && vus.insert($0.lowercased()).inserted }
        lu.copyright = droits.trimmingCharacters(in: .whitespacesAndNewlines)
        let job = (iptc[kCGImagePropertyIPTCOriginalTransmissionReference] as? String) ?? ""
        lu.code = codeDans(lu.copyright)
        if lu.code.isEmpty { lu.code = codeDans(job) }
        // la vignette du boîtier seulement (jamais l'image entière : ce serait lire tout le fichier)
        let vignette = CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceThumbnailMaxPixelSize: coteVignette,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
        return (lu, vignette)
    }
}

// MARK: - Indexation en tâche de fond

/// Parcourt les archives et tient l'index à jour, doucement : une photo à la fois, priorité basse, pause possible.
public final class IndexeurArchives: @unchecked Sendable {
    public struct Progression: Sendable, Equatable {
        public enum Etape: String, Sendable { case attente = "En attente", liste = "Liste des dossiers", lecture = "Lecture des photos",
                                              fini = "À jour", absent = "Disque absent", pause = "En pause", erreur = "Erreur" }
        public var etape: Etape = .attente
        /// Photos trouvées sur le disque (pendant la liste) ; puis photos à lire et déjà lues.
        public var trouvees = 0
        public var aLire = 0
        public var lues = 0
        public var erreurs = 0
        /// Photos laissées dans iCloud (pas sur ce Mac) : pas lues, pour ne pas tout télécharger.
        public var dansICloud = 0
        public var message = ""
        public init() {}
    }

    public let index: IndexArchives
    /// Appelé depuis le fil de l'indexation à chaque avancée (au plus 4 fois par seconde).
    public var surProgression: ((String, Progression) -> Void)?
    /// Pause entre deux photos (secondes) : garde le réseau et le disque libres pour le reste.
    public var pauseEntrePhotos: TimeInterval = 0.02

    private let verrou = NSLock()
    private var file: [ArchiveAnnee] = []
    private var enMarche = false
    private var _pause = false
    private var _arret = false

    public init(index: IndexArchives) { self.index = index }

    public var enPause: Bool {
        get { verrou.lock(); defer { verrou.unlock() }; return _pause }
        set { verrou.lock(); _pause = newValue; verrou.unlock() }
    }

    public var occupe: Bool { verrou.lock(); defer { verrou.unlock() }; return enMarche }

    /// Arrête la passe en cours dès la photo suivante (ce qui est lu est gardé : on reprendra là).
    public func arreter() {
        verrou.lock(); _arret = true; file.removeAll(); verrou.unlock()
    }

    /// Met ces archives dans la file (une archive déjà dans la file n'y est pas mise deux fois).
    public func lancer(_ archives: [ArchiveAnnee]) {
        verrou.lock()
        for a in archives where !file.contains(where: { $0.id == a.id }) { file.append(a) }
        let demarrer = !enMarche
        if demarrer { enMarche = true; _arret = false }
        verrou.unlock()
        guard demarrer else { return }
        let t = Thread { [weak self] in self?.boucle() }
        t.qualityOfService = .utility
        t.name = "Index des archives"
        t.start()
    }

    /// Fait tout le travail dans le fil appelant (outil d'essai).
    public func indexerIci(_ a: ArchiveAnnee) -> Progression { indexer(a) }

    private func prochaine() -> ArchiveAnnee? {
        verrou.lock(); defer { verrou.unlock() }
        if file.isEmpty { enMarche = false; return nil }
        return file.removeFirst()
    }

    private var arretDemande: Bool { verrou.lock(); defer { verrou.unlock() }; return _arret }

    private func boucle() {
        while let a = prochaine() { _ = indexer(a) }
    }

    private var dernierSignal = Date.distantPast
    private func signaler(_ a: ArchiveAnnee, _ p: Progression, forcer: Bool = false) {
        guard forcer || Date().timeIntervalSince(dernierSignal) > 0.25 else { return }
        dernierSignal = Date()
        surProgression?(a.id, p)
    }

    /// Attend la fin de la pause. Rend faux si on doit tout arrêter.
    private func attendre(_ a: ArchiveAnnee, _ p: inout Progression) -> Bool {
        if enPause {
            let avant = p.etape
            p.etape = .pause
            signaler(a, p, forcer: true)
            while enPause && !arretDemande { Thread.sleep(forTimeInterval: 1) }
            p.etape = avant
            signaler(a, p, forcer: true)
        }
        return !arretDemande
    }

    private func indexer(_ a: ArchiveAnnee) -> Progression {
        var p = Progression()
        let fm = FileManager.default
        guard a.present else {
            p.etape = .absent
            signaler(a, p, forcer: true)
            return p
        }
        let passe = index.passe(archive: a.id) + 1
        p.etape = .liste
        signaler(a, p, forcer: true)

        // Dossier par dossier (essai sur le NAS le 26/11 : lister toute une année d'abord prenait plus de 10 min
        // sans rien lire) : on liste un dossier (le disque donne taille et date sans ouvrir les photos), puis on lit
        // tout de suite le début de ses photos nouvelles ou changées. Ce qui est lu est gardé : un arrêt ne perd rien.
        let cles: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .ubiquitousItemDownloadingStatusKey]
        var dejaVues: [Int64] = []
        var incomplet = false
        var arrete = false
        var compteur = 0
        p.etape = .lecture

        // fichiers d'attribution (CSV) du concours en cours : cavalier et cheval de chaque code
        var concoursCSV = ""
        var carteCSV: [String: [String]] = [:]

        func lire(_ aLire: [(rel: String, url: URL, taille: Int64, modif: Double, xmp: URL?)]) {
            guard !aLire.isEmpty else { return }
            p.aLire += aLire.count
            index.debut()
            defer { index.fin() }
            for f in aLire {
                guard attendre(a, &p) else { arrete = true; return }
                autoreleasepool {
                    let (lu, vignette) = LecturePhoto.lire(f.url, xmp: f.xmp)
                    if lu.prise == nil && lu.motsCles.isEmpty && lu.copyright.isEmpty && vignette == nil && !a.present {
                        incomplet = true              // disque parti pendant la lecture
                        return
                    }
                    if let id = index.enregistrer(archive: a.id, chemin: f.rel, taille: f.taille, modif: f.modif, lu: lu,
                                                  vignette: false, passe: passe, csv: carteCSV) {
                        if let vignette, index.ecrireVignette(vignette, archive: a.id, id: id) { index.marquerVignette(id) }
                        else { try? fm.removeItem(at: index.urlVignette(archive: a.id, id: id)) }   // ancienne vignette d'une photo changée
                    } else {
                        p.erreurs += 1
                    }
                }
                p.lues += 1
                compteur += 1
                if compteur % 50 == 0 { index.fin(); index.debut() }
                signaler(a, p)
                if pauseEntrePhotos > 0 { Thread.sleep(forTimeInterval: pauseEntrePhotos) }
            }
        }

        var pile: [String] = [""]
        while let rel = pile.popLast() {
            guard attendre(a, &p) else { return p }
            let dossier = rel.isEmpty ? a.url : a.url.appendingPathComponent(rel, isDirectory: true)
            guard let contenu = try? fm.contentsOfDirectory(at: dossier, includingPropertiesForKeys: cles,
                                                            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                if rel.isEmpty || !a.present {       // disque parti en route : rien n'est retiré de l'index
                    p.etape = .absent
                    signaler(a, p, forcer: true)
                    return p
                }
                incomplet = true
                p.erreurs += 1
                continue
            }
            let connues = index.connues(archive: a.id, dossier: rel)
            let concoursIci = rel.split(separator: "/").first.map(String.init) ?? ""
            if concoursIci != concoursCSV {
                concoursCSV = concoursIci
                carteCSV = [:]
            }
            if !rel.isEmpty && !rel.contains("/") {
                // le dossier du concours : ses .csv (fichiers d'attribution), lus à chaque passage (ils sont petits)
                let csvs = contenu.filter { $0.pathExtension.lowercased() == "csv" }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                var signature = ""
                for u in csvs {
                    let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? 0
                    signature += "\(u.lastPathComponent)|\(Int(d));"
                    carteCSV.merge(LecteurAttributionCSV.lire(fichier: u)) { _, nouveau in nouveau }
                }
                if index.signatureCSV(archive: a.id, concours: rel) != signature {
                    index.appliquerCSV(archive: a.id, concours: rel, carte: carteCSV, signature: signature)
                }
            }
            var aLire: [(rel: String, url: URL, taille: Int64, modif: Double, xmp: URL?)] = []
            let noms = Set(contenu.map { $0.lastPathComponent.lowercased() })
            var sous: [String] = []
            for u in contenu {
                let v = try? u.resourceValues(forKeys: Set(cles))
                let nom = u.lastPathComponent
                let r = rel.isEmpty ? nom : rel + "/" + nom
                if v?.isDirectory == true {
                    sous.append(r)
                    continue
                }
                guard LecturePhoto.extensions.contains(u.pathExtension.lowercased()) else { continue }
                p.trouvees += 1
                let taille = Int64(v?.fileSize ?? 0)
                let modif = v?.contentModificationDate?.timeIntervalSince1970 ?? 0
                // un .xmp à côté (RAW retouchée) : sa date compte aussi, il change quand on retouche dans Lightroom
                let nomXMP = (nom as NSString).deletingPathExtension + ".xmp"
                var xmp: URL?
                var modifTotale = modif
                if noms.contains(nomXMP.lowercased()) {
                    let ux = dossier.appendingPathComponent(nomXMP)
                    xmp = ux
                    modifTotale = max(modif, (try? ux.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?
                        .timeIntervalSince1970) ?? 0)
                }
                if let c = connues[nom], c.1 == taille, abs(c.2 - modifTotale) < 1 {
                    dejaVues.append(c.0)
                } else if v?.ubiquitousItemDownloadingStatus == .notDownloaded {
                    // photo restée dans iCloud : la lire la ferait télécharger en entier (lent, et ça remplit le disque)
                    p.dansICloud += 1
                    incomplet = true
                    if let c = connues[nom] { dejaVues.append(c.0) }
                } else {
                    aLire.append((r, u, taille, modifTotale, xmp))
                }
            }
            if dejaVues.count >= 2000 { index.vues(dejaVues, passe: passe); dejaVues.removeAll() }
            signaler(a, p)
            // les dossiers dans l'ordre alphabétique (concours par date) : la pile les reprend à l'envers
            pile += sous.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
            lire(aLire)
            if arrete { index.vues(dejaVues, passe: passe); return p }
        }
        index.vues(dejaVues, passe: passe)

        // 3. Les photos qui n'existent plus sur le disque sortent de l'index (seulement après un tour complet,
        //    et jamais plus de la moitié d'un coup : un disque mal branché ne vide pas l'index).
        if !incomplet && a.present && !arretDemande {
            let total = index.compte(archive: a.id).photos
            var absentes = 0
            index.lignesAbsentes(archive: a.id, passe: passe) { absentes = $0 }
            if absentes > 500 && absentes * 2 > total {
                p.message = "\(absentes) photos ne sont plus sur le disque : rien retiré de l'index (disque à vérifier)."
            } else {
                for id in index.retirerAbsentes(archive: a.id, passe: passe) {
                    try? fm.removeItem(at: index.urlVignette(archive: a.id, id: id))
                }
                index.finirPasse(archive: a.id, passe: passe)
            }
        }
        p.etape = .fini
        signaler(a, p, forcer: true)
        return p
    }
}

extension IndexArchives {
    /// Signature des fichiers d'attribution d'un concours déjà appliqués (noms et dates), vide si aucun.
    func signatureCSV(archive: String, concours: String) -> String? {
        var s: String?
        lignes("SELECT signature FROM csv WHERE archive = ? AND concours = ?", [.t(archive), .t(concours)]) { s = IndexArchives.texte($0, 0) }
        return s
    }

    /// Applique le fichier d'attribution aux photos déjà indexées d'un concours (sans relire les photos).
    func appliquerCSV(archive: String, concours: String, carte: [String: [String]], signature: String) {
        var codes: [(Int64, String)] = []
        lignes("SELECT id, code FROM photos WHERE archive = ? AND concours = ?", [.t(archive), .t(concours)]) {
            codes.append((sqlite3_column_int64($0, 0), IndexArchives.texte($0, 1)))
        }
        debut()
        for (id, code) in codes {
            let m = (code.isEmpty ? nil : carte[code]) ?? []
            modifier("UPDATE photos SET mots_csv = ?, n_csv = ? WHERE id = ?",
                     [.t(m.joined(separator: "\n")), .t(IndexArchives.normaliser(m.joined(separator: " "))), .i(id)])
        }
        modifier("INSERT INTO csv (archive, concours, signature) VALUES (?,?,?) ON CONFLICT(archive, concours) DO UPDATE SET signature = excluded.signature",
                 [.t(archive), .t(concours), .t(signature)])
        fin()
    }

    /// Nombre de photos plus vues pendant la passe (avant de les retirer).
    func lignesAbsentes(archive: String, passe: Int64, _ fin: (Int) -> Void) {
        var n = 0
        lignes("SELECT COUNT(*) FROM photos WHERE archive = ? AND passe < ?", [.t(archive), .i(passe)]) { n = Int(sqlite3_column_int64($0, 0)) }
        fin(n)
    }
}

// MARK: - Copie d'un original

public enum CopieArchive {
    /// Copie l'original tel quel (octet pour octet) dans `dossier`. Jamais d'écrasement : un nom déjà pris devient
    /// « NOM-2.JPG ». La copie est vérifiée (même taille) ; une copie ratée est retirée. L'original n'est pas touché.
    @discardableResult
    public static func copier(_ source: URL, vers dossier: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: dossier, withIntermediateDirectories: true)
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var cible = dossier.appendingPathComponent(source.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: cible.path) {
            cible = dossier.appendingPathComponent(ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)")
            n += 1
        }
        try fm.copyItem(at: source, to: cible)
        let a = (try? fm.attributesOfItem(atPath: source.path)[.size] as? Int64) ?? -1
        let b = (try? fm.attributesOfItem(atPath: cible.path)[.size] as? Int64) ?? -2
        guard a == b else {
            try? fm.removeItem(at: cible)
            throw NSError(domain: "CopieArchive", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Copie incomplète de \(source.lastPathComponent)"])
        }
        // le .xmp de Lightroom suit sa photo RAW
        let xmp = source.deletingPathExtension().appendingPathExtension("xmp")
        if fm.fileExists(atPath: xmp.path) {
            try? fm.copyItem(at: xmp, to: cible.deletingPathExtension().appendingPathExtension("xmp"))
        }
        return cible
    }
}
