import AppKit
import Combine
import Foundation
import TriPhotoCommun
import TriPhotoMoteur
import UserNotifications

/// Ce qui peut prévenir HUGO (maquette « Son et notifications », 24/11).
enum Evenement: String, CaseIterable, Identifiable, Codable {
    case incident = "Incident d'une piste"
    case message = "Message d'un photographe"
    case serie = "Série « À valider » qui attend"
    case doublon = "Doublon reçu"
    case boitierSilencieux = "Boîtier silencieux"
    case erreur = "Erreur (chrono, serveur, galerie)"
    case commande = "Nouvelle commande de pack"
    case remise = "Remise des prix copiée dans Drive"
    var id: String { rawValue }

    /// Écran ouvert par un clic sur la notification.
    var ecran: Ecran {
        switch self {
        case .incident, .message: return .messages
        case .serie: return .aValider
        case .commande: return .commandes
        default: return .accueil
        }
    }
}

/// Comment un événement se montre : rien, discret (seulement la pastille dans l'app), bannière macOS, ou alerte
/// (bannière + l'icône du Dock rebondit jusqu'à ce qu'on regarde).
enum Affichage: String, CaseIterable, Identifiable, Codable {
    case rien = "Rien", discret = "Discret", banniere = "Bannière", alerte = "Alerte"
    var id: String { rawValue }
}

enum ModeSon: String, CaseIterable, Identifiable, Codable {
    case silencieux = "Silencieux", normal = "Normal", rush = "Rush"
    var id: String { rawValue }
}

struct ReglageEvenement: Codable, Equatable {
    var affichage: Affichage
    var son: String              // nom d'un son du Mac (« Pop »…), vide = aucun
    var enRush: Bool             // gardé en mode Rush
}

/// Préférences de l'app (pas du concours) : thème, ouverture, son et notifications. Gardées dans ce Mac.
@MainActor
final class Preferences: ObservableObject {
    static let partagees = Preferences()

    @Published var theme: ChoixTheme { didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme"); themeChange?() } }
    @Published var mode: ModeSon { didSet { enregistrer() } }
    @Published var volume: Double { didSet { enregistrer() } }
    @Published var ouverture: Bool { didSet { enregistrer() } }
    @Published var sonOuverture: Bool { didSet { enregistrer() } }
    @Published var evenements: [Evenement: ReglageEvenement] { didSet { enregistrer() } }
    var themeChange: (() -> Void)?

    static let sonsDuMac: [String] = {
        let d = URL(fileURLWithPath: "/System/Library/Sounds")
        let l = (try? FileManager.default.contentsOfDirectory(atPath: d.path)) ?? []
        let n = l.filter { $0.hasSuffix(".aiff") }.map { String($0.dropLast(5)) }.sorted()
        return n.isEmpty ? ["Basso", "Glass", "Pop", "Sosumi", "Tink"] : n
    }()

    static let parDefaut: [Evenement: ReglageEvenement] = [
        .incident: .init(affichage: .alerte, son: "Sosumi", enRush: true),
        .message: .init(affichage: .banniere, son: "Pop", enRush: true),
        .serie: .init(affichage: .discret, son: "", enRush: false),
        .doublon: .init(affichage: .discret, son: "", enRush: false),
        .boitierSilencieux: .init(affichage: .banniere, son: "Tink", enRush: true),
        .erreur: .init(affichage: .alerte, son: "Basso", enRush: true),
        .commande: .init(affichage: .banniere, son: "Glass", enRush: false),
        .remise: .init(affichage: .discret, son: "", enRush: false),
    ]

    private struct Stocke: Codable {
        var mode: ModeSon, volume: Double, ouverture: Bool, sonOuverture: Bool, evenements: [String: ReglageEvenement]
    }

    private init() {
        theme = ChoixTheme.courant
        let s = UserDefaults.standard.data(forKey: "preferences").flatMap { try? JSONDecoder().decode(Stocke.self, from: $0) }
        mode = s?.mode ?? .normal
        volume = s?.volume ?? 0.6
        ouverture = s?.ouverture ?? true
        sonOuverture = s?.sonOuverture ?? false
        var e = Preferences.parDefaut
        for (k, v) in s?.evenements ?? [:] { if let ev = Evenement(rawValue: k) { e[ev] = v } }
        evenements = e
    }

    private func enregistrer() {
        let s = Stocke(mode: mode, volume: volume, ouverture: ouverture, sonOuverture: sonOuverture,
                       evenements: Dictionary(uniqueKeysWithValues: evenements.map { ($0.key.rawValue, $0.value) }))
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: "preferences") }
    }

    func reglage(_ e: Evenement) -> ReglageEvenement { evenements[e] ?? Preferences.parDefaut[e]! }
}

