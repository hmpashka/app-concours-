import Foundation

// Commandes de pack photo : listings d'engagés gardés concours par concours, recherche d'un client (nom, prénom
// ou cheval), commande avec prix calculé (pack du couple + cheval de plus), sur le Mac et sur les iPhone.

/// Prix d'un concours : le pack = toutes les photos d'un couple cavalier + cheval sur ce concours ;
/// chaque cheval de plus du même cavalier ajoute `chevalEnPlus`. Modifiables concours par concours.
public struct TarifConcours: Codable, Sendable, Equatable, Hashable {
    public var pack: Double
    public var chevalEnPlus: Double

    public static let parDefaut = TarifConcours(pack: 120, chevalEnPlus: 10)

    public init(pack: Double, chevalEnPlus: Double) {
        self.pack = pack
        self.chevalEnPlus = chevalEnPlus
    }

    /// 1 cheval : le pack ; 2 chevaux : pack + 1 cheval de plus ; 0 : rien.
    public func prix(chevaux n: Int) -> Double {
        n <= 0 ? 0 : pack + Double(n - 1) * chevalEnPlus
    }
}

/// Un couple d'un listing.
public struct CoupleListing: Codable, Sendable, Equatable, Hashable {
    public var epreuve: String
    public var nomEpreuve: String
    public var dossard: String
    public var nom: String
    public var prenom: String
    public var cheval: String
    /// Classement dans l'épreuve (résultats FFE), vide si pas classé ou pas encore connu.
    public var classement: String
    public var terrain: Bool

    public init(epreuve: String, nomEpreuve: String, dossard: String, nom: String, prenom: String, cheval: String,
                classement: String = "", terrain: Bool = false) {
        self.epreuve = epreuve
        self.nomEpreuve = nomEpreuve
        self.dossard = dossard
        self.nom = nom
        self.prenom = prenom
        self.cheval = cheval
        self.classement = classement
        self.terrain = terrain
    }

    public var cavalier: String { [nom, prenom].filter { !$0.isEmpty }.joined(separator: " ") }
}

/// Le listing d'un concours, gardé pour toujours (un fichier par concours).
public struct ListingConcours: Codable, Sendable, Equatable, Identifiable {
    public var id: String              // numéro FFE du concours, sinon son nom nettoyé
    public var nom: String
    public var debut: String           // jj/mm/aaaa
    public var fin: String
    public var couples: [CoupleListing]
    public var tarif: TarifConcours
    public var majLe: Date

    public init(id: String, nom: String, debut: String, fin: String, couples: [CoupleListing],
                tarif: TarifConcours = .parDefaut, majLe: Date = Date()) {
        self.id = id
        self.nom = nom
        self.debut = debut
        self.fin = fin
        self.couples = couples
        self.tarif = tarif
        self.majLe = majLe
    }

    /// « Lamotte Indoor · 20-22/11/2026 »
    public var titre: String {
        guard !debut.isEmpty else { return nom }
        if debut == fin || fin.isEmpty { return "\(nom) · \(debut)" }
        let d = debut.split(separator: "/"), f = fin.split(separator: "/")
        if d.count == 3, f.count == 3, d[1] == f[1], d[2] == f[2] { return "\(nom) · \(d[0])-\(fin)" }
        return "\(nom) · \(debut) au \(fin)"
    }

    /// Le cavalier était-il à la remise des prix ? Vrai s'il est classé ; faux si l'épreuve a des résultats et qu'il
    /// n'y est pas ; nil sans résultats (à dire à la main).
    public func remise(_ c: CoupleListing) -> Bool? {
        if let n = Int(c.classement.trimmingCharacters(in: .whitespaces)), n > 0 { return true }
        let resultats = couples.contains { $0.epreuve == c.epreuve && Int($0.classement.trimmingCharacters(in: .whitespaces)) ?? 0 > 0 }
        return resultats ? false : nil
    }

