import Foundation

/// Ce que le Mac (Tri-photo) et les iPhone (app Piste) se disent sur le wifi du concours.
/// Une ligne de JSON par message. Le Mac envoie seulement quand quelque chose a changé : quelques Ko par minute.
public enum LienPiste {
    /// Nom du service Bonjour : les iPhone trouvent le Mac tout seuls, sans adresse à taper.
    public static let service = "_triphoto._tcp"
    public static let version = 1
}

// MARK: - iPhone → Mac

public enum DepuisPiste: Codable, Sendable, Equatable {
    /// Premier message, puis à chaque changement de nom ou de piste. `piste` vide : pas encore choisie.
    case bonjour(nom: String, piste: String, appareil: String, version: Int)
    /// Message écrit sur l'iPhone. `pour` vide : le stand et toutes les pistes.
    case message(texte: String, pour: String)
    /// Bouton INCIDENT : marque ce moment (chute, refus…). Heure de l'iPhone.
    case incident(heure: Double, note: String)
    /// « C'est changé » touché sur l'alerte de code.
    case alerteVue(boitier: String, attendu: String)
    /// Commandes : chercher un client (nom, prénom ou cheval) dans les listings gardés sur le Mac.
    case chercherClient(texte: String)
    /// Commandes : une commande prise ou modifiée sur l'iPhone.
    case commande(Commande)
    /// Jeton du service d'Apple (APNs) : le Mac prévient cet iPhone même app fermée.
    /// `sorte` : « notifications » (bulles), « activite » (écran verrouillé en cours), « demarrage » (lancer l'écran verrouillé).
    /// `production` : faux pour une app installée depuis le Mac (serveur d'essai d'Apple), vrai pour TestFlight / App Store.
    case jeton(sorte: String, valeur: String, production: Bool)
}

// MARK: - Mac → iPhone

public enum VersPiste: Codable, Sendable, Equatable {
    /// Le concours, les photographes connus et les pistes à choisir (écrans « Qui es-tu ? » et « Sur quelle piste ? »).
    case accueil(AccueilPiste)
    /// L'écran Direct de la piste choisie.
    case direct(DirectPiste)
    /// Les messages que cet iPhone doit voir (les 100 derniers).
    case messages([MessagePiste])
    /// Réponse à une recherche de client.
    case clients(texte: String, [ClientTrouve])
    /// Les commandes du concours en cours (les 200 dernières).
    case commandes([Commande])
    /// Thème choisi sur le Mac (« bleuOr » ou « graphite ») : l'iPhone prend le même.
    case theme(String)
}

public struct AccueilPiste: Codable, Sendable, Equatable {
    public struct Piste: Codable, Sendable, Equatable, Identifiable {
        public var id: String { nom }
        public var nom: String
        /// « Carrière herbe · #12 en piste », « Léa y est déjà »…
        public var info: String
        public init(nom: String, info: String) { self.nom = nom; self.info = info }
    }
    public var concours: String
    public var lieu: String
    public var photographes: [String]
    public var pistes: [Piste]
    public var heureMac: Double
    public init(concours: String, lieu: String, photographes: [String], pistes: [Piste], heureMac: Double) {
        self.concours = concours
        self.lieu = lieu
        self.photographes = photographes
        self.pistes = pistes
        self.heureMac = heureMac
    }
}

/// Un couple, tel qu'affiché sur l'iPhone.
public struct CouplePiste: Codable, Sendable, Equatable {
    public var code: String
    public var cavalier: String
    public var cheval: String
    /// Photos reçues sur le Mac pour ce code (précédent).
    public var photos: Int?
    public init(code: String, cavalier: String, cheval: String, photos: Int? = nil) {
        self.code = code
        self.cavalier = cavalier
        self.cheval = cheval
        self.photos = photos
    }
}

/// L'alerte plein écran « CHANGE TON CODE ».
public struct AlerteCodePiste: Codable, Sendable, Equatable, Hashable {
    public var boitier: String
    /// Code que portent encore les photos (« #11_41 »).
    public var ancien: String
    /// Code à mettre (« #12_01 »).
    public var attendu: String
    /// Photos déjà prises avec l'ancien code depuis le début de l'épreuve.
    public var photos: Int
    public init(boitier: String, ancien: String, attendu: String, photos: Int) {
        self.boitier = boitier
        self.ancien = ancien
        self.attendu = attendu
        self.photos = photos
    }
}

public struct PhotoARenvoyer: Codable, Sendable, Equatable, Identifiable {
    public var id: String { nom + boitier }
    /// Nom d'origine, celui du boîtier (« IMG_8812.JPG »).
    public var nom: String
    public var boitier: String
    public var heure: Double
    /// « arrivée incomplète », « illisible »…
    public var detail: String
    public init(nom: String, boitier: String, heure: Double, detail: String) {
        self.nom = nom
        self.boitier = boitier
        self.heure = heure
        self.detail = detail
    }
}

public struct DirectPiste: Codable, Sendable, Equatable {
    public var piste: String
    public var carriere: String
    public var chronoOK: Bool
    public var epreuve: String           // « 12 »
    public var nomEpreuve: String        // « Amateur 3 Préparatoire »
    public var partis: Int
    public var engages: Int
    public var finEstimee: Double?
    public var enPiste: CouplePiste?
    public var precedent: CouplePiste?
    public var suivant: CouplePiste?
    public var aRenvoyer: [PhotoARenvoyer]
    /// Noms des photos renvoyées et bien arrivées dans les 10 dernières minutes.
    public var bienArrivees: [String]
    public var mesPhotos: Int
    public var alerte: AlerteCodePiste?
    /// Petite info en bas (« #12_02 : aucune photo reçue »).
    public var info: String

