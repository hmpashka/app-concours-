import Foundation

/// Un passage en piste, tel que le chrono (HM Timing, ou la capture Horse & Comp) le donne.
/// Les heures sont en secondes depuis 1970, sur l'horloge du chrono.
public struct Passage: Codable, Hashable, Sendable {
    /// Piste (« source » du chrono) : deux pistes en même temps ne se mélangent pas.
    public var source: String
    public var carriere: String
    public var epreuve: String
    public var dossard: String
    public var cavalier: String
    public var cheval: String
    /// Premier appel en piste par le jury (la piste est au couple dès ce moment).
    public var entree: Double?
    /// Départ (cellule ou chrono lancé).
    public var depart: Double
    /// Arrivée (cellule), si connue.
    public var fin: Double?
    /// Le jury avait d'abord appelé un autre cavalier : son dossard et l'heure de la correction.
    public var remplaceDossard: String?
    public var remplaceA: Double?

    public init(source: String, carriere: String = "", epreuve: String, dossard: String, cavalier: String = "",
                cheval: String = "", entree: Double? = nil, depart: Double, fin: Double? = nil,
                remplaceDossard: String? = nil, remplaceA: Double? = nil) {
        self.source = source
        self.carriere = carriere
        self.epreuve = epreuve
        self.dossard = dossard
        self.cavalier = cavalier
        self.cheval = cheval
        self.entree = entree
        self.depart = depart
        self.fin = fin
        self.remplaceDossard = remplaceDossard
        self.remplaceA = remplaceA
    }

    /// Début du passage : le premier appel en piste, sinon le départ.
    public var debut: Double { entree ?? depart }

    public var code: CodePassage { CodePassage(epreuve: epreuve, dossard: dossard) }

    /// Un passage lu dans la réponse de HM Timing (`/api/flux/passages`). Nil si l'essentiel manque.
    public static func depuisHM(_ d: [String: Any]) -> Passage? {
        func texte(_ k: String) -> String {
            if let s = d[k] as? String { return s }
            if let n = d[k] as? NSNumber { return n.stringValue }
            return ""
        }
        func nombre(_ k: String) -> Double? {
            if let n = d[k] as? NSNumber { return n.doubleValue }
            if let s = d[k] as? String { return Double(s) }
            return nil
        }
        guard let depart = nombre("depart"), !texte("dossard").isEmpty else { return nil }
        let r = d["remplace"] as? [String: Any]
        return Passage(source: texte("source"), carriere: texte("carriere"), epreuve: texte("epreuve"),
                       dossard: texte("dossard"), cavalier: texte("cavalier"), cheval: texte("cheval"),
                       entree: nombre("entree"), depart: depart, fin: nombre("fin"),
                       remplaceDossard: (r?["dossard"] as? String) ?? (r?["dossard"] as? NSNumber)?.stringValue,
                       remplaceA: (r?["a"] as? NSNumber)?.doubleValue)
    }
}
