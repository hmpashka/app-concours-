import AppKit
import Foundation
import Network
import TriPhotoCommun
import TriPhotoMoteur
import UserNotifications

/// Le lien avec les iPhone de l'app Piste : le Mac s'annonce sur le wifi (Bonjour « _triphoto._tcp »), les iPhone le
/// trouvent tout seuls. Toutes les 2 s, chaque iPhone reçoit l'écran Direct de sa piste, seulement s'il a changé.
/// Messages et incidents sont gardés sur le Mac (un fichier par jour).
@MainActor
final class ServeurPiste: ObservableObject {
    struct Connecte: Identifiable {
        let id: UUID
        var nom = ""
        var piste = ""
        var appareil = ""
        var depuis = Date()
        let canal: Canal<DepuisPiste, VersPiste>
        var dernierAccueil: AccueilPiste?
        var dernierDirect: DirectPiste?
        var derniersMessages: [MessagePiste]?
        var dernieresCommandes: [Commande]?
    }

    @Published private(set) var connectes: [Connecte] = []
    @Published private(set) var messages: [MessagePiste] = []
    @Published private(set) var etat = "Pas encore démarré"
    @Published private(set) var enLigne = false
    /// Messages pas encore vus sur le Mac, par conversation (« » : toutes les pistes, sinon le nom).
    @Published var nonLus: [String: Int] = [:]

    /// Fournis par l'état de l'app.
    var resume: () -> ResumeMoteur = { ResumeMoteur() }
    var reglages: () -> ReglagesConcours = { ReglagesConcours() }
    var concours: () -> Concours? = { nil }
    var surMessages: () -> Bool = { false }
    var alerteVue: ((String) -> Void)?
    var suivreEnDirect: ((Bool) -> Void)?
    // Commandes de pack photo
    var chercherClients: (String) -> [ClientTrouve] = { _ in [] }
    var commandesDuConcours: () -> [Commande] = { [] }
    var enregistrerCommande: ((Commande) -> Void)?

    private var ecoute: NWListener?
    private var minuterie: Timer?
    private var personnes: [String] = []
    private var fichierMessages: String { "messages-\(ServeurPiste.jour()).json" }

    init() {
        messages = Stockage.lire([MessagePiste].self, nom: fichierMessages) ?? []
        personnes = Stockage.lire([String].self, nom: "personnes-piste.json") ?? []
    }

