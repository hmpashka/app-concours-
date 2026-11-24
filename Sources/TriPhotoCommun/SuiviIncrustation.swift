import Foundation

/// Capture Horse & Comp : ce que l'on lit sur la page d'incrustation de Horses & Competitions (le bloc « en piste » :
/// épreuve, dossard, cavalier, cheval, temps, points) devient une liste de passages, comme ceux de HM Timing.
/// Reprend les règles du suivi externe de HM Timing : le texte doit rester le même 2 lectures de suite (≈ 1 s)
/// avant d'agir ; l'arrivée est notée quand le temps affiché ne bouge plus.
public struct SuiviIncrustation: Sendable {
    public static let zonesConnues = ["dossard", "nom", "epreuve", "temps", "points"]

    public private(set) var passages: [Passage] = []
    /// Dernière lecture stable (pour l'écran de capture).
    public private(set) var dernierLu: [String: String] = [:]
    public private(set) var raison = ""

    private var candidat: [String: String] = [:]
    private var lecturesPareilles = 0
    private var dernierTemps: String = ""
    private var tempsDepuis: Double = 0
    private var tempsABouge = false
    private let source: String

    public init(source: String = "Horses & Competitions") { self.source = source }

    /// Une lecture de la page (texte de chaque zone) à l'heure `t`. Rend vrai si la liste des passages a changé.
    /// `epreuveForcee` : numéro d'épreuve choisi à la main (si la zone épreuve n'est pas lisible).
    @discardableResult
    public mutating func lecture(_ lu: [String: String], t: Double, concours: Concours?, epreuveForcee: String = "") -> Bool {
        let cle = ["dossard", "nom", "epreuve"].map { lu[$0] ?? "" }
        let cleCandidat = ["dossard", "nom", "epreuve"].map { candidat[$0] ?? "" }
        if cle == cleCandidat { lecturesPareilles += 1 } else { candidat = lu; lecturesPareilles = 1 }
        var change = false

        // arrivée : le temps a bougé, puis ne bouge plus depuis 3 s
        let temps = (lu["temps"] ?? "").trimmingCharacters(in: .whitespaces)
        if temps != dernierTemps {
            if !dernierTemps.isEmpty && !temps.isEmpty { tempsABouge = true }
            dernierTemps = temps
            tempsDepuis = t
        } else if tempsABouge, !temps.isEmpty, t - tempsDepuis >= 3, let i = passages.indices.last, passages[i].fin == nil {
            passages[i].fin = tempsDepuis
            tempsABouge = false
            change = true
        }

        guard lecturesPareilles >= 2 else { return change }
        dernierLu = lu
        let dossard = SuiviIncrustation.dossardLu(lu["dossard"] ?? "")
        guard !dossard.isEmpty else { raison = "Pas de dossard lu"; return change }
        let epreuve = !epreuveForcee.isEmpty ? epreuveForcee
            : (SuiviIncrustation.trouverEpreuve(lu["epreuve"] ?? "", dans: concours)?.numero ?? SuiviIncrustation.numeroEnTete(lu["epreuve"] ?? ""))
        guard !epreuve.isEmpty else { raison = "Épreuve non reconnue : « \(lu["epreuve"] ?? "") » (choisis-la à la main)"; return change }
        raison = ""
        if let p = passages.last, CodePassage.cle(p.dossard) == dossard, CodePassage.cle(p.epreuve) == CodePassage.cle(epreuve) {
            return change     // même couple : rien de neuf
        }
        // nouveau couple en piste : le précédent est fini au plus tard maintenant
        if let i = passages.indices.last, passages[i].fin == nil { passages[i].fin = t }
        let couple = concours?.epreuve(numero: epreuve)?.engage(dossard: dossard)
        let nom = (lu["nom"] ?? "").replacingOccurrences(of: " | ", with: " · ")
        passages.append(Passage(source: source, epreuve: epreuve, dossard: dossard,
                                cavalier: couple?.cavalier ?? nom, cheval: couple?.cheval ?? "",
                                entree: t, depart: t))
        tempsABouge = false
        if passages.count > 2000 { passages.removeFirst(passages.count - 2000) }
        return true
    }

