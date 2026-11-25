import AppKit
import SwiftUI
import TriPhotoMoteur

/// Les deux façons de regarder des photos, partout dans l'app (HUGO 25/11, comme la Bibliothèque de Lightroom) :
/// la GALERIE (grille de vignettes, touche G) et la PHOTO en grand (touche E ou Entrée, double-clic).
struct SelecteurVue: View {
    @Binding var galerie: Bool

    var body: some View {
        HStack(spacing: 0) {
            bouton("Galerie (G)", icone: "square.grid.3x3", actif: galerie) { galerie = true }
            bouton("Photo (E)", icone: "square", actif: !galerie) { galerie = false }
        }
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.bordure, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func bouton(_ titre: String, icone: String, actif: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(titre, systemImage: icone)
                .font(.system(size: 12, weight: actif ? .semibold : .regular))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .foregroundStyle(actif ? Theme.fond : Theme.texte)
                .background(actif ? Theme.accent : Color.clear)
        }
        .buttonStyle(BoutonPlat())
    }
}

/// Curseur de taille des vignettes de la galerie (gardé d'une fois sur l'autre).
struct CurseurTaille: View {
    @Binding var taille: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo").font(.system(size: 9)).foregroundStyle(Theme.texteDiscret)
            Slider(value: $taille, in: 100...280).frame(width: 110).controlSize(.small)
            Image(systemName: "photo").font(.system(size: 13)).foregroundStyle(Theme.texteDiscret)
        }
        .help("Taille des vignettes")
    }
}

/// Nombre de colonnes de la galerie pour une largeur donnée (sert aussi aux flèches ↑ ↓).
func colonnesGalerie(largeur: CGFloat, taille: Double, espace: CGFloat = 8) -> Int {
    max(1, Int((largeur + espace) / (CGFloat(taille) + espace)))
}

/// Une photo à montrer en grand dans la visionneuse.
struct ElementVisionneuse: Identifiable {
    var id: String
    var chemins: [String]
    var titre: String
    var detail: String = ""
}

/// Une photo en grand, en entier (portrait ou paysage), dans une fenêtre par-dessus l'écran.
/// ← → pour avancer ; Échap, G ou E pour revenir à la galerie. Si l'écran le permet, Espace ajoute ou retire
/// la photo du choix (À valider, _00, Mémoire).
struct Visionneuse: View {
    let elements: [ElementVisionneuse]
    var choisie: ((String) -> Bool)? = nil
    var basculer: ((String) -> Void)? = nil
    @State private var index: Int
    @State private var rafraichir = false
    @Environment(\.dismiss) private var fermer

    init(elements: [ElementVisionneuse], depart: String?, choisie: ((String) -> Bool)? = nil, basculer: ((String) -> Void)? = nil) {
        self.elements = elements
        self.choisie = choisie
        self.basculer = basculer
        _index = State(initialValue: elements.firstIndex { $0.id == depart } ?? 0)
    }

    private var courant: ElementVisionneuse? { elements.indices.contains(index) ? elements[index] : nil }

    private static var taille: CGSize {
        let ecran = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return CGSize(width: max(800, ecran.width * 0.85), height: max(560, ecran.height * 0.85))
    }

    var body: some View {
        let _ = rafraichir          // redessine après Espace (le choix vit dans l'écran d'origine)
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(elements.isEmpty ? "Aucune photo" : "Photo \(index + 1) sur \(elements.count)")
                    .font(.system(size: 13, weight: .semibold))
                if let e = courant {
                    Text(e.titre).font(.system(size: 13, design: .monospaced))
                    Text(e.detail).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret).lineLimit(1)
                }
                Spacer()
                Text("← → pour avancer\(basculer != nil ? " · Espace : choisir" : "") · Échap ou G : galerie")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
                Button("Retour à la galerie") { fermer() }.buttonStyle(BoutonStyle())
            }
            if let e = courant {
                VignettePhoto(chemins: e.chemins, cote: 1400, entiere: true)
                    .id(e.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topTrailing) {
                        if let choisie, choisie(e.id) {
                            Label("Choisie", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold)).padding(6)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 5))
                                .foregroundStyle(Theme.fond).padding(8)
                        }
                    }
                    .onTapGesture(count: 2) { fermer() }
                HStack {
                    if let basculer {
                        Button(choisie?(e.id) == true ? "Retirer du choix (Espace)" : "Ajouter au choix (Espace)") {
                            basculer(e.id); rafraichir.toggle()
                        }
                        .buttonStyle(BoutonStyle(principal: choisie?(e.id) == true))
                    }
                    Spacer()
                    Button("◀︎") { avancer(-1) }.buttonStyle(BoutonStyle())
                    Button("▶︎") { avancer(1) }.buttonStyle(BoutonStyle())
                }
            } else {
                Spacer()
            }
        }
        .padding(16)
        .frame(width: Self.taille.width, height: Self.taille.height)
        .background(Theme.fond)
        .foregroundStyle(Theme.texte)
        .background(touches)
    }

    private func avancer(_ pas: Int) {
        guard !elements.isEmpty else { return }
        index = min(max(0, index + pas), elements.count - 1)
    }

    private var touches: some View {
        ZStack {
            Button("") { avancer(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { avancer(1) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { fermer() }.keyboardShortcut(.cancelAction)
            Button("") { fermer() }.keyboardShortcut("g", modifiers: [])
            Button("") { fermer() }.keyboardShortcut("e", modifiers: [])
            Button("") { if let e = courant { basculer?(e.id); rafraichir.toggle() } }.keyboardShortcut(.space, modifiers: [])
        }
        .opacity(0)
    }
}

/// Photo de départ quand on ouvre la visionneuse (fenêtre « photo en grand »).
struct DepartVisionneuse: Identifiable {
    var id: String
}

extension FichePhoto {
    var elementVisionneuse: ElementVisionneuse {
        ElementVisionneuse(
            id: String(id), chemins: [copie, chemin], titre: codeRetenu.isEmpty ? "sans code" : codeRetenu,
            detail: [cavalier.isEmpty ? nil : "\(cavalier) · \(cheval)", boitier,
                     prise.map { $0.formatted(date: .omitted, time: .standard) }].compactMap { $0 }.joined(separator: " · "))
    }
}

/// Le choix Galerie / Photo pour un écran dont la photo en grand s'ouvre par-dessus (À valider, _00, Mémoire).
func choixVue(_ enGrand: Binding<DepartVisionneuse?>, depart: @escaping () -> String?) -> Binding<Bool> {
    Binding(get: { enGrand.wrappedValue == nil },
            set: { galerie in
                if galerie { enGrand.wrappedValue = nil } else if let d = depart() { enGrand.wrappedValue = DepartVisionneuse(id: d) }
            })
}
