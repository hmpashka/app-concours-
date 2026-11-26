import SwiftUI

// MARK: - Visite guidée (bouton « ? », HUGO 26/11 : « comme Adobe sur leurs mises à jour », pour la vendeuse)
//
// L'écran s'assombrit, seule la zone expliquée reste allumée (et cliquable), une bulle dit quoi regarder et quoi faire.
// Quand l'action attendue est faite (onglet cliqué, nom tapé…), une coche verte s'affiche et la visite avance seule.
// Pendant une visite, rien n'est supprimé ni enregistré (voir `Visite.bloque`).

/// Zones de l'écran qu'une visite peut montrer : `.repere("revue.recherche")` sur la vue.
struct RepereCle: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, nouveau in nouveau }
    }
}

extension View {
    /// Marque cette zone pour la visite guidée.
    func repere(_ id: String) -> some View {
        anchorPreference(key: RepereCle.self, value: .bounds) { [id: $0] }
    }
}

/// Une étape : l'écran à afficher, la zone allumée, l'explication, et l'action attendue.
struct EtapeVisite {
    enum Attente: Equatable {
        case rien                  // on lit, puis « Suivant »
        case ecran(Ecran)          // cliquer sur un onglet
        case signal(String)        // une action signalée par l'écran (ex. « revue.recherche »)
    }
    var ecran: Ecran? = nil        // affiché d'office en arrivant sur l'étape
    var repere: String? = nil      // zone allumée (rien : bulle au centre)
    var titre: String
    var texte: String
    var action: String? = nil      // « À toi : … »
    var attente: Attente = .rien
}

struct ParcoursVisite: Identifiable {
    var id: String
    var nom: String                // affiché en haut de la bulle
    var menu: String               // affiché dans le menu « ? »
    var etapes: [EtapeVisite]
}

@MainActor
final class Visite: ObservableObject {
    static let partagee = Visite()

    @Published private(set) var parcours: ParcoursVisite?
    @Published private(set) var index = 0
    @Published private(set) var reussie = false          // coche verte : l'action attendue est faite
    @Published var avertissement: String?                // « pendant la visite, rien n'est supprimé »
    private var generation = 0                           // chaque changement d'étape annule l'avance prévue

    var enCours: Bool { parcours != nil }
    var etape: EtapeVisite? { parcours.flatMap { index < $0.etapes.count ? $0.etapes[index] : nil } }

    func commencer(_ p: ParcoursVisite, etat: Etat) {
        if etat.pleinEcran { return }                    // le bandeau est caché : la visite attendra la sortie
        etat.panneauGauche = true; etat.panneauDroit = true
        parcours = p; index = 0
        entrer(etat: etat)
    }

    func quitter() {
        generation += 1
        parcours = nil; index = 0; reussie = false; avertissement = nil
    }

    func aller(_ i: Int, etat: Etat) {
        guard let p = parcours else { return }
        generation += 1
        if i >= p.etapes.count { quitter(); return }
        index = max(0, i)
        entrer(etat: etat)
    }

    private func entrer(etat: Etat) {
        reussie = false; avertissement = nil
        guard let e = etape else { return }
        if let ecran = e.ecran, etat.ecran != ecran { etat.ecran = ecran }
        if case .ecran(let attendu) = e.attente, etat.ecran == attendu { reussir(etat: etat) }
    }

    /// Un écran dit qu'une action vient d'être faite (nom tapé, photo changée…).
    func signaler(_ s: String) {
        guard let e = etape, e.attente == .signal(s) else { return }
        reussir(etat: nil)
    }

    /// L'onglet affiché a changé.
    func ecranChange(_ ecran: Ecran, etat: Etat) {
        guard let e = etape, e.attente == .ecran(ecran) else { return }
        reussir(etat: etat)
    }

    /// Coche verte, puis étape suivante un peu plus tard. Une nouvelle frappe repousse ce délai :
    /// on ne coupe pas quelqu'un qui est en train de taper un nom.
    private func reussir(etat: Etat?) {
        reussie = true
        generation += 1
        let g = generation, i = index
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard let self, self.generation == g, self.index == i, let etat = etat ?? Visite.etat else { return }
            self.aller(i + 1, etat: etat)
        }
    }

    /// Une action qui efface ou enregistre pour de vrai : refusée pendant la visite, avec un mot dans la bulle.
    func bloque(_ quoi: String) -> Bool {
        guard enCours else { return false }
        avertissement = "Pendant la visite, \(quoi). En vrai, ce bouton fonctionne normalement."
        return true
    }

    /// Pour les étapes réussies par un signal (la vue qui signale n'a pas l'état sous la main).
    static weak var etat: Etat?
}

// MARK: - Calque de la visite (posé sur toute la fenêtre)

