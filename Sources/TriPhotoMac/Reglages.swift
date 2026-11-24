import Foundation
import TriPhotoCommun
import TriPhotoMoteur

/// Réglages d'un concours. Gardés d'un jour à l'autre ; enregistrables comme modèle (« CSO 4 pistes »).
struct ReglagesConcours: Codable, Equatable {
    enum Chronometrage: String, Codable, CaseIterable, Identifiable {
        case hmTiming = "HM Timing"
        case captureHorseComp = "Capture Horse & Comp"
        var id: String { rawValue }
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
        /// Nom de la piste dans le chrono (« source » HM Timing). Vide : trouvé tout seul.
        var sourceChrono = ""

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
        }
    }

    // 1. Concours
    var nomConcours = ""
    var nombreJours = 1
    var cheminFFE = ""
    var chronometrage: Chronometrage = .hmTiming
    var pistes: [Piste] = [Piste(nom: "Piste 1", photographe: "")]

    // 1b. Chrono (étape 2)
    var adresseHM = ""                 // « 192.168.1.20:8080 »
    var codeRegieHM = ""
    var codeTechHM = ""
    var finDeTourSecondes = 15         // la piste reste au couple tant de secondes après l'arrivée
    var latenceSecondes = 5            // tolérée au changement de couple
    var attenteChronoMinutes = 3       // au-delà, la photo part avec son code, marquée « sans vérification »
    var attente00Minutes = 2           // une photo en _00 attend une photo de code ou le chrono
    var fichierPassagesEntrainement = ""   // mode entraînement : passages d'un ancien concours (JSON)

    // 1c. Capture Horse & Comp (page d'incrustation lue par l'app)
    var urlIncrustation = ""
    var zonesIncrustation: [String: [Double]] = [:]   // zone → [x, y, largeur, hauteur] en fractions de la page
    var epreuveForcee = ""                            // numéro d'épreuve choisi à la main (vide : lu sur la page)

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

    init() {}

    // Lecture tolérante : un réglage ajouté dans une version suivante prend sa valeur par défaut.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func lire<T: Decodable>(_ cle: CodingKeys, _ defaut: T) -> T { (try? c.decode(T.self, forKey: cle)) ?? defaut }
        nomConcours = lire(.nomConcours, nomConcours)
        nombreJours = lire(.nombreJours, nombreJours)
        cheminFFE = lire(.cheminFFE, cheminFFE)
        chronometrage = lire(.chronometrage, chronometrage)
        pistes = lire(.pistes, pistes)
        adresseHM = lire(.adresseHM, adresseHM)
        codeRegieHM = lire(.codeRegieHM, codeRegieHM)
        codeTechHM = lire(.codeTechHM, codeTechHM)
        finDeTourSecondes = lire(.finDeTourSecondes, finDeTourSecondes)
        latenceSecondes = lire(.latenceSecondes, latenceSecondes)
        attenteChronoMinutes = lire(.attenteChronoMinutes, attenteChronoMinutes)
        attente00Minutes = lire(.attente00Minutes, attente00Minutes)
        fichierPassagesEntrainement = lire(.fichierPassagesEntrainement, fichierPassagesEntrainement)
        urlIncrustation = lire(.urlIncrustation, urlIncrustation)
        zonesIncrustation = lire(.zonesIncrustation, zonesIncrustation)
        epreuveForcee = lire(.epreuveForcee, epreuveForcee)
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
