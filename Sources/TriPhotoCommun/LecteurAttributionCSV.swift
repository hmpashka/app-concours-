import Foundation

/// Lit un fichier d'attribution des cavaliers (CSV « ; » du début du concours, ou celui de la clôture au format
/// « HMV » avec en-tête TYPE;CHP1;…) et rend, pour chaque code « #épreuve_dossard », les mots-clés du couple :
/// « Prénom NOM » puis le cheval, comme ceux que Groom Pix écrit dans les photos.
/// Sert à l'onglet « Au bureau » : les photos d'archives n'ont que le code dans leur copyright (essai NAS du 26/11).
public enum LecteurAttributionCSV {
    public static func lire(fichier url: URL) -> [String: [String]] {
        guard let d = try? Data(contentsOf: url) else { return [:] }
        return lire(d)
    }

    public static func lire(_ donnees: Data) -> [String: [String]] {
        let texte = String(data: donnees, encoding: .utf8)
            ?? String(data: donnees, encoding: .windowsCP1252)
            ?? String(data: donnees, encoding: .isoLatin1) ?? ""
        var carte: [String: [String]] = [:]
        for ligne in texte.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) {
            var c = ligne.split(separator: ";", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let premier = c.first else { continue }
            // trois formats vus dans les archives de HUGO (26/11) :
            // 2024 « TYPE;CHP1;… » puis « HMV;1;PONEY 4;;0;… » ; 2025 « HMV;CHP1;… » puis « #01_00;1;PREPA 50;;0;… » ;
            // 2026 sans en-tête « 1;CLUB 3;;1;NOM Prénom;;;;;;CHEVAL »
            if premier.uppercased() == "TYPE" { continue }
            if c.count > 1, c[1].uppercased().hasPrefix("CHP") { continue }
            if premier.uppercased() == "HMV" || premier.hasPrefix("#") { c.removeFirst() }
            guard c.count >= 11 else { continue }
            let ep = c[0], dos = c[3], nom = c[4], prenom = c[5], cheval = c[10]
            guard !ep.isEmpty, !dos.isEmpty else { continue }
            let code = CodePassage(epreuve: ep, dossard: dos)
            // lignes « inconnu » (00), « Remise des prix » (99) et « divers » (épreuve 80) : pas de couple
            guard code.special == nil, code.epreuve != "80" else { continue }
            // prénom à part, ou cavalier entier dans la colonne du nom (« NOM Prénom »)
            let cavalier = prenom.isEmpty ? Engage.prenomNom(nom)
                : [Engage.majusculeInitiale(Engage.nettoyer(prenom)), Engage.nettoyer(nom)].filter { !$0.isEmpty }.joined(separator: " ")
            let mots = [cavalier, Engage.nettoyer(cheval)].filter { !$0.isEmpty }
            if !mots.isEmpty { carte[code.texte] = mots }
        }
        return carte
    }
}

/// Relie un fichier CSV à un dossier de concours d'après la date au début du nom (« 25-02-15_CLUB BERGENNE SERV copie »)
/// et les mots du nom. Un petit écart de date est permis (le CSV porte parfois le premier jour, le dossier un autre).
public enum RapprochementCSV {
    static let motsVides: Set<String> = ["serv", "copie", "copy", "ok", "modifie", "csv", "fin", "debut", "hmv", "les", "des", "sur"]

    /// Date (« aa-mm-jj » au début) et mots du nom.
    public static func lire(_ nom: String) -> (date: Date?, mots: Set<String>) {
        let base = (nom as NSString).deletingPathExtension
        var date: Date?
        var reste = base
        if let r = base.range(of: #"^\s*(\d{2})[-_.](\d{2})[-_.](\d{2})"#, options: .regularExpression) {
            let ch = base[r].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if ch.count == 3 {
                date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2000 + ch[0], month: ch[1], day: ch[2]))
            }
            reste = String(base[r.upperBound...])
        }
        let plie = reste.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")).lowercased()
        let mots = plie.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .filter { $0.count >= 3 && !motsVides.contains($0) && !$0.allSatisfy(\.isNumber) }
        return (date, Set(mots))
    }

    /// Note de ressemblance (plus haut = mieux), nil si ce n'est pas le même concours.
    public static func note(concours: String, csv: String, ecartMaxJours: Int = 4) -> Int? {
        let a = lire(concours), b = lire(csv)
        guard let da = a.date, let db = b.date else { return nil }
        let jours = abs(Calendar(identifier: .gregorian).dateComponents([.day], from: da, to: db).day ?? 99)
        guard jours <= ecartMaxJours else { return nil }
        let communs = a.mots.intersection(b.mots).count
        // même date et un seul des deux sans nom : on accepte ; sinon il faut au moins un mot en commun
        if communs == 0 && !(jours == 0 && (a.mots.isEmpty || b.mots.isEmpty)) { return nil }
        return communs * 10 - jours
    }
}

extension RapprochementCSV {
    /// Le CSV qui ressemble le plus à ce concours (le plus récent si plusieurs se valent), nil : aucun.
    public static func meilleur(concours: String, parmi csvs: [URL]) -> URL? {
        let notes = csvs.compactMap { u in note(concours: concours, csv: u.lastPathComponent).map { (u, $0) } }
        guard let max = notes.map(\.1).max() else { return nil }
        func date(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        return notes.filter { $0.1 == max }.map(\.0).max { date($0) < date($1) }
    }
}