    /// Fait depuis le fichier FFE (et les engagés terrain). Le tarif d'un listing déjà gardé est repris tel quel.
    public static func depuis(_ epreuves: [EpreuveEngages], terrain: [EngageTerrain] = [], id: String, nom: String,
                              tarif: TarifConcours = .parDefaut) -> ListingConcours {
        var couples: [CoupleListing] = []
        for e in epreuves {
            for l in e.engages {
                couples.append(CoupleListing(epreuve: e.numero, nomEpreuve: e.nom, dossard: l.dossard, nom: l.nom,
                                             prenom: l.prenom, cheval: l.cheval, classement: l.classement))
            }
        }
        for t in terrain {
            let ep = epreuves.first { CodePassage.cle($0.numero) == CodePassage.cle(t.epreuve) }
            let deja = couples.contains { CodePassage.cle($0.epreuve) == CodePassage.cle(t.epreuve)
                && CodePassage.cle($0.dossard) == CodePassage.cle(t.dossard) }
            if deja { continue }
            couples.append(CoupleListing(epreuve: ep?.numero ?? t.epreuve, nomEpreuve: ep?.nom ?? "", dossard: t.dossard,
                                         nom: t.nom.uppercased(), prenom: FichierEngages.prenomPropre(t.prenom),
                                         cheval: t.cheval.uppercased(), terrain: true))
        }
        let dates = epreuves.map(\.date).filter { !$0.isEmpty }
            .sorted { (FichierEngages.dateDepuisFR($0) ?? .distantPast) < (FichierEngages.dateDepuisFR($1) ?? .distantPast) }
        return ListingConcours(id: id, nom: nom, debut: dates.first ?? "", fin: dates.last ?? "", couples: couples, tarif: tarif)
    }
}

/// Un passage d'un client trouvé : un concours, une épreuve, un cheval.
public struct Participation: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { "\(concours)|\(epreuve)|\(dossard)|\(cheval)" }
    public var concours: String
    public var nomConcours: String
    public var epreuve: String
    public var nomEpreuve: String
    public var dossard: String
    public var cheval: String
    public var remise: Bool?
    /// Photos du couple sur le Mac (concours en cours seulement), nil sinon.
    public var photos: Int?

    public init(concours: String, nomConcours: String, epreuve: String, nomEpreuve: String, dossard: String,
                cheval: String, remise: Bool?, photos: Int? = nil) {
        self.concours = concours
        self.nomConcours = nomConcours
        self.epreuve = epreuve
        self.nomEpreuve = nomEpreuve
        self.dossard = dossard
        self.cheval = cheval
        self.remise = remise
        self.photos = photos
    }
}

/// Un client (cavalier) trouvé dans les listings, avec tous ses passages.
public struct ClientTrouve: Codable, Sendable, Equatable, Identifiable {
    public var id: String { Commandes.normaliser(nom + " " + prenom) }
    public var nom: String
    public var prenom: String
    public var participations: [Participation]
    /// Tarif de chaque concours (id du listing → tarif).
    public var tarifs: [String: TarifConcours]

    public init(nom: String, prenom: String, participations: [Participation], tarifs: [String: TarifConcours]) {
        self.nom = nom
        self.prenom = prenom
        self.participations = participations
        self.tarifs = tarifs
    }

    public var chevaux: [String] { Array(Set(participations.map(\.cheval))).sorted() }
    public var concours: [String] {
        var vus: [String] = []
        for p in participations where !vus.contains(p.concours) { vus.append(p.concours) }
        return vus
    }
}

/// Une commande de pack photo. Toujours pour UN concours (les concours sont séparés).
public struct Commande: Codable, Sendable, Equatable, Identifiable, Hashable {
    public enum Statut: String, Codable, Sendable, CaseIterable, Identifiable {
        case aFaire = "À faire", enCours = "En cours", envoye = "Envoyé"
        public var id: String { rawValue }
    }
    public enum Reglement: String, Codable, Sendable, CaseIterable, Identifiable {
        case cb = "CB", especes = "Espèces", cheque = "Chèque", virement = "Virement"
        public var id: String { rawValue }
    }
    public struct Ligne: Codable, Sendable, Equatable, Hashable {
        public var epreuve: String
        public var nomEpreuve: String
        public var dossard: String
        public var cheval: String
        /// À la remise des prix : vrai / faux, nil si personne ne sait.
        public var remise: Bool?
        public init(epreuve: String, nomEpreuve: String, dossard: String, cheval: String, remise: Bool?) {
            self.epreuve = epreuve
            self.nomEpreuve = nomEpreuve
            self.dossard = dossard
            self.cheval = cheval
            self.remise = remise
        }
    }

    public var id: String
    public var concours: String
    public var nomConcours: String
    public var nom: String
    public var prenom: String
    public var lignes: [Ligne]
    public var prix: Double
    public var telephone: String
    public var mail: String
    public var reglement: Reglement
    public var statut: Statut
    public var note: String
    public var creeeLe: Date
    public var majLe: Date
    /// Qui l'a prise (« Mac », « Léa »…).
    public var par: String

