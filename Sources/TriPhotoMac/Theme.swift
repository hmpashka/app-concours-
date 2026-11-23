import SwiftUI

/// Couleurs des maquettes validées (inspirées de Lightroom, sans copier son look).
enum Theme {
    static let fond = Color(hex: 0x141414)
    static let panneau = Color(hex: 0x1C1C1C)
    static let carte = Color(hex: 0x232323)
    static let bordure = Color(hex: 0x333333)
    static let texte = Color(hex: 0xE6E6E6)
    static let texteDiscret = Color(hex: 0x9A9A9A)
    static let texteTresDiscret = Color(hex: 0x6A6A6A)
    static let accent = Color(hex: 0x5B9BE6)
    static let selection = Color(hex: 0x23344A)
    static let ok = Color(hex: 0x8FD19E)
    static let okFond = Color(hex: 0x1F3324)
    static let attention = Color(hex: 0xF5C58A)
    static let attentionFond = Color(hex: 0x3A2A16)
    static let orange = Color(hex: 0xE8913A)
    static let erreur = Color(hex: 0xEF8A8A)
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
            .foregroundStyle(principal ? Color.white : Theme.texte)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(principal ? Theme.accent : Theme.bordure, in: RoundedRectangle(cornerRadius: 5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
