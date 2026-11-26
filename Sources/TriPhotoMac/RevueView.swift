import AppKit
import SwiftUI
import TriPhotoCommun
import TriPhotoMoteur

/// Écran « Revue » (maquette 3) : une photo à la fois, par épreuve, pour reclasser vite (bonne, floue, sol, code),
/// marquer une chute, changer un code ou supprimer. ← → pour avancer, une lettre pour classer, ⌫ pour supprimer
/// (copie retirée du serveur, original à la Corbeille ; ⌘Z annule).
struct RevueView: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var moteur: Moteur
    @State private var epreuve: String = ""          // vide : toutes
    @State private var boitier: String = ""          // vide : tous
    @AppStorage("revue.ordre") private var ordre: Ordre = .douteuses
    @State private var photos: [FichePhoto] = []
    @State private var index = 0
    @State private var nouveauCode = ""
    @State private var changerCode = false
    @State private var corrections: [String] = []
    @State private var retours: [Retour] = []            // pour ⌘Z : suppression ou retrait des bonnes
    // Filtres personnalisés (se combinent avec le filtre choisi)
    @State private var piste = ""                        // vide : toutes
    @State private var parHeure = false
    @State private var heureDe = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var heureA = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var recherche = ""                    // code, cavalier ou cheval
    @FocusState private var saisieActive: Bool           // on tape dans la recherche : les lettres ne classent pas
    @State private var zoom: CGFloat = 1                 // molette du Loupedeck
    // Vue galerie (HUGO 25/11, comme la Bibliothèque de Lightroom) : G la grille, E / Entrée la photo en grand.
    @AppStorage("revue.galerie") private var galerie = false   // gardé quand on change d'onglet (essai du 26/11)
    @State private var galerieAvantPleinEcran = false     // P depuis la galerie : on y revient en sortant
    @State private var choix: Set<Int64> = []             // photos choisies dans la galerie (⇧ / ⌘ clic)
    @State private var etiquettes: [Int64: String] = [:]  // « sol », « floue », « code » proposés (calculés au chargement)
    @State private var chargement = 0                     // n° du dernier chargement demandé (frappe rapide)
    @State private var colonnes = 5                       // colonnes de la galerie (pour ↑ ↓)
    @AppStorage("revue.tailleVignette") private var taille: Double = 160
    @State private var majPrevue = false                  // Revue en direct : un rechargement attend déjà

    private enum Retour {                                 // un geste peut toucher plusieurs photos (galerie)
        case suppression([FichePhoto])
        case retrait([FichePhoto], String)               // retirées des bonnes : drapeau posé
    }

    /// Les filtres, en trois groupes bien séparés (HUGO 24/11) : tout voir, les photos À TRAITER (les seules où
    /// « Supprimer » est possible) et les BONNES photos (réseaux, meilleures), où rien ne peut être supprimé.
    enum Ordre: String, CaseIterable, Identifiable {
        case douteuses = "Toutes, détection incertaine d'abord"
        case heure = "Toutes, par heure"
        case aTrier = "À traiter : sol, floues et code"
        case sol = "À traiter : sol"
        case floues = "À traiter : floues"
        case code = "À traiter : photos de code"
        case belles = "Bonnes : la plus belle de chaque couple"
        case meilleures = "Bonnes : meilleures (M)"
        case reseaux = "Bonnes : réseaux sociaux (R)"
        var id: String { rawValue }

        enum Groupe { case toutes, aTraiter, bonnes }
        var groupe: Groupe {
            switch self {
            case .douteuses, .heure: return .toutes
            case .aTrier, .sol, .floues, .code: return .aTraiter
            case .belles, .meilleures, .reseaux: return .bonnes
            }
        }
        static func du(_ g: Groupe) -> [Ordre] { allCases.filter { $0.groupe == g } }

        /// Bonnes photos : drapeau posé quand HUGO retire une photo de ce filtre (⌫), pour qu'elle n'y revienne pas.
        var drapeauRetrait: String? {
            switch self {
            case .belles: return "pasBelle"
            case .meilleures: return "pasMeilleure"
            case .reseaux: return "pasReseaux"
            default: return nil
            }
        }
    }

    /// « Supprimer » : dans « Toutes » et « À traiter » (HUGO 26/11 : « depuis l'app on ne peut pas supprimer »),
    /// jamais sur les bonnes photos. Toujours annulable (⌘Z), original à la Corbeille.
    private var suppressionPermise: Bool { ordre.groupe != .bonnes }

    private struct Classe: Identifiable {
        var id: String { cle }
        var cle: String
        var nom: String
        var touche: Character
    }
    private let classes = [Classe(cle: "bonne", nom: "Bonne", touche: "b"), Classe(cle: "floue", nom: "Floue", touche: "f"),
                           Classe(cle: "sol", nom: "Sol", touche: "s"), Classe(cle: "code", nom: "Code", touche: "c")]

    private var courante: FichePhoto? { photos.indices.contains(index) ? photos[index] : nil }

    var body: some View {
        Group {
            if etat.pleinEcran, let f = courante { vuePleinEcran(f) } else { ecranNormal }
        }
        .onAppear { Clic.surveiller(); charger() }
        .onChange(of: galerie) { g in if !g { choix = [] }; Visite.partagee.signaler("revue.vue") }
        .onChange(of: courante?.id) { id in if let id { etat.revuePhotoId = id }; Visite.partagee.signaler("revue.photo") }
        .onChange(of: epreuve) { _ in charger() }
        .onChange(of: boitier) { _ in charger() }
        .onChange(of: ordre) { _ in charger(); Visite.partagee.signaler("revue.filtre") }
        .onChange(of: piste) { _ in charger() }
        .onChange(of: parHeure) { _ in charger() }
        .onChange(of: heureDe) { _ in if parHeure { charger() } }
        .onChange(of: heureA) { _ in if parHeure { charger() } }
        .onChange(of: recherche) { t in charger(); if !t.isEmpty { Visite.partagee.signaler("revue.recherche") } }
        .onChange(of: etat.momentRevue?.heure) { _ in charger() }
        .onChange(of: etat.photosRevue?.ids) { _ in charger() }
        // En direct (essai du 26/11) : nouvelles photos, codes changés, photos retirées dans Lightroom… la Revue suit,
        // au plus toutes les 3 s, sans perdre la photo regardée ni le choix fait dans la galerie.
        .onChange(of: moteur.resume.versionJournal) { _ in enDirect() }
        .background(raccourcis)
        .onReceive(etat.ordresLoupedeck) { recevoirLoupedeck($0) }
        // Sortie du plein écran par le bouton vert ou le menu Présentation : la Revue suit (bandeau remis).
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            guard etat.pleinEcran else { return }
            etat.pleinEcran = false
            if galerieAvantPleinEcran { galerie = true; galerieAvantPleinEcran = false }
        }
        .onChange(of: signatureLoupedeck) { _ in publierLoupedeck() }
        .onAppear(perform: publierLoupedeck)
        .onDisappear {
            etat.infoRevueLoupedeck = nil; etat.photoLoupedeck = nil
            if etat.pleinEcran { basculerPleinEcran() }
        }
    }

    private var ecranNormal: some View {
        HStack(spacing: 0) {
            if etat.panneauGauche {
                ScrollView { filtres }.frame(width: 240).background(Theme.panneau).repere("revue.gauche")
                Divider().overlay(Theme.bordure)
            }
            centre.frame(maxWidth: .infinity, maxHeight: .infinity)
            if etat.panneauDroit {
                Divider().overlay(Theme.bordure)
                panneauDroit.frame(width: 300).background(Theme.panneau).repere("revue.droite")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()                                       // rien ne déborde sous la barre de titre
    }

    // MARK: - Plein écran (touche P, comme F dans Lightroom : F sert déjà à « floue »)

    /// La photo seule, sur fond noir, sur tout l'écran. ← → avancer, les lettres classent, P ou Échap pour sortir.
    private func vuePleinEcran(_ f: FichePhoto) -> some View {
        ZStack(alignment: .bottom) {
            Color.black
            VignettePhoto(chemins: [f.copie, f.chemin], cote: 2000, entiere: true)
                .id(f.id)
                .scaleEffect(zoom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .onTapGesture(count: 2) { basculerPleinEcran() }
            HStack(spacing: 12) {
                Text("\(index + 1) / \(photos.count)").font(.system(size: 12, weight: .semibold))
                Text(f.codeRetenu.isEmpty ? "sans code" : f.codeRetenu).font(.system(size: 12, design: .monospaced))
                if !f.cavalier.isEmpty { Text("\(f.cavalier) · \(f.cheval)").font(.system(size: 12)) }
                if !f.classe.isEmpty { Text(f.classe).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent) }
                if f.chute { Text("CHUTE").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.attention) }
                if f.a("meilleure") { Text("★ M").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent) }
                if f.a("reseaux") { Text("R").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent) }
                Spacer()
                Text("← → avancer · B F S C X M R classer · P ou Échap : sortir").font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .foregroundStyle(Color.white.opacity(0.85))
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color.black.opacity(0.55))
        }
        .ignoresSafeArea()
    }

    /// Entre ou sort du plein écran : la fenêtre passe en plein écran macOS, bandeau et panneaux masqués.
    private func basculerPleinEcran() {
        let entrer = !etat.pleinEcran
        guard !entrer || courante != nil else { return }
        if let w = NSApp.keyWindow ?? NSApp.mainWindow, w.styleMask.contains(.fullScreen) != entrer { w.toggleFullScreen(nil) }
        if entrer { galerieAvantPleinEcran = galerie; galerie = false }
        else if galerieAvantPleinEcran { galerie = true; galerieAvantPleinEcran = false }
        etat.pleinEcran = entrer
    }

    // MARK: - Loupedeck CT

    /// Change dès que ce que montre le Loupedeck doit changer.
    private var signatureLoupedeck: String {
        let f = courante
        return "\(index)|\(photos.count)|\(f?.id ?? 0)|\(f?.classe ?? "")|\(f?.chute ?? false)|\(f?.drapeaux ?? "")|\(f?.codeRetenu ?? "")|\(ordre.rawValue)|\(epreuve)|\(zoom)"
    }

    private func publierLoupedeck() {
        let f = courante
        let filtre: String
        switch ordre.groupe {
        case .toutes: filtre = "Toutes"
        case .aTraiter: filtre = "À traiter"
        case .bonnes: filtre = "Bonnes"
        }
        let court: String
        switch ordre {
        case .douteuses: court = "Douteuses"
        case .heure: court = "Heure"
        case .aTrier: court = "Tout"
        case .sol: court = "Sol"
        case .floues: court = "Floues"
        case .code: court = "Code"
        case .belles: court = "Belles"
        case .meilleures: court = "Meilleures"
        case .reseaux: court = "Réseaux"
        }
        etat.infoRevueLoupedeck = EtatLoupedeck.Revue(
            position: photos.isEmpty ? 0 : index + 1, total: photos.count,
            code: f?.codeRetenu ?? "", cavalier: f?.cavalier ?? "", cheval: f?.cheval ?? "",
            classe: f?.classe ?? "", meilleure: f?.a("meilleure") ?? false, reseaux: f?.a("reseaux") ?? false,
            chute: f?.chute ?? false, filtre: filtre, ordre: court, epreuve: epreuve,
            suppressionPermise: suppressionPermise, zoom: Double(zoom))
        etat.photoLoupedeck = f?.id
    }

    /// Les boutons et molettes du Loupedeck : mêmes gestes que le clavier.
    private func recevoirLoupedeck(_ o: OrdreLoupedeck) {
        guard !changerCode || o.nom == "changerCode" else { return }
        switch o.nom {
        case "photo": avancer(o.pas)
        case "photo.premiere": index = 0
        case "classe.bonne": classer("bonne")
        case "classe.floue": classer("floue")
        case "classe.sol": classer("sol")
        case "classe.code": classer("code")
        case "meilleure": basculer("meilleure")
        case "reseaux": basculer("reseaux")
        case "chute": basculerChute()
        case "supprimer": supprimer()
        case "annuler": annulerSuppression()
        case "changerCode":
            if let f = courante { nouveauCode = f.codeRetenu; changerCode.toggle() }
        case "filtre":
            let groupes: [Ordre] = [.douteuses, .aTrier, .belles]
            let i = groupes.firstIndex { $0.groupe == ordre.groupe } ?? 0
            ordre = groupes[((i + o.pas) % groupes.count + groupes.count) % groupes.count]
        case "filtre.toutes": ordre = .douteuses
        case "ordre":
            let l = Ordre.du(ordre.groupe)
            let i = l.firstIndex(of: ordre) ?? 0
            ordre = l[(i + 1) % l.count]
        case "epreuve":
            let l = [""] + (etat.concours?.epreuves ?? []).map(\.numero)
            let i = l.firstIndex(of: epreuve) ?? 0
            epreuve = l[min(max(0, i + o.pas), l.count - 1)]
        case "epreuve.toutes": epreuve = ""
        case "zoom": zoom = min(max(1, zoom + CGFloat(o.pas) * 0.25), 4)
        case "zoom.ajuster": zoom = 1
        default: break
        }
    }

    // MARK: - Données

    /// Rafale : photos du même boîtier à moins de 1,5 s. Une photo nettement moins nette que la meilleure de sa
    /// rafale est « floue ? » (comme la v00, seuil 30 %).
    private func douteuse(_ f: FichePhoto, dans l: [FichePhoto]) -> String? {
        if f.scene == "code" { return "photo de code ?" }
        if f.scene == "sol" { return "photo du sol ?" }
        guard let p = f.prise, f.nettete > 0 else { return nil }
        let rafale = l.filter { $0.boitier == f.boitier && abs(($0.prise ?? .distantPast).timeIntervalSince(p)) < 1.5 }
        let meilleure = rafale.map(\.nettete).max() ?? 0
        if rafale.count > 1, meilleure > 0, f.nettete < 0.3 * meilleure { return "floue ?" }
        return nil
    }

    /// Ce que la mémoire propose pour cette photo (« floue (82 %) », « chute »), nil si rien.
    static func memoire(_ f: FichePhoto) -> String? {
        let l = f.detection.split(separator: "|").map(String.init).filter { $0 != "-" && $0 != "?" }
        guard !l.isEmpty else { return nil }
        return l.enumerated().map { i, c in
            let nom = Memoire.nom(de: c).lowercased()
            return i == 0 && Memoire.genre(de: c) == .scene && f.confianceDetection > 0 ? "\(nom) (\(f.confianceDetection) %)" : nom
        }.joined(separator: " · ")
    }

    /// La mémoire voit-elle autre chose que le classement actuel (flou, sol, code, chute pas marquée) ?
    static func memoireDoute(_ f: FichePhoto) -> Bool {
        let l = f.detection.split(separator: "|").map(String.init)
        if let s = l.first, ["floue", "sol", "code"].contains(s), f.classe.isEmpty { return true }
        return l.contains("chute") && !f.chute
    }

    /// Note « réseaux sociaux » : ressemblance aux meilleures de la mémoire, marques de HUGO, netteté.
    static func noteBelle(_ f: FichePhoto, netteteMax: Double) -> Double {
        let mauvaises: Set<String> = ["floue", "sol", "code"]
        if f.a("pasBelle") { return -1 }
        if mauvaises.contains(f.classe) || mauvaises.contains(String(f.detection.split(separator: "|").first ?? "")) { return -1 }
        var n = 0.6 * max(f.belle, 0) + 0.4 * (netteteMax > 0 ? min(f.nettete / netteteMax, 1) : 0)
        if f.a("meilleure") { n += 2 }
        if f.a("reseaux") || f.detection.contains("reseaux") { n += 1 }
        return n
    }

    /// La plus belle photo de chaque couple d'abord (la meilleure en tête), puis toutes les autres.
    static func bellesDabord(_ l: [FichePhoto], seulementLesTetes: Bool = false) -> [FichePhoto] {
        let nmax = l.map(\.nettete).max() ?? 0
        let parCouple = Dictionary(grouping: l.filter { !$0.codeRetenu.isEmpty }, by: \.codeRetenu)
        let tetes = parCouple.values.compactMap { groupe in
            groupe.max { a, b in noteBelle(a, netteteMax: nmax) < noteBelle(b, netteteMax: nmax) }
        }
            .filter { noteBelle($0, netteteMax: nmax) >= 0 }
            .sorted { noteBelle($0, netteteMax: nmax) > noteBelle($1, netteteMax: nmax) }
        if seulementLesTetes { return tetes }
        let ids = Set(tetes.map(\.id))
        return tetes + l.filter { !ids.contains($0.id) }
    }

    /// Les photos à regarder d'abord (détection code / sol, ou floue dans sa rafale), pas encore classées.
    /// Rafales calculées boîtier par boîtier, photos triées par heure : rapide même sur des milliers de photos.
    static func douteuses(_ l: [FichePhoto]) -> Set<Int64> {
        var marques: Set<Int64> = []
        for (_, liste) in Dictionary(grouping: l.filter { $0.prise != nil }, by: \.boitier) {
            let t = liste.sorted { $0.prise! < $1.prise! }
            var debut = 0
            for (i, f) in t.enumerated() {
                if memoireDoute(f) { marques.insert(f.id); continue }
                guard f.classe.isEmpty else { continue }
                if f.scene == "code" || f.scene == "sol" { marques.insert(f.id); continue }
                while t[debut].prise!.timeIntervalSince(f.prise!) < -1.5 { debut += 1 }
                var fin = i
                while fin + 1 < t.count && t[fin + 1].prise!.timeIntervalSince(f.prise!) < 1.5 { fin += 1 }
                let meilleure = t[debut...fin].map(\.nettete).max() ?? 0
                if fin > debut, meilleure > 0, f.nettete > 0, f.nettete < 0.3 * meilleure { marques.insert(f.id) }
            }
        }
        return marques
    }

    /// Photos à traiter et leur catégorie (« sol », « floue », « code ») : classement de HUGO d'abord, sinon la
    /// mémoire, sinon l'analyse rapide (comme la v00 : scène vide, ou nettement moins nette que sa rafale).
    /// Une photo classée « bonne » par HUGO n'est jamais à traiter.
    static func aTraiter(_ l: [FichePhoto]) -> [Int64: String] {
        let mauvaises: Set<String> = ["sol", "floue", "code"]
        var r: [Int64: String] = [:]
        var floues: Set<Int64> = []
        for (_, liste) in Dictionary(grouping: l.filter { $0.prise != nil && $0.nettete > 0 }, by: \.boitier) {
            let t = liste.sorted { $0.prise! < $1.prise! }
            var debut = 0
            for (i, f) in t.enumerated() {
                while t[debut].prise!.timeIntervalSince(f.prise!) < -1.5 { debut += 1 }
                var fin = i
                while fin + 1 < t.count && t[fin + 1].prise!.timeIntervalSince(f.prise!) < 1.5 { fin += 1 }
                let meilleure = t[debut...fin].map(\.nettete).max() ?? 0
                if fin > debut, meilleure > 0, f.nettete < 0.3 * meilleure { floues.insert(f.id) }
            }
        }
        for f in l {
            if !f.classe.isEmpty {
                if mauvaises.contains(f.classe) { r[f.id] = f.classe }
                continue
            }
            if let d = f.detection.split(separator: "|").first.map(String.init), mauvaises.contains(d) { r[f.id] = d; continue }
            if f.scene == "code" || f.scene == "sol" { r[f.id] = f.scene; continue }
            if floues.contains(f.id) { r[f.id] = "floue" }
        }
        return r
    }

    /// Minutes depuis minuit (filtre par heure).
    static func minutes(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Piste de chaque boîtier : celle de sa photo de synchro, sinon celle apprise avec le chrono.
    private var pisteParBoitier: [String: String] {
        var d = moteur.resume.boitierPiste
        for b in moteur.resume.boitiers { if let s = b.synchro, !s.piste.isEmpty { d[b.nom] = s.piste } }
        return d
    }

    private var pistesConnues: [String] {
        Array(Set(etat.reglages.pistes.map(\.nom).filter { !$0.isEmpty } + pisteParBoitier.values)).sorted()
    }

    private func enDirect() {
        guard !majPrevue else { return }
        majPrevue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            majPrevue = false
            // on tape un code ou une recherche : on attend la fin pour ne rien bousculer
            if changerCode || saisieActive { enDirect(); return }
            charger()
        }
    }

    private func charger() {
        let ep = epreuve.isEmpty ? nil : epreuve
        let b = boitier
        let tri = ordre
        let moment = etat.momentRevue?.heure
        let ids = etat.photosRevue?.ids
        let p = piste
        let pisteDe = pisteParBoitier
        let heures = parHeure ? (RevueView.minutes(heureDe), RevueView.minutes(heureA)) : nil
        let texte = recherche.trimmingCharacters(in: .whitespaces).lowercased()
        chargement += 1
        let numero = chargement
        DispatchQueue.global(qos: .userInitiated).async {
            var l = ids.map { moteur.fiches(ids: $0) } ?? moment.map { moteur.photosAutour($0) } ?? moteur.photosRevue(epreuve: ep)
            if !b.isEmpty { l = l.filter { $0.boitier == b } }
            if !p.isEmpty { l = l.filter { pisteDe[$0.boitier] == p } }
            if let h = heures {
                let de = h.0, a = h.1
                l = l.filter { f in
                    guard let pr = f.prise else { return false }
                    let m = RevueView.minutes(pr)
                    return de <= a ? (m >= de && m <= a) : (m >= de || m <= a)
                }
            }
            if !texte.isEmpty {
                l = l.filter { $0.codeRetenu.lowercased().contains(texte) || $0.cavalier.lowercased().contains(texte)
                    || $0.cheval.lowercased().contains(texte) }
            }
            switch tri {
            case .douteuses:
                let marques = RevueView.douteuses(l)
                l = l.filter { marques.contains($0.id) } + l.filter { !marques.contains($0.id) }
            case .aTrier, .sol, .floues, .code:
                let cats = RevueView.aTraiter(l)
                let voulue: String? = tri == .sol ? "sol" : tri == .floues ? "floue" : tri == .code ? "code" : nil
                l = l.filter { f in cats[f.id].map { voulue == nil || $0 == voulue } ?? false }
            case .belles:
                l = RevueView.bellesDabord(l, seulementLesTetes: true)
            case .meilleures:
                l = l.filter { !$0.a("pasMeilleure") && ($0.a("meilleure") || $0.detection.split(separator: "|").contains("meilleure")) }
            case .reseaux:
                l = l.filter { !$0.a("pasReseaux") && ($0.a("reseaux") || $0.detection.split(separator: "|").contains("reseaux")) }
            case .heure:
                break
            }
            let cats = RevueView.aTraiter(l)
            DispatchQueue.main.async {
                guard numero == chargement else { return }   // un chargement plus récent est en route : on l'attend
                let garde = courante?.id ?? etat.revuePhotoId   // retour sur l'onglet : la photo où on en était
                if photos != l { photos = l }          // en direct : rien ne bouge à l'écran si rien n'a changé
                if etiquettes != cats { etiquettes = cats }
                index = garde.flatMap { g in l.firstIndex { $0.id == g } } ?? 0
                choix = choix.intersection(l.map(\.id))
            }
        }
    }

    // MARK: - Filtres

    private var filtres: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Afficher").font(.system(size: 14, weight: .semibold))
            if let p = etat.photosRevue {
                VStack(alignment: .leading, spacing: 6) {
                    Text(p.titre).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.attention)
                    Button("Revenir à toutes les photos") { etat.photosRevue = nil }.buttonStyle(BoutonStyle())
                }
                .padding(10)
                .background(Theme.carte, in: RoundedRectangle(cornerRadius: 6))
            }
            if let m = etat.momentRevue {
                VStack(alignment: .leading, spacing: 6) {
                    Text(m.titre).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.attention)
                    Text("Photos prises une minute avant et après \(m.heure.formatted(date: .omitted, time: .standard)), tous boîtiers.")
                        .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
                    Button("Revenir à toutes les photos") { etat.momentRevue = nil }.buttonStyle(BoutonStyle())
                }
                .padding(10)
                .background(Theme.carte, in: RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 12) {
            Text("Épreuve").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
            Picker("", selection: $epreuve) {
                Text("Toutes les épreuves").tag("")
                ForEach(etat.concours?.epreuves ?? []) { e in Text(e.nomDossier).tag(e.numero) }
            }
            .labelsHidden()
            Text("Boîtier").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
            Picker("", selection: $boitier) {
                Text("Tous").tag("")
                ForEach(moteur.resume.boitiers) { b in Text(b.nom).tag(b.nom) }
            }
            .labelsHidden()
            Text("Piste").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
            Picker("", selection: $piste) {
                Text("Toutes").tag("")
                ForEach(pistesConnues, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            }
            .repere("revue.epreuve")
            Toggle("Entre deux heures", isOn: $parHeure).font(.system(size: 12))
            if parHeure {
                HStack(spacing: 6) {
                    DatePicker("", selection: $heureDe, displayedComponents: .hourAndMinute).labelsHidden()
                    Text("à").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                    DatePicker("", selection: $heureA, displayedComponents: .hourAndMinute).labelsHidden()
                }
            }
            TextField("Code, cavalier ou cheval", text: $recherche).textFieldStyle(.roundedBorder)
                .focused($saisieActive)
                .onSubmit { saisieActive = false }
                .onExitCommand { saisieActive = false }
                .repere("revue.recherche")
            Text("Filtre").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
            Picker("", selection: $ordre) {
                Section("Toutes les photos (suppression possible)") { ForEach(Ordre.du(.toutes)) { Text($0.rawValue).tag($0) } }
                Section("Photos à traiter (suppression possible)") { ForEach(Ordre.du(.aTraiter)) { Text($0.rawValue).tag($0) } }
                Section("Bonnes photos (jamais supprimées ici)") { ForEach(Ordre.du(.bonnes)) { Text($0.rawValue).tag($0) } }
            }
            .labelsHidden()
            .repere("revue.filtre")
            Text(ordre.groupe == .bonnes ? "Bonnes photos : rien n'est supprimé ici. ⌫ retire la photo de cette sélection seulement, ⌘Z annule."
                 : "⌫ supprime (serveur, galerie en ligne, original à la Corbeille), ⌘Z annule. Plusieurs d'un coup : ⇧ ou ⌘ + clic dans la galerie.")
                .font(.system(size: 11)).foregroundStyle(ordre.groupe == .bonnes ? Theme.texteTresDiscret : Theme.attention)
            if ordre == .belles {
                Text("Pour les réseaux sociaux : la plus belle photo de chaque couple, d'après la mémoire (catégorie « Meilleures ») et la netteté.")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            }
            Button("Actualiser") { charger() }.buttonStyle(BoutonStyle())
            Text(Pluriel.photos(photos.count)).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                .padding(.top, 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Centre

    private var centre: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // Le titre ne se coupe jamais ; l'aide prend la version qui tient en entier, ou disparaît (essai du 26/11).
                if galerie {
                    Text(Pluriel.photos(photos.count)).font(.system(size: 13, weight: .semibold)).fixedSize()
                    if choix.count > 1 {
                        aide(["\(choix.count) photos choisies : les touches et les boutons s'appliquent à toutes (⌘Z annule)",
                              "\(choix.count) choisies · ⌘Z annule"], accent: true)
                    } else {
                        aide(["clic : choisir · ⇧ ou ⌘ clic : plusieurs · double-clic ou Entrée : en grand",
                              "⇧ ou ⌘ clic : plusieurs · double-clic : en grand"])
                    }
                } else if courante != nil {
                    Text("Photo \(index + 1) sur \(photos.count)").font(.system(size: 13, weight: .semibold)).fixedSize()
                    aide(["← → avancer · B F S C classer · X chute · M meilleure · R réseaux · G galerie · P plein écran · Échap galerie",
                          "← → avancer · lettre : classer · G galerie · P plein écran",
                          "← → · G · P"])
                }
                Spacer(minLength: 8)
                if !galerie, let f = courante {
                    if let m = RevueView.memoire(f) {
                        Pastille(texte: "Mémoire : \(m)", genre: RevueView.memoireDoute(f) ? .attention : .neutre)
                    }
                    if let d = douteuse(f, dans: photos) { Pastille(texte: "Détectée : \(d)", genre: .attention) }
                }
                if galerie { CurseurTaille(taille: $taille) }
                SelecteurVue(galerie: $galerie).repere("revue.vue")
            }
            if photos.isEmpty {
                Spacer()
                Text("Aucune photo envoyée pour ce choix.").foregroundStyle(Theme.texteDiscret)
                Spacer()
            } else if galerie {
                grille.repere("revue.centre")
                if let f = courante { boutons(f).repere("revue.boutons") }
                changementDeCode
            } else if let f = courante {
                // La photo en entier, portrait ou paysage : elle prend la place qui reste, jamais plus.
                VignettePhoto(chemins: [f.copie, f.chemin], cote: 1400, entiere: true)
                    .id(f.id)
                    .scaleEffect(zoom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { galerie = true }
                    .repere("revue.centre")
                    .overlay(alignment: .topTrailing) {
                        Button { basculerPleinEcran() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                            .buttonStyle(BoutonStyle()).help("Plein écran (P)").padding(6)
                    }
                boutons(f).repere("revue.boutons")
                changementDeCode
                bande
            }
        }
        .padding(20)
    }

    /// Une ligne d'aide : la plus longue version qui tient en entier, sinon rien (jamais de « … »).
    private func aide(_ versions: [String], accent: Bool = false) -> some View {
        let v = versions + ["", "", ""]
        func ligne(_ t: String) -> some View {
            Text(t).font(.system(size: 11)).foregroundStyle(accent ? Theme.accent : Theme.texteTresDiscret)
                .lineLimit(1).fixedSize()
        }
        return ViewThatFits(in: .horizontal) {
            ligne(v[0])
            ligne(v[1])
            ligne(v[2])
            ligne("")
        }
        .frame(minWidth: 0, alignment: .leading)
        .layoutPriority(-1)
    }

    /// Les boutons sous la photo. Fenêtre étroite (deux panneaux ouverts sur un petit écran) : ils passent sur deux
    /// lignes, puis en lettres seules, mais ne sont jamais coupés (Supprimer et Changer le code restent visibles).
    private func boutons(_ f: FichePhoto) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { classement(f, court: false); Spacer(minLength: 8); actions(court: false, f) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) { classement(f, court: false) }
                HStack(spacing: 8) { Spacer(minLength: 0); actions(court: false, f) }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { classement(f, court: true) }
                HStack(spacing: 6) { Spacer(minLength: 0); actions(court: true, f) }
            }
        }
    }

    @ViewBuilder
    private func classement(_ f: FichePhoto, court: Bool) -> some View {
        ForEach(classes) { c in
            Button(court ? String(c.touche).uppercased() : "\(c.nom) (\(String(c.touche).uppercased()))") { classer(c.cle) }
                .buttonStyle(BoutonStyle(principal: f.classe == c.cle))
                .help(c.nom)
        }
        Button(court ? "X" : f.chute ? "Chute ✓ (X)" : "Chute (X)") { basculerChute() }
            .buttonStyle(BoutonStyle(principal: f.chute)).help("Chute")
        Button(court ? "M" : f.a("meilleure") ? "Meilleure ✓ (M)" : "Meilleure (M)") { basculer("meilleure") }
            .buttonStyle(BoutonStyle(principal: f.a("meilleure"))).help("Meilleure")
        Button(court ? "R" : f.a("reseaux") ? "Réseaux ✓ (R)" : "Réseaux (R)") { basculer("reseaux") }
            .buttonStyle(BoutonStyle(principal: f.a("reseaux"))).help("Réseaux sociaux")
    }

    @ViewBuilder
    private func actions(court: Bool, _ f: FichePhoto) -> some View {
        if !retours.isEmpty {
            Button(court ? "⌘Z" : "Annuler (⌘Z)") { annulerSuppression() }.buttonStyle(BoutonStyle()).help("Annuler")
        }
        if ordre.drapeauRetrait != nil {
            Button(court ? "Retirer ⌫" : "Retirer de la sélection (⌫)") { supprimer() }
                .buttonStyle(BoutonStyle())
                .help("La photo n'est plus retenue dans ce filtre. Elle reste sur le serveur et dans Lightroom.")
        }
        if suppressionPermise {
            Button(court ? "Suppr. ⌫" : "Supprimer (⌫)") { supprimer() }
                .buttonStyle(BoutonStyle())
                .help("Retire la copie du serveur local et de la galerie en ligne, et met l'original à la Corbeille. Dans Lightroom, elle apparaît manquante : clic droit sur le dossier › Synchroniser le dossier.")
        }
        Button(court ? "Code…" : "Changer le code…") { nouveauCode = f.codeRetenu; changerCode = true }
            .buttonStyle(BoutonStyle())
    }

    @ViewBuilder
    private var changementDeCode: some View {
        if changerCode {
            HStack {
                TextField("#08_14", text: $nouveauCode).textFieldStyle(.roundedBorder).frame(width: 140)
                    .onSubmit(appliquerCode)
                if let c = CodePassage.lire(nouveauCode), let g = etat.concours?.couple(pour: c) {
                    Text("\(g.cavalier) · \(g.cheval)").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                }
                Button(cibles.count > 1 ? "Appliquer aux \(cibles.count) photos" : "Appliquer", action: appliquerCode)
                    .buttonStyle(BoutonStyle(principal: true))
                    .disabled(CodePassage.lire(nouveauCode) == nil)
                Button("Annuler") { changerCode = false }.buttonStyle(BoutonStyle())
                Spacer()
            }
        }
    }

    // MARK: - Galerie

    /// La grille de vignettes. Seules les vignettes visibles sont lues (petites, en priorité basse).
    private var grille: some View {
        GeometryReader { geo in
            let n = colonnesGalerie(largeur: geo.size.width - 4, taille: taille)
            ScrollViewReader { lecteur in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: n), spacing: 8) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { i, f in tuile(i, f) }
                    }
                    .padding(2)
                }
                .onAppear {
                    colonnes = n
                    if let f = courante { lecteur.scrollTo(f.id, anchor: .center) }
                }
                .onChange(of: n) { colonnes = $0 }
                .onChange(of: index) { i in
                    if photos.indices.contains(i) { withAnimation { lecteur.scrollTo(photos[i].id) } }
                }
            }
        }
    }

    private func tuile(_ i: Int, _ f: FichePhoto) -> some View {
        let active = i == index
        let choisie = choix.contains(f.id)
        return VStack(alignment: .leading, spacing: 3) {
            // en entier : une verticale se voit verticale (essai du 26/11), avec un fond autour
            VignettePhoto(chemins: [f.copie, f.chemin], cote: 260, entiere: true)
                .background(Theme.fond)
                .aspectRatio(3 / 2, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(alignment: .bottomTrailing) {
                    if choisie {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 18))
                            .foregroundStyle(Theme.surAccent, Theme.accent).padding(4)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let e = etiquette(f) {
                        Text(e.texte).font(.system(size: 9, weight: .semibold)).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(e.sure ? Theme.carte.opacity(0.9) : Theme.attentionFond, in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(e.sure ? Theme.texte : Theme.attention)
                            .padding(4)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 2) {
                        if f.chute { marque("X") }
                        if f.a("meilleure") { marque("★ M") }
                        if f.a("reseaux") { marque("R") }
                    }
                    .padding(4)
                }
            HStack {
                Text(f.codeRetenu.isEmpty ? "sans code" : f.codeRetenu).font(.system(size: 10, design: .monospaced))
                Spacer()
                Text(f.prise.map { $0.formatted(date: .omitted, time: .shortened) } ?? "?").font(.system(size: 10))
                    .foregroundStyle(Theme.texteDiscret)
            }
            .lineLimit(1)
        }
        .padding(5)
        .background(active || choisie ? Theme.selection : Theme.carte, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4)
            .stroke(active || choisie ? Theme.accent : Color.clear, lineWidth: active ? 3 : 2.5))
        .contentShape(Rectangle())
        .onTapGesture { cliquer(i, f) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { index = i; galerie = false })
        .id(f.id)
    }

    private func marque(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 3)).foregroundStyle(Theme.surAccent)
    }

    /// Ce que dit l'étiquette d'une vignette : le classement de HUGO (sûr), sinon ce que l'app soupçonne (« sol ? »).
    private func etiquette(_ f: FichePhoto) -> (texte: String, sure: Bool)? {
        if !f.classe.isEmpty { return (f.classe, true) }
        if let e = etiquettes[f.id] { return ("\(e) ?", false) }
        return nil
    }

    /// Clic : une photo. ⌘ clic : ajoute ou retire. ⇧ clic : toutes celles entre la photo active et celle-ci.
    private func cliquer(_ i: Int, _ f: FichePhoto) {
        let touches = Clic.touches
        if touches.contains(.shift), photos.indices.contains(index) {
            let (a, b) = (min(index, i), max(index, i))
            choix = Set(photos[a...b].map(\.id))
        } else if touches.contains(.command) {
            if choix.isEmpty, let c = courante { choix = [c.id] }
            if choix.contains(f.id) { choix.remove(f.id) } else { choix.insert(f.id) }
            index = i
        } else {
            index = i
            choix = []
        }
    }

    private var bande: some View {
        ScrollViewReader { lecteur in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { i, f in
                        Button { index = i } label: {
                            VignettePhoto(chemins: [f.copie, f.chemin], cote: 260, entiere: true)
                                .background(Theme.fond)
                                .frame(width: 96, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(i == index ? Theme.accent : Color.clear, lineWidth: 2))
                        }
                        .buttonStyle(BoutonPlat())
                        .id(i)
                    }
                }
            }
            .frame(height: 70)
            .onAppear { lecteur.scrollTo(index, anchor: .center) }
            .onChange(of: index) { i in withAnimation { lecteur.scrollTo(i, anchor: .center) } }
        }
    }

    // MARK: - Panneau de droite

    private var panneauDroit: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if galerie, choix.count > 1 {
                    let l = photos.filter { choix.contains($0.id) }
                    Text("\(l.count) photos choisies").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
                    let codes = Set(l.map(\.codeRetenu))
                    info("Codes", codes.count == 1 ? (codes.first.map { $0.isEmpty ? "sans code" : $0 } ?? "") : "\(codes.count) différents")
                    let prises = l.compactMap(\.prise)
                    if let a = prises.min(), let b = prises.max() {
                        info("Prises", "\(a.formatted(date: .omitted, time: .shortened)) à \(b.formatted(date: .omitted, time: .shortened))")
                    }
                    Text("Les touches et les boutons s'appliquent aux \(l.count) photos. Échap : n'en garder aucune.")
                        .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
                    Divider().overlay(Theme.bordure)
                    Text("Photo active").font(.system(size: 13, weight: .semibold))
                }
                if let f = courante {
                    if !(galerie && choix.count > 1) { Text("Cette photo").font(.system(size: 14, weight: .semibold)) }
                    info("Code", f.codeRetenu.isEmpty ? "sans code" : f.codeRetenu)
                    if !f.cavalier.isEmpty { info("Couple", "\(f.cavalier) · \(f.cheval)") }
                    info("Nom", f.nom)
                    info("Boîtier", f.boitier)
                    info("Prise", f.prise.map { $0.formatted(date: .omitted, time: .standard) } ?? "?")
                    info("Netteté", String(format: "%.0f", f.nettete))
                    if !f.classe.isEmpty { info("Classée", f.classe) }
                    if let m = RevueView.memoire(f) { info("Mémoire", m) }
                    if f.visage >= 0 { info("Visage", String(format: "%.0f %%", f.visage * 100)) }
                    Divider().overlay(Theme.bordure)
                    Text("Historique des codes").font(.system(size: 13, weight: .semibold))
                    Text(f.historique.isEmpty ? "—" : f.historique).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.texteDiscret)
                }
                Divider().overlay(Theme.bordure)
                Text("Mes dernières corrections").font(.system(size: 13, weight: .semibold))
                ForEach(Array(corrections.prefix(8).enumerated()), id: \.offset) { _, c in
                    Text(c).font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
                }
                Text("Chaque classement (bonne, floue, sol, code, chute, meilleure, réseaux) ajoute un exemple à la mémoire partagée ; l'enlever retire l'exemple. Classer ne retire rien du serveur : seul « Supprimer » le fait (annulable).")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            }
            .padding(14)
        }
    }

    private func info(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret).frame(width: 70, alignment: .leading)
            Text(v).font(.system(size: 12)).textSelection(.enabled)
        }
    }

    // MARK: - Actions

    /// Les photos touchées par un geste : celles choisies dans la galerie, sinon la photo affichée.
    private var cibles: [Int] {
        if galerie, !choix.isEmpty { return photos.indices.filter { choix.contains(photos[$0].id) } }
        return photos.indices.contains(index) ? [index] : []
    }

    private func resume(_ l: [Int], _ texte: String) -> String {
        l.count == 1 ? "\(photos[l[0]].origine) \(texte)" : "\(l.count) photos \(texte)"
    }

    /// Classer (B, F, S, C). Plusieurs photos : toutes prennent la classe ; si elles l'avaient toutes, elle est retirée.
    private func classer(_ cle: String) {
        let l = cibles
        guard !l.isEmpty else { return }
        let retirer = l.allSatisfy { photos[$0].classe == cle }
        let devient = retirer ? "" : cle
        corrections.insert(resume(l, "→ \(retirer ? "sans classe" : cle)"), at: 0)
        for i in l {
            let f = photos[i]
            guard f.classe != devient else { continue }
            moteur.classer(f.id, cle)                    // le moteur bascule : même classe → aucune, sinon cle
            if !f.classe.isEmpty && f.classe != cle { etat.noterDansLaMemoire(f, categorie: f.classe, ajouter: false) }
            etat.noterDansLaMemoire(f, categorie: cle, ajouter: !retirer)
            photos[i].classe = devient
        }
        if !galerie { avancer(1) }
    }

    private func basculerChute() {
        let l = cibles
        guard !l.isEmpty else { return }
        let chute = !l.allSatisfy { photos[$0].chute }
        corrections.insert(resume(l, chute ? ": CHUTE" : ": plus de chute"), at: 0)
        for i in l where photos[i].chute != chute {
            let f = photos[i]
            moteur.marquerChute(f.id, chute)
            etat.noterDansLaMemoire(f, categorie: "chute", ajouter: chute)
            photos[i].chute = chute
        }
    }

    /// Meilleure (M) ou réseaux sociaux (R) : marque de HUGO, gardée aussi dans la mémoire.
    private func basculer(_ drapeau: String) {
        let l = cibles
        guard !l.isEmpty else { return }
        let actif = !l.allSatisfy { photos[$0].a(drapeau) }
        corrections.insert(resume(l, ": \(actif ? "" : "plus ")\(Memoire.nom(de: drapeau).lowercased())"), at: 0)
        for i in l where photos[i].a(drapeau) != actif {
            let f = photos[i]
            moteur.marquer(f.id, drapeau, actif)
            etat.noterDansLaMemoire(f, categorie: drapeau, ajouter: actif)
            if actif { photos[i].marquer(drapeau) } else {
                photos[i].drapeaux = f.drapeaux.split(separator: "|").filter { $0 != drapeau }.joined(separator: "|")
            }
        }
    }

    private func appliquerCode() {
        let l = cibles
        guard !l.isEmpty, let c = CodePassage.lire(nouveauCode) else { return }
        moteur.appliquer(code: c.texte, a: l.map { photos[$0].id })
        if l.count == 1 {
            let f = photos[l[0]]
            corrections.insert("\(f.origine) : \(f.codeRetenu.isEmpty ? "sans code" : f.codeRetenu) → \(c.texte)", at: 0)
        } else {
            corrections.insert("\(l.count) photos → \(c.texte)", at: 0)
        }
        let ids = l.map { photos[$0].id }
        for i in l { photos[i].codeFinal = c.texte }
        changerCode = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { rafraichir(ids) }
    }

    private func rafraichir(_ ids: [Int64]) {
        for id in ids {
            guard let i = photos.firstIndex(where: { $0.id == id }), let f = moteur.fiche(id: id) else { continue }
            photos[i] = f
        }
    }

    /// ⌫ : dans « À traiter », supprime (serveur, galerie en ligne, original à la Corbeille) ; dans « Bonnes »,
    /// retire seulement la photo de la sélection (rien n'est effacé) ; ailleurs, rien. Plusieurs photos d'un coup
    /// dans la galerie ; ⌘Z les remet toutes.
    private func supprimer() {
        if suppressionPermise, Visite.partagee.bloque("rien n'est supprimé") { return }
        let l = cibles
        guard let premier = l.first else { return }
        let fiches = l.map { photos[$0] }
        if suppressionPermise {
            moteur.supprimer(fiches.map(\.id))
            retours.append(.suppression(fiches))
            corrections.insert(resume(l, ": supprimée\(l.count > 1 ? "s" : "")"), at: 0)
        } else if let d = ordre.drapeauRetrait {
            for f in fiches {
                moteur.marquer(f.id, d, true)
                if ordre == .meilleures, f.a("meilleure") { moteur.marquer(f.id, "meilleure", false); etat.noterDansLaMemoire(f, categorie: "meilleure", ajouter: false) }
                if ordre == .reseaux, f.a("reseaux") { moteur.marquer(f.id, "reseaux", false); etat.noterDansLaMemoire(f, categorie: "reseaux", ajouter: false) }
            }
            retours.append(.retrait(fiches, d))
            corrections.insert(resume(l, ": retirée\(l.count > 1 ? "s" : "") de « \(ordre.rawValue) »"), at: 0)
        } else {
            return
        }
        for i in l.reversed() { photos.remove(at: i) }
        choix = []
        index = min(premier, max(0, photos.count - 1))
    }

    private func annulerSuppression() {
        guard let r = retours.popLast() else { return }
        let fiches: [FichePhoto]
        switch r {
        case .suppression(let l):
            fiches = l
            moteur.annulerSuppression(l.map(\.id))
            corrections.insert(l.count == 1 ? "\(l[0].origine) : suppression annulée" : "\(l.count) photos : suppression annulée", at: 0)
        case .retrait(let l, let d):
            fiches = l
            for f in l {
                moteur.marquer(f.id, d, false)
                if d == "pasMeilleure", f.a("meilleure") { moteur.marquer(f.id, "meilleure", true); etat.noterDansLaMemoire(f, categorie: "meilleure", ajouter: true) }
                if d == "pasReseaux", f.a("reseaux") { moteur.marquer(f.id, "reseaux", true); etat.noterDansLaMemoire(f, categorie: "reseaux", ajouter: true) }
            }
            corrections.insert(l.count == 1 ? "\(l[0].origine) : remise dans la sélection" : "\(l.count) photos remises dans la sélection", at: 0)
        }
        let ou = min(index, photos.count)
        photos.insert(contentsOf: fiches, at: ou)
        index = ou
        if galerie, fiches.count > 1 { choix = Set(fiches.map(\.id)) }
    }

    private func avancer(_ pas: Int) {
        guard !photos.isEmpty else { return }
        index = min(max(0, index + pas), photos.count - 1)
        if galerie { choix = [] }
    }

    /// Raccourcis de la revue : flèches et lettres, sans touche de modification.
    /// G : galerie · E ou Entrée : photo en grand · ↑ ↓ : ligne du dessus / du dessous dans la galerie ·
    /// ⌘A : tout choisir · Échap : plus rien de choisi.
    private var raccourcis: some View {
        ZStack {
            Button("") { avancer(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { avancer(1) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { if galerie { avancer(-colonnes) } }.keyboardShortcut(.upArrow, modifiers: [])
            Button("") { if galerie { avancer(colonnes) } }.keyboardShortcut(.downArrow, modifiers: [])
            Button("") { if etat.pleinEcran { basculerPleinEcran() }; galerie = true }.keyboardShortcut("g", modifiers: [])
            Button("") { galerie = false }.keyboardShortcut("e", modifiers: [])
            Button("") { if galerie { galerie = false } }.keyboardShortcut(.return, modifiers: [])
            Button("") { if galerie { choix = Set(photos.map(\.id)) } }.keyboardShortcut("a", modifiers: .command)
            Button("") {
                if etat.pleinEcran { basculerPleinEcran() } else if !galerie { galerie = true } else { choix = [] }
            }.keyboardShortcut(.escape, modifiers: [])
            Button("") { basculerPleinEcran() }.keyboardShortcut("p", modifiers: [])
            ForEach(classes) { c in
                Button("") { classer(c.cle) }.keyboardShortcut(KeyEquivalent(c.touche), modifiers: [])
            }
            Button("") { basculerChute() }.keyboardShortcut("x", modifiers: [])
            Button("") { basculer("meilleure") }.keyboardShortcut("m", modifiers: [])
            Button("") { basculer("reseaux") }.keyboardShortcut("r", modifiers: [])
            Button("") { supprimer() }.keyboardShortcut(.delete, modifiers: [])
            Button("") { annulerSuppression() }.keyboardShortcut("z", modifiers: .command)
        }
        .opacity(0)
        .disabled(changerCode || saisieActive)
    }
}
