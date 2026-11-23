import AppKit
import SwiftUI

/// Les actions qui ont un raccourci clavier. La liste grandira avec les étapes (valider, revue…).
enum ActionClavier: String, Codable, CaseIterable, Identifiable {
    case accueil, aValider, revue, memoire, reglages
    case panneauGauche, panneauDroit, tousLesPanneaux
    case chargerFFE, entrainement

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .accueil: return "Aller à l'accueil"
        case .aValider: return "Aller à « À valider »"
        case .revue: return "Aller à la revue"
        case .memoire: return "Aller à la mémoire"
        case .reglages: return "Aller aux réglages"
        case .panneauGauche: return "Afficher / masquer le panneau de gauche"
        case .panneauDroit: return "Afficher / masquer le panneau de droite"
        case .tousLesPanneaux: return "Afficher / masquer tous les panneaux"
        case .chargerFFE: return "Charger le fichier FFE…"
        case .entrainement: return "Mode entraînement…"
        }
    }

    var famille: String {
        switch self {
        case .accueil, .aValider, .revue, .memoire, .reglages: return "Écrans"
        case .panneauGauche, .panneauDroit, .tousLesPanneaux: return "Panneaux"
        case .chargerFFE, .entrainement: return "Concours"
        }
    }

    var parDefaut: Raccourci? {
        switch self {
        case .accueil: return Raccourci(touche: "1", commande: true)
        case .aValider: return Raccourci(touche: "2", commande: true)
        case .revue: return Raccourci(touche: "3", commande: true)
        case .memoire: return Raccourci(touche: "4", commande: true)
        case .reglages: return Raccourci(touche: ",", commande: true)
        case .panneauGauche: return Raccourci(touche: "g", commande: true, option: true)
        case .panneauDroit: return Raccourci(touche: "d", commande: true, option: true)
        case .tousLesPanneaux: return Raccourci(touche: "p", commande: true, option: true)
        case .chargerFFE: return Raccourci(touche: "o", commande: true)
        case .entrainement: return Raccourci(touche: "e", commande: true, majuscule: true)
        }
    }
}

/// Une touche et ses modificateurs (⌘ ⌥ ⌃ ⇧).
struct Raccourci: Codable, Equatable, Hashable {
    var touche: String
    var commande = false
    var option = false
    var controle = false
    var majuscule = false

    var cleSwiftUI: KeyEquivalent { KeyEquivalent(Character(touche.isEmpty ? " " : String(touche.prefix(1)))) }

    var modificateurs: EventModifiers {
        var m: EventModifiers = []
        if commande { m.insert(.command) }
        if option { m.insert(.option) }
        if controle { m.insert(.control) }
        if majuscule { m.insert(.shift) }
        return m
    }

    /// « ⌥⌘G »
    var affichage: String {
        var s = ""
        if controle { s += "⌃" }
        if option { s += "⌥" }
        if majuscule { s += "⇧" }
        if commande { s += "⌘" }
        return s + touche.uppercased()
    }

    /// Raccourci tapé au clavier, ou nil pour une touche qu'on ne peut pas utiliser.
    init?(evenement e: NSEvent) {
        guard let c = e.charactersIgnoringModifiers?.lowercased(), let premier = c.first,
              premier.isLetter || premier.isNumber || ",.;/-=".contains(premier) else { return nil }
        let f = e.modifierFlags
        self.init(touche: String(premier), commande: f.contains(.command), option: f.contains(.option),
                  controle: f.contains(.control), majuscule: f.contains(.shift))
    }

    init(touche: String, commande: Bool = false, option: Bool = false, controle: Bool = false, majuscule: Bool = false) {
        self.touche = touche
        self.commande = commande
        self.option = option
        self.controle = controle
        self.majuscule = majuscule
    }
}

/// Les raccourcis choisis par HUGO, enregistrés sur le Mac.
final class Raccourcis: ObservableObject {
    @Published private(set) var liste: [ActionClavier: Raccourci]

    private static let fichier = "raccourcis.json"

    init() {
        let lus: [String: Raccourci] = Stockage.lire([String: Raccourci].self, nom: Raccourcis.fichier) ?? [:]
        var l: [ActionClavier: Raccourci] = [:]
        for a in ActionClavier.allCases {
            if let r = lus[a.rawValue] { l[a] = r } else if let d = a.parDefaut { l[a] = d }
        }
        liste = l
    }