    public init(id: String = UUID().uuidString, concours: String, nomConcours: String, nom: String, prenom: String,
                lignes: [Ligne], prix: Double, telephone: String = "", mail: String = "", reglement: Reglement = .cb,
                statut: Statut = .aFaire, note: String = "", creeeLe: Date = Date(), majLe: Date = Date(), par: String = "") {
        self.id = id
        self.concours = concours
        self.nomConcours = nomConcours
        self.nom = nom
        self.prenom = prenom
        self.lignes = lignes
        self.prix = prix
        self.telephone = telephone
        self.mail = mail
        self.reglement = reglement
        self.statut = statut
        self.note = note
        self.creeeLe = creeeLe
        self.majLe = majLe
        self.par = par
    }

    public var client: String { [nom, prenom].filter { !$0.isEmpty }.joined(separator: " ") }
    public var chevaux: [String] { Array(Set(lignes.map(\.cheval))).sorted() }
    /// Remise des prix pour au moins une épreuve de la commande (nil si inconnue partout).
    public var remise: Bool? {
        if lignes.contains(where: { $0.remise == true }) { return true }
        return lignes.contains { $0.remise == nil } ? nil : false
    }

    /// « 120 € », « 130,50 € »
    public static func euros(_ x: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.numberStyle = .decimal
        f.minimumFractionDigits = x.rounded() == x ? 0 : 2
        f.maximumFractionDigits = 2
        return (f.string(from: NSNumber(value: x)) ?? "\(x)") + " €"
    }

    /// Une commande neuve pour un client, avec les passages choisis d'un même concours ; prix d'après le tarif.
    public static func nouvelle(_ client: ClientTrouve, choix: [Participation], par: String) -> Commande? {
        guard let c = choix.first?.concours else { return nil }
        let l = choix.filter { $0.concours == c }
        let tarif = client.tarifs[c] ?? .parDefaut
        let lignes = l.map { Ligne(epreuve: $0.epreuve, nomEpreuve: $0.nomEpreuve, dossard: $0.dossard, cheval: $0.cheval, remise: $0.remise) }
        let n = Set(l.map { normaliser($0.cheval) }).count
        return Commande(concours: c, nomConcours: l[0].nomConcours, nom: client.nom, prenom: client.prenom, lignes: lignes,
                        prix: tarif.prix(chevaux: n), par: par)
    }
}

public enum Commandes {
    /// Sans accents ni majuscules, espaces simples : « Loïc DURAND » → « loic durand ».
    public static func normaliser(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
            .replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "'", with: " ")
            .split(separator: " ").joined(separator: " ")
    }

    /// Clients dont le nom, le prénom ou un cheval commence par chaque mot tapé (« dur lor » trouve DURAND · LOREL).
    /// Les concours les plus récents d'abord. `photos` : nombre de photos par code « #17_12 » (concours en cours).
    public static func chercher(_ texte: String, dans listings: [ListingConcours], concoursEnCours: String = "",
                                photos: [String: Int] = [:], limite: Int = 30) -> [ClientTrouve] {
        let mots = normaliser(texte).split(separator: " ").map(String.init)
        guard !mots.isEmpty, mots.joined().count >= 2 else { return [] }
        let tries = listings.sorted { (FichierEngages.dateDepuisFR($0.fin) ?? $0.majLe) > (FichierEngages.dateDepuisFR($1.fin) ?? $1.majLe) }
        var parClient: [String: ClientTrouve] = [:]
        var ordre: [String] = []
        for l in tries {
            for c in l.couples {
                let cleCavalier = normaliser(c.nom + " " + c.prenom)
                let mesMots = (cleCavalier + " " + normaliser(c.cheval)).split(separator: " ")
                guard mots.allSatisfy({ m in mesMots.contains { $0.hasPrefix(m) } }) else { continue }
                // un cavalier trouvé par son cheval : on garde tous ses passages, pas seulement ce cheval
                if parClient[cleCavalier] == nil {
                    parClient[cleCavalier] = ClientTrouve(nom: c.nom, prenom: c.prenom, participations: [], tarifs: [:])
                    ordre.append(cleCavalier)
                }
            }
        }
        guard !ordre.isEmpty else { return [] }
        for l in tries {
            for c in l.couples {
                let cle = normaliser(c.nom + " " + c.prenom)
                guard parClient[cle] != nil else { continue }
                let code = CodePassage(epreuve: c.epreuve, dossard: c.dossard).texte
                let p = Participation(concours: l.id, nomConcours: l.titre, epreuve: c.epreuve, nomEpreuve: c.nomEpreuve,
                                      dossard: c.dossard, cheval: c.cheval, remise: l.remise(c),
                                      photos: l.id == concoursEnCours ? (photos[code] ?? 0) : nil)
                if !(parClient[cle]!.participations.contains(p)) { parClient[cle]!.participations.append(p) }
                parClient[cle]!.tarifs[l.id] = l.tarif
            }
        }
        return Array(ordre.prefix(limite).compactMap { parClient[$0] })
    }
}
