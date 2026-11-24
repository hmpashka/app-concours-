import SwiftUI
import TriPhotoCommun

@main
struct PisteApp: App {
    @StateObject private var liaison = Liaison()
    @Environment(\.scenePhase) private var phase

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

/// Couleurs de l'app Piste (maquettes) : bleu nuit, crème, or.
enum Style {
    static let nuit = Color(red: 0x0e / 255, green: 0x2a / 255, blue: 0x47 / 255)
    static let nuitFonce = Color(red: 0x08 / 255, green: 0x1a / 255, blue: 0x2e / 255)
    static let nuitClair = Color(red: 0x15 / 255, green: 0x36 / 255, blue: 0x5c / 255)
    static let creme = Color(red: 0xf5 / 255, green: 0xf1 / 255, blue: 0xe8 / 255)
    static let cremeDiscret = Color(red: 0xc9 / 255, green: 0xc3 / 255, blue: 0xb6 / 255)
    static let or = Color(red: 0xc9 / 255, green: 0xa3 / 255, blue: 0x4a / 255)
    static let orange = Color(red: 0xe8 / 255, green: 0x91 / 255, blue: 0x3a / 255)
    static let orangeClair = Color(red: 0xf7 / 255, green: 0xc7 / 255, blue: 0x8f / 255)
    static let rouge = Color(red: 0xb8 / 255, green: 0x32 / 255, blue: 0x2a / 255)
    static let vert = Color(red: 0x8f / 255, green: 0xd1 / 255, blue: 0x9e / 255)

    static var fond: some View {
        RadialGradient(colors: [nuitClair, nuit, nuitFonce], center: UnitPoint(x: 0.62, y: 0.3), startRadius: 0, endRadius: 700)
            .ignoresSafeArea()
    }

    static func titre(_ taille: CGFloat) -> Font { .system(size: taille, weight: .bold).italic().width(.condensed) }
}

/// Carte translucide des maquettes.
struct Bloc<Contenu: View>: View {
    var bord: Color = .white.opacity(0.10)
    var fond: Color = .white.opacity(0.06)
    var rayon: CGFloat = 14
    @ViewBuilder var contenu: () -> Contenu

    var body: some View {
        contenu()
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fond, in: RoundedRectangle(cornerRadius: rayon))
            .overlay(RoundedRectangle(cornerRadius: rayon).stroke(bord, lineWidth: 1))
    }
}

/// Qui es-tu → quelle piste → Direct. Tant que le Mac n'est pas trouvé : écran de recherche.
struct RacineView: View {
    @EnvironmentObject var liaison: Liaison

    var body: some View {
        ZStack {
            Style.fond
            NavigationStack {
                Group {
                    if liaison.nom.isEmpty {
                        QuiView()
                    } else if liaison.piste.isEmpty {
                        ChoixPisteView()
                    } else {
                        DirectView()
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            .foregroundStyle(Style.creme)
        }
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
                        .font(.system(size: 12)).foregroundStyle(Style.cremeDiscret)
                }
                Text("Même wifi que le Mac du stand. La première fois, autorise « réseau local » quand l'iPhone le demande.")
                    .font(.system(size: 11)).foregroundStyle(Style.cremeDiscret)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Style.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Style.orange, lineWidth: 1))
        }
    }
}
