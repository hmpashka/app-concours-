import Foundation

/// Les deux fichiers de concours que la FFE fournit. Tri-photo reconnaît tout seul lequel on lui donne.
public enum FormatFFE: String, Codable, Sendable {
    /// Export du SIF : « conc<numéro>.xml », ISO-8859-1, résultats et officiels, pas d'horaires.
    case sif = "SIF"
    /// Export FFE Compet : nom à 9 chiffres, UTF-8, heure de début et piste de chaque épreuve.
    case ffeCompet = "FFE Compet"
}

/// Un couple engagé dans une épreuve. Seuls le dossard, le cavalier et le cheval sont gardés :
/// ce sont les seules informations qui iront dans les mots-clés des photos.
public struct Engage: Codable, Hashable, Sendable {
    public var dossard: String
    public var cavalier: String
    public var cheval: String
    public var horsClassement: Bool
    /// Vrai pour un engagé ajouté sur le terrain (pas dans le fichier FFE d'origine).
    public var terrain: Bool

    public init(dossard: String, cavalier: String, cheval: String, horsClassement: Bool = false, terrain: Bool = false) {
        self.dossard = dossard
        self.cavalier = cavalier
        self.cheval = cheval
        self.horsClassement = horsClassement
        self.terrain = terrain
    }
}

public struct Epreuve: Codable, Hashable, Identifiable, Sendable {
    /// Numéro tel qu'écrit dans le fichier (« 01 », « 5A »…).
    public var numero: String
    public var nom: String
    /// Date au format AAAA-MM-JJ, si le fichier la donne.
    public var date: String
    /// Heure de début « HH:MM » (FFE Compet seulement), vide sinon.
    public var heure: String
    /// Nom de la piste (FFE Compet seulement), vide sinon.
    public var piste: String
    /// Nombre d'engagés annoncé par le fichier (FFE Compet), sinon nil.
    public var nombreAnnonce: Int?
    public var engages: [Engage]

    public var id: String { cle }

    /// Numéro ramené à la forme des codes : « 01 » → « 1 », « 5A » → « 5a ».
    public var cle: String { CodePassage.cle(numero) }

    /// Nom du dossier de l'épreuve sur le serveur local : « 08 Amateur 2 Grand Prix 1,15 m ».
    public var nomDossier: String { NomDossier.pourEpreuve(numero: numero, nom: nom) }

    public init(numero: String, nom: String, date: String = "", heure: String = "", piste: String = "",
                nombreAnnonce: Int? = nil, engages: [Engage] = []) {
        self.numero = numero
        self.nom = nom
        self.date = date
        self.heure = heure
        self.piste = piste
        self.nombreAnnonce = nombreAnnonce
        self.engages = engages
    }

    /// Le couple qui porte ce dossard dans l'épreuve, s'il existe.
    public func engage(dossard: String) -> Engage? {
        let d = CodePassage.cle(dossard)
        return engages.first { CodePassage.cle($0.dossard) == d }
    }
}

public struct Concours: Codable, Hashable, Sendable {
    public var numero: String
    public var nom: String
    public var format: FormatFFE
    public var epreuves: [Epreuve]

    public init(numero: String, nom: String, format: FormatFFE, epreuves: [Epreuve]) {
        self.numero = numero
        self.nom = nom
        self.format = format
        self.epreuves = epreuves
    }

    public var nombreEngages: Int { epreuves.reduce(0) { $0 + $1.engages.count } }

    /// L'épreuve d'un numéro (« 8 », « 08 » et « #08 » donnent la même).
    public func epreuve(numero: String) -> Epreuve? {
        let c = CodePassage.cle(numero.replacingOccurrences(of: "#", with: ""))
        return epreuves.first { $0.cle == c }
    }

    /// Cavalier et cheval d'un code de passage, pour les mots-clés IPTC. Nil pour _00, _99 ou un dossard inconnu.
    public func couple(pour code: CodePassage) -> Engage? {
        guard code.special == nil else { return nil }
        return epreuve(numero: code.epreuve)?.engage(dossard: code.dossard)
    }
}
