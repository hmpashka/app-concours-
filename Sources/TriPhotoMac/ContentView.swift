import SwiftUI
import TriPhotoCommun

/// Fenêtre principale : bandeau du concours et onglets en haut, puis l'écran choisi.
struct ContentView: View {
    @EnvironmentObject var etat: Etat

    var body: some View {
        VStack(spacing: 0) {
            Bandeau()
            Divider().overlay(Theme.bordure)
            Group {
                switch etat.ecran {
                case .reglages: ReglagesView()
                case .accueil: AccueilView(moteur: etat.moteur)
                case .aValider: BientotView(titre: "À valider", etape: 2,
                                            texte: "Corrections de code proposées d'après le chrono, par série, avec vignettes avant / après.")
                case .revue: BientotView(titre: "Revue", etape: 2,
                                         texte: "Revue rapide, une photo à la fois : bonne, floue, sol, code.")
                case .memoire: BientotView(titre: "Mémoire", etape: 5,
                                           texte: "Exemples par catégorie, partagés entre les stands par iCloud.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.fond)
        .foregroundStyle(Theme.texte)
        .preferredColorScheme(.dark)
        .frame(minWidth: 980, minHeight: 640)
        .sheet(isPresented: $etat.montrerEntrainement) {
            EntrainementView(entrainement: etat.entrainement, dossierReception: etat.reglages.dossierReception)
        }
    }
}

/// Bandeau du haut : nom du concours, état, onglets, bouton de clôture.
struct Bandeau: View {
    @EnvironmentObject var etat: Etat

    private var sousTitre: String {
        var morceaux: [String] = [Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR")))]
        morceaux.append(etat.reglages.chronometrage.rawValue)
        if let c = etat.concours {
            morceaux.append("Fichier FFE chargé (\(c.nombreEngages) engagés)")
        } else {
            morceaux.append("Fichier FFE à charger")
        }
        return morceaux.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text(etat.reglages.nomConcours.isEmpty ? "Nouveau concours" : etat.reglages.nomConcours)
                    .font(.system(size: 15, weight: .semibold))
                Text(sousTitre).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
            }
            Spacer()
            HStack(spacing: 4) {
                ForEach(Ecran.allCases) { e in
                    Button { etat.ecran = e } label: {
                        Text(e.rawValue)
                            .font(.system(size: 13, weight: etat.ecran == e ? .semibold : .regular))
                            .foregroundStyle(etat.ecran == e ? Color.white : Theme.texteDiscret)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(etat.ecran == e ? Theme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            Button("Clôturer la journée") {}
                .buttonStyle(BoutonStyle())
                .disabled(true)
                .help("Arrive à l'étape 4")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.panneau)
    }
}

/// Écran pas encore construit : dit à quelle étape il arrive.
struct BientotView: View {
    var titre: String
    var etape: Int
    var texte: String

    var body: some View {
        VStack(spacing: 10) {
            Text(titre).font(.system(size: 20, weight: .semibold))
            Text("Arrive à l'étape \(etape) du plan.").foregroundStyle(Theme.accent)
            Text(texte).font(.system(size: 13)).foregroundStyle(Theme.texteDiscret)
                .multilineTextAlignment(.center).frame(maxWidth: 460)
        }
        .padding(40)
    }
}
