import SwiftUI
import TriPhotoCommun
import TriPhotoMoteur

/// Fenêtre principale : bandeau du concours et onglets en haut, puis l'écran choisi.
struct ContentView: View {
    @EnvironmentObject var etat: Etat

    var body: some View {
        VStack(spacing: 0) {
            if !etat.pleinEcran {
                Bandeau(moteur: etat.moteur, serveur: etat.serveur)
                BandeauUDMFenetre()
                Divider().overlay(Theme.bordure)
            }
            Group {
                switch etat.ecran {
                case .reglages: ReglagesView()
                case .accueil: AccueilView(moteur: etat.moteur)
                case .aValider: AValiderView(moteur: etat.moteur)
                case .revue: RevueView(moteur: etat.moteur)
                case .messages: MessagesView(serveur: etat.serveur)
                case .memoire: MemoireView(moteur: etat.moteur)
                case .commandes: CommandesView(archives: etat.archives)
                case .auBureau: AuBureauView(bureau: etat.bureau)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.fond)
        .foregroundStyle(Theme.texte)
        .frame(minWidth: 980, minHeight: 640)
        .sheet(isPresented: $etat.montrerSynchro) {
            SynchroView(moteur: etat.moteur)
        }
        .sheet(isPresented: $etat.montrerEntrainement) {
            EntrainementView(entrainement: etat.entrainement, dossierReception: etat.reglages.dossierReception)
        }
        .sheet(isPresented: $etat.montrerTerrain) {
            EngagesTerrainView(moteur: etat.moteur).environmentObject(etat)
        }
        .sheet(item: $etat.cloture) { g in
            ClotureView(moteur: etat.moteur, genre: g).environmentObject(etat)
        }
        .sheet(item: $etat.nouveauConcours) { d in
            NouveauConcoursView(demande: d).environmentObject(etat)
        }
        // Visite guidée (bouton « ? ») : voile troué sur la zone expliquée + bulle.
        .overlayPreferenceValue(RepereCle.self) { r in CalqueVisite(reperes: r) }
        .onAppear { Visite.etat = etat }
    }
}

/// Bandeau du haut : nom du concours, état, onglets, bouton de clôture.
struct Bandeau: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var moteur: Moteur
    @ObservedObject var serveur: ServeurPiste

    private func badge(_ e: Ecran) -> (Int, Color)? {
        switch e {
        case .aValider:
            let n = moteur.resume.series.filter { $0.genre != .rush }.count
            return n == 0 ? nil : (n, Theme.orange)
        case .messages:
            let n = serveur.nonLus.values.reduce(0, +)
            return n == 0 ? nil : (n, Theme.accent)
        default: return nil
        }
    }

    private var sousTitre: String {
        var morceaux: [String] = [Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR")))]
        morceaux.append(etat.texteChronos)
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
                // une ligne chacun, coupés au milieu si la fenêtre est étroite (essai du 26/11 : titre sur 4 lignes)
                Text(etat.reglages.nomConcours.isEmpty ? "Nouveau concours" : etat.reglages.nomConcours)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Text(sousTitre).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                    .lineLimit(1).truncationMode(.tail)
            }
            .help("\(etat.reglages.nomConcours)\n\(sousTitre)")
            .layoutPriority(0)
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                ForEach(Ecran.allCases) { e in
                    Button { etat.ecran = e } label: {
                        HStack(spacing: 5) {
                            Text(e.rawValue).lineLimit(1).fixedSize()
                            if let (n, couleur) = badge(e) {
                                Text("\(n)")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(couleur, in: Capsule())
                                    .foregroundStyle(Color.black)
                            }
                        }
                            .font(.system(size: 13, weight: etat.ecran == e ? .semibold : .regular))
                            .foregroundStyle(etat.ecran == e ? Theme.texte : Theme.texteDiscret)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(etat.ecran == e ? Theme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(BoutonPlat())
                    .repere("onglet." + e.rawValue)
                }
            }
            .repere("bandeau.onglets")
            .fixedSize()            // les onglets ne se coupent jamais lettre par lettre : le titre à gauche cède la place
            .layoutPriority(1)
            Spacer(minLength: 8)
            if moteur.actif {
                let enPause = moteur.resume.enPause
                Button {
                    moteur.mettreEnPause(!enPause)
                } label: {
                    Label(enPause ? "Reprendre" : "Pause", systemImage: enPause ? "play.fill" : "pause.fill")
                        .font(.system(size: 12, weight: enPause ? .semibold : .regular))
                        .foregroundStyle(enPause ? Color.black : Theme.texte)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(enPause ? Theme.orange : Theme.bordure, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(BoutonPlat())
                .help(enPause ? "Tout repart : serveur, Lightroom, galerie en ligne."
                              : "Plus rien ne part (serveur, Lightroom, galerie en ligne). Les photos attendent dans la réception.")
                .repere("bandeau.pause")
            }
            Menu {
                Button(GenreCloture.journee.rawValue + "…") { etat.cloture = .journee }
                Button(GenreCloture.finale.rawValue + "…") { etat.cloture = .finale }
                Divider()
                Button("Engagés terrain…") { etat.montrerTerrain = true }
            } label: {
                Text("Clôturer").font(.system(size: 12))
            } primaryAction: {
                etat.cloture = .journee
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.bordure, in: RoundedRectangle(cornerRadius: 5))
            .help("Clic : clôturer la journée. Flèche : clôturer le concours, engagés terrain.")
            .repere("bandeau.cloturer")
            BoutonAide().repere("bandeau.aide")
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
