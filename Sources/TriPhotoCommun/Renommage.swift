import Foundation

/// Renommage unique d'une photo à son arrivée : nom d'origine + minute de prise de vue.
/// « IMG_4410.JPG » prise à 14:32:07 → « IMG_4410_1432.JPG ». Évite les doublons quand un boîtier repart à
/// IMG_0001 ou que deux boîtiers ont le même compteur.
public enum Renommage {
    /// - Parameters:
    ///   - origine: nom donné par le boîtier (« IMG_4410.JPG »).
    ///   - priseEXIF: date de prise de vue telle qu'écrite dans l'EXIF (« 2026:11:29 14:32:07 »), lue sans
    ///     conversion de fuseau : c'est l'heure de l'appareil.
    ///   - secours: heure à utiliser si l'EXIF n'a pas de date (heure du fichier).
    public static func nom(origine: String, priseEXIF: String?, secours: Date? = nil) -> String {
        let ext = (origine as NSString).pathExtension
        let base = (origine as NSString).deletingPathExtension
        let hhmm = minute(priseEXIF) ?? secours.map(minute(date:)) ?? "0000"
        return ext.isEmpty ? "\(base)_\(hhmm)" : "\(base)_\(hhmm).\(ext)"
    }

    /// Nom libre dans un dossier : « IMG_4410_1432.JPG », sinon « IMG_4410_1432-2.JPG », « -3 »…
    public static func libre(_ nom: String, existe: (String) -> Bool) -> String {
        guard existe(nom) else { return nom }
        let ext = (nom as NSString).pathExtension
        let base = (nom as NSString).deletingPathExtension
        var i = 2
        while true {
            let n = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            if !existe(n) { return n }
            i += 1
        }
    }

    /// « 2026:11:29 14:32:07 » → « 1432 ».
    public static func minute(_ priseEXIF: String?) -> String? {
        guard let p = priseEXIF?.trimmingCharacters(in: .whitespaces), p.count >= 16 else { return nil }
        let heure = p.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        let morceaux = heure.split(separator: ":")
        guard morceaux.count >= 2, let h = Int(morceaux[0]), let m = Int(morceaux[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return String(format: "%02d%02d", h, m)
    }

    static func minute(date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
