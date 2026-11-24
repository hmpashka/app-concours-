import SwiftUI
import TriPhotoCommun

/// Onglet « Messages » (maquette) : les conversations avec les iPhone des pistes, les incidents, les iPhone connectés.
struct MessagesView: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var serveur: ServeurPiste
    @State private var conv = ""            // « » : toutes les pistes
    @State private var texte = ""

    var body: some View {
        HStack(spacing: 0) {
            if etat.panneauGauche {
                conversations.frame(width: 260).background(Theme.panneau)
                Divider().overlay(Theme.bordure)
            }
            fil.frame(maxWidth: .infinity, maxHeight: .infinity)
            if etat.panneauDroit {
                Divider().overlay(Theme.bordure)
                iphones.frame(width: 280).background(Theme.panneau)
            }
        }
        .onAppear { serveur.lu(conv) }
        .onChange(of: conv) { c in serveur.lu(c) }
        .onChange(of: serveur.messages.count) { _ in serveur.lu(conv) }
    }

    // MARK: - Conversations

    private var conversations: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Conversations").font(.system(size: 14, weight: .semibold)).padding(.bottom, 6)
            ligne("", titre: "Toutes les pistes",
                  detail: serveur.connectes.map(\.nom).filter { !$0.isEmpty }.joined(separator: ", ").ifEmpty("personne en ligne"))
            ForEach(serveur.conversations, id: \.self) { nom in
                ligne(nom, titre: nom, detail: serveur.messages(de: nom).last?.texte ?? "")
            }
            Spacer()
        }
        .padding(14)
    }

    private func ligne(_ c: String, titre: String, detail: String) -> some View {
        Button { conv = c } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titre).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(Theme.texteDiscret).lineLimit(1)
                }
                Spacer()
                if let n = serveur.nonLus[c], n > 0 {
                    Text("\(n)").font(.system(size: 10, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Theme.accent, in: Capsule()).foregroundStyle(Color.black)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(conv == c ? Theme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fil

    private var fil: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(conv.isEmpty ? "Toutes les pistes" : conv).font(.system(size: 15, weight: .semibold))
            ScrollViewReader { lecteur in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(serveur.messages(de: conv)) { m in bulle(m).id(m.id) }
                    }
                    .padding(.vertical, 4)
                }
                .onAppear { lecteur.scrollTo(serveur.messages(de: conv).last?.id, anchor: .bottom) }
                .onChange(of: serveur.messages.count) { _ in
                    withAnimation { lecteur.scrollTo(serveur.messages(de: conv).last?.id, anchor: .bottom) }
                }
            }
            HStack {
                Text("À : \(conv.isEmpty ? "toutes les pistes" : conv)").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                TextField("Message", text: $texte).textFieldStyle(.roundedBorder).onSubmit(envoyer)
                Button("Envoyer", action: envoyer).buttonStyle(BoutonStyle(principal: true))
                    .disabled(texte.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 6) {
                ForEach(["Bien reçu", "J'arrive", "Change ton code", "Renvoie tes photos"], id: \.self) { r in
                    Button(r) { serveur.envoyerDuStand(r, pour: conv) }.buttonStyle(BoutonStyle())
                }
            }
        }
        .padding(20)
    }

    private func bulle(_ m: MessagePiste) -> some View {
        let stand = m.qui == "Stand"
        return HStack {
            if stand { Spacer(minLength: 80) }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(m.qui)\(m.piste.isEmpty ? "" : " · \(m.piste)") · \(Date(timeIntervalSince1970: m.heure).formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
                Text(m.texte).font(.system(size: 13, weight: m.incident ? .semibold : .regular))
                    .foregroundStyle(m.incident ? Theme.attention : Theme.texte)
                    .textSelection(.enabled)
                if m.incident {
                    Button("Voir les photos de ce moment") {
                        etat.voirMoment(Date(timeIntervalSince1970: m.heure), titre: "Incident · \(m.qui)\(m.piste.isEmpty ? "" : " · \(m.piste)")")
                    }
                    .buttonStyle(BoutonStyle())
                }
            }
            .padding(10)
            .background(stand ? Theme.selection : (m.incident ? Theme.attentionFond : Theme.carte), in: RoundedRectangle(cornerRadius: 8))
            if !stand { Spacer(minLength: 80) }
        }
    }

    private func envoyer() {
        serveur.envoyerDuStand(texte, pour: conv)
        texte = ""
    }

    // MARK: - iPhone connectés

    private var iphones: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iPhone des pistes").font(.system(size: 14, weight: .semibold))
            HStack(spacing: 6) {
                Circle().fill(serveur.enLigne ? Theme.ok : Theme.erreur).frame(width: 8, height: 8)
                Text(serveur.etat).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
            }
            if serveur.connectes.isEmpty {
                Text("Aucun iPhone connecté. Sur l'iPhone, ouvre l'app Piste sur le même wifi que ce Mac : il le trouve tout seul.")
                    .font(.system(size: 12)).foregroundStyle(Theme.texteTresDiscret)
            }
            ForEach(serveur.connectes) { c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.nom.isEmpty ? "iPhone (pas encore choisi)" : c.nom).font(.system(size: 13, weight: .semibold))
                    Text([c.piste.isEmpty ? "piste pas choisie" : c.piste, c.appareil,
                          "depuis \(c.depuis.formatted(date: .omitted, time: .shortened))"].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.carte, in: RoundedRectangle(cornerRadius: 6))
            }
            Divider().overlay(Theme.bordure)
            Text("Notifications du Mac").font(.system(size: 13, weight: .semibold))
            Text("Une notification pour chaque message ou incident, sauf quand cet onglet est ouvert. Un clic dessus ouvre Tri-photo ici.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            Spacer()
        }
        .padding(14)
    }
}

private extension String {
    func ifEmpty(_ autre: String) -> String { isEmpty ? autre : self }
}
