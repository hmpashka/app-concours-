import Foundation

/// Noms des dossiers d'épreuve sur le serveur local : numéro sur deux chiffres puis le nom FFE nettoyé
/// (sans parenthèses, tirets, barres ni caractères refusés par les partages SMB), accents gardés.
public enum NomDossier {
    /// « 08 », « Amateur 2 - Grand Prix (1,15 m) » → « 08 Amateur 2 Grand Prix 1,15 m ».
    public static func pourEpreuve(numero: String, nom: String) -> String {
        let n = CodePassage.deuxChiffres(CodePassage.cle(numero)).uppercased()
        let propre = nettoyer(nom)
        return propre.isEmpty ? n : "\(n) \(propre)"
    }

    /// Enlève ce qui gêne dans un nom de dossier et resserre les espaces.
    public static func nettoyer(_ texte: String) -> String {
        let interdits = CharacterSet(charactersIn: "()[]{}-–—_/\\:*?\"<>|#%&;").union(.controlCharacters)
        var sortie = ""
        for scalaire in texte.unicodeScalars {
            if scalaire == "." {
                sortie.append(",")
            } else if interdits.contains(scalaire) {
                sortie.append(" ")
            } else {
                sortie.unicodeScalars.append(scalaire)
            }
        }
        // la virgule des hauteurs (« 1,15 m ») est gardée ; « 1.15 m » devient « 1,15 m »
        let mots = sortie.split(whereSeparator: { $0.isWhitespace })
        return mots.joined(separator: " ")
    }
}
