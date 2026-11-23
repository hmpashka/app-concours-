import Foundation
import SQLite3

/// Où en est une photo dans le moteur.
public enum EtatPhoto: String, CaseIterable, Sendable {
    case recue          // vue dans le dossier de réception
    case copiee         // copie .cube déposée sur le serveur local
    case tampon         // original (avec IPTC) dans le dossier tampon, en attente du lot
    case envoyee        // original (avec IPTC) dans l'import Lightroom : terminé
    case aRenvoyer      // mal transférée : à redemander au boîtier
    case doublon        // même nom qu'une photo déjà envoyée : attend la décision de HUGO, rien n'est envoyé
    case ecartee        // doublon mis à la corbeille par HUGO
    case erreur         // problème (serveur absent…) : sera retentée
}

/// Une ligne du journal.
public struct FichePhoto: Identifiable, Sendable {
    public var id: Int64 = 0
    public var origine: String           // nom donné par le boîtier
    public var nom: String               // nom après renommage
    public var boitier: String
    public var prise: Date?
    public var code: String              // code lu (« #08_05 »), vide si aucun
    public var etat: EtatPhoto
    public var chemin: String            // emplacement actuel de l'original
    public var copie: String             // chemin de la copie sur le serveur local
    public var erreur: String
    public var recue: Date
    public var maj: Date
}

/// Journal du concours, une petite base SQLite sur le Mac. Chaque étape y est notée : après un plantage ou une
/// coupure, le moteur sait où en était chaque photo et reprend sans perte ni doublon.
/// Utilisé depuis une seule file (celle du moteur) : pas de verrou ici.
final class Journal {
    private var db: OpaquePointer?
    private static let transitoire = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(fichier: URL) throws {
        if sqlite3_open(fichier.path, &db) != SQLITE_OK {
            throw NSError(domain: "Journal", code: 1, userInfo: [NSLocalizedDescriptionKey: "Journal illisible : \(fichier.path)"])
        }
        executer("PRAGMA journal_mode=WAL")
        executer("PRAGMA synchronous=NORMAL")
        executer("""
        CREATE TABLE IF NOT EXISTS photos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            origine TEXT NOT NULL, nom TEXT NOT NULL, boitier TEXT NOT NULL, prise REAL,
            code TEXT NOT NULL, etat TEXT NOT NULL, chemin TEXT NOT NULL, copie TEXT NOT NULL,
            erreur TEXT NOT NULL, recue REAL NOT NULL, maj REAL NOT NULL)
        """)
        executer("CREATE INDEX IF NOT EXISTS photos_etat ON photos(etat)")
        executer("CREATE INDEX IF NOT EXISTS photos_chemin ON photos(chemin)")
    }

    deinit { sqlite3_close(db) }

    @discardableResult
    private func executer(_ sql: String) -> Bool { sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK }

    private func preparer(_ sql: String) -> OpaquePointer? {
        var st: OpaquePointer?
        return sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK ? st : nil
    }

    private func lier(_ st: OpaquePointer?, _ i: Int32, _ s: String) { sqlite3_bind_text(st, i, s, -1, Journal.transitoire) }
    private func lier(_ st: OpaquePointer?, _ i: Int32, _ d: Date?) {
        if let d { sqlite3_bind_double(st, i, d.timeIntervalSince1970) } else { sqlite3_bind_null(st, i) }
    }

    private func texte(_ st: OpaquePointer?, _ i: Int32) -> String {
        guard let c = sqlite3_column_text(st, i) else { return "" }
        return String(cString: c)
    }