/// Prévient HUGO selon les préférences. Plusieurs notifications du même genre en moins d'une minute sont
/// regroupées en une seule (« 10 messages »). Le son est joué par l'app (volume réglable).
@MainActor
final class Notifieur {
    static let partage = Notifieur()
    private var recents: [Evenement: [Date]] = [:]
    private var surveillance: AnyCancellable?
    private var avant = ResumeMoteur()
    private var silencieuxVus: Set<String> = []
    private var dernierSon = Date.distantPast

    private var possible: Bool { Bundle.main.bundleIdentifier != nil }

    func demanderAutorisation() {
        guard possible else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func jouer(_ son: String) {
        guard !son.isEmpty, Preferences.partagees.mode != .silencieux else { return }
        guard Date().timeIntervalSince(dernierSon) > 0.8 else { return }   // jamais une rafale de sons
        dernierSon = Date()
        guard let s = NSSound(named: NSSound.Name(son)) else { return }
        s.volume = Float(Preferences.partagees.volume)
        s.play()
    }

    func signaler(_ e: Evenement, titre: String, texte: String, id: String = UUID().uuidString, infos: [String: String] = [:]) {
        let p = Preferences.partagees
        let r = p.reglage(e)
        if p.mode == .rush && !r.enRush { return }
        guard r.affichage == .banniere || r.affichage == .alerte else { return }
        jouer(r.son)
        if r.affichage == .alerte { NSApp.requestUserAttention(.criticalRequest) }
        guard possible else { return }
        // regroupement : à partir de 3 en une minute, une seule notification mise à jour
        let maintenant = Date()
        var l = (recents[e] ?? []).filter { maintenant.timeIntervalSince($0) < 60 }
        l.append(maintenant)
        recents[e] = l
        let n = UNMutableNotificationContent()
        var ident = id
        if l.count >= 3 {
            ident = "groupe-\(e.rawValue)"
            n.title = "\(l.count) × \(e.rawValue.lowercased())"
            n.body = "Dernier : \(titre) — \(texte)"
        } else {
            n.title = titre
            n.body = texte
        }
        n.sound = nil                                        // le son est joué par l'app
        n.threadIdentifier = e.rawValue
        var info: [String: String] = infos
        info["ecran"] = e.ecran.rawValue
        n.userInfo = info
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: ident, content: n, trigger: nil))
    }

    /// Surveille le moteur : nouvelles séries à valider, doublons, erreurs, boîtiers silencieux, remises copiées.
    func surveiller(_ m: Moteur, silenceMinutes: @escaping () -> Int) {
        surveillance = m.$resume.receive(on: DispatchQueue.main).sink { [weak self] r in
            MainActor.assumeIsolated { self?.comparer(r, silence: silenceMinutes()) }
        }
    }

    private func comparer(_ r: ResumeMoteur, silence: Int) {
        defer { avant = r }
        guard avant.recues > 0 || !avant.boitiers.isEmpty else { return }   // premier passage : rien à signaler
        if r.series.count > avant.series.count, let s = r.series.last {
            signaler(.serie, titre: "À valider", texte: "\(r.series.count) série\(r.series.count > 1 ? "s" : "") en attente (\(s.photos.count) photos)")
        }
        if r.doublons.count > avant.doublons.count, let d = r.doublons.last {
            signaler(.doublon, titre: "Doublon reçu", texte: d.nom)
        }
        if r.enErreur > avant.enErreur {
            signaler(.erreur, titre: "Erreur", texte: r.derniereErreur.isEmpty ? "\(r.enErreur) photo(s) en erreur" : r.derniereErreur)
        }
        let copiees = r.remises.copiees.values.reduce(0, +), avantCopiees = avant.remises.copiees.values.reduce(0, +)
        if copiees > avantCopiees {
            signaler(.remise, titre: "Remise des prix", texte: "\(copiees - avantCopiees) photos copiées dans Google Drive")
        }
        let limite = Double(max(1, silence) * 60)
        for b in r.boitiers {
            guard let d = b.derniere else { continue }
            if Date().timeIntervalSince(d) > limite {
                if !silencieuxVus.contains(b.nom) {
                    silencieuxVus.insert(b.nom)
                    signaler(.boitierSilencieux, titre: "Boîtier silencieux", texte: "\(b.nomAffiche) : rien depuis \(max(1, silence)) min")
                }
            } else {
                silencieuxVus.remove(b.nom)
            }
        }
    }
}
