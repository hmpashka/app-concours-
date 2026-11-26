import Combine
import Foundation
import ImageIO
import Network
import TriPhotoCommun
import TriPhotoMoteur
import UniformTypeIdentifiers

/// Ce que le Loupedeck CT affiche (lu chaque seconde par le module Groom Pix du logiciel Loupedeck).
struct EtatLoupedeck: Codable {
    struct Chrono: Codable { var nom: String; var ok: Bool? }
    struct Piste: Codable { var piste: String; var code: String; var cavalier: String; var cheval: String; var termine: Bool }
    struct Revue: Codable {
        var position: Int          // 1 = première photo
        var total: Int
        var code: String
        var cavalier: String
        var cheval: String
        var classe: String         // « bonne », « floue », « sol », « code » ou vide
        var meilleure: Bool
        var reseaux: Bool
        var chute: Bool
        var filtre: String         // « Toutes », « À traiter », « Bonnes »
        var ordre: String          // texte court du filtre exact
        var epreuve: String        // vide : toutes
        var suppressionPermise: Bool
        var zoom: Double
    }
    struct Serie: Codable {
        var position: Int
        var total: Int
        var code: String
        var proposition: String
        var photos: Int
        var photoCode: Bool
    }
    struct Message: Codable { var id: String; var qui: String; var piste: String; var texte: String; var heure: Double; var incident: Bool }

    var version = 1
    var concours: String
    var actif: Bool
    var ecran: String              // « accueil », « aValider », « revue »…
    var pause: Bool
    var aValider: Int              // photos en attente de validation
    var series: Int                // séries en attente (hors rush)
    var aReprendre: Int
    var enFile: Int
    var retardSecondes: Double
    var parMinute: Double
    var recues: Int
    var enErreur: Int
    var chronos: [Chrono]
    var galerie: String            // « ok », « attente », « nuit », « pause », « erreur » ou « aucune »
    var galerieAFaire: Int
    var pistes: [Piste]
    var alertes: [String]
    var revue: Revue?
    var serie: Serie?
    var message: Message?          // dernier message non lu d'un iPhone
    var nonLus: Int
    var photo: Int64?              // photo affichée dans l'app (pour l'écran de la roue)
    var heure: Double
}

/// Un ordre du Loupedeck (« photo », pas +1 ; « classe.bonne »…).
struct OrdreLoupedeck {
    var nom: String
    var pas: Int
}

/// Le « pont » entre Groom Pix et le Loupedeck CT : une toute petite adresse web, joignable SEULEMENT depuis ce Mac
/// (127.0.0.1, rien ne sort sur le réseau). Le module Loupedeck y lit l'état chaque seconde et y envoie les
/// boutons pressés. Marche que Groom Pix soit devant ou non (pas de touches clavier simulées).
/// Ne touche jamais au tri : au pire le Loupedeck ne répond plus, le tri continue.
final class PontLoupedeck: @unchecked Sendable {
    static let port: UInt16 = 8095
    private let file = DispatchQueue(label: "tri-photo.pont-loupedeck", qos: .utility)
    private var ecoute: NWListener?
    private let vignettes = NSCache<NSNumber, NSData>()
    /// Fournis par l'app (appelés sur le fil principal).
    var etat: @MainActor () -> EtatLoupedeck? = { nil }
    var ordre: @MainActor (OrdreLoupedeck) -> Void = { _ in }
    var moteur: Moteur?

    init() { vignettes.countLimit = 60 }

    func demarrer() {
        file.async {
            guard self.ecoute == nil else { return }
            let p = NWParameters.tcp
            p.requiredInterfaceType = .loopback          // joignable seulement depuis ce Mac
            p.allowLocalEndpointReuse = true
            guard let port = NWEndpoint.Port(rawValue: PontLoupedeck.port), let l = try? NWListener(using: p, on: port) else { return }
            l.newConnectionHandler = { [weak self] c in self?.servir(c) }
            l.stateUpdateHandler = { [weak self] e in
                if case .failed = e { self?.file.async { self?.ecoute?.cancel(); self?.ecoute = nil } }
            }
            l.start(queue: self.file)
            self.ecoute = l
        }
    }

    func arreter() {
        file.async {
            self.ecoute?.cancel()
            self.ecoute = nil
        }
    }

    // MARK: - HTTP minimal