    private func date(_ st: OpaquePointer?, _ i: Int32) -> Date? {
        sqlite3_column_type(st, i) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(st, i))
    }

    private static let colonnes = "id, origine, nom, boitier, prise, code, etat, chemin, copie, erreur, recue, maj"

    private func fiche(_ st: OpaquePointer?) -> FichePhoto {
        FichePhoto(id: sqlite3_column_int64(st, 0), origine: texte(st, 1), nom: texte(st, 2), boitier: texte(st, 3),
                   prise: date(st, 4), code: texte(st, 5), etat: EtatPhoto(rawValue: texte(st, 6)) ?? .erreur,
                   chemin: texte(st, 7), copie: texte(st, 8), erreur: texte(st, 9),
                   recue: date(st, 10) ?? Date(), maj: date(st, 11) ?? Date())
    }

    /// Ajoute une photo et renvoie son numéro.
    func ajouter(_ f: FichePhoto) -> Int64 {
        let st = preparer("INSERT INTO photos (origine, nom, boitier, prise, code, etat, chemin, copie, erreur, recue, maj) VALUES (?,?,?,?,?,?,?,?,?,?,?)")
        defer { sqlite3_finalize(st) }
        lier(st, 1, f.origine); lier(st, 2, f.nom); lier(st, 3, f.boitier); lier(st, 4, f.prise)
        lier(st, 5, f.code); lier(st, 6, f.etat.rawValue); lier(st, 7, f.chemin); lier(st, 8, f.copie)
        lier(st, 9, f.erreur); lier(st, 10, f.recue); lier(st, 11, Date())
        sqlite3_step(st)
        return sqlite3_last_insert_rowid(db)
    }

    func mettreAJour(_ f: FichePhoto) {
        let st = preparer("UPDATE photos SET nom=?, code=?, etat=?, chemin=?, copie=?, erreur=?, maj=? WHERE id=?")
        defer { sqlite3_finalize(st) }
        lier(st, 1, f.nom); lier(st, 2, f.code); lier(st, 3, f.etat.rawValue); lier(st, 4, f.chemin)
        lier(st, 5, f.copie); lier(st, 6, f.erreur); lier(st, 7, Date()); sqlite3_bind_int64(st, 8, f.id)
        sqlite3_step(st)
    }

    /// La fiche d'un fichier du dossier de réception, s'il est déjà connu.
    func fiche(chemin: String) -> FichePhoto? {
        let st = preparer("SELECT \(Journal.colonnes) FROM photos WHERE chemin=? ORDER BY id DESC LIMIT 1")
        defer { sqlite3_finalize(st) }
        lier(st, 1, chemin)
        return sqlite3_step(st) == SQLITE_ROW ? fiche(st) : nil
    }

    /// Ce nom est-il déjà pris par une autre photo (copiée, envoyée, au tampon ou doublon en attente) ?
    func nomDejaUtilise(_ nom: String, sauf id: Int64) -> Bool {
        let st = preparer("SELECT 1 FROM photos WHERE nom=? COLLATE NOCASE AND id<>? AND etat IN ('copiee','tampon','envoyee','doublon') LIMIT 1")
        defer { sqlite3_finalize(st) }
        lier(st, 1, nom)
        sqlite3_bind_int64(st, 2, id)
        return sqlite3_step(st) == SQLITE_ROW
    }

    func fiches(etat: EtatPhoto, limite: Int = 10_000) -> [FichePhoto] {
        let st = preparer("SELECT \(Journal.colonnes) FROM photos WHERE etat=? ORDER BY id LIMIT ?")
        defer { sqlite3_finalize(st) }
        lier(st, 1, etat.rawValue)
        sqlite3_bind_int(st, 2, Int32(limite))
        var l: [FichePhoto] = []
        while sqlite3_step(st) == SQLITE_ROW { l.append(fiche(st)) }
        return l
    }

    func dernieres(_ n: Int) -> [FichePhoto] {
        let st = preparer("SELECT \(Journal.colonnes) FROM photos ORDER BY id DESC LIMIT ?")
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int(st, 1, Int32(n))
        var l: [FichePhoto] = []
        while sqlite3_step(st) == SQLITE_ROW { l.append(fiche(st)) }
        return l
    }

    /// Nombre de photos par état, depuis une heure donnée (début de la journée).
    func compter(depuis: Date) -> [EtatPhoto: Int] {
        let st = preparer("SELECT etat, COUNT(*) FROM photos WHERE recue>=? GROUP BY etat")
        defer { sqlite3_finalize(st) }
        lier(st, 1, depuis)
        var c: [EtatPhoto: Int] = [:]
        while sqlite3_step(st) == SQLITE_ROW {
            if let e = EtatPhoto(rawValue: texte(st, 0)) { c[e] = Int(sqlite3_column_int(st, 1)) }
        }
        return c
    }

    /// Photos terminées (copie + Lightroom) depuis une heure donnée : pour la cadence par minute.
    func terminees(depuis: Date) -> Int {
        let st = preparer("SELECT COUNT(*) FROM photos WHERE etat IN ('envoyee','tampon') AND maj>=?")
        defer { sqlite3_finalize(st) }
        lier(st, 1, depuis)
        return sqlite3_step(st) == SQLITE_ROW ? Int(sqlite3_column_int(st, 0)) : 0
    }

    /// Par boîtier : nombre de photos du jour et heure de la dernière.
    func boitiers(depuis: Date) -> [(nom: String, photos: Int, derniere: Date?)] {
        let st = preparer("SELECT boitier, COUNT(*), MAX(recue) FROM photos WHERE recue>=? GROUP BY boitier ORDER BY boitier")
        defer { sqlite3_finalize(st) }
        lier(st, 1, depuis)
        var l: [(nom: String, photos: Int, derniere: Date?)] = []
        while sqlite3_step(st) == SQLITE_ROW { l.append((nom: texte(st, 0), photos: Int(sqlite3_column_int(st, 1)), derniere: date(st, 2))) }
        return l
    }
}
