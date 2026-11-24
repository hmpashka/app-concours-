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
    @State private var ordre: Ordre = .douteuses
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

    private enum Retour {
        case suppression(FichePhoto)
        case retrait(FichePhoto, String)                 // retirée des bonnes : drapeau posé
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

    /// « Supprimer » n'existe que dans les filtres « À traiter » : jamais sur les bonnes photos.
    private var suppressionPermise: Bool { ordre.groupe == .aTraiter }

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
        HStack(spacing: 0) {
            if etat.panneauGauche {
                filtres.frame(width: 240).background(Theme.panneau)
                Divider().overlay(Theme.bordure)
            }
            centre.frame(maxWidth: .infinity, maxHeight: .infinity)
            if etat.panneauDroit {
                Divider().overlay(Theme.bordure)
                panneauDroit.frame(width: 300).background(Theme.panneau)
            }
        }
        .onAppear(perform: charger)
        .onChange(of: epreuve) { _ in charger() }
        .onChange(of: boitier) { _ in charger() }
        .onChange(of: ordre) { _ in charger() }
        .onChange(of: piste) { _ in charger() }
        .onChange(of: parHeure) { _ in charger() }
        .onChange(of: heureDe) { _ in if parHeure { charger() } }
        .onChange(of: heureA) { _ in if parHeure { charger() } }
        .onChange(of: recherche) { _ in charger() }
        .onChange(of: etat.momentRevue?.heure) { _ in charger() }
        .onChange(of: etat.photosRevue?.ids) { _ in charger() }
        .background(raccourcis)
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
            DispatchQueue.main.async {
                let garde = courante?.id
                photos = l
                index = garde.flatMap { g in l.firstIndex { $0.id == g } } ?? 0
            }
        }
    }

    private func rafraichirCourante() {
        guard let c = courante, let f = moteur.fiche(id: c.id), photos.indices.contains(index) else { return }
        photos[index] = f
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
            Toggle("Entre deux heures", isOn: $parHeure).font(.system(size: 12))
            if parHeure {
                HStack(spacing: 6) {
                    DatePicker("", selection: $heureDe, displayedComponents: .hourAndMinute).labelsHidden()
                    Text("à").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                    DatePicker("", selection: $heureA, displayedComponents: .hourAndMinute).labelsHidden()
                }
            }
            TextField("Code, cavalier ou cheval", text: $recherche).textFieldStyle(.roundedBorder)
            Text("Filtre").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
            Picker("", selection: $ordre) {
                Section("Toutes les photos") { ForEach(Ordre.du(.toutes)) { Text($0.rawValue).tag($0) } }
                Section("Photos à traiter (suppression possible)") { ForEach(Ordre.du(.aTraiter)) { Text($0.rawValue).tag($0) } }
                Section("Bonnes photos (jamais supprimées ici)") { ForEach(Ordre.du(.bonnes)) { Text($0.rawValue).tag($0) } }
            }
            .labelsHidden()
            Text(ordre.groupe == .aTraiter ? "À traiter : ⌫ supprime (serveur, galerie en ligne, original à la Corbeille), ⌘Z annule."
                 : ordre.groupe == .bonnes ? "Bonnes photos : rien n'est supprimé ici. ⌫ retire la photo de cette sélection seulement, ⌘Z annule."
                 : "Pour supprimer, passe par un filtre « À traiter ».")
                .font(.system(size: 11)).foregroundStyle(ordre.groupe == .aTraiter ? Theme.attention : Theme.texteTresDiscret)
            if ordre == .belles {
                Text("Pour les réseaux sociaux : la plus belle photo de chaque couple, d'après la mémoire (catégorie « Meilleures ») et la netteté.")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            }
            Button("Actualiser") { charger() }.buttonStyle(BoutonStyle())
            Spacer()
            Text("\(photos.count) photos").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
        }
        .padding(14)
    }

    // MARK: - Centre

    private var centre: some View {
        VStack(spacing: 10) {
            if let f = courante {
                HStack {
                    Text("Photo \(index + 1) sur \(photos.count)").font(.system(size: 13, weight: .semibold))
                    Text("← → pour avancer · la lettre pour classer · X : chute · M : meilleure · R : réseaux").font(.system(size: 11))
                        .foregroundStyle(Theme.texteTresDiscret)
                    Spacer()
                    if let m = RevueView.memoire(f) {
                        Pastille(texte: "Mémoire : \(m)", genre: RevueView.memoireDoute(f) ? .attention : .neutre)
                    }
                    if let d = douteuse(f, dans: photos) { Pastille(texte: "Détectée : \(d)", genre: .attention) }
                }
                VignettePhoto(chemins: [f.copie, f.chemin], cote: 1400)
                    .aspectRatio(3 / 2, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 8) {
                    ForEach(classes) { c in
                        Button("\(c.nom) (\(String(c.touche).uppercased()))") { classer(c.cle) }
                            .buttonStyle(BoutonStyle(principal: f.classe == c.cle))
                    }
                    Button(f.chute ? "Chute ✓ (X)" : "Chute (X)") { basculerChute() }
                        .buttonStyle(BoutonStyle(principal: f.chute))
                    Button(f.a("meilleure") ? "Meilleure ✓ (M)" : "Meilleure (M)") { basculer("meilleure") }
                        .buttonStyle(BoutonStyle(principal: f.a("meilleure")))
                    Button(f.a("reseaux") ? "Réseaux ✓ (R)" : "Réseaux (R)") { basculer("reseaux") }
                        .buttonStyle(BoutonStyle(principal: f.a("reseaux")))
                    Spacer()
                    if !retours.isEmpty {
                        Button("Annuler (⌘Z)") { annulerSuppression() }.buttonStyle(BoutonStyle())
                    }
                    if ordre.drapeauRetrait != nil {
                        Button("Retirer de la sélection (⌫)") { supprimer() }
                            .buttonStyle(BoutonStyle())
                            .help("La photo n'est plus retenue dans ce filtre. Elle reste sur le serveur et dans Lightroom.")
                    }
                    if suppressionPermise {
                        Button("Supprimer (⌫)") { supprimer() }
                            .buttonStyle(BoutonStyle())
                            .help("Retire la copie du serveur local et de la galerie en ligne, et met l'original à la Corbeille. Dans Lightroom, elle apparaît manquante : clic droit sur le dossier › Synchroniser le dossier.")
                    }
                    Button("Changer le code…") { nouveauCode = f.codeRetenu; changerCode = true }
                        .buttonStyle(BoutonStyle())
                }
                if changerCode {
                    HStack {
                        TextField("#08_14", text: $nouveauCode).textFieldStyle(.roundedBorder).frame(width: 140)
                            .onSubmit(appliquerCode)
                        if let c = CodePassage.lire(nouveauCode), let g = etat.concours?.couple(pour: c) {
                            Text("\(g.cavalier) · \(g.cheval)").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                        }
                        Button("Appliquer", action: appliquerCode).buttonStyle(BoutonStyle(principal: true))
                            .disabled(CodePassage.lire(nouveauCode) == nil)
                        Button("Annuler") { changerCode = false }.buttonStyle(BoutonStyle())
                        Spacer()
                    }
                }
                bande
            } else {
                Spacer()
                Text("Aucune photo envoyée pour ce choix.").foregroundStyle(Theme.texteDiscret)
                Spacer()
            }
        }
        .padding(20)
    }

    private var bande: some View {
        ScrollViewReader { lecteur in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { i, f in
                        Button { index = i } label: {
                            VignettePhoto(chemins: [f.copie, f.chemin], cote: 200)
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
            .onChange(of: index) { i in withAnimation { lecteur.scrollTo(i, anchor: .center) } }
        }
    }

    // MARK: - Panneau de droite

    private var panneauDroit: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let f = courante {
                    Text("Cette photo").font(.system(size: 14, weight: .semibold))
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

    private func classer(_ cle: String) {
        guard let f = courante else { return }
        moteur.classer(f.id, cle)
        if !f.classe.isEmpty && f.classe != cle { etat.noterDansLaMemoire(f, categorie: f.classe, ajouter: false) }
        etat.noterDansLaMemoire(f, categorie: cle, ajouter: f.classe != cle)
        corrections.insert("\(f.origine) → \(f.classe == cle ? "sans classe" : cle)", at: 0)
        photos[index].classe = f.classe == cle ? "" : cle
        avancer(1)
    }

    private func basculerChute() {
        guard let f = courante else { return }
        moteur.marquerChute(f.id, !f.chute)
        etat.noterDansLaMemoire(f, categorie: "chute", ajouter: !f.chute)
        photos[index].chute.toggle()
        corrections.insert("\(f.origine) : \(f.chute ? "plus de chute" : "CHUTE")", at: 0)
    }

    /// Meilleure (M) ou réseaux sociaux (R) : marque de HUGO, gardée aussi dans la mémoire.
    private func basculer(_ drapeau: String) {
        guard let f = courante else { return }
        let actif = !f.a(drapeau)
        moteur.marquer(f.id, drapeau, actif)
        etat.noterDansLaMemoire(f, categorie: drapeau, ajouter: actif)
        if actif { photos[index].marquer(drapeau) } else {
            photos[index].drapeaux = f.drapeaux.split(separator: "|").filter { $0 != drapeau }.joined(separator: "|")
        }
        corrections.insert("\(f.origine) : \(actif ? "" : "plus ")\(Memoire.nom(de: drapeau).lowercased())", at: 0)
    }

    private func appliquerCode() {
        guard let f = courante, let c = CodePassage.lire(nouveauCode) else { return }
        moteur.appliquer(code: c.texte, a: [f.id])
        corrections.insert("\(f.origine) : \(f.codeRetenu.isEmpty ? "sans code" : f.codeRetenu) → \(c.texte)", at: 0)
        photos[index].codeFinal = c.texte
        changerCode = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { rafraichirCourante() }
    }

    /// Supprimer la photo affichée : copie retirée du serveur (et de la galerie en ligne), original à la Corbeille.
    /// ⌫ : dans « À traiter », supprime (serveur, galerie en ligne, original à la Corbeille) ; dans « Bonnes »,
    /// retire seulement la photo de la sélection (rien n'est effacé) ; ailleurs, rien.
    private func supprimer() {
        guard let f = courante else { return }
        if suppressionPermise {
            moteur.supprimer([f.id])
            retours.append(.suppression(f))
            corrections.insert("\(f.origine) : supprimée", at: 0)
        } else if let d = ordre.drapeauRetrait {
            moteur.marquer(f.id, d, true)
            if ordre == .meilleures, f.a("meilleure") { moteur.marquer(f.id, "meilleure", false); etat.noterDansLaMemoire(f, categorie: "meilleure", ajouter: false) }
            if ordre == .reseaux, f.a("reseaux") { moteur.marquer(f.id, "reseaux", false); etat.noterDansLaMemoire(f, categorie: "reseaux", ajouter: false) }
            retours.append(.retrait(f, d))
            corrections.insert("\(f.origine) : retirée de « \(ordre.rawValue) »", at: 0)
        } else {
            return
        }
        photos.remove(at: index)
        if index >= photos.count { index = max(0, photos.count - 1) }
    }

    private func annulerSuppression() {
        guard let r = retours.popLast() else { return }
        switch r {
        case .suppression(let f):
            moteur.annulerSuppression([f.id])
            corrections.insert("\(f.origine) : suppression annulée", at: 0)
            photos.insert(f, at: min(index, photos.count))
        case .retrait(let f, let d):
            moteur.marquer(f.id, d, false)
            if d == "pasMeilleure", f.a("meilleure") { moteur.marquer(f.id, "meilleure", true); etat.noterDansLaMemoire(f, categorie: "meilleure", ajouter: true) }
            if d == "pasReseaux", f.a("reseaux") { moteur.marquer(f.id, "reseaux", true); etat.noterDansLaMemoire(f, categorie: "reseaux", ajouter: true) }
            corrections.insert("\(f.origine) : remise dans la sélection", at: 0)
            photos.insert(f, at: min(index, photos.count))
        }
    }

    private func avancer(_ pas: Int) {
        guard !photos.isEmpty else { return }
        index = min(max(0, index + pas), photos.count - 1)
    }

    /// Raccourcis de la revue : flèches et lettres, sans touche de modification.
    private var raccourcis: some View {
        ZStack {
            Button("") { avancer(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { avancer(1) }.keyboardShortcut(.rightArrow, modifiers: [])
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
        .disabled(changerCode)
    }
}
