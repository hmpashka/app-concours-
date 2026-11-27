import Foundation
import SQLite3
import TriPhotoCommun

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
    case aValider       // le chrono propose un autre code : attend la validation de HUGO, rien n'est envoyé
    case photoCode      // photo de code (ciel, plafond) : jamais envoyée, sert à recoder les photos d'avant
    case retiree        // supprimée dans Lightroom : sa copie a été retirée du serveur local
    case synchro        // photo du QR de synchro : règle l'heure du boîtier, jamais envoyée
}

/// Une ligne du journal.
public struct FichePhoto: Identifiable, Equatable, Sendable {
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
    // Étape 2 : codes et revue
    public var proposition: String = ""   // code proposé d'après le chrono (« #11_14 »)
    public var raison: String = ""        // pourquoi cette proposition
    public var confiance: Int = 0         // indice de confiance de la proposition, en %
    public var codeFinal: String = ""     // code validé par HUGO (prend le pas sur le Copyright)
    public var serie: String = ""         // série « À valider » (mêmes boîtier, code et proposition, à la suite)
    public var historique: String = ""    // « 15:03:12 · boîtier · #11_00 », une ligne par changement
    public var scene: String = ""         // détection : « code », « sol » ou vide
    public var nettete: Double = 0
    public var classe: String = ""        // revue : « bonne », « floue », « sol », « code » (choix de HUGO)
    public var chute = false              // mot-clé CHUTE
    public var cavalier: String = ""      // d'après le code final et le fichier FFE
    public var cheval: String = ""
    public var drapeaux: String = ""      // décisions de HUGO déjà prises (« codeGarde », « pasPhotoCode »…)
    // Étape 5 : mémoire et détections (en tâche de fond, seulement des propositions)
    public var detection: String = ""     // catégorie que la mémoire reconnaît (« floue », « sol »…), « - » : rien de sûr
    public var confianceDetection: Int = 0
    public var belle: Double = -1         // ressemblance aux « meilleures » de la mémoire (0 à 1), -1 : pas calculée
    public var visage: Double = -1        // qualité du meilleur visage (yeux ouverts, net), -1 : aucun visage ou pas calculée

    public func a(_ d: String) -> Bool { drapeaux.split(separator: "|").contains { $0 == d } }
    public mutating func marquer(_ d: String) { if !a(d) { drapeaux = drapeaux.isEmpty ? d : drapeaux + "|" + d } }
    public mutating func retirer(_ d: String) { drapeaux = drapeaux.split(separator: "|").filter { $0 != d }.joined(separator: "|") }
    /// Ajoute une ligne à l'historique des codes : « 15:03:12 · boîtier · #11_00 ».
    public mutating func noter(_ qui: String, _ quoi: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let l = "\(f.string(from: Date())) · \(qui) · \(quoi)"
        historique = historique.isEmpty ? l : historique + "\n" + l
    }

    /// Le code qui part avec la photo : celui validé par HUGO, sinon celui du photographe.
    public var codeRetenu: String { codeFinal.isEmpty ? code : codeFinal }
}

/// Journal du concours, une petite base SQLite sur le Mac. Chaque étape y est notée : après un plantage ou une
/// coupure, le moteur sait où en était chaque photo et reprend sans perte ni doublon.
/// Utilisé depuis une seule file (celle du moteur) : pas de verrou ici.
final class Journal {
    private var db: OpaquePointer?
    /// Augmente à chaque photo ajoutée ou changée : la Revue se met à jour toute seule quand il bouge.
    private(set) var version = 0
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
        // colonnes ajoutées à l'étape 2 (un journal plus ancien est complété, rien n'est perdu)
        for (nom, type) in Journal.colonnesEtape2 { executer("ALTER TABLE photos ADD COLUMN \(nom) \(type)") }
        executer("CREATE INDEX IF NOT EXISTS photos_etat ON photos(etat)")
        executer("CREATE INDEX IF NOT EXISTS photos_nom ON photos(nom)")
        executer("CREATE INDEX IF NOT EXISTS photos_serie ON photos(serie)")
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

