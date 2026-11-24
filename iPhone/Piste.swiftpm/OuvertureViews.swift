import SwiftUI
import TriPhotoCommun

/// Étape 1 sur 2 : qui es-tu ?
struct QuiView: View {
    @EnvironmentObject var liaison: Liaison
    @State private var autre = ""
    @State private var saisir = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("HM TIMINGS · PISTE").font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(Style.cremeDiscret)
            Text("Qui es-tu ?").font(Style.titre(40))
            Text(liaison.accueil.map { "Connecté à Tri-photo · \($0.lieu.isEmpty ? $0.concours : $0.lieu)" } ?? liaison.etat)
                .font(.system(size: 13)).foregroundStyle(Style.cremeDiscret)
            EtatLienView()
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(liaison.accueil?.photographes ?? [], id: \.self) { p in
                        Button { liaison.nom = p } label: { ligne(p) }
                    }
                    if saisir {
                        HStack {
                            TextField("Ton prénom", text: $autre)
                                .textInputAutocapitalization(.words)
                                .font(.system(size: 18, weight: .semibold))
                                .onSubmit(valider)
                            Button("OK", action: valider).font(.system(size: 17, weight: .bold)).foregroundStyle(Style.or)
                        }
                        .padding(16)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    } else {
                        Button { saisir = true } label: {
                            Text("+ Quelqu'un d'autre").font(.system(size: 17, weight: .semibold)).foregroundStyle(Style.or)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Style.or.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [6])))
                        }
                    }
                }
            }
            Text("Étape 1 sur 2 · ensuite, ta piste").font(.system(size: 12)).foregroundStyle(Style.cremeDiscret)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 10)
    }

    private func ligne(_ t: String) -> some View {
        HStack {
            Text(t).font(.system(size: 19, weight: .semibold))
            Spacer()
            Text("›").font(.system(size: 24)).foregroundStyle(Style.cremeDiscret)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
    }

    private func valider() {
        let n = autre.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { liaison.nom = n }
    }
}

/// Étape 2 sur 2 : sur quelle piste ?
struct ChoixPisteView: View {
    @EnvironmentObject var liaison: Liaison
    var fermer: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                if let fermer { fermer() } else { liaison.nom = "" }
            } label: {
                Text("‹ \(liaison.nom)").font(.system(size: 16, weight: .semibold)).foregroundStyle(Style.or)
            }
            Text("Sur quelle piste ?").font(Style.titre(40))
            Text(liaison.accueil?.lieu ?? "").font(.system(size: 13)).foregroundStyle(Style.cremeDiscret)
            EtatLienView()
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(liaison.accueil?.pistes ?? []) { p in
                        Button {
                            liaison.piste = p.nom
                            fermer?()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(p.nom).font(.system(size: 20, weight: .semibold))
                                    if !p.info.isEmpty {
                                        Text(p.info).font(.system(size: 13)).foregroundStyle(Style.cremeDiscret)
                                    }
                                }
                                Spacer()
                                Text("›").font(.system(size: 24)).foregroundStyle(Style.cremeDiscret)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 68)
                            .background(liaison.piste == p.nom ? Style.or.opacity(0.18) : .white.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(liaison.piste == p.nom ? Style.or : .white.opacity(0.12), lineWidth: 1))
                        }
                    }
                }
            }
            Text("Étape 2 sur 2 · modifiable à tout moment").font(.system(size: 12)).foregroundStyle(Style.cremeDiscret)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 10)
    }
}
