import AppKit
import SwiftUI

/// Fenêtre du mode entraînement : choisir les photos d'un ancien concours et les rejouer.
struct EntrainementView: View {
    @ObservedObject var entrainement: Entrainement
    var dossierReception: String
    @Environment(\.dismiss) private var fermer

    enum Choix: String, CaseIterable, Identifiable {
        case concours = "Comme au concours"
        case cadence = "Cadence fixe"
        var id: String { rawValue }
    }

    @State private var choix: Choix = .cadence
    @State private var acceleration = 1.0
    @State private var parMinute = 100.0
    @State private var horloge = Date()
    private let minuterie = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mode entraînement").font(.system(size: 18, weight: .semibold))
                    Text("Les photos sont copiées dans le dossier de réception comme si les boîtiers les envoyaient. Les photos de départ ne sont pas touchées.")
                        .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                }
                Spacer()
                Button("Fermer") { fermer() }.buttonStyle(BoutonStyle()).keyboardShortcut(.cancelAction)
            }

            Carte(titre: "1. Photos à rejouer") {
                HStack {
                    Text(entrainement.dossierSource?.path ?? "Choisis le dossier d'un ancien concours (ex. le dossier de test de 1452 photos).")
                        .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choisir…") {
                        if let url = choisirDossier("Photos à rejouer") { entrainement.preparer(source: url) }
                    }
                    .buttonStyle(BoutonStyle())
                    .disabled(entrainement.enCours)
                }
            }

            Carte(titre: "2. Dossier de réception") {
                HStack {
                    Text(entrainement.dossierCible?.path ?? "Pas encore choisi")
                        .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if !dossierReception.isEmpty {
                        Button("Celui des réglages") { entrainement.dossierCible = URL(fileURLWithPath: dossierReception) }
                            .buttonStyle(BoutonStyle())
                    }
                    Button("Choisir…") {
                        if let url = choisirDossier("Dossier de réception") { entrainement.dossierCible = url }
                    }
                    .buttonStyle(BoutonStyle())
                }
                .disabled(entrainement.enCours)
            }

            Carte(titre: "3. Rythme") {
                Picker("", selection: $choix) {
                    ForEach(Choix.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 320)
                if choix == .cadence {
                    HStack {
                        Slider(value: $parMinute, in: 10...400, step: 10).frame(width: 300)
                        Text("\(Int(parMinute)) photos par minute").font(.system(size: 13))
                    }
                    Text("100 par minute = la pointe d'un concours à 4 ou 5 pistes.")
                        .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
                } else {
                    HStack {
                        Slider(value: $acceleration, in: 1...20, step: 1).frame(width: 300)
                        Text(acceleration == 1 ? "Temps réel" : "\(Int(acceleration)) fois plus vite").font(.system(size: 13))
                    }
                    Text("Respecte les écarts entre les heures de prise de vue (pauses de plus de 2 minutes raccourcies).")
                        .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
                }
            }
            .disabled(entrainement.enCours)

            Carte(titre: "Avancement") {
                ProgressView(value: Double(entrainement.envoyees), total: Double(max(entrainement.total, 1)))
                HStack {
                    Text("\(entrainement.envoyees) / \(entrainement.total) photos")
                    if entrainement.enCours {
                        Text("· \(Int(entrainement.cadenceReelle.rounded())) par minute").foregroundStyle(Theme.texteDiscret)
                            .id(horloge)
                    }
                    Spacer()
                    if entrainement.enCours {
                        Button("Pause") { entrainement.arreter() }.buttonStyle(BoutonStyle())
                    } else {
                        Button("Recommencer") { entrainement.recommencer() }
                            .buttonStyle(BoutonStyle())
                            .disabled(entrainement.envoyees == 0)
                        Button("Démarrer") {
                            entrainement.demarrer(rythme: choix == .cadence ? .cadence(parMinute: parMinute)
                                                                           : .commeAuConcours(acceleration: acceleration))
                        }
                        .buttonStyle(BoutonStyle(principal: true))
                        .disabled(entrainement.total == 0 || entrainement.dossierCible == nil
                                  || entrainement.envoyees >= entrainement.total)
                    }
                }
                .font(.system(size: 13))
                if !entrainement.message.isEmpty {
                    Text(entrainement.message).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                }
            }
        }
        .padding(24)
        .frame(width: 720)
        .background(Theme.fond)
        .foregroundStyle(Theme.texte)
        .onReceive(minuterie) { horloge = $0 }
    }

    private func choisirDossier(_ titre: String) -> URL? {
        let p = NSOpenPanel()
        p.title = titre
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        return p.runModal() == .OK ? p.url : nil
    }
}
