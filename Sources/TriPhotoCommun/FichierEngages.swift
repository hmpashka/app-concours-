import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Une ligne du fichier des engagés (« fichier d'attribution ») : les 18 colonnes de l'ancien Excel des engagés,
/// dans l'ordre exact du CSV que HUGO utilise (« 26-11-24_LAMOTTE INDOOR.csv ») :
///
///     n° épreuve ; épreuve + jour ; date ; dossard ; NOM ; Prénom ; Cavalier ; ; ; club ; cheval ;
///     Cheval / Poney Titulaire ; ; « 9 ans » ; sexe ; robe ; race ;
public struct LigneEngage: Codable, Hashable, Sendable {
    public var epreuve: String
    public var nomEpreuve: String      // déjà nettoyé, avec le jour (« Preparatoire 110 m VEN »)
    public var date: String            // jj/mm/aaaa
    public var dossard: String
    public var nom: String
    public var prenom: String
    public var role = ""
    public var club = ""
    public var cheval = ""
    public var titulaire = ""
    public var age = ""
    public var sexe = ""
    public var robe = ""
    public var race = ""

    public init(epreuve: String, nomEpreuve: String, date: String, dossard: String, nom: String, prenom: String,
                role: String = "", club: String = "", cheval: String = "", titulaire: String = "", age: String = "",
                sexe: String = "", robe: String = "", race: String = "") {
        self.epreuve = epreuve
        self.nomEpreuve = nomEpreuve
        self.date = date
        self.dossard = dossard
        self.nom = nom
        self.prenom = prenom
        self.role = role
        self.club = club
        self.cheval = cheval
        self.titulaire = titulaire
        self.age = age
        self.sexe = sexe
        self.robe = robe
        self.race = race
    }

    /// Les 18 champs du CSV.
    public var champs: [String] {
        [epreuve, nomEpreuve, date, dossard, nom, prenom, role, "", "", club, cheval, titulaire, "", age, sexe, robe, race, ""]
            .map(FichierEngages.nettoyer)
    }
}

/// Une épreuve avec ses engagés, telle qu'elle ira dans le fichier.
public struct EpreuveEngages: Hashable, Sendable {
    public var numero: String
    public var nom: String             // nettoyé, avec le jour
    public var date: String            // jj/mm/aaaa
    public var engages: [LigneEngage]
}

/// Un couple ajouté sur le terrain : à la main dans l'app, ou vu par le chrono sans être dans le fichier FFE.
public struct EngageTerrain: Codable, Hashable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable { case main, chrono }
    public var id = UUID()
    public var epreuve: String
    public var dossard: String
    public var nom: String
    public var prenom: String
    public var cheval: String
    public var source: Source
    public var ajoute = Date()

    public init(epreuve: String, dossard: String, nom: String, prenom: String, cheval: String, source: Source) {
        self.epreuve = epreuve
        self.dossard = dossard
        self.nom = nom
        self.prenom = prenom
        self.cheval = cheval
        self.source = source
    }

    /// « Prénom NOM », comme les engagés du fichier FFE (mots-clés des photos).
    public var cavalier: String { [prenom, nom].filter { !$0.isEmpty }.joined(separator: " ") }

    /// Le chrono donne le cavalier en un seul texte : les mots tout en majuscules font le NOM, le reste le prénom.
    public static func couper(_ cavalier: String) -> (nom: String, prenom: String) {
        let mots = cavalier.split(separator: " ").map(String.init)
        let nom = mots.filter { $0 == $0.uppercased() && $0 != $0.lowercased() }
        let prenom = mots.filter { !($0 == $0.uppercased() && $0 != $0.lowercased()) }
        if nom.isEmpty || prenom.isEmpty, let dernier = mots.last {
            // Pas de majuscules pour s'y retrouver : le dernier mot est le nom.
            return (dernier, mots.dropLast().joined(separator: " "))
        }
        return (nom.joined(separator: " "), prenom.joined(separator: " "))
    }
}

/// Les deux fichiers des engagés (« fichiers d'attribution ») :
/// - au début du concours, fait à partir du fichier FFE (SIF ou FFE Compet), au format de l'ancien script
///   « creation fichier concours » : « ; », sans en-tête, fins de ligne Windows, sans accents ;
///   d'abord la ligne 80 « divers », puis pour chaque épreuve la ligne 00 « inconnu », les engagés et la ligne 99
///   « Remise des prix » ;
/// - à la clôture finale, au format « HMV » (en-tête TYPE;CHP1;…;CHP17; puis « HMV; » devant chaque ligne), avec en
///   plus les engagés terrain, rangés dans leur épreuve par dossard.
public enum FichierEngages {
    public static let fin = "\r\n"
    static let joursFR = ["DIM", "LUN", "MAR", "MER", "JEU", "VEN", "SAM"]     // dimanche = 1 pour Calendar

    // MARK: - Fichiers

    public static func debut(_ epreuves: [EpreuveEngages]) -> String {
        lignes(epreuves, terrain: []).map { $0.joined(separator: ";") + fin }.joined()
    }