    private func servir(_ c: NWConnection) {
        c.start(queue: file)
        c.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, _, _ in
            guard let self, let data, let texte = String(data: data, encoding: .utf8) else { c.cancel(); return }
            self.repondre(texte, sur: c)
        }
        file.asyncAfter(deadline: .now() + 10) { c.cancel() }
    }

    private func repondre(_ requete: String, sur c: NWConnection) {
        let lignes = requete.components(separatedBy: "\r\n")
        let morceaux = (lignes.first ?? "").split(separator: " ")
        guard morceaux.count >= 2 else { envoyer(400, sur: c); return }
        // Le module envoie toujours cet en-tête. Une page web ouverte dans un navigateur ne peut pas l'ajouter
        // sans permission : elle ne peut donc pas piloter Groom Pix à la place de HUGO.
        guard lignes.contains(where: { $0.lowercased().hasPrefix("x-groom-pix:") }) else { envoyer(403, sur: c); return }
        let methode = morceaux[0]
        let comps = URLComponents(string: "http://x" + morceaux[1])
        let chemin = comps?.path ?? "/"
        let params = Dictionary((comps?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })

        if methode == "GET" && chemin == "/etat" {
            let e = DispatchQueue.main.sync { MainActor.assumeIsolated { self.etat() } }
            let d = (try? JSONEncoder().encode(e)) ?? Data("null".utf8)
            envoyer(200, type: "application/json", corps: d, sur: c)
        } else if methode == "GET", chemin.hasPrefix("/photo/"), let id = Int64(chemin.dropFirst(7)) {
            if let d = vignette(id) { envoyer(200, type: "image/jpeg", corps: d, sur: c) } else { envoyer(404, sur: c) }
        } else if methode == "POST", chemin.hasPrefix("/action/") {
            let o = OrdreLoupedeck(nom: String(chemin.dropFirst(8)), pas: Int(params["pas"] ?? "") ?? 1)
            DispatchQueue.main.async { MainActor.assumeIsolated { self.ordre(o) } }
            envoyer(200, sur: c)
        } else {
            envoyer(404, sur: c)
        }
    }

    /// Petite vignette carrée (≈ 10 Ko) pour l'écran rond de la roue, gardée en mémoire.
    private func vignette(_ id: Int64) -> Data? {
        if let d = vignettes.object(forKey: NSNumber(value: id)) { return d as Data }
        guard let f = moteur?.fiche(id: id) else { return nil }
        let source = FileManager.default.fileExists(atPath: f.copie) ? f.copie : f.chemin
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: source) as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 240]
        guard let grande = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        // carrée (centre de la photo) : l'écran de la roue est rond
        let cote = min(grande.width, grande.height)
        let img = grande.cropping(to: CGRect(x: (grande.width - cote) / 2, y: (grande.height - cote) / 2, width: cote, height: cote)) ?? grande
        let sortie = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(sortie, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        vignettes.setObject(sortie, forKey: NSNumber(value: id))
        return sortie as Data
    }

    private func envoyer(_ code: Int, type: String = "text/plain", corps: Data = Data(), sur c: NWConnection) {
        let raison = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found"][code] ?? "OK"
        var d = Data("HTTP/1.1 \(code) \(raison)\r\nContent-Type: \(type)\r\nContent-Length: \(corps.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
        d.append(corps)
        c.send(content: d, completion: .contentProcessed { _ in c.cancel() })
    }
}

// MARK: - Côté app : état montré et ordres reçus

extension Etat {
    static let cleLoupedeck = "loupedeckActif"

