import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Lecture du fichier de concours FFE. Les deux exports ont la même structure XML :
///
///     <ffe:message version="1.6">                      (SIF ; « 1 » pour FFE Compet)
///       <concours num nom …>
///         <epreuve num date nom_categorie [heure_debut="09h15" nom_piste nbr_engages] …>
///           <profil>…</profil>                         (ignoré : il contient aussi des balises <engagement>)
///           <engagement id dossard [hors_classement="1"]>
///             <cavalier nom prenom …/> <equide nom …/>
///           </engagement>
///         </epreuve>
///       </concours>
///     </ffe:message>
///
/// Le format est reconnu tout seul : FFE Compet si le message est en version 1, si une épreuve a une heure de
/// début ou un nombre d'engagés, ou si le nom du fichier fait 9 chiffres ; SIF sinon.
public enum LecteurFFE {
    public enum Erreur: Error, LocalizedError, Equatable {
        case illisible(String)
        case pasUnConcoursFFE

        public var errorDescription: String? {
            switch self {
            case .illisible(let detail): return "Fichier XML illisible : \(detail)"
            case .pasUnConcoursFFE: return "Ce n'est pas un fichier de concours FFE (balise <concours> absente)."
            }
        }
    }

    public static func lire(fichier url: URL) throws -> Concours {
        let donnees = try Data(contentsOf: url)
        return try lire(donnees, nomFichier: url.lastPathComponent)
    }

    public static func lire(_ donnees: Data, nomFichier: String = "") throws -> Concours {
        let lecteur = Lecteur()
        let parser = XMLParser(data: donnees)
        parser.delegate = lecteur
        parser.shouldProcessNamespaces = false
        if !parser.parse() {
            let detail = parser.parserError?.localizedDescription ?? "erreur inconnue"
            throw Erreur.illisible(detail)
        }
        guard lecteur.vuConcours else { throw Erreur.pasUnConcoursFFE }

        let base = (nomFichier as NSString).deletingPathExtension
        let neufChiffres = base.count == 9 && base.allSatisfy(\.isNumber)
        let compet = lecteur.version == "1" || lecteur.vuHoraires || neufChiffres
        return Concours(numero: lecteur.numero, nom: lecteur.nom,
                        format: compet ? .ffeCompet : .sif, epreuves: lecteur.epreuves)
    }

    /// « 09h15 » ou « 9:15 » → « 09:15 » ; vide si absent ou illisible.
    public static func heure(_ texte: String?) -> String {
        guard let t = texte?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return "" }
        let morceaux = t.lowercased().split(whereSeparator: { $0 == "h" || $0 == ":" }).map(String.init)
        guard let h = morceaux.first.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }), (0...23).contains(h)
        else { return "" }
        var m = 0
        if morceaux.count > 1 {
            guard let mm = Int(morceaux[1].trimmingCharacters(in: .whitespaces)), (0...59).contains(mm) else { return "" }
            m = mm
        }
        return String(format: "%02d:%02d", h, m)
    }
}

private final class Lecteur: NSObject, XMLParserDelegate {
    var version = ""
    var numero = ""
    var nom = ""
    var vuConcours = false
    var vuHoraires = false
    var epreuves: [Epreuve] = []

    private var pile: [String] = []
    private var epreuve: Epreuve?
    private var engage: Engage?

    private func propre(_ v: String?) -> String { (v ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes a: [String: String] = [:]) {
        let nomBalise = elementName.split(separator: ":").last.map(String.init) ?? elementName
        let parent = pile.last
        pile.append(nomBalise)

        switch (nomBalise, parent) {
        case ("message", nil):
            version = propre(a["version"])
        case ("concours", "message"?):
            vuConcours = true
            numero = propre(a["num"])
            nom = propre(a["nom"])
        case ("epreuve", "concours"?):
            let heureDebut = a["heure_debut"]
            let annonce = Int(propre(a["nbr_engages"]))
            if heureDebut != nil || annonce != nil { vuHoraires = true }
            let nomEp = propre(a["nom_categorie"]).isEmpty ? propre(a["nom_epreuve"]) : propre(a["nom_categorie"])
            epreuve = Epreuve(numero: propre(a["num"]), nom: nomEp, date: propre(a["date"]),
                              heure: LecteurFFE.heure(heureDebut), piste: propre(a["nom_piste"]),
                              nombreAnnonce: annonce)
        case ("engagement", "epreuve"?) where epreuve != nil:
            engage = Engage(dossard: propre(a["dossard"]), cavalier: "", cheval: "",
                            horsClassement: a["hors_classement"] == "1")
        case ("cavalier", "engagement"?) where engage != nil:
            engage?.cavalier = [propre(a["prenom"]), propre(a["nom"])].filter { !$0.isEmpty }.joined(separator: " ")
        case ("equide", "engagement"?) where engage != nil:
            engage?.cheval = propre(a["nom"])
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let nomBalise = pile.popLast()
        let parent = pile.last
        switch (nomBalise, parent) {
        case ("engagement"?, "epreuve"?):
            if let e = engage, !e.dossard.isEmpty { epreuve?.engages.append(e) }
            engage = nil
        case ("epreuve"?, "concours"?):
            if let e = epreuve { epreuves.append(e) }
            epreuve = nil
        default:
            break
        }
    }
}
