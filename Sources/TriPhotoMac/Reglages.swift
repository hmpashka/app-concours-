import Foundation
import TriPhotoCommun
import TriPhotoMoteur

/// Réglages d'un concours. Gardés d'un jour à l'autre ; enregistrables comme modèle (« CSO 4 pistes »).
struct ReglagesConcours: Codable, Equatable {
    /// Un chrono du concours : un ordinateur HM Timing (une ou plusieurs pistes), ou une page d'incrustation
    /// Horse & Comp (une piste). Un concours peut en avoir plusieurs, et mélanger les deux.
    struct ChronoConcours: Codable, Equatable, Identifiable {
        enum Genre: String, Codable, CaseIterable, Identifiable {
            case hmTiming = "HM Timing"
            case horseComp = "Horse & Comp"
            var id: String { rawValue }
        }
        var id = UUID()
        var genre: Genre
        var nom: String
        // HM Timing
        var adresse = ""                                  // « 192.168.1.20:8080 »
        var codeRegie = ""
        var codeTech = ""
        // Horse & Comp (page d'incrustation lue par l'app)
        var urlIncrustation = ""
        var zones: [String: [Double]] = [:]               // zone → [x, y, largeur, hauteur] en fractions de la page
        var epreuveForcee = ""                            // numéro d'épreuve choisi à la main (vide : lu sur la page)

        init(genre: Genre, nom: String) {
            self.genre = genre
            self.nom = nom
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
            genre = (try? c.decode(Genre.self, forKey: .genre)) ?? .hmTiming
            nom = (try? c.decode(String.self, forKey: .nom)) ?? genre.rawValue
            adresse = (try? c.decode(String.self, forKey: .adresse)) ?? ""
            codeRegie = (try? c.decode(String.self, forKey: .codeRegie)) ?? ""
            codeTech = (try? c.decode(String.self, forKey: .codeTech)) ?? ""
            urlIncrustation = (try? c.decode(String.self, forKey: .urlIncrustation)) ?? ""
            zones = (try? c.decode([String: [Double]].self, forKey: .zones)) ?? [:]
            epreuveForcee = (try? c.decode(String.self, forKey: .epreuveForcee)) ?? ""
        }

        /// Réglé assez pour être interrogé.
        var pret: Bool {
            genre == .hmTiming ? !adresse.trimmingCharacters(in: .whitespaces).isEmpty : !urlIncrustation.isEmpty
        }
    }

    enum Protocole: String, Codable, CaseIterable, Identifiable {
        case smb = "SMB"
        case ftp = "FTP"
        var id: String { rawValue }
    }

    struct Piste: Codable, Equatable, Identifiable {
        var id = UUID()
        var nom: String
        var photographe: String
        /// Le chrono de la piste : identifiant d'un chrono des réglages, « aucun », ou vide (trouvé tout seul).
        var chrono = ""
        /// Nom de la piste dans ce chrono (« source » HM Timing). Vide : trouvé tout seul.
        var sourceChrono = ""

        static let aucun = "aucun"

        init(nom: String, photographe: String, sourceChrono: String = "") {
            self.nom = nom
            self.photographe = photographe
            self.sourceChrono = sourceChrono
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
            nom = (try? c.decode(String.self, forKey: .nom)) ?? "Piste"
            photographe = (try? c.decode(String.self, forKey: .photographe)) ?? ""
            sourceChrono = (try? c.decode(String.self, forKey: .sourceChrono)) ?? ""
            chrono = (try? c.decode(String.self, forKey: .chrono)) ?? ""
        }
    }

    // 1. Concours
    var nomConcours = ""
    var nombreJours = 1
    var cheminFFE = ""
    var pistes: [Piste] = [Piste(nom: "Piste 1", photographe: "")]

    // 1b. Chronos (un ou plusieurs : HM Timing et/ou Horse & Comp ; chaque piste choisit le sien)
    var chronos: [ChronoConcours] = [ChronoConcours(genre: .hmTiming, nom: "HM Timing")]
    var finDeTourSecondes = 15         // la piste reste au couple tant de secondes après l'arrivée
    var latenceSecondes = 5            // tolérée au changement de couple
    var attenteChronoMinutes = 3       // au-delà, la photo part avec son code, marquée « sans vérification »
    var attente00Minutes = 2           // une photo en _00 attend une photo de code ou le chrono
    var rushAutoPhotos = 40            // rush : au-delà, tout part avec le code du photographe (0 : jamais tout seul)
    var fichierPassagesEntrainement = ""   // mode entraînement : passages d'un ancien concours (JSON)

