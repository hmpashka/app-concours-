import AppKit
import Foundation
import TriPhotoCommun
import WebKit

/// Capture Horse & Comp : la page d'incrustation de Horses & Competitions est ouverte dans une page web cachée
/// (comme le suivi externe de HM Timing), et le texte des zones choisies (dossard, nom, épreuve, temps, points) est
/// lu deux fois par seconde. Quand le couple change, un passage est créé et envoyé au moteur, qui vérifie les codes
/// des photos exactement comme avec HM Timing. Lecture du texte de la page seulement : pas d'image, très léger.
@MainActor
final class CaptureHorseComp: ObservableObject {
    @Published private(set) var ouverte = false
    @Published private(set) var etatPage = "Page pas encore ouverte"
    @Published private(set) var lu: [String: String] = [:]
    @Published private(set) var passages: [Passage] = []
    @Published private(set) var raison = ""
    @Published private(set) var apercu: NSImage?
    @Published private(set) var derniereLecture: Date?

    /// Réglages et destinataire, fournis par l'état de l'app.
    var zones: () -> [String: [Double]] = { [:] }
    var concours: () -> Concours? = { nil }
    var epreuveForcee: () -> String = { "" }
    var envoyer: (([Passage], String) -> Void)?

    private var web: WKWebView?
    private var fenetre: NSWindow?
    private var minuterie: Timer?
    private var suivi = SuiviIncrustation()
    private var lecturesVides = 0

    static let largeur: CGFloat = 1280
    static let hauteur: CGFloat = 720

    /// Identifiant du chrono Horse & Comp dans les réglages (une capture par chrono Horse & Comp).
    let id: String
    private var fichier: String { "passages-capture-\(id).json" }

    init(id: String) {
        self.id = id
        if let p = Stockage.lire([Passage].self, nom: "passages-capture-\(id).json") {
            passages = p
        } else if let p = Stockage.lire([Passage].self, nom: "passages-capture.json") {
            passages = p        // passages d'avant la version à plusieurs chronos
        }
    }

    // MARK: - Ouvrir / fermer

    func ouvrir(_ adresse: String) {
        var a = adresse.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.hasPrefix("/") { a = URL(fileURLWithPath: a).absoluteString }        // fichier d'essai sur le Mac
        if !a.isEmpty && !a.lowercased().hasPrefix("http") && !a.lowercased().hasPrefix("file:") { a = "https://" + a }
        guard let url = URL(string: a), !a.isEmpty else {
            etatPage = "Adresse invalide : colle l'adresse complète de la page d'incrustation (https://…)"
            return
        }
        if web == nil {
            let conf = WKWebViewConfiguration()
            conf.websiteDataStore = .nonPersistent()
            conf.suppressesIncrementalRendering = false
            let w = WKWebView(frame: NSRect(x: 0, y: 0, width: Self.largeur, height: Self.hauteur), configuration: conf)
            // fenêtre hors de l'écran : la page vit comme chez un spectateur, mais personne ne la voit
            let f = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: Self.largeur, height: Self.hauteur),
                             styleMask: [.borderless], backing: .buffered, defer: false)
            f.isReleasedWhenClosed = false
            f.ignoresMouseEvents = true
            f.contentView = w
            f.orderBack(nil)
            web = w
            fenetre = f
        }
        if url.isFileURL {
            web?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            web?.load(URLRequest(url: url))
        }
        ouverte = true
        etatPage = "Chargement de la page…"
        lecturesVides = 0
        minuterie?.invalidate()
        minuterie = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.lire() }
        }
    }

    func fermer() {
        minuterie?.invalidate()
        minuterie = nil
        web?.stopLoading()
        web?.loadHTMLString("", baseURL: nil)
        fenetre?.orderOut(nil)
        ouverte = false
        etatPage = "Page fermée"
    }

    /// Oublie les passages lus (nouvelle journée).
    func effacerPassages() {
        suivi = SuiviIncrustation()
        passages = []
        Stockage.ecrire(passages, nom: fichier)
        envoyer?(passages, "")
    }

    /// Concours rangé (son fichier est parti avec lui) : passages oubliés, sans rien écrire.
    func oublierPassages() {
        suivi = SuiviIncrustation()
        passages = []
    }

    /// Concours rouvert : passages relus dans son fichier remis en place.
    func relirePassages() {
        suivi = SuiviIncrustation()
        passages = Stockage.lire([Passage].self, nom: fichier) ?? []
    }

    // MARK: - Lecture

    private func lire() {
        guard let web else { return }
        let z = zones()
        guard !z.isEmpty, let data = try? JSONSerialization.data(withJSONObject: z),
              let json = String(data: data, encoding: .utf8) else {
            etatPage = web.isLoading ? "Chargement de la page…" : "Page ouverte : dessine les zones à lire"
            return
        }
        let script = SuiviIncrustation.scriptLecture.replacingOccurrences(of: "ZONES", with: json)
        web.evaluateJavaScript(script) { [weak self] resultat, erreur in
            Task { @MainActor in self?.traiter(resultat, erreur) }
        }
    }

    private func traiter(_ resultat: Any?, _ erreur: Error?) {
        guard let texte = resultat as? String, let data = texte.data(using: .utf8),
              let d = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            etatPage = erreur.map { "Page illisible : \($0.localizedDescription)" } ?? "Page illisible"
            return
        }
        derniereLecture = Date()
        lu = d
        if d.values.allSatisfy({ $0.isEmpty }) {
            lecturesVides += 1
            etatPage = lecturesVides > 20 ? "Rien à lire dans les zones : la page a changé ? (vérifie les zones)" : "Page ouverte"
        } else {
            lecturesVides = 0
            etatPage = "Lecture en cours"
        }
        let change = suivi.lecture(d, t: Date().timeIntervalSince1970, concours: concours(), epreuveForcee: epreuveForcee())
        raison = suivi.raison
        if change {
            // on garde les passages d'avant (relance de la page) et on ajoute ceux de la lecture en cours
            let nouveaux = suivi.passages
            var tous = passages.filter { p in !nouveaux.contains { $0.debut == p.debut } }
            tous.append(contentsOf: nouveaux)
            tous.sort { $0.debut < $1.debut }
            if tous.count > 2000 { tous.removeFirst(tous.count - 2000) }
            passages = tous
            Stockage.ecrire(passages, nom: fichier)
            envoyer?(passages, raison)
        }
    }

    /// Image de la page, pour dessiner les zones (seulement quand l'écran de capture est affiché).
    func rafraichirApercu() {
        guard let web, ouverte else { return }
        let conf = WKSnapshotConfiguration()
        conf.rect = NSRect(x: 0, y: 0, width: Self.largeur, height: Self.hauteur)
        conf.snapshotWidth = 960
        web.takeSnapshot(with: conf) { [weak self] image, _ in
            Task { @MainActor in if let image { self?.apercu = image } }
        }
    }
}
