import AppKit
import SwiftUI

/// Les deux thèmes de Groom Pix (choix de HUGO, 24/11) : « Bleu et or » et « Graphite ». Chacun a une version
/// sombre et une version claire, qui suit toute seule l'apparence du Mac (Réglages Système › Apparence).
/// Les iPhone du stand reçoivent le même thème.
enum ChoixTheme: String, CaseIterable, Identifiable, Codable {
    case bleuOr = "Bleu et or"
    case graphite = "Graphite"
    var id: String { rawValue }
    /// Nom envoyé aux iPhone (stable, sans accent).
    var code: String { self == .bleuOr ? "bleuOr" : "graphite" }

    static var courant: ChoixTheme {
        ChoixTheme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .bleuOr
    }
}

/// Une palette : la valeur sombre et la valeur claire de chaque couleur.
private struct Palette {
    var fond, panneau, carte, bordure, texte, texteDiscret, texteTresDiscret, accent, surAccent, selection,
        ok, okFond, attention, attentionFond, orange, erreur, texteSection: (UInt32, UInt32)

    static let graphite = Palette(
        fond: (0x141414, 0xF2F2F2), panneau: (0x1C1C1C, 0xFAFAFA), carte: (0x232323, 0xFFFFFF),
        bordure: (0x333333, 0xD4D4D4), texte: (0xE6E6E6, 0x1E1E1E), texteDiscret: (0x9A9A9A, 0x5E5E5E),
        texteTresDiscret: (0x6A6A6A, 0x8A8A8A), accent: (0x5B9BE6, 0x2F6FC0), surAccent: (0xFFFFFF, 0xFFFFFF),
        selection: (0x23344A, 0xD6E4F5), ok: (0x8FD19E, 0x2E8B47), okFond: (0x1F3324, 0xDDF0E2),
        attention: (0xF5C58A, 0x9A6312), attentionFond: (0x3A2A16, 0xF8E8CF), orange: (0xE8913A, 0xC66A12),
        erreur: (0xEF8A8A, 0xC23B3B), texteSection: (0xD0D0D0, 0x333333))

    static let bleuOr = Palette(
        fond: (0x081A2E, 0xF4F0E6), panneau: (0x0E2A47, 0xFFFDF8), carte: (0x15365C, 0xFFFFFF),
        bordure: (0x23466F, 0xD8D1C1), texte: (0xF5F1E8, 0x0E2A47), texteDiscret: (0xC9C3B6, 0x5A6472),
        texteTresDiscret: (0x8F8A80, 0x8F8A80), accent: (0xC9A34A, 0xA8842F), surAccent: (0x0E2A47, 0xFFFFFF),
        selection: (0x1D4672, 0xE8DDBF), ok: (0xA9E7BF, 0x2E8B47), okFond: (0x17402A, 0xDDF0E2),
        attention: (0xF7C78F, 0x9A6312), attentionFond: (0x3A2E14, 0xF8E8CF), orange: (0xE8913A, 0xC66A12),
        erreur: (0xF4A39C, 0xB8322A), texteSection: (0xE8E2D4, 0x23364D))
}

/// Les couleurs de l'app. Chaque couleur suit le thème choisi et l'apparence (claire ou sombre) du Mac.
enum Theme {
    private static var cache: [String: Color] = [:]

    private static func c(_ cle: String, _ v: KeyPath<Palette, (UInt32, UInt32)>) -> Color {
        let t = ChoixTheme.courant
        let k = t.rawValue + cle
        if let x = cache[k] { return x }
        let (sombre, clair) = (t == .bleuOr ? Palette.bleuOr : Palette.graphite)[keyPath: v]
        let ns = NSColor(name: nil) { a in
            let h = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? sombre : clair
            return NSColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255,
                           blue: CGFloat(h & 0xFF) / 255, alpha: 1)
        }
        let x = Color(nsColor: ns)
        cache[k] = x
        return x
    }

    static var fond: Color { c("fond", \.fond) }
    static var panneau: Color { c("panneau", \.panneau) }
    static var carte: Color { c("carte", \.carte) }
    static var bordure: Color { c("bordure", \.bordure) }
    static var texte: Color { c("texte", \.texte) }
    static var texteDiscret: Color { c("texteDiscret", \.texteDiscret) }
    static var texteTresDiscret: Color { c("texteTresDiscret", \.texteTresDiscret) }
    static var accent: Color { c("accent", \.accent) }
    /// Texte posé sur la couleur d'accent (bouton principal).
    static var surAccent: Color { c("surAccent", \.surAccent) }
    static var selection: Color { c("selection", \.selection) }
    static var ok: Color { c("ok", \.ok) }
    static var okFond: Color { c("okFond", \.okFond) }
    static var attention: Color { c("attention", \.attention) }
    static var attentionFond: Color { c("attentionFond", \.attentionFond) }
    static var orange: Color { c("orange", \.orange) }
    static var erreur: Color { c("erreur", \.erreur) }
    static var texteSection: Color { c("texteSection", \.texteSection) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Une carte sombre aux coins arrondis, comme sur les maquettes.
struct Carte<Contenu: View>: View {
    var titre: String?
    var sousTitre: String?
    @ViewBuilder var contenu: () -> Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let titre {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titre).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.texte)
                    if let sousTitre {
                        Text(sousTitre).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                    }
                }
            }
            contenu()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.carte, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.bordure, lineWidth: 1))
    }
}

/// Petite pastille d'état : vert « OK », orange « à faire ».
struct Pastille: View {
    enum Genre { case ok, attention, neutre }
    var texte: String
    var genre: Genre

    var body: some View {
        Text(texte)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(genre == .ok ? Theme.ok : genre == .attention ? Theme.attention : Theme.texteDiscret)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(genre == .ok ? Theme.okFond : genre == .attention ? Theme.attentionFond : Theme.bordure,
                        in: RoundedRectangle(cornerRadius: 4))
    }
}

/// Bouton sobre, dans le style des maquettes.
struct BoutonStyle: ButtonStyle {
    var principal = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: principal ? .semibold : .regular))
            .foregroundStyle(principal ? Theme.surAccent : Theme.texte)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(principal ? Theme.accent : Theme.bordure, in: RoundedRectangle(cornerRadius: 5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
