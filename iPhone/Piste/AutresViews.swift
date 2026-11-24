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
                EnteteRetour(titre: "Photos à renvoyer", taille: 30) { fermer() }
                (Text("Ces photos ne sont pas bien arrivées sur le Mac. Renvoie-les depuis le boîtier, avec leur ")
                    + Text("nom d’origine").foregroundColor(Style.creme).fontWeight(.semibold) + Text("."))
                    .font(.system(size: 14)).foregroundColor(Style.cremeDiscret).lineSpacing(3).padding(.horizontal, 4)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(liaison.direct?.aRenvoyer ?? []) { p in
                            Bloc(marge: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text((p.nom as NSString).deletingPathExtension).font(Style.code(30)).monospacedDigit()
                                            .foregroundStyle(Style.or)
                                        Spacer()
                                        Text(Date(timeIntervalSince1970: p.heure).formatted(date: .omitted, time: .standard))
                                            .font(.system(size: 13)).monospacedDigit().foregroundStyle(Style.cremeDiscret)
                                    }
                                    Text(p.detail.prefix(1).uppercased() + p.detail.dropFirst()).font(.system(size: 13))
                                        .foregroundStyle(Style.cremeDiscret)
                                }
                            }
                        }
                        ForEach(liaison.direct?.bienArrivees ?? [], id: \.self) { n in
                            Bloc(bord: Style.vert.opacity(0.5), fond: Style.vert.opacity(0.12)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\((n as NSString).deletingPathExtension) est bien arrivée")
                                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Style.vertTexte)
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
                    .font(.system(size: 13)).foregroundStyle(Style.cremeDiscret).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 10)
        }
        .foregroundStyle(Style.creme)
    }
}

/// Maquette « Piste, messages » : le stand (Mac) et toutes les pistes.
struct MessagesPisteView: View {
    @EnvironmentObject var liaison: Liaison
    @Environment(\.dismiss) private var fermer
    @State private var texte = ""
    /// Destinataire choisi (HUGO 24/11) : vide = tout le monde, « Stand » = le Mac seulement, sinon une personne.
    @State private var pour = ""
    private let rapides = ["Batterie", "Carte pleine", "Pause 5 min", "Besoin de relève"]

    /// Les personnes vues dans les messages (sauf moi et le stand).
    private var personnes: [String] {
        var l: [String] = []
        for m in liaison.messages {
            for n in [m.qui, m.pour] where !n.isEmpty && n != "Stand" && n != liaison.nom && n != "iPhone" && !l.contains(n) { l.append(n) }
        }
        return l.sorted()
    }

    private var destinataires: [(String, String)] { [("", "Tout le monde"), ("Stand", "Le stand seulement")] + personnes.map { ($0, $0) } }

