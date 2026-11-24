import SwiftUI
import TriPhotoCommun
import TriPhotoMoteur

/// Engagés terrain : les couples qui ne sont pas dans le fichier FFE. Le chrono en ajoute tout seul ; HUGO peut en
/// ajouter à la main (épreuve, dossard, nom, prénom, cheval), les corriger ou les retirer. Ils vont dans les
/// mots-clés des photos et dans le fichier d'attribution de fin.
struct EngagesTerrainView: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var moteur: Moteur
    @Environment(\.dismiss) private var fermer

    @State private var enCorrection: UUID?
    @State private var epreuve = ""
    @State private var dossard = ""
    @State private var nom = ""
    @State private var prenom = ""
    @State private var cheval = ""
    @State private var message = ""

    private var epreuves: [Epreuve] { etat.concours?.epreuves ?? [] }

    private var liste: [EngageTerrain] {
        etat.engagesTerrain.sorted { ($0.epreuve.count, $0.epreuve, $0.dossard.count, $0.dossard) < ($1.epreuve.count, $1.epreuve, $1.dossard.count, $1.dossard) }
    }

    private var valide: Bool {
        !epreuve.trimmingCharacters(in: .whitespaces).isEmpty && !dossard.trimmingCharacters(in: .whitespaces).isEmpty
            && !(nom + prenom).trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Engagés terrain").font(.system(size: 16, weight: .semibold))
                    Text("Couples absents du fichier FFE. Le chrono en ajoute tout seul ; tu peux en ajouter à la main.")
                        .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                }
                Spacer()
                Button("Fermer") { fermer() }.buttonStyle(BoutonStyle()).keyboardShortcut(.cancelAction)
            }

            Carte(titre: enCorrection == nil ? "Ajouter un couple" : "Corriger le couple") {
                HStack(spacing: 8) {
                    if epreuves.isEmpty {
                        TextField("N° épreuve", text: $epreuve).textFieldStyle(.roundedBorder).frame(width: 90)
                    } else {
                        Picker("", selection: $epreuve) {
                            Text("Épreuve…").tag("")
                            ForEach(epreuves) { e in Text("\(e.numero) · \(e.nom)").tag(e.numero) }
                        }
                        .labelsHidden().frame(width: 230)
                    }
                    TextField("Dossard", text: $dossard).textFieldStyle(.roundedBorder).frame(width: 70)
                    TextField("Nom", text: $nom).textFieldStyle(.roundedBorder)
                    TextField("Prénom", text: $prenom).textFieldStyle(.roundedBorder)
                    TextField("Cheval", text: $cheval).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Button(enCorrection == nil ? "Ajouter" : "Enregistrer", action: enregistrer)
                        .buttonStyle(BoutonStyle(principal: true)).disabled(!valide)
                        .keyboardShortcut(.defaultAction)
                    if enCorrection != nil {
                        Button("Annuler la correction") { vider() }.buttonStyle(BoutonStyle())
                    }
                    if !message.isEmpty {
                        Text(message).font(.system(size: 12)).foregroundStyle(message.hasPrefix("Déjà") ? Theme.attention : Theme.ok)
                    }
                }
            }

            Table(liste) {
                TableColumn("Épreuve") { e in Text(e.epreuve) }.width(60)
                TableColumn("Dossard") { e in Text(e.dossard) }.width(60)
                TableColumn("Nom") { e in Text(e.nom) }
                TableColumn("Prénom") { e in Text(e.prenom) }
                TableColumn("Cheval") { e in Text(e.cheval) }
                TableColumn("Ajouté par") { e in
                    Text(e.source == .chrono ? "Chrono" : "À la main").foregroundStyle(Theme.texteDiscret)
                }.width(80)
                TableColumn("") { e in
                    HStack(spacing: 6) {
                        Button("Corriger") { corriger(e) }.buttonStyle(BoutonStyle())
                        Button("Retirer") { etat.retirerEngageTerrain(e) }.buttonStyle(BoutonStyle())
                    }
                }.width(150)
            }
            Text("\(liste.count) engagé\(liste.count > 1 ? "s" : "") terrain. Retirer se rattrape : il suffit de rajouter le couple.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 520)
        .background(Theme.fond)
        .preferredColorScheme(.dark)
    }

    private func enregistrer() {
        let ep = epreuve.trimmingCharacters(in: .whitespaces)
        let d = dossard.trimmingCharacters(in: .whitespaces)
        // Dossard déjà dans le fichier FFE ou déjà ajouté (autre que celui qu'on corrige).
        if etat.concours?.epreuve(numero: ep)?.engages.contains(where: { !$0.terrain && CodePassage.cle($0.dossard) == CodePassage.cle(d) }) == true {
            message = "Déjà dans le fichier FFE : n° \(d) de l'épreuve \(ep)."
            return
        }
        if etat.engagesTerrain.contains(where: { $0.id != enCorrection && CodePassage.cle($0.epreuve) == CodePassage.cle(ep)
            && CodePassage.cle($0.dossard) == CodePassage.cle(d) }) {
            message = "Déjà ajouté : n° \(d) de l'épreuve \(ep)."
            return
        }
        var e = EngageTerrain(epreuve: ep, dossard: d, nom: nom.trimmingCharacters(in: .whitespaces).uppercased(),
                              prenom: FichierEngages.prenomPropre(prenom.trimmingCharacters(in: .whitespaces)),
                              cheval: cheval.trimmingCharacters(in: .whitespaces).uppercased(), source: .main)
        if let id = enCorrection { e.id = id }
        etat.enregistrerEngageTerrain(e)
        message = "\(e.cavalier) · \(e.cheval) : enregistré (épreuve \(ep), n° \(d))."
        let garde = epreuve
        vider()
        epreuve = garde       // souvent plusieurs couples de suite dans la même épreuve
    }

    private func corriger(_ e: EngageTerrain) {
        enCorrection = e.id
        epreuve = epreuves.first { $0.cle == CodePassage.cle(e.epreuve) }?.numero ?? e.epreuve
        dossard = e.dossard
        nom = e.nom
        prenom = e.prenom
        cheval = e.cheval
        message = ""
    }

    private func vider() {
        enCorrection = nil
        dossard = ""
        nom = ""
        prenom = ""
        cheval = ""
    }
}
