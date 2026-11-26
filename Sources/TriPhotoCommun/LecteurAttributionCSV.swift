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
            if premier.uppercased() == "TYPE" { continue }                 // en-tête du fichier de clôture
            if premier.uppercased() == "HMV" { c.removeFirst() }
            guard c.count >= 11 else { continue }
            let ep = c[0], dos = c[3], nom = c[4], prenom = c[5], cheval = c[10]
            guard !ep.isEmpty, !dos.isEmpty else { continue }
            let code = CodePassage(epreuve: ep, dossard: dos)
            // lignes « inconnu » (00), « Remise des prix » (99) et « divers » (épreuve 80) : pas de couple
            guard code.special == nil, code.epreuve != "80" else { continue }
            let cavalier = [Engage.majusculeInitiale(Engage.nettoyer(prenom)), Engage.nettoyer(nom)]
                .filter { !$0.isEmpty }.joined(separator: " ")
            let mots = [cavalier, Engage.nettoyer(cheval)].filter { !$0.isEmpty }
            if !mots.isEmpty { carte[code.texte] = mots }
        }
        return carte
    }
}