struct CalqueVisite: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var visite = Visite.partagee
    var reperes: [String: Anchor<CGRect>]

    var body: some View {
        if let p = visite.parcours, let e = visite.etape {
            GeometryReader { g in
                let zone = e.repere.flatMap { reperes[$0] }.map { g[$0].insetBy(dx: -6, dy: -6) }
                    .flatMap { $0.width > 12 && $0.height > 12 ? $0.intersection(CGRect(origin: .zero, size: g.size)) : nil }
                ZStack(alignment: .topLeading) {
                    // Voile sombre, troué sur la zone expliquée : on ne peut cliquer que dans le trou.
                    Voile(trou: zone)
                        .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
                        .contentShape(Voile(trou: zone), eoFill: true)
                        .onTapGesture {}
                    if let z = zone {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.accent, lineWidth: 2.5)
                            .frame(width: z.width, height: z.height)
                            .offset(x: z.minX, y: z.minY)
                            .allowsHitTesting(false)
                    }
                    Bulle(parcours: p, etape: e)
                        .frame(width: Bulle.largeur)
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(Bulle.position(pres: zone, dans: g.size))
                }
                .animation(.easeInOut(duration: 0.25), value: visite.index)
            }
            .onChange(of: etat.ecran) { visite.ecranChange($0, etat: etat) }
            .transition(.opacity)
        }
    }
}

/// Le voile : tout le rectangle, moins la zone allumée (remplissage pair-impair).
private struct Voile: Shape {
    var trou: CGRect?
    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        if let t = trou { p.addRoundedRect(in: t, cornerSize: CGSize(width: 8, height: 8)) }
        return p
    }
}

private struct Bulle: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var visite = Visite.partagee
    var parcours: ParcoursVisite
    var etape: EtapeVisite

    static let largeur: CGFloat = 390
    static let hauteurPrevue: CGFloat = 270

    /// À droite de la zone s'il y a la place, sinon à gauche, dessous, dessus ; toujours dans la fenêtre.
    static func position(pres z: CGRect?, dans taille: CGSize) -> CGSize {
        let marge: CGFloat = 16
        func borne(_ x: CGFloat, _ y: CGFloat) -> CGSize {
            CGSize(width: min(max(marge, x), max(marge, taille.width - largeur - marge)),
                   height: min(max(marge, y), max(marge, taille.height - hauteurPrevue - marge)))
        }
        guard let z else { return borne((taille.width - largeur) / 2, (taille.height - hauteurPrevue) / 2) }
        if z.maxX + marge + largeur < taille.width - marge { return borne(z.maxX + marge, z.minY) }
        if z.minX - marge - largeur > marge { return borne(z.minX - marge - largeur, z.minY) }
        if z.maxY + marge + hauteurPrevue < taille.height { return borne(z.midX - largeur / 2, z.maxY + marge) }
        return borne(z.midX - largeur / 2, z.minY - marge - hauteurPrevue)
    }

    var body: some View {
        let n = parcours.etapes.count
        let derniere = visite.index == n - 1
        VStack(alignment: .leading, spacing: 8) {
            Text("\(parcours.nom.uppercased()) · ÉTAPE \(visite.index + 1) SUR \(n)")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(etape.titre).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.texte)
            Text(etape.texte).font(.system(size: 13)).foregroundStyle(Theme.texte.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            if let a = etape.action {
                VStack(alignment: .leading, spacing: 4) {
                    Text("👉 À toi : \(a)").font(.system(size: 13, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if visite.reussie {
                        Text("✓ Bien joué !").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ok)
                    } else if etape.attente != .rien {
                        Text("La visite avance toute seule dès que c'est fait.")
                            .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.selection, in: RoundedRectangle(cornerRadius: 6))
            }
            if let w = visite.avertissement {
                Text(w).font(.system(size: 12)).foregroundStyle(Theme.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                // petits points d'avancement (au plus 24, sinon trop serrés)
                if n <= 24 {
                    HStack(spacing: 3) {
                        ForEach(0..<n, id: \.self) { i in
                            Circle().fill(i <= visite.index ? Theme.accent : Theme.bordure).frame(width: 6, height: 6)
                        }
                    }
                }
                Spacer(minLength: 6)
                if visite.index > 0 {
                    Button("◀ Précédent") { visite.aller(visite.index - 1, etat: etat) }.buttonStyle(BoutonStyle())
                }
                Button(derniere ? "Terminer" : "Suivant ▶") { visite.aller(visite.index + 1, etat: etat) }
                    .buttonStyle(BoutonStyle(principal: true))
            }
            HStack {
                Spacer()
                Button("Quitter la visite") { visite.quitter() }
                    .buttonStyle(BoutonPlat())
                    .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
            }
        }
        .padding(16)
        .background(Theme.carte, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
    }
}

// MARK: - Bouton « ? » du bandeau

struct BoutonAide: View {
    @EnvironmentObject var etat: Etat

    var body: some View {
        Menu {
            if let p = Visites.ecran(etat.ecran) {
                Button("Visite de cet écran (\(etat.ecran.rawValue))") { Visite.partagee.commencer(p, etat: etat) }
            }
            Button(Visites.vendeuse.menu) { Visite.partagee.commencer(Visites.vendeuse, etat: etat) }
            Divider()
            Section("Autres écrans") {
                ForEach(Ecran.allCases.filter { $0 != etat.ecran }) { e in
                    if let p = Visites.ecran(e) {
                        Button(p.menu) { Visite.partagee.commencer(p, etat: etat) }
                    }
                }
            }
        } label: {
            Text("?").font(.system(size: 15, weight: .heavy))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 28, height: 28)
        .background(Theme.accent, in: Circle())
        .foregroundStyle(Theme.surAccent)
        .help("Visite guidée : l'app expliquée pas à pas")
    }
}
