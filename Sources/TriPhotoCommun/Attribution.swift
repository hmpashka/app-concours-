import Foundation

/// À quel passage appartient une photo, et faut-il proposer un autre code que celui du photographe ?
///
/// Règles (reprises de la v00, validées par HUGO) :
/// - la piste est au couple dès son premier appel en piste, jusqu'à son arrivée + `apres` secondes (fin de tour),
///   et au plus jusqu'à l'entrée du suivant ;
/// - quelques secondes de latence sont tolérées au changement de couple : une photo prise juste après l'entrée du
///   suivant, qui porte le code du précédent, est gardée ;
/// - une photo plus récente que tout ce que le chrono connaît attend (le couple n'est peut-être pas encore parti) ;
/// - aucune correction n'est jamais appliquée seule : une proposition va dans « À valider ».
public enum Attribution {
    /// Où tombe la photo sur une piste.
    public struct Place: Equatable, Sendable {
        public var passage: Passage
        public var debut: Double
        public var limite: Double?        // nil : dernier passage connu, sans arrivée
        public var precedent: Passage?
    }

    public enum Resultat: Equatable, Sendable {
        case trouve([Place])              // une place par piste où la photo tombe dans un passage
        case attente(voisin: Passage?)
        case entre(voisin: Passage?)
    }

    /// Les passages où tombe une photo prise à `t` (horloge du chrono).
    public static func placer(t: Double, passages: [Passage], apres: Double = 15) -> Resultat {
        var parPiste: [String: [Passage]] = [:]
        for p in passages { parPiste[p.source, default: []].append(p) }
        var trouves: [Place] = []
        var voisin: Passage?
        var ecartVoisin = Double.infinity
        var attente = false
        for (_, liste0) in parPiste {
            let liste = liste0.sorted { $0.debut < $1.debut }
            for (i, p) in liste.enumerated() {
                let debut = p.debut
                let suivant = i + 1 < liste.count ? liste[i + 1] : nil
                var limite = p.fin.map { $0 + apres }
                if let s = suivant { limite = min(limite ?? s.debut, s.debut) }
                let ecart: Double
                if t < debut {
                    ecart = debut - t
                } else if limite == nil || t <= limite! {
                    trouves.append(Place(passage: p, debut: debut, limite: limite, precedent: i > 0 ? liste[i - 1] : nil))
                    continue
                } else {
                    ecart = t - limite!
                    if suivant == nil { attente = true }
                }
                if ecart < ecartVoisin { voisin = p; ecartVoisin = ecart }
            }
        }
        if !trouves.isEmpty { return .trouve(trouves) }
        return attente ? .attente(voisin: voisin) : .entre(voisin: voisin)
    }

    // MARK: - Décision pour une photo

    public enum Decision: Equatable, Sendable {
        /// Le code du photographe est juste (ou il n'y a rien à redire) : la photo part.
        case conforme(raison: String)
        /// Rien à proposer (entre deux passages, piste inconnue…) : la photo part avec son code.
        case garder(raison: String)
        /// Le chrono n'a pas encore l'information : redemander dans quelques secondes.
        case attendre(raison: String)
        /// Le chrono donne un autre couple : proposition à valider (jamais appliquée seule).
        case proposer(code: CodePassage, raison: String, confiance: Int, passage: Passage)
    }

    /// - Parameters:
    ///   - code: code du photographe (nil : pas de code).
    ///   - t: heure de la photo sur l'horloge du chrono.
    ///   - piste: piste déjà connue pour ce boîtier (apprise sur ses photos conformes), pour départager deux pistes.
    ///   - latence: secondes tolérées après l'entrée du couple suivant.
    public static func decider(code: CodePassage?, t: Double, passages: [Passage], apres: Double = 15,
                               latence: Double = 5, piste: String? = nil) -> Decision {
        if code?.special == .remiseDesPrix { return .conforme(raison: "Remise des prix") }
        switch placer(t: t, passages: passages, apres: apres) {
        case .attente:
            return .attendre(raison: "Le chrono n'a pas encore ce passage")
        case .entre(let voisin):
            if let code, let v = voisin, code == v.code { return .conforme(raison: "Fin de tour") }
            return .garder(raison: "Prise entre deux passages")
        case .trouve(let places):
            // Plusieurs pistes en même temps : la piste du boîtier, sinon celle de l'épreuve du code.
            var place: Place?
            if places.count == 1 {
                place = places[0]
            } else if let piste, let p = places.first(where: { $0.passage.source == piste }) {
                place = p
            } else if let code, let p = places.first(where: { CodePassage.cle($0.passage.epreuve) == code.epreuve }) {
                place = p
            }
            guard let pl = place else { return .garder(raison: "Plusieurs pistes en piste à ce moment") }
            let p = pl.passage
            if let code, code == p.code { return .conforme(raison: "Le chrono donne le même couple") }
            // Latence : juste après l'entrée du suivant, le code du précédent est normal.
            if let code, let prec = pl.precedent, code == prec.code, t - pl.debut <= latence {
                return .conforme(raison: "Changement de couple (latence)")
            }
            // Fin de tour du précédent : déjà couvert par la limite (arrivée + `apres`).
            let marge = min(t - pl.debut, pl.limite.map { $0 - t } ?? .infinity)
            var confiance = marge > 10 ? 95 : marge > 3 ? 80 : 60
            let heure = Attribution.heure(t)
            let raison: String
            if let code, let r = p.remplaceDossard, code == CodePassage(epreuve: p.epreuve, dossard: r) {
                raison = "Le jury a remplacé le n° \(r) par le n° \(p.dossard)"
                confiance = max(confiance, 90)
            } else if code == nil {
                raison = "Pas de code ; le chrono donne le n° \(p.dossard) en piste à \(heure)"
            } else if code?.special == .inconnu {
                raison = "Code _00 ; le chrono donne le n° \(p.dossard) en piste à \(heure)"
            } else if let code, code.epreuve != CodePassage.cle(p.epreuve) {
                raison = "Le chrono donne l'épreuve \(p.epreuve), n° \(p.dossard), à \(heure) : code d'épreuve à changer ?"
                confiance = min(confiance, 80)
            } else {
                raison = "Le chrono donne le n° \(p.dossard) en piste à \(heure)"
            }
            return .proposer(code: p.code, raison: raison, confiance: confiance, passage: p)
        }
    }

    static func heure(_ t: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date(timeIntervalSince1970: t))
    }
}