    // MARK: - Lecture du texte

    /// « 124 », « N°124 FRA » → « 124 ».
    public static func dossardLu(_ texte: String) -> String {
        guard let r = texte.range(of: #"\d{1,5}"#, options: .regularExpression) else { return "" }
        return CodePassage.cle(String(texte[r]))
    }

    /// « 4 - Préparatoire » → « 4 ».
    static func numeroEnTete(_ texte: String) -> String {
        let t = normaliser(texte)
        guard let r = t.range(of: #"^(EPREUVE )?(N )?\d{1,3}\b"#, options: .regularExpression) else { return "" }
        return String(t[r]).components(separatedBy: " ").last ?? ""
    }

    /// L'épreuve affichée (« 4 - Préparatoire (1,00 m) », « CCI1*-INTRO ») retrouvée dans le fichier FFE :
    /// le numéro en tête suffit, sinon le nom le plus proche.
    public static func trouverEpreuve(_ texte: String, dans concours: Concours?) -> Epreuve? {
        guard let concours, !normaliser(texte).isEmpty else { return nil }
        let num = numeroEnTete(texte)
        if !num.isEmpty {
            let l = concours.epreuves.filter { $0.cle == CodePassage.cle(num) }
            if l.count == 1 { return l[0] }
        }
        let lu = Set(normaliser(texte).split(separator: " ").map(String.init).filter { $0.count > 1 })
        var meilleure: (Epreuve, Double)?
        for e in concours.epreuves {
            let mots = Set(normaliser(e.nom).split(separator: " ").map(String.init).filter { $0.count > 1 })
            guard !mots.isEmpty, !lu.isEmpty else { continue }
            let score = Double(lu.intersection(mots).count) / Double(lu.count)
            if score > (meilleure?.1 ?? 0) { meilleure = (e, score) }
        }
        if let m = meilleure, m.1 >= 0.75 { return m.0 }
        return nil
    }

    static func normaliser(_ s: String) -> String {
        let sans = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")).uppercased()
        let r = sans.replacingOccurrences(of: #"[^A-Z0-9]+"#, with: " ", options: .regularExpression)
        return r.trimmingCharacters(in: .whitespaces)
    }

    /// Script lu dans la page : le texte visible dans chaque zone (fractions de la page), ligne par ligne
    /// séparées par « | ». Le même que le suivi externe de HM Timing.
    public static let scriptLecture = #"""
    (function (Z) {
      var W = innerWidth, H = innerHeight, items = [], r = document.createRange(), n, out = {};
      if (!document.body) return out;
      var w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      while ((n = w.nextNode())) {
        var t = n.nodeValue; if (!t || !t.trim() || !n.parentElement) continue;
        var cs = getComputedStyle(n.parentElement);
        if (cs.visibility === "hidden" || cs.display === "none" || +cs.opacity === 0) continue;
        r.selectNodeContents(n); var b = r.getBoundingClientRect(); if (!b.width || !b.height) continue;
        items.push([b.left + b.width / 2, b.top + b.height / 2, b.top, b.left, t.trim()]);
      }
      for (var k in Z) {
        var z = Z[k], x0 = z[0] * W, y0 = z[1] * H, x1 = x0 + z[2] * W, y1 = y0 + z[3] * H;
        out[k] = items.filter(function (i) { return i[0] >= x0 && i[0] <= x1 && i[1] >= y0 && i[1] <= y1; })
          .sort(function (a, b) { return Math.abs(a[2] - b[2]) > 4 ? a[2] - b[2] : a[3] - b[3]; })
          .reduce(function (o, i, n, l) {
            return o + (n ? (Math.abs(i[2] - l[n - 1][2]) > 4 ? " | " : " ") : "") + i[4];
          }, "").replace(/[ \t\r\n]+/g, " ").trim().slice(0, 200);
      }
      return JSON.stringify(out);
    })(ZONES)
    """#
}