    private static let colonnesEtape2: [(String, String)] = [
        ("proposition", "TEXT NOT NULL DEFAULT ''"), ("raison", "TEXT NOT NULL DEFAULT ''"),
        ("confiance", "INTEGER NOT NULL DEFAULT 0"), ("codeFinal", "TEXT NOT NULL DEFAULT ''"),
        ("serie", "TEXT NOT NULL DEFAULT ''"), ("historique", "TEXT NOT NULL DEFAULT ''"),
        ("scene", "TEXT NOT NULL DEFAULT ''"), ("nettete", "REAL NOT NULL DEFAULT 0"),
        ("classe", "TEXT NOT NULL DEFAULT ''"), ("chute", "INTEGER NOT NULL DEFAULT 0"),
        ("cavalier", "TEXT NOT NULL DEFAULT ''"), ("cheval", "TEXT NOT NULL DEFAULT ''"),
        ("drapeaux", "TEXT NOT NULL DEFAULT ''"),
        ("detection", "TEXT NOT NULL DEFAULT ''"), ("confianceDetection", "INTEGER NOT NULL DEFAULT 0"),
        ("belle", "REAL NOT NULL DEFAULT -1"), ("visage", "REAL NOT NULL DEFAULT -1"),
    ]

    private static let colonnes = "id, origine, nom, boitier, prise, code, etat, chemin, copie, erreur, recue, maj, "
        + "proposition, raison, confiance, codeFinal, serie, historique, scene, nettete, classe, chute, cavalier, cheval, drapeaux, "
        + "detection, confianceDetection, belle, visage"

    private func fiche(_ st: OpaquePointer?) -> FichePhoto {
        var f = FichePhoto(id: sqlite3_column_int64(st, 0), origine: texte(st, 1), nom: texte(st, 2), boitier: texte(st, 3),
                           prise: date(st, 4), code: texte(st, 5), etat: EtatPhoto(rawValue: texte(st, 6)) ?? .erreur,
                           chemin: texte(st, 7), copie: texte(st, 8), erreur: texte(st, 9),
                           recue: date(st, 10) ?? Date(), maj: date(st, 11) ?? Date())
        f.proposition = texte(st, 12)
        f.raison = texte(st, 13)
        f.confiance = Int(sqlite3_column_int(st, 14))
        f.codeFinal = texte(st, 15)
        f.serie = texte(st, 16)
        f.historique = texte(st, 17)
        f.scene = texte(st, 18)
        f.nettete = sqlite3_column_double(st, 19)
        f.classe = texte(st, 20)
        f.chute = sqlite3_column_int(st, 21) != 0
        f.cavalier = texte(st, 22)
        f.cheval = texte(st, 23)
        f.drapeaux = texte(st, 24)
        f.detection = texte(st, 25)
        f.confianceDetection = Int(sqlite3_column_int(st, 26))
        f.belle = sqlite3_column_double(st, 27)
        f.visage = sqlite3_column_double(st, 28)
        return f
    }

    private func liste(_ st: OpaquePointer?) -> [FichePhoto] {
        var l: [FichePhoto] = []
        while sqlite3_step(st) == SQLITE_ROW { l.append(fiche(st)) }
        return l
    }

    /// Ajoute une photo et renvoie son numéro.
    func ajouter(_ f: FichePhoto) -> Int64 {
        let st = preparer("INSERT INTO photos (origine, nom, boitier, prise, code, etat, chemin, copie, erreur, recue, maj) VALUES (?,?,?,?,?,?,?,?,?,?,?)")
        defer { sqlite3_finalize(st) }
        lier(st, 1, f.origine); lier(st, 2, f.nom); lier(st, 3, f.boitier); lier(st, 4, f.prise)
        lier(st, 5, f.code); lier(st, 6, f.etat.rawValue); lier(st, 7, f.chemin); lier(st, 8, f.copie)
        lier(st, 9, f.erreur); lier(st, 10, f.recue); lier(st, 11, Date())
        sqlite3_step(st)
        version += 1
        return sqlite3_last_insert_rowid(db)
    }