    public static func cloture(_ epreuves: [EpreuveEngages], terrain: [EngageTerrain]) -> String {
        let entete = (["TYPE"] + (1...17).map { "CHP\($0)" }).joined(separator: ";") + ";" + fin
        return entete + lignes(epreuves, terrain: terrain).map { "HMV;" + $0.joined(separator: ";") + fin }.joined()
    }

    /// Les lignes (18 champs chacune) : 80 divers, puis par épreuve 00, engagés (et engagés terrain), 99.
    public static func lignes(_ epreuves: [EpreuveEngages], terrain: [EngageTerrain]) -> [[String]] {
        var sortie: [[String]] = [["80", "divers", "", "00", "divers"] + Array(repeating: "", count: 13)]
        var parEpreuve: [String: [EngageTerrain]] = [:]
        for t in terrain { parEpreuve[CodePassage.cle(t.epreuve), default: []].append(t) }
        for e in epreuves.sorted(by: { ordre($0.numero, $1.numero) }) {
            var engages = e.engages
            for t in parEpreuve[CodePassage.cle(e.numero)] ?? [] {
                // Un dossard déjà dans le fichier FFE n'est pas ajouté une deuxième fois.
                if engages.contains(where: { CodePassage.cle($0.dossard.replacingOccurrences(of: " HC", with: "")) == CodePassage.cle(t.dossard) }) { continue }
                engages.append(LigneEngage(epreuve: e.numero, nomEpreuve: e.nom, date: e.date, dossard: t.dossard,
                                           nom: t.nom.uppercased(), prenom: prenomPropre(t.prenom), role: "Cavalier",
                                           cheval: t.cheval.uppercased(), titulaire: "Cheval / Poney Titulaire"))
            }
            guard !engages.isEmpty else { continue }      // comme l'Excel : une épreuve sans engagé n'y est pas
            engages.sort { ordre($0.dossard, $1.dossard) }
            let tete = [e.numero, e.nom, e.date]
            sortie.append((tete + ["00", "inconnu \(e.nom)"] + Array(repeating: "", count: 13)).map(nettoyer))
            sortie.append(contentsOf: engages.map(\.champs))
            sortie.append((tete + ["99", "Remise des prix \(e.nom)"] + Array(repeating: "", count: 13)).map(nettoyer))
        }
        return sortie
    }

    /// Nom du fichier, comme HUGO le fait : « 26-11-22_LAMOTTE INDOOR.csv » (aa-mm-jj du DERNIER jour du concours).
    public static func nomFichier(concours: String, dernierJour: Date?, suffixe: String = "") -> String {
        var debut = ""
        if let d = dernierJour {
            let f = DateFormatter()
            f.locale = Locale(identifier: "fr_FR")
            f.dateFormat = "yy-MM-dd"
            debut = f.string(from: d) + "_"
        }
        let nom = NomDossier.nettoyer(nettoyer(concours).uppercased())
        return debut + (nom.isEmpty ? "CONCOURS" : nom) + suffixe + ".csv"
    }

    // MARK: - Nettoyage (repris de l'ancien script)

    /// Sans ( ) , ni « SO - », sans accents (le fichier est lu par des logiciels qui ne les aiment pas), et sans
    /// « ; » ni retour à la ligne qui casseraient les colonnes.
    public static func nettoyer(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "(HC)", with: "")
        for c in ["(", ")", ",", ";", "\r", "\n", "\t"] { t = t.replacingOccurrences(of: c, with: c == "\n" || c == "\t" ? " " : "") }
        t = t.replacingOccurrences(of: "SO -", with: "")
        t = t.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        t = t.replacingOccurrences(of: "œ", with: "oe").replacingOccurrences(of: "Œ", with: "OE")
            .replacingOccurrences(of: "æ", with: "ae").replacingOccurrences(of: "’", with: "'")
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// « MELINDA » ou « jean-paul » → « Melinda », « Jean-Paul ».
    public static func prenomPropre(_ s: String) -> String {
        var sortie = ""
        var debutMot = true
        for ch in s.lowercased() {
            sortie += debutMot ? String(ch).uppercased() : String(ch)
            debutMot = ch == " " || ch == "-" || ch == "'"
        }
        return sortie
    }

    /// « VEN » pour une date AAAA-MM-JJ.
    static func jour(_ iso: String) -> String {
        guard let d = dateISO(iso) else { return "" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return joursFR[cal.component(.weekday, from: d) - 1]
    }

    public static func dateISO(_ iso: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(iso.prefix(10)))
    }

    /// AAAA-MM-JJ → jj/mm/aaaa.
    static func dateFR(_ iso: String) -> String {
        let p = iso.prefix(10).split(separator: "-")
        guard p.count == 3 else { return iso }
        return "\(p[2])/\(p[1])/\(p[0])"
    }