    static func jour(_ d: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    // MARK: - Démarrer

    func demarrer() {
        guard ecoute == nil else { return }
        do {
            let l = try NWListener(using: Canal<DepuisPiste, VersPiste>.parametres)
            let nom = reglages().nomConcours.isEmpty ? "Groom Pix" : "Groom Pix · \(reglages().nomConcours)"
            l.service = NWListener.Service(name: String(nom.prefix(60)), type: LienPiste.service)
            l.stateUpdateHandler = { [weak self] e in
                Task { @MainActor in
                    guard let self else { return }
                    switch e {
                    case .ready:
                        self.enLigne = true
                        self.etat = "Visible des iPhone sur le wifi"
                    case .failed(let err):
                        self.enLigne = false
                        self.etat = "Lien iPhone arrêté : \(err.localizedDescription)"
                        self.ecoute?.cancel()
                        self.ecoute = nil
                        // nouvel essai dans 10 s (wifi coupé, changement de réseau…)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.demarrer() }
                    default: break
                    }
                }
            }
            l.newConnectionHandler = { [weak self] c in
                Task { @MainActor in self?.accueillir(c) }
            }
            l.start(queue: DispatchQueue(label: "tri-photo.ecoute", qos: .utility))
            ecoute = l
        } catch {
            etat = "Lien iPhone impossible : \(error.localizedDescription)"
        }
        minuterie?.invalidate()
        minuterie = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.actualiser() }
        }
        demanderNotifications()
    }

    private func accueillir(_ c: NWConnection) {
        let canal = Canal<DepuisPiste, VersPiste>(c)
        let id = canal.id
        connectes.append(Connecte(id: id, canal: canal))
        canal.recu = { [weak self] m in self?.recevoir(m, de: id) }
        canal.etat = { [weak self] pret in
            guard let self else { return }
            if pret { self.actualiser() } else { self.connectes.removeAll { $0.id == id } }
            self.suivreEnDirect?(!self.connectes.isEmpty)
        }
        canal.demarrer()
    }

    // MARK: - Reçu d'un iPhone

    private func recevoir(_ m: DepuisPiste, de id: UUID) {
        guard let i = connectes.firstIndex(where: { $0.id == id }) else { return }
        switch m {
        case .bonjour(let nom, let piste, let appareil, _):
            connectes[i].nom = nom
            connectes[i].piste = piste
            connectes[i].appareil = appareil
            connectes[i].dernierDirect = nil
            connectes[i].derniersMessages = nil
            connectes[i].dernieresCommandes = nil
            connectes[i].canal.envoyer(.theme(ChoixTheme.courant.code))
            APNs.partage.misAJour(nom: nom, appareil: appareil, piste: piste)
            if !nom.isEmpty && !personnes.contains(nom) {
                personnes.append(nom)
                Stockage.ecrire(personnes, nom: "personnes-piste.json")
            }
            actualiser()
        case .message(let texte, let pour):
            let c = connectes[i]
            ajouter(MessagePiste(qui: c.nom.isEmpty ? "iPhone" : c.nom, piste: c.piste, texte: texte,
                                 heure: Date().timeIntervalSince1970, pour: pour))
        case .incident(let heure, let note):
            let c = connectes[i]
            let h = Date(timeIntervalSince1970: heure).formatted(date: .omitted, time: .standard)
            ajouter(MessagePiste(qui: c.nom.isEmpty ? "iPhone" : c.nom, piste: c.piste,
                                 texte: "INCIDENT à \(h)" + (note.isEmpty ? "" : " : \(note)"),
                                 heure: heure, pour: "", incident: true))
        case .alerteVue(let boitier, _):
            alerteVue?(boitier)
        case .chercherClient(let texte):
            connectes[i].canal.envoyer(.clients(texte: texte, chercherClients(texte)))
        case .jeton(let sorte, let valeur, let production):
            let c = connectes[i]
            APNs.partage.enregistrer(sorte: sorte, valeur: valeur, production: production,
                                     nom: c.nom, appareil: c.appareil, piste: c.piste)
            actualiser()
        case .commande(var k):
            if k.par.isEmpty { k.par = connectes[i].nom.isEmpty ? "iPhone" : connectes[i].nom }
            enregistrerCommande?(k)
            Notifieur.partage.signaler(.commande, titre: "Commande · \(k.par)",
                                       texte: "\(k.client) · \(Commande.euros(k.prix)) · \(k.statut.rawValue)")
            actualiser()
        }
    }

    // MARK: - Messages

    /// Message écrit sur le Mac. `pour` vide : toutes les pistes.
    func envoyerDuStand(_ texte: String, pour: String) {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        ajouter(MessagePiste(qui: "Stand", piste: "", texte: t, heure: Date().timeIntervalSince1970, pour: pour))
    }

    private func ajouter(_ m: MessagePiste) {
        // nouvelle journée : on repart d'un fichier neuf (l'ancien reste sur le Mac)
        if let d = messages.last, ServeurPiste.jour(Date(timeIntervalSince1970: d.heure)) != ServeurPiste.jour() { messages = [] }
        messages.append(m)
        if messages.count > 2000 { messages.removeFirst(messages.count - 2000) }
        Stockage.ecrire(messages, nom: fichierMessages)
        // iPhone pas connecté (app fermée, iPhone verrouillé) : bulle par le service d'Apple
        let presents = Set(connectes.map(\.appareil))
        APNs.partage.bulle(titre: m.incident ? "Incident · \(m.qui)" : m.qui + (m.pour.isEmpty ? " · à tous" : ""),
                           texte: m.texte,
                           pour: { p in !presents.contains(p.appareil) && p.nom != m.qui && m.pourPersonne(p.nom) },
                           urgent: m.incident)
        if m.qui != "Stand" {
            let conv = ServeurPiste.conversation(de: m)
            if !surMessages() || NSApp.isActive == false {
                nonLus[conv, default: 0] += 1
                notifier(m)
            } else {
                // déjà sur l'onglet Messages : pas de bulle, mais le son quand même
                Notifieur.partage.jouer(Preferences.partagees.reglage(m.incident ? .incident : .message).son)
            }
        }
        actualiser()
    }

    /// Conversation d'un message, vue du Mac : « » pour toutes les pistes, sinon la personne.
    static func conversation(de m: MessagePiste) -> String {
        if m.pour.isEmpty { return "" }
        return m.qui == "Stand" ? m.pour : m.qui
    }

    func messages(de conv: String) -> [MessagePiste] {
        messages.filter { ServeurPiste.conversation(de: $0) == conv }
    }

    func lu(_ conv: String) { nonLus[conv] = nil }

    /// Personnes à qui écrire en privé : connectées maintenant ou déjà vues aujourd'hui.
    var conversations: [String] {
        var l = connectes.map(\.nom).filter { !$0.isEmpty }
        for m in messages where m.qui != "Stand" && !l.contains(m.qui) { l.append(m.qui) }
        return Array(Set(l)).sorted()
    }

    /// Thème changé sur le Mac : tous les iPhone le prennent.
    func themeChange() {
        for c in connectes { c.canal.envoyer(.theme(ChoixTheme.courant.code)) }
    }

    // MARK: - Notifications du Mac

    private var notificationsPossibles: Bool { Bundle.main.bundleIdentifier != nil }

    private func demanderNotifications() {
        guard notificationsPossibles else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func notifier(_ m: MessagePiste) {
        // affichage et son selon Réglages › Son et notifications
        Notifieur.partage.signaler(m.incident ? .incident : .message,
                                   titre: m.incident ? "Incident · \(m.qui)" : m.qui + (m.piste.isEmpty ? "" : " · \(m.piste)"),
                                   texte: m.texte, id: m.id, infos: ["message": m.id, "qui": m.qui, "pour": m.pour])
    }

    // MARK: - Envoi aux iPhone (toutes les 2 s, seulement ce qui a changé)

    private func actualiser() {
        let r = resume()
        let reg = reglages()
        let accueil = fabriquerAccueil(r, reg)
        let commandes = connectes.isEmpty ? [] : commandesDuConcours()
        for i in connectes.indices {
            let c = connectes[i]
            if c.dernierAccueil != accueil {
                c.canal.envoyer(.accueil(accueil))
                connectes[i].dernierAccueil = accueil
            }
            if !c.piste.isEmpty {
                let d = fabriquerDirect(piste: c.piste, r, reg)
                if c.dernierDirect != d {
                    c.canal.envoyer(.direct(d))
                    connectes[i].dernierDirect = d
                }
            }
            let ks = Array(commandes.prefix(200))
            if c.dernieresCommandes != ks {
                c.canal.envoyer(.commandes(ks))
                connectes[i].dernieresCommandes = ks
            }
            let ms = Array(messages.filter { $0.pourPersonne(c.nom) }.suffix(100))
            if c.derniersMessages != ms {
                c.canal.envoyer(.messages(ms))
                connectes[i].derniersMessages = ms
            }
        }
        // écrans verrouillés : chaque piste suivie, iPhone connecté ou non
        let apns = APNs.partage
        guard apns.pret else { return }
        let presents = Set(connectes.map(\.appareil))
        for piste in Set(apns.iphones.filter { !$0.activite.isEmpty }.map(\.piste)) where !piste.isEmpty {
            let d = fabriquerDirect(piste: piste, r, reg)
            apns.ecranVerrouille(piste: piste, etat: EcranVerrouille(d))
            // CHANGE TON CODE : bulle urgente sur les iPhone de la piste qui ne sont pas devant l'app
            if let a = d.alerte, alertesPoussees[piste] != a {
                alertesPoussees[piste] = a
                apns.bulle(titre: "CHANGE TON CODE", texte: "Boîtier \(a.boitier) : mets \(a.attendu) (encore \(a.ancien))",
                           pour: { $0.piste == piste && !presents.contains($0.appareil) && $0.activite.isEmpty }, urgent: true)
            } else if d.alerte == nil {
                alertesPoussees[piste] = nil
            }
        }
    }

    private var alertesPoussees: [String: AlerteCodePiste] = [:]

    /// Piste du chrono qui correspond à une piste des réglages.
    static func source(pour piste: String, reglages: ReglagesConcours, sources: [String]) -> String? {
        guard let i = reglages.pistes.firstIndex(where: { $0.nom == piste }) else { return nil }
        let p = reglages.pistes[i]
        if !p.sourceChrono.isEmpty { return p.sourceChrono }
        if let s = sources.first(where: { $0.caseInsensitiveCompare(piste) == .orderedSame }) { return s }
        let chiffres = piste.filter(\.isNumber)
        if !chiffres.isEmpty, let s = sources.first(where: { $0.filter(\.isNumber) == chiffres }) { return s }
        let triees = sources.sorted()
        if reglages.pistes.count == 1 { return triees.first }
        return triees.indices.contains(i) ? triees[i] : nil
    }

    private func fabriquerAccueil(_ r: ResumeMoteur, _ reg: ReglagesConcours) -> AccueilPiste {
        let sources = Array(r.suivis.keys)
        var noms = reg.pistes.map(\.photographe).filter { !$0.isEmpty }
        for p in personnes where !noms.contains(p) { noms.append(p) }
        let pistes = reg.pistes.map { p -> AccueilPiste.Piste in
            var info: [String] = []
            if let s = ServeurPiste.source(pour: p.nom, reglages: reg, sources: sources), let suivi = r.suivis[s] {
                if !suivi.carriere.isEmpty { info.append(suivi.carriere) }
                if !suivi.epreuve.isEmpty { info.append("#\(suivi.epreuve) en piste") }
            }
            let la = connectes.filter { $0.piste == p.nom && !$0.nom.isEmpty }.map(\.nom)
            if !la.isEmpty { info.append(la.joined(separator: ", ") + (la.count > 1 ? " y sont" : " y est")) }
            else if !p.photographe.isEmpty { info.append("prévue pour \(p.photographe)") }
            // photographe attendu sur cette piste d'après la photo de synchro de son boîtier
            for s in r.boitiersSynchro where s.piste == p.nom && !s.photographe.isEmpty && la.isEmpty && p.photographe.isEmpty {
                info.append("prévue pour \(s.photographe)")
                break
            }
            if info.isEmpty { info.append("Pas d'épreuve en cours") }
            return .init(nom: p.nom, info: info.joined(separator: " · "))
        }
        return AccueilPiste(concours: reg.nomConcours.isEmpty ? "Concours" : reg.nomConcours,
                            lieu: concours()?.nom.capitalized ?? "", photographes: noms, pistes: pistes,
                            heureMac: (Date().timeIntervalSince1970 / 60).rounded(.down) * 60)
    }

    private func fabriquerDirect(piste: String, _ r: ResumeMoteur, _ reg: ReglagesConcours) -> DirectPiste {
        var d = DirectPiste(piste: piste)
        let source = ServeurPiste.source(pour: piste, reglages: reg, sources: Array(r.suivis.keys))
        d.chronoOK = r.chrono?.ok == true
        // boîtiers de la piste : choisis à la photo de synchro, sinon appris sur les photos au bon code
        var boitiers = Set(r.boitierPiste.filter { source != nil && $0.value == source }.map(\.key))
        for s in r.boitiersSynchro {
            if s.piste == piste { boitiers.insert(s.boitier) } else if !s.piste.isEmpty { boitiers.remove(s.boitier) }
        }
        if let source, let s = r.suivis[source] {
            d.carriere = s.carriere
            d.epreuve = s.epreuve
            d.nomEpreuve = s.nomEpreuve
            d.partis = s.partis
            d.engages = s.engages
            d.finEstimee = s.finEstimee.map { ($0 / 60).rounded() * 60 }     // à la minute : pas d'envoi toutes les 2 s
            if let p = s.enPiste { d.enPiste = CouplePiste(code: p.code.texte, cavalier: p.cavalier, cheval: p.cheval) }
            if let p = s.precedent {
                let n = r.compteParCode[p.code.texte] ?? 0
                d.precedent = CouplePiste(code: p.code.texte, cavalier: p.cavalier, cheval: p.cheval, photos: n)
                if n == 0, p.code.special == nil, s.enPiste != nil { d.info = "\(p.code.texte) : aucune photo reçue sur le Mac" }
            }
            if let e = s.suivant {
                d.suivant = CouplePiste(code: CodePassage(epreuve: s.epreuve, dossard: e.dossard).texte,
                                        cavalier: e.cavalier, cheval: e.cheval)
            }
        }
        d.mesPhotos = r.boitiers.filter { boitiers.contains($0.nom) }.reduce(0) { $0 + $1.photos }
        d.alerte = r.alertesCode.first { boitiers.contains($0.boitier) }
        // photos mal arrivées : celles des boîtiers de la piste (retrouvés par le début du nom), ou de boîtier inconnu
        d.aRenvoyer = r.aRenvoyer.filter { f in
            let b = f.boitier.isEmpty ? (r.prefixeBoitier[Moteur.prefixe(f.origine)] ?? "") : f.boitier
            return b.isEmpty || b == "*" || boitiers.contains(b) || boitiers.isEmpty
        }.map { PhotoARenvoyer(nom: $0.origine, boitier: $0.boitier, heure: $0.recue.timeIntervalSince1970,
                               detail: $0.erreur.isEmpty ? "mal transférée" : $0.erreur.lowercased()) }
        d.bienArrivees = r.bienArrivees.map(\.origine)
        return d
    }
}
