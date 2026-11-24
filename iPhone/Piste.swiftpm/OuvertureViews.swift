import SwiftUI
import TriPhotoCommun

/// Maquette « Piste, qui es-tu » : étape 1 sur 2.
struct QuiView: View {
    @EnvironmentObject var liaison: Liaison
    @State private var autre = ""
    @State private var saisir = false

    private var lieu: String {
        guard let a = liaison.accueil else { return "" }
        return a.lieu.isEmpty ? a.concours : a.lieu
    }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("HM TIMINGS · PISTE").font(Style.titre(18)).tracking(1.4).foregroundStyle(Style.or)
                Text("Qui es-tu ?").font(Style.titre(40)).foregroundStyle(Style.creme)
                Text(liaison.connecte ? "Connecté à Groom Pix\(lieu.isEmpty ? "" : " · \(lieu)")" : liaison.etat)
                    .font(.system(size: 14)).foregroundStyle(Style.cremeDiscret).multilineTextAlignment(.center)
            }
            .padding(.top, 12)
            EtatLienView()
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(liaison.accueil?.photographes ?? [], id: \.self) { p in
                        Button { liaison.nom = p } label: { LigneChoix(titre: p, choisie: false) }
                            .buttonStyle(.plain)
                    }
                    if saisir {
                        HStack {
                            TextField("Ton prénom", text: $autre)
                                .textInputAutocapitalization(.words)
                                .font(.system(size: 20, weight: .semibold))
                                .onSubmit(valider)
                            Button("OK", action: valider).font(.system(size: 17, weight: .bold)).foregroundStyle(Style.or)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 64)
                        .background(Style.or.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Style.or, lineWidth: 2))
                    } else {
                        Button { saisir = true } label: {
                            Text("+ Quelqu'un d'autre").font(.system(size: 15)).foregroundStyle(Style.cremeDiscret)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .overlay(RoundedRectangle(cornerRadius: 14)
                                    .stroke(Style.voile.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("Étape 1 sur 2 · ensuite, ta piste").font(.system(size: 13)).foregroundStyle(Style.cremeDiscret)
        }
        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 10)
    }

    private func valider() {
        let n = autre.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { liaison.nom = n }
    }
}

/// Maquette « Piste, sur quelle piste » : étape 2 sur 2.
struct ChoixPisteView: View {
    @EnvironmentObject var liaison: Liaison
    var fermer: (() -> Void)?

    /// La piste où le stand attend cette personne (réglages du Mac), sinon celle déjà choisie.
    private func proposee(_ p: AccueilPiste.Piste) -> Bool {
        if !liaison.piste.isEmpty { return liaison.piste == p.nom }
        return p.info.contains("prévue pour \(liaison.nom)")
    }

    var body: some View {
        VStack(spacing: 20) {
            Button {
                if let fermer { fermer() } else { liaison.nom = "" }
            } label: {
                Text("‹ \(liaison.nom)").font(.system(size: 15)).foregroundStyle(Style.or).frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 6) {
                Text("Sur quelle piste ?").font(Style.titre(40)).foregroundStyle(Style.creme)
                if let lieu = liaison.accueil?.lieu, !lieu.isEmpty {
                    Text(lieu).font(.system(size: 14)).foregroundStyle(Style.cremeDiscret)
                }
            }
            EtatLienView()
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(liaison.accueil?.pistes ?? []) { p in
                        Button {
                            liaison.piste = p.nom
                            fermer?()
                        } label: {
                            LigneChoix(titre: p.nom, info: p.info.replacingOccurrences(of: "prévue pour \(liaison.nom)", with: "proposée par le stand"),
                                       choisie: proposee(p))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("Étape 2 sur 2 · modifiable à tout moment").font(.system(size: 13)).foregroundStyle(Style.cremeDiscret)
        }
        .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 10)
    }
}