    subscript(_ action: ActionClavier) -> Raccourci? { liste[action] }

    /// L'action qui utilise déjà ce raccourci, s'il y en a une.
    func conflit(_ r: Raccourci, sauf action: ActionClavier) -> ActionClavier? {
        liste.first { $0.key != action && $0.value == r }?.key
    }

    func changer(_ action: ActionClavier, en r: Raccourci?) {
        liste[action] = r
        enregistrer()
    }

    func toutRemettreParDefaut() {
        var l: [ActionClavier: Raccourci] = [:]
        for a in ActionClavier.allCases { l[a] = a.parDefaut }
        liste = l
        enregistrer()
    }

    private func enregistrer() {
        Stockage.ecrire(Dictionary(uniqueKeysWithValues: liste.map { ($0.key.rawValue, $0.value) }), nom: Raccourcis.fichier)
    }
}

extension View {
    /// Applique le raccourci choisi pour cette action (aucun si HUGO l'a retiré).
    @ViewBuilder
    func raccourci(_ r: Raccourci?) -> some View {
        if let r {
            keyboardShortcut(r.cleSwiftUI, modifiers: r.modificateurs)
        } else {
            self
        }
    }
}

/// Écran « Raccourcis clavier » : une ligne par action, clic sur « Changer » puis on tape la nouvelle touche.
struct RaccourcisView: View {
    @ObservedObject var raccourcis: Raccourcis
    @State private var enCours: ActionClavier?
    @State private var message = ""
    @State private var moniteur: Any?

    private var familles: [String] {
        var vues: [String] = []
        for a in ActionClavier.allCases where !vues.contains(a.famille) { vues.append(a.famille) }
        return vues
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Raccourcis clavier").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.texte)
                    Text("Clique sur « Changer », puis tape la touche voulue (avec ⌘, ⌥, ⌃ ou ⇧ si tu veux). Échap annule.")
                        .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                }
                Spacer()
                Button("Tout remettre par défaut") { raccourcis.toutRemettreParDefaut() }
                    .buttonStyle(BoutonStyle())
            }
            if !message.isEmpty {
                Text(message).font(.system(size: 12)).foregroundStyle(Theme.attention)
            }
            ForEach(familles, id: \.self) { famille in
                Carte(titre: famille) {
                    VStack(spacing: 0) {
                        ForEach(ActionClavier.allCases.filter { $0.famille == famille }) { action in
                            ligne(action)
                            if action != ActionClavier.allCases.last(where: { $0.famille == famille }) {
                                Divider().overlay(Theme.bordure)
                            }
                        }
                    }
                }
            }
        }
        .onDisappear { arreterEcoute() }
    }

    private func ligne(_ action: ActionClavier) -> some View {
        HStack {
            Text(action.libelle).font(.system(size: 13)).foregroundStyle(Theme.texte)
            Spacer()
            if enCours == action {
                Text("Tape la touche…").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
            } else {
                Text(raccourcis[action]?.affichage ?? "aucun")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(raccourcis[action] == nil ? Theme.texteTresDiscret : Theme.texte)
                    .frame(minWidth: 60, alignment: .trailing)
            }
            Button(enCours == action ? "Annuler" : "Changer") {
                if enCours == action { arreterEcoute() } else { ecouter(action) }
            }
            .buttonStyle(BoutonStyle())
            Button("Retirer") { raccourcis.changer(action, en: nil) }
                .buttonStyle(BoutonStyle())
                .disabled(raccourcis[action] == nil)
        }
        .padding(.vertical, 8)
    }

    private func ecouter(_ action: ActionClavier) {
        arreterEcoute()
        enCours = action
        message = ""
        moniteur = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { // Échap
                arreterEcoute()
                return nil
            }
            guard let r = Raccourci(evenement: e) else { return nil }
            if let autre = raccourcis.conflit(r, sauf: action) {
                message = "\(r.affichage) sert déjà à « \(autre.libelle) ». Il a été retiré de cette action."
                raccourcis.changer(autre, en: nil)
            }
            raccourcis.changer(action, en: r)
            arreterEcoute()
            return nil
        }
    }

    private func arreterEcoute() {
        if let m = moniteur { NSEvent.removeMonitor(m) }
        moniteur = nil
        enCours = nil
    }
}