    /// Réglage du Mac (pas du concours) : vrai par défaut.
    var loupedeckActif: Bool {
        get { UserDefaults.standard.object(forKey: Etat.cleLoupedeck) as? Bool ?? true }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: Etat.cleLoupedeck)
            reglerLoupedeck()
        }
    }

    func brancherLoupedeck() {
        loupedeck.moteur = moteur
        loupedeck.etat = { [weak self] in self?.etatLoupedeck() }
        loupedeck.ordre = { [weak self] o in self?.executer(o) }
        reglerLoupedeck()
    }

    func reglerLoupedeck() {
        if loupedeckActif { loupedeck.demarrer() } else { loupedeck.arreter() }
    }

    private static let nomsEcrans: [Ecran: String] = [.accueil: "accueil", .aValider: "aValider", .revue: "revue",
                                                       .messages: "messages", .memoire: "memoire", .commandes: "commandes", .auBureau: "auBureau",
                                                       .reglages: "reglages"]

    func etatLoupedeck() -> EtatLoupedeck {
        let r = moteur.resume
        var chronos: [EtatLoupedeck.Chrono] = []
        if let c = r.chrono {
            chronos = c.liens.isEmpty ? [.init(nom: texteChronos, ok: c.ok)] : c.liens.map { .init(nom: $0.nom, ok: $0.ok) }
        }
        var galerie = "aucune"
        var aFaire = 0
        if let g = r.galerieEnLigne {
            aFaire = g.aFaire
            if g.ok == false { galerie = "erreur" }
            else if g.pauseManuelle || g.pauseReseau { galerie = "pause" }
            else if g.aFaire > 0 { galerie = g.attendLaNuit ? "nuit" : "attente" }
            else { galerie = "ok" }
        }
        let nonLu = serveur.messages.last { m in
            serveur.nonLus[ServeurPiste.conversation(de: m), default: 0] > 0 && m.qui != "Stand"
        }
        return EtatLoupedeck(
            concours: reglages.nomConcours.isEmpty ? (concours?.nom ?? "") : reglages.nomConcours,
            actif: moteur.actif,
            ecran: Etat.nomsEcrans[ecran] ?? "accueil",
            pause: r.enPause,
            aValider: r.aValider,
            series: r.series.filter { $0.genre != .rush }.count,
            aReprendre: r.aReprendre,
            enFile: r.enFile, retardSecondes: r.retardSecondes, parMinute: r.parMinute, recues: r.recues, enErreur: r.enErreur,
            chronos: chronos, galerie: galerie, galerieAFaire: aFaire,
            pistes: r.enPiste.map { p in
                let code = p.passage.dossard.isEmpty ? "" : "\(p.passage.epreuve)_\(p.passage.dossard)"
                return .init(piste: p.piste, code: code, cavalier: p.passage.cavalier, cheval: p.passage.cheval, termine: p.termine)
            },
            alertes: r.alertes,
            revue: ecran == .revue ? infoRevueLoupedeck : nil,
            serie: ecran == .aValider ? infoSerieLoupedeck : nil,
            message: nonLu.map { .init(id: $0.id, qui: $0.qui, piste: $0.piste, texte: $0.texte, heure: $0.heure, incident: $0.incident) },
            nonLus: serveur.nonLus.values.reduce(0, +),
            photo: ecran == .revue ? photoLoupedeck : (ecran == .aValider ? photoLoupedeck : nil),
            heure: Date().timeIntervalSince1970)
    }

    /// Un bouton ou une molette du Loupedeck. Ce qui concerne un écran précis (revue, À valider) est passé à cet
    /// écran ; s'il n'est pas affiché, on l'affiche d'abord (le cran suivant agira).
    func executer(_ o: OrdreLoupedeck) {
        let ecransMolette: [Ecran] = [.accueil, .aValider, .revue, .memoire]
        switch o.nom {
        case "ecran":
            let i = ecransMolette.firstIndex(of: ecran) ?? 0
            ecran = ecransMolette[((i + o.pas) % ecransMolette.count + ecransMolette.count) % ecransMolette.count]
        case "ecran.accueil": ecran = .accueil
        case "ecran.aValider": ecran = .aValider
        case "ecran.revue": ecran = .revue
        case "ecran.memoire": ecran = .memoire
        case "ecran.commandes": ecran = .commandes
        case "ecran.messages": ecran = .messages
        case "ecran.reglages": ecran = .reglages
        case "cloture": if moteur.actif { cloture = .journee }
        case "panneaux": basculerTousLesPanneaux()
        case "panneauGauche": panneauGauche.toggle()
        case "panneauDroit": panneauDroit.toggle()
        case "pause": if moteur.actif { moteur.mettreEnPause(!moteur.resume.enPause) }
        case "rush": if moteur.resume.aValider > 0 { moteur.rushToutEnvoyer() }
        case "messageLu":
            for k in serveur.nonLus.keys { serveur.lu(k) }
        case "message":
            ecran = .messages
        default:
            let pourRevue = o.nom.hasPrefix("classe.") || ["meilleure", "reseaux", "chute", "supprimer", "changerCode",
                                                             "filtre", "filtre.toutes", "epreuve", "epreuve.toutes",
                                                             "zoom", "zoom.ajuster", "ordre"].contains(o.nom)
            let pourSerie = ["serie", "valider", "ignorer", "serie.ouvrir"].contains(o.nom)
            if pourRevue && ecran != .revue { ecran = .revue; return }
            if pourSerie && ecran != .aValider { ecran = .aValider; return }
            if o.nom == "photo" && ecran != .revue && ecran != .aValider { ecran = .revue; return }
            ordresLoupedeck.send(o)
        }
    }
}
