import Foundation

/// Code d'un passage, écrit par le photographe dans le Copyright de la photo : « #08_05 » = épreuve 8, dossard 5.
/// « #08_00 » = engagé terrain ou cavalier inconnu ; « #08_99 » = remise des prix de l'épreuve 8.
public struct CodePassage: Hashable, Codable, Sendable, CustomStringConvertible {
    public enum Special: String, Codable, Sendable {
        /// _00 : engagé terrain ou cavalier non identifié à la prise de vue (« à attribuer »).
        case inconnu
        /// _99 : remise des prix.
        case remiseDesPrix
    }

    /// Numéro d'épreuve sans zéros devant, en minuscules (« 8 », « 5a »).
    public let epreuve: String
    /// Dossard sans zéros devant, en minuscules (« 5 », « 0 », « 99 »).
    public let dossard: String

    public init(epreuve: String, dossard: String) {
        self.epreuve = CodePassage.cle(epreuve)
        self.dossard = CodePassage.cle(dossard)
    }

    public var special: Special? {
        switch dossard {
        case "0": return .inconnu
        case "99": return .remiseDesPrix
        default: return nil
        }
    }

    /// Le code écrit comme HUGO l'écrit : « #08_05 » (deux chiffres au moins pour les nombres).
    public var texte: String { "#\(CodePassage.deuxChiffres(epreuve))_\(CodePassage.deuxChiffres(dossard))" }

    public var description: String { texte }

    // MARK: - Lecture

    private static let motif = try! NSRegularExpression(
        pattern: #"#?\s*0*(\d+[A-Za-z]?|[A-Za-z][A-Za-z0-9]*)\s*[_\-]\s*0*([A-Za-z0-9]+)"#)

    /// Retrouve le code dans un texte (Copyright, mot-clé…). « #01_025 », « #1_25 » et « 1-25 » donnent le même.
    public static func lire(_ texte: String?) -> CodePassage? {
        guard let texte, !texte.isEmpty else { return nil }
        let ns = texte as NSString
        guard let m = motif.firstMatch(in: texte, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges == 3 else { return nil }
        let e = ns.substring(with: m.range(at: 1))
        let d = ns.substring(with: m.range(at: 2))
        return CodePassage(epreuve: e, dossard: d)
    }

    /// Deux codes désignent-ils le même passage ?
    public static func meme(_ a: String?, _ b: String?) -> Bool {
        guard let ca = lire(a), let cb = lire(b) else { return false }
        return ca == cb
    }

    // MARK: - Outils

    /// « 01 » → « 1 », « 00 » → « 0 », « 5A » → « 5a », espaces enlevés.
    public static func cle(_ valeur: String) -> String {
        let s = valeur.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return "" }
        let sansZeros = s.drop { $0 == "0" }
        return sansZeros.isEmpty ? "0" : String(sansZeros)
    }

    static func deuxChiffres(_ s: String) -> String {
        if let n = Int(s) { return n < 10 ? "0\(n)" : String(n) }
        return s
    }
}
