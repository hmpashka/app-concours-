import Foundation
import Network
import TriPhotoCommun
import UIKit

/// Le lien avec le Mac Tri-photo : cherche le Mac sur le wifi (Bonjour), s'y connecte, se reconnecte tout seul.
/// Garde le nom et la piste choisis (ils restent d'un jour à l'autre).
@MainActor
final class Liaison: ObservableObject {
    @Published private(set) var connecte = false
    @Published private(set) var macs: [String] = []          // noms des Mac Tri-photo trouvés
    @Published private(set) var macChoisi = ""
    @Published private(set) var accueil: AccueilPiste?
    @Published private(set) var direct: DirectPiste?
    @Published private(set) var messages: [MessagePiste] = []
    @Published private(set) var etat = "Recherche du Mac Tri-photo sur le wifi…"

    @Published var nom: String { didSet { UserDefaults.standard.set(nom, forKey: "nom"); direBonjour() } }
    @Published var piste: String { didSet { UserDefaults.standard.set(piste, forKey: "piste"); direct = nil; direBonjour() } }
    /// Écran gardé allumé pendant le concours (les alertes s'affichent tout de suite). Réglable dans le menu.
    @Published var ecranAllume: Bool {
        didSet {
            UserDefaults.standard.set(ecranAllume, forKey: "ecranAllume")
            UIApplication.shared.isIdleTimerDisabled = ecranAllume
        }
    }
    /// Heure du dernier message lu (pour la pastille du bouton Messages).
    @Published var luJusqua: Double { didSet { UserDefaults.standard.set(luJusqua, forKey: "luJusqua") } }

    private var chercheur: NWBrowser?
    private var resultats: [String: NWEndpoint] = [:]
    private var canal: Canal<VersPiste, DepuisPiste>?
    private var relance: Timer?
    /// Messages et incidents écrits sans réseau : envoyés dès que le Mac est retrouvé.
    @Published private(set) var enAttente: [DepuisPiste] = []

    init() {
        nom = UserDefaults.standard.string(forKey: "nom") ?? ""
        piste = UserDefaults.standard.string(forKey: "piste") ?? ""
        luJusqua = UserDefaults.standard.double(forKey: "luJusqua")
        ecranAllume = UserDefaults.standard.object(forKey: "ecranAllume") as? Bool ?? true
        macChoisi = UserDefaults.standard.string(forKey: "mac") ?? ""
    }

    var nonLus: Int { messages.filter { $0.qui != nom && $0.heure > luJusqua }.count }

    // MARK: - Chercher le Mac

    func demarrer() {
        guard chercheur == nil else { return }
        let b = NWBrowser(for: .bonjour(type: LienPiste.service, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] resultats, _ in
            var d: [String: NWEndpoint] = [:]
            for r in resultats {
                if case .service(let nom, _, _, _) = r.endpoint { d[nom] = r.endpoint }
            }
            Task { @MainActor in self?.trouves(d) }
        }
        b.stateUpdateHandler = { [weak self] e in
            if case .failed = e { Task { @MainActor in self?.arreter(); self?.plusTard() } }
        }
        b.start(queue: .main)
        chercheur = b
        relance?.invalidate()
        relance = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.connecterSiBesoin() }
        }
    }

    /// L'app passe en arrière-plan : on coupe (iOS le ferait de toute façon), on reprend au retour.
    func arreter() {
        chercheur?.cancel()
        chercheur = nil
        relance?.invalidate()
        relance = nil
        canal?.fermer()
        canal = nil
        connecte = false
    }

    private func plusTard() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.demarrer() }
    }

    private func trouves(_ d: [String: NWEndpoint]) {
        resultats = d
        macs = d.keys.sorted()
        connecterSiBesoin()
    }

    /// Choisir un autre Mac (deux stands sur le même wifi).
    func choisirMac(_ m: String) {
        macChoisi = m
        UserDefaults.standard.set(m, forKey: "mac")
        canal?.fermer()
        canal = nil
        connecte = false
        connecterSiBesoin()
    }

    private func connecterSiBesoin() {
        guard canal == nil else { return }
        let nomMac = resultats[macChoisi] != nil ? macChoisi : (macs.count == 1 ? macs[0] : "")
        guard let point = resultats[nomMac] else {
            etat = macs.count > 1 ? "Plusieurs Mac Tri-photo : choisis le tien" : "Recherche du Mac Tri-photo sur le wifi…"
            return
        }
        etat = "Connexion à \(nomMac)…"
        let c = Canal<VersPiste, DepuisPiste>(NWConnection(to: point, using: Canal<VersPiste, DepuisPiste>.parametres))
        canal = c
        c.recu = { [weak self] m in self?.recevoir(m) }
        c.etat = { [weak self] pret in
            guard let self, self.canal === c else { return }
            if pret {
                self.connecte = true
                self.etat = "Tri-photo connecté"
                self.direBonjour()
                self.enAttente.forEach { c.envoyer($0) }
                self.enAttente = []
            } else {
                self.connecte = false
                self.canal = nil
                self.etat = "Connexion perdue, nouvel essai…"
            }
        }
        c.demarrer()
    }

    // MARK: - Échanges

    private func recevoir(_ m: VersPiste) {
        switch m {
        case .accueil(let a): accueil = a
        case .direct(let d): if d.piste == piste { direct = d }
        case .messages(let l): messages = l
        }
    }

    private func direBonjour() {
        canal?.envoyer(.bonjour(nom: nom, piste: piste, appareil: UIDevice.current.name, version: LienPiste.version))
    }

    func envoyer(message texte: String, pour: String = "") {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        envoyerOuGarder(.message(texte: t, pour: pour))
    }

    func incident(_ heure: Date) {
        envoyerOuGarder(.incident(heure: heure.timeIntervalSince1970, note: ""))
    }

    private func envoyerOuGarder(_ m: DepuisPiste) {
        if connecte, let canal { canal.envoyer(m) } else { enAttente.append(m) }
    }

    /// En attente d'envoi (pas de réseau).
    var nombreEnAttente: Int { enAttente.count }

    func alerteVue(_ a: AlerteCodePiste) {
        canal?.envoyer(.alerteVue(boitier: a.boitier, attendu: a.attendu))
    }
}
