import Foundation

/// Fichier .cube (LUT 3D d'Adobe / Resolve), lu pour être appliqué par la carte graphique (Core Image).
/// Dans le fichier, le rouge varie le plus vite : c'est exactement l'ordre qu'attend Core Image.
public struct FichierCube: Equatable, Sendable {
    public enum Erreur: Error, LocalizedError, Equatable {
        case lut1D
        case tailleInvalide
        case incomplet(lues: Int, attendues: Int)

        public var errorDescription: String? {
            switch self {
            case .lut1D: return "Fichier .cube 1D : seules les LUT 3D sont prises."
            case .tailleInvalide: return "Fichier .cube sans LUT_3D_SIZE valable (2 à 128)."
            case .incomplet(let l, let a): return "Fichier .cube incomplet : \(l) valeurs au lieu de \(a)."
            }
        }
    }

    public let taille: Int
    /// taille³ couleurs × 4 nombres (rouge, vert, bleu, opacité 1), entre 0 et 1.
    public let valeurs: [Float]

    public init(texte: String) throws {
        var taille: Int?
        var mini: [Float] = [0, 0, 0]
        var maxi: [Float] = [1, 1, 1]
        var rgb: [Float] = []
        rgb.reserveCapacity(33 * 33 * 33 * 3)
        for brute in texte.split(whereSeparator: \.isNewline) {
            let ligne = brute.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            let mots = ligne.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let premier = mots.first else { continue }
            switch premier.uppercased() {
            case "LUT_3D_SIZE":
                taille = mots.count > 1 ? Int(mots[1]) : nil
            case "DOMAIN_MIN":
                mini = mots.dropFirst().prefix(3).compactMap { Float($0) }
            case "DOMAIN_MAX":
                maxi = mots.dropFirst().prefix(3).compactMap { Float($0) }
            case "LUT_1D_SIZE", "LUT_1D_INPUT_RANGE":
                throw Erreur.lut1D
            default:
                if mots.count >= 3, let r = Float(mots[0]), let v = Float(mots[1]), let b = Float(mots[2]) {
                    rgb.append(contentsOf: [r, v, b])
                }
            }
        }
        guard let t = taille, (2...128).contains(t), mini.count == 3, maxi.count == 3 else { throw Erreur.tailleInvalide }
        let attendues = t * t * t
        guard rgb.count / 3 == attendues else { throw Erreur.incomplet(lues: rgb.count / 3, attendues: attendues) }
        var sortie = [Float]()
        sortie.reserveCapacity(attendues * 4)
        for i in 0..<attendues {
            for c in 0..<3 {
                let ecart = maxi[c] - mini[c]
                sortie.append(ecart == 0 ? rgb[i * 3 + c] : (rgb[i * 3 + c] - mini[c]) / ecart)
            }
            sortie.append(1)
        }
        self.taille = t
        self.valeurs = sortie
    }

    public init(fichier url: URL) throws {
        let data = try Data(contentsOf: url)
        try self.init(texte: String(decoding: data, as: UTF8.self))
    }
}
