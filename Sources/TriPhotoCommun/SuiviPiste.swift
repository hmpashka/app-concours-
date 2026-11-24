import Foundation

/// Ce qui se passe sur une piste, d'après les passages du chrono : épreuve en cours, couples partis, rythme,
/// heure de fin estimée, précédent / en piste / suivant. Sert à l'écran Direct de l'app Piste et à l'accueil du Mac.
public struct SuiviPiste: Sendable, Equatable {
    public var epreuve: String = ""
    public var nomEpreuve: String = ""
    public var carriere: String = ""
    public var partis = 0
    public var engages = 0
    /// Secondes par couple (médiane des 30 dernières minutes), si assez de passages.
    public var secondesParCouple: Double?
    public var finEstimee: Double?
    public var enPiste: Passage?
    public var precedent: Passage?
    public var suivant: Engage?
    /// Début de l'épreuve en cours sur cette piste (premier passage de la série en cours).
    public var debutEpreuve: Double?

    public init() {}

    /// `source` : la piste telle que le chrono la nomme. `maintenant` : heure du chrono.
    public static func calculer(source: String, passages: [Passage], concours: Concours?, maintenant: Double) -> SuiviPiste {
        var s = SuiviPiste()
        let ps = passages.filter { $0.source == source }.sorted { $0.debut < $1.debut }
        guard let dernier = ps.last else { return s }
        s.enPiste = dernier
        s.carriere = dernier.carriere
        let e = CodePassage.cle(dernier.epreuve)
        s.epreuve = dernier.epreuve
        let ep = concours?.epreuve(numero: dernier.epreuve)
        s.nomEpreuve = ep?.nom ?? ""
        // série en cours : les passages de la même épreuve, à la suite, en partant de la fin
        var serie: [Passage] = []
        for p in ps.reversed() {
            if CodePassage.cle(p.epreuve) == e { serie.insert(p, at: 0) } else { break }
        }
        s.debutEpreuve = serie.first?.debut
        if ps.count >= 2 { s.precedent = ps[ps.count - 2] }
        let partis = Set(ps.filter { CodePassage.cle($0.epreuve) == e }.map { CodePassage.cle($0.dossard) })
        s.partis = partis.count
        s.engages = max(ep?.nombreAnnonce ?? 0, ep?.engages.count ?? 0, s.partis)

        // rythme : écart entre deux entrées en piste, médiane des 30 dernières minutes (pauses de plus de 10 min ignorées)
        let debuts = serie.map(\.debut)
        func ecarts(_ l: [Double]) -> [Double] {
            zip(l.dropFirst(), l).map { $0 - $1 }.filter { $0 > 5 && $0 < 600 }
        }
        var g = ecarts(debuts.filter { $0 >= maintenant - 1800 })
        if g.count < 2 { g = ecarts(Array(debuts.suffix(12))) }
        if g.count >= 2 {
            let t = g.sorted()
            let m = t.count % 2 == 1 ? t[t.count / 2] : (t[t.count / 2 - 1] + t[t.count / 2]) / 2
            s.secondesParCouple = m
            let restants = Double(max(0, s.engages - s.partis))
            s.finEstimee = max(dernier.debut + m * (restants + 1), maintenant + m * restants)
        }

        // suivant : dans l'ordre du fichier FFE, le premier engagé après celui en piste qui n'est pas encore parti
        if let ep {
            let l = ep.engages
            let i = l.firstIndex { CodePassage.cle($0.dossard) == CodePassage.cle(dernier.dossard) }
            let apres = i.map { Array(l[(l.index(after: $0))...]) + Array(l[..<$0]) } ?? l
            s.suivant = apres.first { !partis.contains(CodePassage.cle($0.dossard)) }
        }
        return s
    }

    /// Alerte « CHANGE TON CODE » : l'épreuve a changé sur la piste, mais les dernières photos du boîtier portent
    /// encore le code d'une autre épreuve. `photos` : code du photographe et heure (chrono) des dernières photos
    /// de ce boîtier, dans n'importe quel ordre. 30 s de grâce après le début de l'épreuve ; il faut 2 photos de
    /// suite au moins (une photo isolée ne déclenche rien).
    public static func alerteCode(boitier: String, photos: [(code: String, prise: Double)], suivi: SuiviPiste) -> AlerteCodePiste? {
        guard let p = suivi.enPiste, let debut = suivi.debutEpreuve else { return nil }
        let e = CodePassage.cle(p.epreuve)
        let apres = photos.filter { $0.prise >= debut + 30 }.sorted { $0.prise < $1.prise }
        func mauvais(_ c: String) -> Bool {
            guard let k = CodePassage.lire(c) else { return false }          // sans code : autre souci (_00)
            return k.special == nil && k.epreuve != e
        }
        let fin = Array(apres.suffix(3))
        guard fin.count >= 2, fin.allSatisfy({ mauvais($0.code) }), let derniere = fin.last else { return nil }
        let ancien = CodePassage.lire(derniere.code)?.texte ?? derniere.code
        return AlerteCodePiste(boitier: boitier, ancien: ancien, attendu: p.code.texte,
                               photos: apres.filter { mauvais($0.code) }.count)
    }
}