    // 2. Dossiers
    var dossierReception = ""
    var dossierImportLightroom = ""
    var dossierTravailLightroom = ""
    var dossierServeurLocal = ""
    var dossierTampon = ""

    // 3. Copies compressées
    var cubeServeur = ""
    var coteServeur = 1500
    var qualiteServeur = 56
    var cubeGalerieIdentique = true
    var cubeGalerie = ""
    var coteGalerie = 1200
    var qualiteGalerie = 56
    var numeroIncruste = true

    // 4. Lightroom et dossier tampon
    var tamponActif = false
    var tailleLot = 20
    var silenceBoitierMinutes = 5
    var retarderSiLightroomOccupe = true

    // 5. Envois
    var protocoleServeur: Protocole = .smb
    // Galerie du stand (serveur local) : rafraîchie par lots, jamais à chaque photo. Mot de passe : trousseau du Mac.
    var urlGalerieStand = ""             // « https://190.160.40.5 »
    var identifiantGalerieStand = ""
    var minutesGalerieStand = 2          // au plus tard X minutes après la première copie en attente
    var empreinteGalerieStand = ""       // certificat du serveur retenu à la 1re connexion
    // Galerie en ligne (comme un site dans FileZilla). Mot de passe : trousseau du Mac.
    var adresseFTPGalerie = ""           // hôte : « ftp.mon-site.fr »
    var protocoleGalerie: ConfigGalerieEnLigne.Protocole = .ftp
    var portGalerie = 0                  // 0 : port habituel du protocole
    var identifiantGalerie = ""
    var dossierGalerie = ""              // dossier distant, à plat : « /www/album »
    var accepterCertificatGalerie = false
    var galerieLaNuit = false
    var heureNuitGalerie = 22
    var heureMatinGalerie = 7
    var limiteKoGalerie = 0              // Ko/s, 0 : sans limite
    var auteurGalerie = ""               // quand le boîtier n'a pas de photographe
    // Sans connexion au concours : copies de la galerie dans un dossier du Mac au lieu du FTP.
    var galerieVersDossier = false
    var dossierLocalGalerie = ""
    // Régulateur réseau (console UniFi, UDM Pro). Clé API : trousseau du Mac.
    var adresseUniFi = ""                // « 192.168.1.1 »
    var montantMbitLigne = 10            // débit montant de la ligne internet du concours
    var seuilUniFi = 70                  // % de la ligne utilisés par les autres → galerie en pause
    var empreinteUniFi = ""
    // Accès à distance (page en lecture seule)
    var accesDistance = false
    var portAccesDistance = 8090
    var codeAccesDistance = String(Int.random(in: 100_000...999_999))
    var sauvegardeActive = false
    var dossierSauvegarde = ""

    // 6. Clôture
    var dossierClotures = ""

    // 7. Mémoire (étape 5) et remises des prix
    var dossierMemoire = ""              // vide : iCloud Drive › Tri-photo Mémoire
    var detectionsActives = true
    var remisesActives = false
    var dossierRemises = ""              // dossier Google Drive sur le Mac (« Mon Drive › Remises des prix »)
    var photosParRemise = 12
    var attenteRemiseMinutes = 10

    // 8. Commandes de pack photo
    var dossierListings = ""             // vide : iCloud Drive › Tri-photo Listings

    init() {}

