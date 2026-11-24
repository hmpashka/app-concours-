import Foundation
import Security

/// Mots de passe gardés dans le trousseau du Mac (jamais dans les fichiers de réglages).
enum Trousseau {
    private static let service = "fr.hmtimings.triphoto"

    static func lire(_ compte: String) -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: compte, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var r: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return "" }
        return String(decoding: d, as: UTF8.self)
    }

    static func ecrire(_ compte: String, _ valeur: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: compte]
        SecItemDelete(q as CFDictionary)
        guard !valeur.isEmpty else { return }
        var a = q
        a[kSecValueData as String] = Data(valeur.utf8)
        SecItemAdd(a as CFDictionary, nil)
    }
}