    public init(piste: String, carriere: String = "", chronoOK: Bool = false, epreuve: String = "", nomEpreuve: String = "",
                partis: Int = 0, engages: Int = 0, finEstimee: Double? = nil, enPiste: CouplePiste? = nil,
                precedent: CouplePiste? = nil, suivant: CouplePiste? = nil, aRenvoyer: [PhotoARenvoyer] = [],
                bienArrivees: [String] = [], mesPhotos: Int = 0, alerte: AlerteCodePiste? = nil, info: String = "") {
        self.piste = piste
        self.carriere = carriere
        self.chronoOK = chronoOK
        self.epreuve = epreuve
        self.nomEpreuve = nomEpreuve
        self.partis = partis
        self.engages = engages
        self.finEstimee = finEstimee
        self.enPiste = enPiste
        self.precedent = precedent
        self.suivant = suivant
        self.aRenvoyer = aRenvoyer
        self.bienArrivees = bienArrivees
        self.mesPhotos = mesPhotos
        self.alerte = alerte
        self.info = info
    }
}

public struct MessagePiste: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var qui: String            // « Tom », « Stand »
    public var piste: String          // piste de l'auteur (vide pour le stand)
    public var texte: String
    public var heure: Double
    /// Vide : tout le monde. Sinon le nom du destinataire.
    public var pour: String
    /// Vrai : bouton INCIDENT (le Mac propose « Voir les photos de ce moment »).
    public var incident: Bool

    public init(id: String = UUID().uuidString, qui: String, piste: String, texte: String, heure: Double,
                pour: String = "", incident: Bool = false) {
        self.id = id
        self.qui = qui
        self.piste = piste
        self.texte = texte
        self.heure = heure
        self.pour = pour
        self.incident = incident
    }

    /// Ce message est-il pour cette personne ?
    public func pourPersonne(_ nom: String) -> Bool {
        pour.isEmpty || pour == nom || qui == nom
    }
}

// MARK: - Une ligne de JSON par message

/// Découpe le flux reçu en messages (une ligne de JSON chacun).
public struct Trames {
    private var tampon = Data()
    public init() {}

    public static func encoder<T: Encodable>(_ v: T) -> Data? {
        guard var d = try? JSONEncoder().encode(v) else { return nil }
        d.append(0x0A)
        return d
    }

    /// Ajoute ce qui vient d'arriver ; rend les messages complets. Une ligne illisible est ignorée.
    public mutating func recevoir<T: Decodable>(_ d: Data, comme: T.Type) -> [T] {
        tampon.append(d)
        var sortie: [T] = []
        while let i = tampon.firstIndex(of: 0x0A) {
            let ligne = tampon[tampon.startIndex..<i]
            tampon.removeSubrange(tampon.startIndex...i)
            if let v = try? JSONDecoder().decode(T.self, from: ligne) { sortie.append(v) }
        }
        if tampon.count > 1_000_000 { tampon.removeAll() }    // jamais de ligne aussi longue : flux abîmé
        return sortie
    }
}

// MARK: - Écran verrouillé de l'iPhone (Live Activity)

/// Ce que montre le bloc Groom Pix sur l'écran verrouillé et dans la Dynamic Island.
/// Envoyé par le Mac au service d'Apple : court (Apple refuse plus de 4 Ko).
public struct EcranVerrouille: Codable, Sendable, Hashable {
    public var piste: String
    public var epreuve: String          // « 12 »
    public var nomEpreuve: String
    public var partis: Int
    public var engages: Int
    public var finEstimee: Double?
    public var code: String             // code du couple en piste, « #12_45 »
    public var cavalier: String
    public var cheval: String
    public var suivant: String          // « Cavalier · Cheval »
    /// Code à mettre quand l'alerte « CHANGE TON CODE » est levée.
    public var alerte: String?
    public var aRenvoyer: Int
    public var chronoOK: Bool

    public init(piste: String, epreuve: String = "", nomEpreuve: String = "", partis: Int = 0, engages: Int = 0,
                finEstimee: Double? = nil, code: String = "", cavalier: String = "", cheval: String = "",
                suivant: String = "", alerte: String? = nil, aRenvoyer: Int = 0, chronoOK: Bool = false) {
        self.piste = piste
        self.epreuve = epreuve
        self.nomEpreuve = nomEpreuve
        self.partis = partis
        self.engages = engages
        self.finEstimee = finEstimee
        self.code = code
        self.cavalier = cavalier
        self.cheval = cheval
        self.suivant = suivant
        self.alerte = alerte
        self.aRenvoyer = aRenvoyer
        self.chronoOK = chronoOK
    }

    public init(_ d: DirectPiste) {
        self.init(piste: d.piste, epreuve: d.epreuve, nomEpreuve: String(d.nomEpreuve.prefix(60)),
                  partis: d.partis, engages: d.engages, finEstimee: d.finEstimee,
                  code: d.enPiste?.code ?? "", cavalier: String((d.enPiste?.cavalier ?? "").prefix(50)),
                  cheval: String((d.enPiste?.cheval ?? "").prefix(50)),
                  suivant: d.suivant.map { String("\($0.cavalier) · \($0.cheval)".prefix(80)) } ?? "",
                  alerte: d.alerte?.attendu, aRenvoyer: d.aRenvoyer.count, chronoOK: d.chronoOK)
    }

    /// Avancement de l'épreuve, de 0 à 1.
    public var avancement: Double { engages > 0 ? min(max(Double(partis) / Double(engages), 0), 1) : 0 }
}