    var body: some View {
        ZStack {
            Style.fond
            VStack(alignment: .leading, spacing: 12) {
                EnteteRetour(titre: "Messages", taille: 28, sousTitre: "Choisis à qui tu écris : tout le monde, le stand ou une personne") { fermer() }
                ScrollViewReader { lecteur in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            Spacer(minLength: 0)
                            ForEach(liaison.messages) { m in bulle(m).id(m.id) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .defaultScrollAnchorBas()
                    .onAppear { lecteur.scrollTo(liaison.messages.last?.id, anchor: .bottom) }
                    .onChange(of: liaison.messages.count) { _ in
                        withAnimation { lecteur.scrollTo(liaison.messages.last?.id, anchor: .bottom) }
                    }
                }
                Rangees(espace: 6) {
                    ForEach(destinataires, id: \.0) { d in
                        Button(d.1) { pour = d.0 }
                            .font(.system(size: 13, weight: pour == d.0 ? .semibold : .regular))
                            .foregroundStyle(pour == d.0 ? Style.nuit : Style.creme)
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .background(pour == d.0 ? Style.or : Style.voile.opacity(0.08), in: Capsule())
                            .contentShape(Capsule())
                    }
                }
                Rangees(espace: 6) {
                    ForEach(rapides, id: \.self) { r in
                        Button(r) { liaison.envoyer(message: r, pour: pour) }
                            .font(.system(size: 13)).foregroundStyle(Style.creme)
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .background(Style.voile.opacity(0.08), in: Capsule())
                            .overlay(Capsule().stroke(Style.voile.opacity(0.15), lineWidth: 1))
                    }
                }
                HStack(spacing: 8) {
                    TextField("", text: $texte, prompt: Text(pour.isEmpty ? "Écrire à tout le monde…" : pour == "Stand" ? "Écrire au stand…" : "Écrire à \(pour)…").foregroundColor(Style.cremeDiscret), axis: .vertical)
                        .lineLimit(1...4)
                        .font(.system(size: 15)).foregroundStyle(Style.creme)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Style.voile.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Style.voile.opacity(0.15), lineWidth: 1))
                    Button {
                        liaison.envoyer(message: texte, pour: pour)
                        texte = ""
                    } label: {
                        Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold)).foregroundStyle(Style.nuit)
                            .frame(width: 44, height: 44).background(Style.or, in: Circle())
                    }
                    .disabled(texte.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 10)
        }
        .foregroundStyle(Style.creme)
        .onAppear { liaison.luJusqua = Date().timeIntervalSince1970 }
        .onChange(of: liaison.messages.count) { _ in liaison.luJusqua = Date().timeIntervalSince1970 }
    }

    private func bulle(_ m: MessagePiste) -> some View {
        let moi = m.qui == liaison.nom
        let qui = moi ? "Moi" : (m.piste.isEmpty ? m.qui : "\(m.qui) · \(m.piste)")
        let forme = UnevenRoundedRectangleCompat(haut: 16, basGauche: moi ? 16 : 4, basDroit: moi ? 4 : 16)
        return HStack {
            if moi { Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(qui)\(m.pour.isEmpty ? "" : (m.pour == liaison.nom ? " · pour toi" : m.pour == "Stand" ? " → le stand" : " → \(m.pour)")) · \(Date(timeIntervalSince1970: m.heure).formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(Style.cremeDiscret)
                Text(m.texte).font(.system(size: 15, weight: m.incident ? .semibold : .regular)).lineSpacing(2)
                    .foregroundStyle(m.incident ? Style.orangeClair : Style.creme)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(moi ? Style.or.opacity(0.22) : Style.voile.opacity(0.08), in: forme)
            .overlay(forme.stroke(moi ? Style.or.opacity(0.5) : Style.voile.opacity(0.12), lineWidth: 1))
            .frame(maxWidth: UIScreen.main.bounds.width * 0.78, alignment: moi ? .trailing : .leading)
            if !moi { Spacer(minLength: 0) }
        }
    }
}

/// Bulle aux coins inégaux (iOS 16 n'a pas UnevenRoundedRectangle).
struct UnevenRoundedRectangleCompat: Shape {
    var haut: CGFloat
    var basGauche: CGFloat
    var basDroit: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + haut, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - haut, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + haut), radius: haut)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - basDroit))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - basDroit, y: r.maxY), radius: basDroit)
        p.addLine(to: CGPoint(x: r.minX + basGauche, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - basGauche), radius: basGauche)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + haut))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + haut, y: r.minY), radius: haut)
        p.closeSubpath()
        return p
    }
}

/// Boutons rapides sur plusieurs lignes si besoin (comme « flex-wrap »).
struct Rangees: Layout {
    var espace: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largeur = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, ligne: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let t = v.sizeThatFits(.unspecified)
            if x > 0 && x + t.width > largeur { x = 0; y += ligne + espace; ligne = 0 }
            x += t.width + espace
            maxX = max(maxX, x - espace)
            ligne = max(ligne, t.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + ligne)
    }

    func placeSubviews(in r: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = r.minX, y = r.minY, ligne: CGFloat = 0
        for v in subviews {
            let t = v.sizeThatFits(.unspecified)
            if x > r.minX && x + t.width > r.maxX { x = r.minX; y += ligne + espace; ligne = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + espace
            ligne = max(ligne, t.height)
        }
    }
}

extension View {
    /// Fil des messages collé en bas (iOS 17 : ancre de défilement ; iOS 16 : rien, le défilement suffit).
    @ViewBuilder func defaultScrollAnchorBas() -> some View {
        if #available(iOS 17.0, *) { self.defaultScrollAnchor(.bottom) } else { self }
    }
}