    // Lecture tolérante : un réglage ajouté dans une version suivante prend sa valeur par défaut.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func lire<T: Decodable>(_ cle: CodingKeys, _ defaut: T) -> T { (try? c.decode(T.self, forKey: cle)) ?? defaut }
        nomConcours = lire(.nomConcours, nomConcours)
        nombreJours = lire(.nombreJours, nombreJours)
        cheminFFE = lire(.cheminFFE, cheminFFE)
        pistes = lire(.pistes, pistes)
        if let l = try? c.decode([ChronoConcours].self, forKey: .chronos) {
            chronos = l
        } else {
            // anciens réglages (un seul chrono) : il devient le premier chrono de la liste
            let a = try decoder.container(keyedBy: Ancien.self)
            func ancien<T: Decodable>(_ cle: Ancien, _ defaut: T) -> T { (try? a.decode(T.self, forKey: cle)) ?? defaut }
            if ancien(.chronometrage, "HM Timing") == "Capture Horse & Comp" {
                var ch = ChronoConcours(genre: .horseComp, nom: "Horse & Comp")
                ch.urlIncrustation = ancien(.urlIncrustation, "")
                ch.zones = ancien(.zonesIncrustation, [:])
                ch.epreuveForcee = ancien(.epreuveForcee, "")
                chronos = [ch]
            } else {
                var ch = ChronoConcours(genre: .hmTiming, nom: "HM Timing")
                ch.adresse = ancien(.adresseHM, "")
                ch.codeRegie = ancien(.codeRegieHM, "")
                ch.codeTech = ancien(.codeTechHM, "")
                chronos = [ch]
            }
        }
        finDeTourSecondes = lire(.finDeTourSecondes, finDeTourSecondes)
        latenceSecondes = lire(.latenceSecondes, latenceSecondes)
        attenteChronoMinutes = lire(.attenteChronoMinutes, attenteChronoMinutes)
        attente00Minutes = lire(.attente00Minutes, attente00Minutes)
        rushAutoPhotos = lire(.rushAutoPhotos, rushAutoPhotos)
        fichierPassagesEntrainement = lire(.fichierPassagesEntrainement, fichierPassagesEntrainement)
        dossierReception = lire(.dossierReception, dossierReception)
        dossierImportLightroom = lire(.dossierImportLightroom, dossierImportLightroom)
        dossierTravailLightroom = lire(.dossierTravailLightroom, dossierTravailLightroom)
        dossierServeurLocal = lire(.dossierServeurLocal, dossierServeurLocal)
        dossierTampon = lire(.dossierTampon, dossierTampon)
        cubeServeur = lire(.cubeServeur, cubeServeur)
        coteServeur = lire(.coteServeur, coteServeur)
        qualiteServeur = lire(.qualiteServeur, qualiteServeur)
        cubeGalerieIdentique = lire(.cubeGalerieIdentique, cubeGalerieIdentique)
        cubeGalerie = lire(.cubeGalerie, cubeGalerie)
        coteGalerie = lire(.coteGalerie, coteGalerie)
        qualiteGalerie = lire(.qualiteGalerie, qualiteGalerie)
        numeroIncruste = lire(.numeroIncruste, numeroIncruste)
        tamponActif = lire(.tamponActif, tamponActif)
        tailleLot = lire(.tailleLot, tailleLot)
        silenceBoitierMinutes = lire(.silenceBoitierMinutes, silenceBoitierMinutes)
        retarderSiLightroomOccupe = lire(.retarderSiLightroomOccupe, retarderSiLightroomOccupe)
        protocoleServeur = lire(.protocoleServeur, protocoleServeur)
        urlGalerieStand = lire(.urlGalerieStand, urlGalerieStand)
        identifiantGalerieStand = lire(.identifiantGalerieStand, identifiantGalerieStand)
        minutesGalerieStand = lire(.minutesGalerieStand, minutesGalerieStand)
        empreinteGalerieStand = lire(.empreinteGalerieStand, empreinteGalerieStand)
        adresseFTPGalerie = lire(.adresseFTPGalerie, adresseFTPGalerie)
        protocoleGalerie = lire(.protocoleGalerie, protocoleGalerie)
        portGalerie = lire(.portGalerie, portGalerie)
        identifiantGalerie = lire(.identifiantGalerie, identifiantGalerie)
        dossierGalerie = lire(.dossierGalerie, dossierGalerie)
        accepterCertificatGalerie = lire(.accepterCertificatGalerie, accepterCertificatGalerie)
        galerieLaNuit = lire(.galerieLaNuit, galerieLaNuit)
        heureNuitGalerie = lire(.heureNuitGalerie, heureNuitGalerie)
        heureMatinGalerie = lire(.heureMatinGalerie, heureMatinGalerie)
        limiteKoGalerie = lire(.limiteKoGalerie, limiteKoGalerie)
        auteurGalerie = lire(.auteurGalerie, auteurGalerie)
        galerieVersDossier = lire(.galerieVersDossier, galerieVersDossier)
        dossierLocalGalerie = lire(.dossierLocalGalerie, dossierLocalGalerie)
        adresseUniFi = lire(.adresseUniFi, adresseUniFi)
        montantMbitLigne = lire(.montantMbitLigne, montantMbitLigne)
        seuilUniFi = lire(.seuilUniFi, seuilUniFi)
        empreinteUniFi = lire(.empreinteUniFi, empreinteUniFi)
        accesDistance = lire(.accesDistance, accesDistance)
        portAccesDistance = lire(.portAccesDistance, portAccesDistance)
        codeAccesDistance = lire(.codeAccesDistance, codeAccesDistance)
        sauvegardeActive = lire(.sauvegardeActive, sauvegardeActive)
        dossierSauvegarde = lire(.dossierSauvegarde, dossierSauvegarde)
        dossierClotures = lire(.dossierClotures, dossierClotures)
        dossierMemoire = lire(.dossierMemoire, dossierMemoire)
        detectionsActives = lire(.detectionsActives, detectionsActives)
        remisesActives = lire(.remisesActives, remisesActives)
        dossierRemises = lire(.dossierRemises, dossierRemises)
        photosParRemise = lire(.photosParRemise, photosParRemise)
        attenteRemiseMinutes = lire(.attenteRemiseMinutes, attenteRemiseMinutes)
        dossierListings = lire(.dossierListings, dossierListings)
    }

    /// Clés des anciens réglages (un seul chrono), lues une fois pour les reprendre.
    private enum Ancien: String, CodingKey {
        case chronometrage, adresseHM, codeRegieHM, codeTechHM, urlIncrustation, zonesIncrustation, epreuveForcee
    }

    // MARK: - Chronos et pistes

    /// Plus d'un HM Timing réglé : le nom des pistes est précédé du nom du chrono (deux « Piste 1 » ne se mélangent pas).
    var prefixerHM: Bool { chronos.filter { $0.genre == .hmTiming && $0.pret }.count > 1 }

    func chrono(id: String) -> ChronoConcours? { chronos.first { $0.id.uuidString == id } }

    /// Le chrono d'une piste : celui choisi, sinon le seul chrono du concours. Nil : aucun, ou à trouver tout seul.
    func chronoDe(_ p: Piste) -> ChronoConcours? {
        if p.chrono == Piste.aucun { return nil }
        if let c = chrono(id: p.chrono) { return c }
        let prets = chronos.filter(\.pret)
        return prets.count == 1 ? prets[0] : nil
    }

    /// Le lien vu par le moteur pour un chrono des réglages.
    func lien(_ c: ChronoConcours) -> ConfigLienChrono {
        ConfigLienChrono(id: c.id.uuidString, nom: c.nom, adresse: c.adresse, codeRegie: c.codeRegie,
                         codeTechnicien: c.codeTech, externe: c.genre == .horseComp,
                         prefixer: c.genre == .hmTiming && prefixerHM,
                         sourceFixe: c.genre == .horseComp ? c.nom : nil)
    }

    /// Un nom libre pour un nouveau chrono (« HM Timing 2 »).
    func nomLibre(_ genre: ChronoConcours.Genre) -> String {
        var n = 1
        while true {
            let nom = n == 1 ? genre.rawValue : "\(genre.rawValue) \(n)"
            if !chronos.contains(where: { $0.nom == nom }) { return nom }
            n += 1
        }
    }
}

/// Où l'app range ce qu'elle garde : ~/Library/Application Support/Tri-photo/
enum Stockage {
    static var dossier: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("Tri-photo", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static var dossierModeles: URL {
        let d = dossier.appendingPathComponent("Modèles", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func lire<T: Decodable>(_ type: T.Type, nom: String) -> T? {
        let url = dossier.appendingPathComponent(nom)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Écriture sûre : fichier temporaire puis remplacement, pour ne jamais laisser un fichier à moitié écrit.
    static func ecrire<T: Encodable>(_ valeur: T, nom: String) {
        ecrire(valeur, vers: dossier.appendingPathComponent(nom))
    }

    static func ecrire<T: Encodable>(_ valeur: T, vers url: URL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(valeur) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func modeles() -> [String] {
        let fichiers = (try? FileManager.default.contentsOfDirectory(atPath: dossierModeles.path)) ?? []
        return fichiers.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }
}
