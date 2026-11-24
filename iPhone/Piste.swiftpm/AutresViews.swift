import SwiftUI
import TriPhotoCommun

/// Maquette « Piste, photos à renvoyer » : la liste se vide toute seule quand le Mac reçoit la photo.
struct RenvoyerView: View {
    @EnvironmentObject var liaison: Liaison
    @Environment(\.dismiss) private var fermer

    var body: some View {
        ZStack {
            Style.fond
            VStack(alignment: .leading, spacing: 14) {
                Button { fermer() } label: { Text("‹ Retour").font(.system(size: 16, weight: .semibold)).foregroundStyle(Style.or) }
                Text("Photos à renvoyer").font(Style.titre(34))
                (Text("Ces photos ne sont pas bien arrivées sur le Mac. Renvoie-les depuis le boîtier, avec leur ")
                    + Text("nom d'origine").bold() + Text("."))
                    .font(.system(size: 14)).foregroundStyle(Style.cremeDiscret)
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(liaison.direct?.aRenvoyer ?? []) { p in
                            Bloc(bord: Style.orange, fond: Style.orange.opacity(0.14)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.nom).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                                        Text(p.detail).font(.system(size: 12)).foregroundStyle(Style.cremeDiscret)
                                    }
                                    Spacer()
                                    Text(Date(timeIntervalSince1970: p.heure).formatted(date: .omitted, time: .shortened))
                                        .font(.system(size: 13)).foregroundStyle(Style.cremeDiscret)
                                }
                            }
                        }
                        ForEach(liaison.direct?.bienArrivees ?? [], id: \.self) { n in
                            Bloc {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(n) est bien arrivée").font(.system(size: 15, weight: .semibold)).foregroundStyle(Style.vert)
                                    Text("Retirée de la liste toute seule").font(.system(size: 12)).foregroundStyle(Style.cremeDiscret)
                                }
                            }
                        }
                        if (liaison.direct?.aRenvoyer ?? []).isEmpty {
                            Text("Rien à renvoyer.").font(.system(size: 15)).foregroundStyle(Style.cremeDiscret).padding(.top, 20)
                        }
                    }
                }
                Text("La liste se vide toute seule dès que le Mac reçoit la photo.")
                    .font(.system(size: 12)).foregroundStyle(Style.cremeDiscret).frame(maxWidth: .infinity)
            }
            .padding(18)
        }
        .foregroundStyle(Style.creme)
        .preferredColorScheme(.dark)
    }
}

/// Maquette « Piste, messages » : le stand (Mac) et toutes les pistes.
struct MessagesPisteView: View {
    @EnvironmentObject var liaison: Liaison
    @Environment(\.dismiss) private var fermer
    @State private var texte = ""
    private let rapides = ["Bien reçu", "J'arrive", "Batterie faible", "Carte pleine", "Pause"]

    var body: some View {
        ZStack {
            Style.fond
            VStack(alignment: .leading, spacing: 12) {
                Button { fermer() } label: { Text("‹ Retour").font(.system(size: 16, weight: .semibold)).foregroundStyle(Style.or) }
                Text("Messages").font(Style.titre(34))
                Text("Stand (Mac) et toutes les pistes").font(.system(size: 13)).foregroundStyle(Style.cremeDiscret)
                ScrollViewReader { lecteur in
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(liaison.messages) { m in bulle(m).id(m.id) }
                        }
                    }
                    .onAppear { lecteur.scrollTo(liaison.messages.last?.id, anchor: .bottom) }
                    .onChange(of: liaison.messages.count) { _ in
                        withAnimation { lecteur.scrollTo(liaison.messages.last?.id, anchor: .bottom) }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(rapides, id: \.self) { r in
                            Button(r) { liaison.envoyer(message: r) }
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(.white.opacity(0.10), in: Capsule())
                        }
                    }
                }
                HStack {
                    TextField("Message", text: $texte, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(12)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    Button {
                        liaison.envoyer(message: texte)
                        texte = ""
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)).foregroundStyle(Style.or)
                    }
                    .disabled(texte.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(18)
        }
        .foregroundStyle(Style.creme)
        .preferredColorScheme(.dark)
        .onAppear { liaison.luJusqua = Date().timeIntervalSince1970 }
        .onChange(of: liaison.messages.count) { _ in liaison.luJusqua = Date().timeIntervalSince1970 }
    }

    private func bulle(_ m: MessagePiste) -> some View {
        let moi = m.qui == liaison.nom
        return HStack {
            if moi { Spacer(minLength: 50) }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(m.qui)\(m.pour.isEmpty ? "" : " → \(m.pour == liaison.nom ? "toi" : m.pour)") · \(Date(timeIntervalSince1970: m.heure).formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(Style.cremeDiscret)
                Text(m.texte).font(.system(size: 15, weight: m.incident ? .semibold : .regular))
                    .foregroundStyle(m.incident ? Style.orangeClair : Style.creme)
            }
            .padding(10)
            .background(moi ? Style.or.opacity(0.22) : (m.qui == "Stand" ? Style.nuitClair : .white.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: 12))
            if !moi { Spacer(minLength: 50) }
        }
    }
}
