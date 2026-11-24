import SwiftUI
import TriPhotoCommun

/// Écran de la capture Horse & Comp : l'adresse de la page d'incrustation, la page elle-même pour dessiner les
/// zones à lire, ce qui est lu en direct et les passages trouvés.
struct CaptureView: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var capture: CaptureHorseComp
    @Environment(\.dismiss) private var fermer
    @State private var zone = "dossard"
    @State private var debutTrace: CGPoint?
    @State private var trace: CGRect?
    private let minuterie = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private let noms = ["dossard": "Dossard", "nom": "Cavalier / cheval", "epreuve": "Épreuve", "temps": "Temps", "points": "Points"]
    private let couleurs: [String: Color] = ["dossard": .yellow, "nom": .green, "epreuve": .blue, "temps": .orange, "points": .pink]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Capture Horse & Comp").font(.system(size: 16, weight: .semibold))
                Text(capture.etatPage).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                Spacer()
                Button("Fermer") { fermer() }.buttonStyle(BoutonStyle()).keyboardShortcut(.cancelAction)
            }
            HStack {
                TextField("Adresse de la page d'incrustation (https://…)", text: $etat.reglages.urlIncrustation)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { capture.ouvrir(etat.reglages.urlIncrustation) }
                Button(capture.ouverte ? "Recharger" : "Ouvrir la page") { capture.ouvrir(etat.reglages.urlIncrustation) }
                    .buttonStyle(BoutonStyle(principal: true))
                if capture.ouverte {
                    Button("Arrêter") { capture.fermer() }.buttonStyle(BoutonStyle())
                }
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Zone à dessiner :").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                        Picker("", selection: $zone) {
                            ForEach(SuiviIncrustation.zonesConnues, id: \.self) { Text(noms[$0] ?? $0).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        Button("Effacer") { etat.reglages.zonesIncrustation[zone] = nil }.buttonStyle(BoutonStyle())
                    }
                    page
                    Text("Glisse sur la page pour entourer la zone choisie. Dossard et nom suffisent ; l'épreuve évite de la choisir à la main.")
                        .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
                }
                .frame(width: 640)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Lu en direct").font(.system(size: 13, weight: .semibold))
                    ForEach(SuiviIncrustation.zonesConnues, id: \.self) { k in
                        HStack(alignment: .top) {
                            Circle().fill(couleurs[k] ?? .gray).frame(width: 8, height: 8).padding(.top, 4)
                            Text(noms[k] ?? k).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret).frame(width: 110, alignment: .leading)
                            Text(capture.lu[k].map { $0.isEmpty ? "—" : $0 } ?? (etat.reglages.zonesIncrustation[k] == nil ? "zone pas dessinée" : "—"))
                                .font(.system(size: 12, design: .monospaced)).lineLimit(2)
                        }
                    }
                    if !capture.raison.isEmpty {
                        Text(capture.raison).font(.system(size: 12)).foregroundStyle(Theme.attention)
                    }
                    Divider().overlay(Theme.bordure)
                    HStack {
                        Text("Épreuve").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                        Picker("", selection: $etat.reglages.epreuveForcee) {
                            Text("Lue sur la page").tag("")
                            ForEach(etat.concours?.epreuves ?? []) { e in Text(e.nomDossier).tag(e.numero) }
                        }
                        .labelsHidden()
                    }
                    Divider().overlay(Theme.bordure)
                    HStack {
                        Text("Passages trouvés (\(capture.passages.count))").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button("Effacer") { capture.effacerPassages() }.buttonStyle(BoutonStyle())
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(capture.passages.reversed().prefix(40).enumerated()), id: \.offset) { _, p in
                                HStack {
                                    Text(AValiderView.heures(p)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.texteDiscret)
                                    Text(p.code.texte).font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    Text(p.cavalier).font(.system(size: 11)).foregroundStyle(Theme.texteDiscret).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 1080, height: 640)
        .background(Theme.fond)
        .foregroundStyle(Theme.texte)
        .preferredColorScheme(.dark)
        .onAppear { capture.rafraichirApercu() }
        .onReceive(minuterie) { _ in capture.rafraichirApercu() }
    }

    /// La page (image rafraîchie toutes les 2 s) avec les zones dessinées par-dessus.
    private var page: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Theme.carte)
                if let im = capture.apercu {
                    Image(nsImage: im).resizable().frame(width: geo.size.width, height: geo.size.height)
                } else {
                    Text(capture.ouverte ? "Chargement…" : "Ouvre la page pour la voir ici.")
                        .foregroundStyle(Theme.texteDiscret)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                ForEach(Array(etat.reglages.zonesIncrustation.keys.sorted()), id: \.self) { k in
                    if let z = etat.reglages.zonesIncrustation[k], z.count == 4 {
                        Rectangle()
                            .stroke(couleurs[k] ?? .gray, lineWidth: 2)
                            .frame(width: z[2] * geo.size.width, height: z[3] * geo.size.height)
                            .offset(x: z[0] * geo.size.width, y: z[1] * geo.size.height)
                    }
                }
                if let t = trace {
                    Rectangle().stroke(couleurs[zone] ?? .gray, style: StrokeStyle(lineWidth: 2, dash: [5]))
                        .frame(width: t.width, height: t.height)
                        .offset(x: t.minX, y: t.minY)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3)
                .onChanged { v in
                    let a = v.startLocation, b = v.location
                    trace = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                }
                .onEnded { _ in
                    if let t = trace, t.width > 4, t.height > 4 {
                        let W = geo.size.width, H = geo.size.height
                        etat.reglages.zonesIncrustation[zone] = [t.minX / W, t.minY / H, t.width / W, t.height / H].map {
                            (min(max(Double($0), 0), 1) * 1000).rounded() / 1000
                        }
                    }
                    trace = nil
                })
        }
        .aspectRatio(CaptureHorseComp.largeur / CaptureHorseComp.hauteur, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
