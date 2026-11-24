import Foundation

/// Collections dynamiques Lightroom (.lrsmcol), une par épreuve, comme l'ancien outil de HUGO
/// (generateur_lrsmcol_final.py) : « Tout champ contient #NN_ », pas rejetée, prise pendant le concours.
/// À importer dans Lightroom : clic droit sur Collections › Importer des paramètres de collection dynamique.
public enum CollectionsLightroom {
    public struct Collection: Hashable, Sendable {
        public var fichier: String      // « 01_PREPA_110_M_VEN.lrsmcol »
        public var titre: String        // « 01 PREPA 110 M VEN »
        public var contenu: String
    }

    /// Une collection par épreuve (et « 80 DIVERS »), toutes sur les dates du concours (premier au dernier jour).
    public static func collections(_ epreuves: [EpreuveEngages], id: () -> String = { UUID().uuidString.uppercased() }) -> [Collection] {
        let dates = epreuves.compactMap { jjmmaaaa($0.date) }.sorted()
        let mn = dates.first ?? "", mx = dates.last ?? ""
        var vues: Set<String> = []
        var l: [Collection] = []
        let toutes = [("80", "divers")] + epreuves.map { ($0.numero, $0.nom) }
        for (numero, nomEpreuve) in toutes {
            let num = numero.trimmingCharacters(in: .whitespaces)
            guard !num.isEmpty else { continue }
            let n = num.count < 2 ? String(repeating: "0", count: 2 - num.count) + num : num
            let nom = nettoyer(nomEpreuve)
            let titre = "\(n) \(nom)"
            guard vues.insert(titre).inserted else { continue }
            l.append(Collection(fichier: "\(n)_\(nom.replacingOccurrences(of: " ", with: "_")).lrsmcol", titre: titre,
                                contenu: gabarit(id: id(), titre: titre, num: n, mn: mn, mx: mx)))
        }
        return l
    }

    /// Même nettoyage que l'ancien outil : majuscules, PREPA, GP, CL, 95 / 90 / 1M, tirets en espaces.
    static func nettoyer(_ s: String) -> String {
        var n = FichierEngages.nettoyer(s).uppercased()
        for (a, b) in [("PREPARATOIRE", "PREPA"), ("GRAND PRIX", "GP"), ("SO CYCLE LIBRE", "CL"),
                       ("095", "95"), ("090", "90"), ("100", "1M")] {
            n = n.replacingOccurrences(of: a, with: b)
        }
        n = n.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return n.split(separator: " ").joined(separator: " ")
    }

    /// « 22/11/2026 » → « 2026-11-22 » (jour d'abord, toujours).
    static func jjmmaaaa(_ s: String) -> String? {
        let p = s.split(separator: "/")
        guard p.count == 3, p[2].count == 4, let j = Int(p[0]), let m = Int(p[1]) else { return nil }
        return "\(p[2])-" + String(format: "%02d-%02d", m, j)
    }

    static func gabarit(id: String, titre: String, num: String, mn: String, mx: String) -> String {
        """
        s = {
        \tid = "\(id)",
        \tinternalName = "\(titre)",
        \ttitle = "\(titre)",
        \ttype = "LibrarySmartCollection",
        \tvalue = {
        \t\t{
        \t\t\tcriteria = "all",
        \t\t\toperation = "any",
        \t\t\tvalue = "#\(num)_",
        \t\t\tvalue2 = "",
        \t\t},
        \t\t{
        \t\t\tcriteria = "pick",
        \t\t\toperation = "!=",
        \t\t\tvalue = -1,
        \t\t},
        \t\t{
        \t\t\tcriteria = "captureTime",
        \t\t\toperation = "in",
        \t\t\tvalue = "\(mn)",
        \t\t\tvalue2 = "\(mx)",
        \t\t},
        \t\tcombine = "intersect",
        \t},
        \tversion = 0,
        }

        """
    }

    /// Écrit les fichiers dans un dossier (un ancien fichier du même nom part à la corbeille). Renvoie le nombre écrit.
    @discardableResult
    public static func ecrire(_ epreuves: [EpreuveEngages], dans dossier: URL) throws -> Int {
        let fm = FileManager.default
        try fm.createDirectory(at: dossier, withIntermediateDirectories: true)
        let l = collections(epreuves)
        for c in l {
            let url = dossier.appendingPathComponent(c.fichier)
            if fm.fileExists(atPath: url.path) { try? fm.trashItem(at: url, resultingItemURL: nil) }
            try Data(c.contenu.utf8).write(to: url, options: .atomic)
        }
        return l.count
    }
}