    /// Ordre naturel : « 2 » avant « 10 », « 5 » avant « 5A ».
    static func ordre(_ a: String, _ b: String) -> Bool {
        let na = Int(a.prefix(while: \.isNumber)) ?? Int.max
        let nb = Int(b.prefix(while: \.isNumber)) ?? Int.max
        return na != nb ? na < nb : a < b
    }
}

/// Lecture des engagés du fichier FFE avec tout ce que le fichier d'attribution demande (club, âge, sexe, robe,
/// race…). Les deux exports sont acceptés : FFE Compet (« equide_age », « sexe="Hongre" », « role ») et SIF (âge
/// calculé depuis la naissance, sexe en une lettre).
public enum LecteurEngagesFFE {
    public static func lire(fichier url: URL) throws -> [EpreuveEngages] {
        try lire(Data(contentsOf: url))
    }

    public static func lire(_ donnees: Data) throws -> [EpreuveEngages] {
        let l = LecteurEngages()
        let parser = XMLParser(data: donnees)
        parser.delegate = l
        if !parser.parse() {
            throw LecteurFFE.Erreur.illisible(parser.parserError?.localizedDescription ?? "erreur inconnue")
        }
        guard l.vuConcours else { throw LecteurFFE.Erreur.pasUnConcoursFFE }
        return l.epreuves
    }

    /// Sexe du SIF (une lettre) en toutes lettres, comme l'export FFE Compet.
    static func sexe(_ s: String) -> String {
        switch s.uppercased() {
        case "H": return "Hongre"
        case "F", "J": return "Jument"
        case "M", "E": return "Etalon"
        default: return s
        }
    }
}

private final class LecteurEngages: NSObject, XMLParserDelegate {
    var vuConcours = false
    var epreuves: [EpreuveEngages] = []
    private var pile: [String] = []
    private var epreuve: EpreuveEngages?
    private var dateIso = ""
    private var ligne: LigneEngage?
    private var vuClubCavalier = false

    private func propre(_ v: String?) -> String { (v ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes a: [String: String] = [:]) {
        let balise = elementName.split(separator: ":").last.map(String.init) ?? elementName
        let parent = pile.last
        pile.append(balise)
        switch (balise, parent) {
        case ("concours", "message"?):
            vuConcours = true
        case ("epreuve", "concours"?):
            dateIso = propre(a["date"])
            let nomBrut = propre(a["nom_categorie"]).isEmpty ? propre(a["nom_epreuve"]) : propre(a["nom_categorie"])
            // comme l'Excel : « Amateur 1 - Grand Prix (1,20 m) » → « Amateur 1 Grand Prix 120 m »
            var nom = FichierEngages.nettoyer(nomBrut.replacingOccurrences(of: " - ", with: " "))
            let j = FichierEngages.jour(dateIso)
            if !j.isEmpty && !nom.hasSuffix(" " + j) { nom += " " + j }
            epreuve = EpreuveEngages(numero: propre(a["num"]), nom: nom, date: FichierEngages.dateFR(dateIso), engages: [])
        case ("engagement", "epreuve"?) where epreuve != nil:
            vuClubCavalier = false
            let role = propre(a["role"])
            // hors classement : « 12 HC », comme dans l'Excel des engagés
            let hc = a["hors_classement"] == "1" && !propre(a["dossard"]).isEmpty
            ligne = LigneEngage(epreuve: epreuve!.numero, nomEpreuve: epreuve!.nom, date: epreuve!.date,
                                dossard: propre(a["dossard"]) + (hc ? " HC" : ""), nom: "", prenom: "",
                                role: role.isEmpty ? "Cavalier" : role, titulaire: "Cheval / Poney Titulaire")
        case ("cavalier", "engagement"?) where ligne != nil:
            ligne?.nom = propre(a["nom"]).uppercased()
            ligne?.prenom = FichierEngages.prenomPropre(propre(a["prenom"]))
            let club = propre(a["nom_club"])
            if !club.isEmpty { ligne?.club = club; vuClubCavalier = true }
        case ("club", "engagement"?) where ligne != nil && !vuClubCavalier:
            ligne?.club = propre(a["nom"])
        case ("equide", "engagement"?) where ligne != nil:
            ligne?.cheval = propre(a["nom"])
            ligne?.sexe = LecteurEngagesFFE.sexe(propre(a["sexe"]))
            ligne?.robe = propre(a["robe"])
            ligne?.race = propre(a["code_race"])
            if let age = Int(propre(a["equide_age"])) {
                ligne?.age = "\(age) ans"
            } else if let an = Int(propre(a["dnaiss"]).prefix(4)), let anEp = Int(dateIso.prefix(4)), anEp >= an {
                ligne?.age = "\(anEp - an) ans"       // âge FFE : année du concours − année de naissance
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let balise = pile.popLast()
        let parent = pile.last
        switch (balise, parent) {
        case ("engagement"?, "epreuve"?):
            if let l = ligne, !l.dossard.isEmpty { epreuve?.engages.append(l) }
            ligne = nil
        case ("epreuve"?, "concours"?):
            if let e = epreuve { epreuves.append(e) }
            epreuve = nil
        default:
            break
        }
    }
}
