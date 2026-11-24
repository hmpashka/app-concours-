import CoreText
import SwiftUI
import TriPhotoCommun

@main
struct PisteApp: App {
    @StateObject private var liaison = Liaison()
    @Environment(\.scenePhase) private var phase

    init() { Style.chargerPolices() }

    var body: some Scene {
        WindowGroup {
            RacineView()
                .environmentObject(liaison)
                .preferredColorScheme(.dark)
                .onAppear { liaison.demarrer() }
                .onChange(of: phase) { p in
                    switch p {
                    case .active:
                        liaison.demarrer()
                        // l'écran reste allumé pendant le concours (réglable) : les alertes arrivent tout de suite
                        UIApplication.shared.isIdleTimerDisabled = liaison.ecranAllume
                    case .background:
                        liaison.arreter()
                        UIApplication.shared.isIdleTimerDisabled = false
                    default: break
                    }
                }
        }
    }
}

/// Le style des maquettes validées : bleu nuit en dégradé, crème, or ; titres en Barlow Condensed italique.
enum Style {
    static func rvb(_ h: UInt32, _ a: Double = 1) -> Color {
        Color(red: Double((h >> 16) & 0xff) / 255, green: Double((h >> 8) & 0xff) / 255, blue: Double(h & 0xff) / 255, opacity: a)
    }
    static let nuit = rvb(0x0e2a47)
    static let nuitFonce = rvb(0x081a2e)
    static let nuitClair = rvb(0x15365c)
    static let creme = rvb(0xf5f1e8)
    static let cremeDiscret = rvb(0xc9c3b6)
    static let fleche = rvb(0x8f8a80)
    static let or = rvb(0xc9a34a)
    static let orPale = rvb(0xe8cf8f)
    static let orange = rvb(0xe8913a)
    static let orangeClair = rvb(0xf7c78f)
    static let orangeTexte = rvb(0xe9d3b5)
    static let rouge = rvb(0xb8322a)
    static let rougeTexte = rvb(0xf4d4d0)
    static let alerteFond = rvb(0x5a1a16)
    static let alerteOr = rvb(0xffd7a1)
    static let alerteTexte = rvb(0xf6d6d2)
    static let vert = rvb(0x4cc77a)
    static let vertTexte = rvb(0xa9e7bf)

    /// Fond de tous les écrans : dégradé radial (#15365c au centre, #0e2a47, #081a2e).
    static var fond: some View {
        GeometryReader { g in
            RadialGradient(stops: [.init(color: nuitClair, location: 0), .init(color: nuit, location: 0.45),
                                   .init(color: nuitFonce, location: 1)],
                           center: UnitPoint(x: 0.62, y: 0.3), startRadius: 0,
                           endRadius: max(g.size.width, g.size.height) * 0.75)
        }
        .ignoresSafeArea()
    }

    /// Barlow Condensed (fournie avec l'app) : « italique gras » pour les titres, « semi-gras » pour les codes.
    static func titre(_ taille: CGFloat) -> Font { .custom("BarlowCondensed-BoldItalic", size: taille) }
    static func code(_ taille: CGFloat) -> Font { .custom("BarlowCondensed-SemiBold", size: taille) }

    static func chargerPolices() {
        for nom in ["BarlowCondensed-BoldItalic", "BarlowCondensed-SemiBold", "BarlowCondensed-SemiBoldItalic"] {
            if let url = Bundle.module.url(forResource: nom, withExtension: "ttf", subdirectory: "Polices")
                ?? Bundle.module.url(forResource: nom, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

/// Carte translucide des maquettes (fond blanc 6 %, bord blanc 10 %, coins 14).
struct Bloc<Contenu: View>: View {
    var bord: Color = .white.opacity(0.10)
    var fond: Color = .white.opacity(0.06)
    var rayon: CGFloat = 14
    var largeurBord: CGFloat = 1
    var marge = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
    @ViewBuilder var contenu: () -> Contenu

    var body: some View {
        contenu()
            .padding(marge)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fond, in: RoundedRectangle(cornerRadius: rayon))
            .overlay(RoundedRectangle(cornerRadius: rayon).stroke(bord, lineWidth: largeurBord))
    }
}

/// Ligne à choisir (personne, piste) : 64 de haut, flèche ›, la ligne choisie en or.
struct LigneChoix: View {
    var titre: String
    var info: String = ""
    var choisie: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(titre).font(.system(size: 20, weight: .semibold)).foregroundStyle(Style.creme)
                if !info.isEmpty {
                    Text(info).font(.system(size: 13, weight: choisie ? .semibold : .regular))
                        .foregroundStyle(choisie ? Style.orPale : Style.cremeDiscret)
                }
            }
            Spacer()
            Text("›").font(.system(size: 26)).foregroundStyle(choisie ? Style.or : Style.fleche)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: 64)
        .background(choisie ? Style.or.opacity(0.16) : .white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(choisie ? Style.or : .white.opacity(0.10), lineWidth: choisie ? 2 : 1))
        .contentShape(Rectangle())
    }
}

/// En-tête des écrans secondaires : ‹ doré, titre en Barlow, sous-titre.
struct EnteteRetour: View {
    var titre: String
    var taille: CGFloat = 30
    var sousTitre: String = ""
    var retour: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: retour) {
                Text("‹").font(.system(size: 28)).foregroundStyle(Style.or).frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(titre).font(Style.titre(taille)).foregroundStyle(Style.creme)
                if !sousTitre.isEmpty { Text(sousTitre).font(.system(size: 12)).foregroundStyle(Style.cremeDiscret) }
            }
            Spacer()
        }
    }
}

/// Qui es-tu → quelle piste → Direct.
struct RacineView: View {
    @EnvironmentObject var liaison: Liaison

    var body: some View {
        ZStack {
            Style.fond
            Group {
                if liaison.nom.isEmpty {
                    QuiView()
                } else if liaison.piste.isEmpty {
                    ChoixPisteView()
                } else {
                    DirectView()
                }
            }
        }
        .foregroundStyle(Style.creme)
    }
}

/// Bandeau quand le Mac n'est pas joint.
struct EtatLienView: View {
    @EnvironmentObject var liaison: Liaison

    var body: some View {
        if !liaison.connecte {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView().tint(Style.creme)
                    Text(liaison.etat).font(.system(size: 13, weight: .semibold))
                }
                if liaison.macs.count > 1 {
                    ForEach(liaison.macs, id: \.self) { m in
                        Button { liaison.choisirMac(m) } label: {
                            Text(m).font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                if !liaison.enAttente.isEmpty {
                    Text("\(liaison.enAttente.count) message(s) partiront dès que le Mac sera retrouvé.")
                        .font(.system(size: 12)).foregroundStyle(Style.orangeTexte)
                }
                Text("Même wifi que le Mac du stand. La première fois, autorise « réseau local » quand l'iPhone le demande.")
                    .font(.system(size: 11)).foregroundStyle(Style.orangeTexte)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Style.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Style.orange, lineWidth: 1))
        }
    }
}