    func mettreAJour(_ f: FichePhoto) {
        let st = preparer("""
        UPDATE photos SET nom=?, code=?, etat=?, chemin=?, copie=?, erreur=?, maj=?, boitier=?, prise=?,
          proposition=?, raison=?, confiance=?, codeFinal=?, serie=?, historique=?, scene=?, nettete=?, classe=?,
          chute=?, cavalier=?, cheval=?, drapeaux=?, detection=?, confianceDetection=?, belle=?, visage=? WHERE id=?
        """)
        defer { sqlite3_finalize(st) }
        lier(st, 1, f.nom); lier(st, 2, f.code); lier(st, 3, f.etat.rawValue); lier(st, 4, f.chemin)
        lier(st, 5, f.copie); lier(st, 6, f.erreur); lier(st, 7, Date()); lier(st, 8, f.boitier); lier(st, 9, f.prise)
        lier(st, 10, f.proposition); lier(st, 11, f.raison); sqlite3_bind_int(st, 12, Int32(f.confiance))
        lier(st, 13, f.codeFinal); lier(st, 14, f.serie); lier(st, 15, f.historique); lier(st, 16, f.scene)
        sqlite3_bind_double(st, 17, f.nettete); lier(st, 18, f.classe); sqlite3_bind_int(st, 19, f.chute ? 1 : 0)
        lier(st, 20, f.cavalier); lier(st, 21, f.cheval); lier(st, 22, f.drapeaux)
        lier(st, 23, f.detection); sqlite3_bind_int(st, 24, Int32(f.confianceDetection))
        sqlite3_bind_double(st, 25, f.belle); sqlite3_bind_double(st, 26, f.visage)
        sqlite3_bind_int64(st, 27, f.id)
        sqlite3_step(st)
        version += 1
    }

    func fiche(id: Int64) -> FichePhoto? {
        let st = preparer("SELECT \(Journal.colonnes) FROM photos WHERE id=?")
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int64(st, 1, id)
        return sqlite3_step(st) == SQLITE_ROW ? fiche(st) : nil
    }

    /// La photo envoyée (ou au tampon) qui porte ce nom : pour suivre le dossier de travail de Lightroom.
    func ficheEnvoyee(nom: String) -> FichePhoto? {
        let st = preparer("SELECT \(Journal.colonnes) FROM photos WHERE nom=? COLLATE NOCASE AND etat IN ('envoyee','tampon') ORDER BY id DESC LIMIT 1")
        defer { sqlite3_finalize(st) }
        lier(st, 1, nom)
        return sqlite3_step(st) == SQLITE_ROW ? fiche(st) : nil
    }

    /// Les photos d'une série « À valider ».
    func fiches(serie: String) -> [FichePhoto] {
        let st = preparer("SELECT \(Journal.colonnes) FROM photos WHERE serie=? AND etat='aValider' ORDER BY prise, id")
        defer { sqlite3_finalize(st) }
        lier(st, 1, serie)
        return liste(st)
    }

    /// Les `n` photos d'un boîtier prises juste avant une heure (pour une photo de code : les 15 d'avant).
    func precedentes(boitier: String, avant: Date, n: Int) -> [FichePhoto] {
        let st = preparer("""
        SELECT \(Journal.colonnes) FROM photos WHERE boitier=? AND prise<? AND prise>=?
          AND etat NOT IN ('photoCode','ecartee','aRenvoyer','doublon','retiree','synchro') ORDER BY prise DESC LIMIT ?
        """)
        defer { sqlite3_finalize(st) }
        lier(st, 1, boitier); lier(st, 2, avant); lier(st, 3, avant.addingTimeInterval(-3600))
        sqlite3_bind_int(st, 4, Int32(n))
        return liste(st).reversed()
    }

    /// Photos parties aujourd'hui en _00 ou sans code (à attribuer).
    func fiches00(depuis: Date, limite: Int = 300) -> [FichePhoto] {
        let st = preparer("""
        SELECT \(Journal.colonnes) FROM photos WHERE etat IN ('envoyee','tampon') AND recue>=?
          AND ((codeFinal<>'' AND codeFinal LIKE '%\\_00' ESCAPE '\\') OR (codeFinal='' AND (code='' OR code LIKE '%\\_00' ESCAPE '\\')))
          ORDER BY prise DESC LIMIT ?
        """)
        defer { sqlite3_finalize(st) }
        lier(st, 1, depuis)
        sqlite3_bind_int(st, 2, Int32(limite))
        return liste(st)
    }

    /// Nombre de photos par code retenu, pour une épreuve (courbe photos par cavalier).
    func photosParCode(epreuve: String, depuis: Date) -> [(code: String, photos: Int)] {
        let st = preparer("""
        SELECT CASE WHEN codeFinal<>'' THEN codeFinal ELSE code END AS c, COUNT(*) FROM photos
          WHERE etat IN ('envoyee','tampon','copiee') AND recue>=? GROUP BY c
        """)
        defer { sqlite3_finalize(st) }
        lier(st, 1, depuis)
        var l: [(code: String, photos: Int)] = []
        let e = CodePassage.cle(epreuve)
        while sqlite3_step(st) == SQLITE_ROW {
            let c = texte(st, 0)
            if let k = CodePassage.lire(c), k.epreuve == e, k.special == nil { l.append((code: k.texte, photos: Int(sqlite3_column_int(st, 1)))) }
        }
        return l.sorted { $0.code.localizedStandardCompare($1.code) == .orderedAscending }
    }

    /// Photos envoyées dont le code (retenu) commence par cette épreuve, ou toutes (revue).
    func fichesRevue(epreuve: String?, limite: Int = 5000) -> [FichePhoto] {
        let st = preparer("""
        SELECT \(Journal.colonnes) FROM photos WHERE etat IN ('envoyee','tampon','copiee') ORDER BY prise DESC, id DESC LIMIT ?
        """)
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int(st, 1, Int32(limite))
        let l = liste(st)
        guard let epreuve else { return l }
        let e = CodePassage.cle(epreuve)
        return l.filter { CodePassage.lire($0.codeRetenu)?.epreuve == e }
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

    /// La photo déjà reçue qui porte ce nom (celle qu'un doublon pourrait remplacer).
    func fiche(nom: String, sauf id: Int64) -> FichePhoto? {
        let st = preparer("SELECT \(Journal.colonnes) FROM photos WHERE nom=? COLLATE NOCASE AND id<>? AND etat IN ('copiee','tampon','envoyee') ORDER BY id LIMIT 1")
        defer { sqlite3_finalize(st) }
        lier(st, 1, nom)
        sqlite3_bind_int64(st, 2, id)
        return sqlite3_step(st) == SQLITE_ROW ? fiche(st) : nil
    }

    /// Nombre de photos parties par code depuis le début de la journée (« #12_03 » → 8).
    func compteParCode(depuis: Date) -> [String: Int] {
        let st = preparer("""
        SELECT CASE WHEN codeFinal<>'' THEN codeFinal ELSE code END AS c, COUNT(*) FROM photos
          WHERE etat IN ('envoyee','tampon','copiee','aValider') AND recue>=? GROUP BY c
        """)
        defer { sqlite3_finalize(st) }
        lier(st, 1, depuis)
        var d: [String: Int] = [:]
        while sqlite3_step(st) == SQLITE_ROW {
            if let k = CodePassage.lire(texte(st, 0)) { d[k.texte, default: 0] += Int(sqlite3_column_int(st, 1)) }
        }
        return d
    }

    /// Photos d'un état modifiées depuis une heure donnée (les plus récentes d'abord).
    func fiches(etat: EtatPhoto, majDepuis: Date, limite: Int = 50) -> [FichePhoto] {
        let st = preparer("SELECT \(Journal.colonnes) FROM photos WHERE etat=? AND maj>=? ORDER BY maj DESC LIMIT ?")
        defer { sqlite3_finalize(st) }
        lier(st, 1, etat.rawValue)
        lier(st, 2, majDepuis)
        sqlite3_bind_int(st, 3, Int32(limite))
        return liste(st)
    }

    func fiches(etat: EtatPhoto, limite: Int = 10_000) -> [FichePhoto] {
        let st = preparer("SELECT \(Journal.colonnes) FROM photos WHERE etat=? ORDER BY id LIMIT ?")
        defer { sqlite3_finalize(st) }
        lier(st, 1, etat.rawValue)
        sqlite3_bind_int(st, 2, Int32(limite))
        return liste(st)
    }

    /// Photos qui portent une décision (drapeau), parties vers le serveur.
    func fiches(drapeau: String, limite: Int = 2000) -> [FichePhoto] {
        let st = preparer("SELECT \(Journal.colonnes) FROM photos WHERE instr(drapeaux, ?) > 0 AND etat IN ('copiee','tampon','envoyee') ORDER BY id LIMIT ?")
        defer { sqlite3_finalize(st) }
        lier(st, 1, drapeau)
        sqlite3_bind_int(st, 2, Int32(limite))
        return liste(st).filter { $0.a(drapeau) }
    }

    /// Photos qui ont une copie sur le serveur local (donc à mettre en ligne), reçues depuis le début du concours.
    func fichesEnLigne(depuis: Date) -> [FichePhoto] {
        let st = preparer("SELECT \(Journal.colonnes) FROM photos WHERE etat IN ('copiee','tampon','envoyee') AND copie<>'' AND recue>=? ORDER BY id")
        defer { sqlite3_finalize(st) }
        lier(st, 1, depuis)
        return liste(st)
    }

    /// Nombre de photos par épreuve (code retenu) et par boîtier, depuis le début du concours (statistiques).
    func statistiques(depuis: Date) -> [FichePhoto] {
        let st = preparer("SELECT \(Journal.colonnes) FROM photos WHERE etat IN ('copiee','tampon','envoyee') AND recue>=? ORDER BY id")
        defer { sqlite3_finalize(st) }
        lier(st, 1, depuis)
        return liste(st)
    }

    /// Photos parties pas encore regardées par la mémoire (les plus récentes d'abord : utile tout de suite en revue).
    func fichesADetecter(limite: Int) -> [FichePhoto] {
        let st = preparer("SELECT \(Journal.colonnes) FROM photos WHERE etat IN ('copiee','tampon','envoyee') AND detection='' ORDER BY id DESC LIMIT ?")
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int(st, 1, Int32(limite))
        return liste(st)
    }

    /// Note le résultat de la mémoire sans toucher au reste de la fiche (le moteur a pu la changer entre-temps).
    func noterDetection(id: Int64, detection: String, confiance: Int, belle: Double, visage: Double) {
        let st = preparer("UPDATE photos SET detection=?, confianceDetection=?, belle=?, visage=? WHERE id=?")
        defer { sqlite3_finalize(st) }
        lier(st, 1, detection); sqlite3_bind_int(st, 2, Int32(confiance))
        sqlite3_bind_double(st, 3, belle); sqlite3_bind_double(st, 4, visage)
        sqlite3_bind_int64(st, 5, id)
        sqlite3_step(st)
        version += 1
    }

    /// Détections à refaire : toutes (la mémoire a beaucoup changé) ou seulement celles faites sans mémoire prête (« ? »).
    func oublierDetections(seulementSansMemoire: Bool = false) {
        executer(seulementSansMemoire ? "UPDATE photos SET detection='' WHERE detection='?'"
                                      : "UPDATE photos SET detection='' WHERE detection<>''")
    }

    func compterADetecter() -> Int {
        let st = preparer("SELECT COUNT(*) FROM photos WHERE etat IN ('copiee','tampon','envoyee') AND detection=''")
        defer { sqlite3_finalize(st) }
        return sqlite3_step(st) == SQLITE_ROW ? Int(sqlite3_column_int(st, 0)) : 0
    }

    /// Photos de remise des prix (code _99) parties depuis une date.
    func fiches99(depuis: Date) -> [FichePhoto] {
        let st = preparer("""
        SELECT \(Journal.colonnes) FROM photos WHERE etat IN ('copiee','tampon','envoyee') AND recue>=?
          AND (codeFinal LIKE '%99%' OR (codeFinal='' AND code LIKE '%99%')) ORDER BY id
        """)
        defer { sqlite3_finalize(st) }
        lier(st, 1, depuis)
        return liste(st).filter { CodePassage.lire($0.codeRetenu)?.special == .remiseDesPrix }
    }

    func dernieres(_ n: Int) -> [FichePhoto] {
        let st = preparer("SELECT \(Journal.colonnes) FROM photos ORDER BY id DESC LIMIT ?")
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int(st, 1, Int32(n))
        return liste(st)
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
