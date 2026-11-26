import SwiftUI
import TriPhotoCommun
import TriPhotoMoteur

/// Écran « À valider » (maquette 2) : les corrections de code proposées, série par série.
/// Rien n'est appliqué sans HUGO. Entrée valide, Échap refuse (le code du photographe est gardé).
struct AValiderView: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var moteur: Moteur
    @State private var choisie: String?
    @State private var selection: Set<Int64> = []
    @State private var saisie = ""
    @State private var montrer00 = false
    @State private var serieDeLaSelection = ""
    @State private var enGrand: DepartVisionneuse?      // photo en grand (double-clic, ou bouton « Photo »)

    private var r: ResumeMoteur { moteur.resume }
    /// Séries que HUGO vient de traiter : cachées quelques secondes, le temps que le moteur les retire. En rush,
    /// Entrée ou Échap tapés deux fois de suite ne revalident jamais la même série : on passe à la suivante.
    @State private var traitees: [String: Date] = [:]
    private var series: [SerieAValider] {
        let maintenant = Date()
        return r.series.filter { s in traitees[s.id].map { maintenant.timeIntervalSince($0) > 4 } ?? true }
    }
    private var serie: SerieAValider? { series.first { $0.id == choisie } ?? series.first }

    private func traitee(_ s: SerieAValider) {
        traitees[s.id] = Date()
        traitees = traitees.filter { Date().timeIntervalSince($0.value) < 30 }
        serieDeLaSelection = ""
        choisie = nil
    }

    var body: some View {
        HStack(spacing: 0) {
            if etat.panneauGauche {
                listeSeries.frame(width: 300).background(Theme.panneau)
                Divider().overlay(Theme.bordure)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let s = serie {
                        detail(s)
                    } else {
                        Carte(titre: "Rien à valider") {
                            Text("Toutes les photos partent avec le bon code. Les propositions du chrono et les photos de code apparaîtront ici.")
                                .font(.system(size: 13)).foregroundStyle(Theme.texteDiscret)
                        }
                    }
                    carte00
                    carteValidees
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity)
            if etat.panneauDroit {
                Divider().overlay(Theme.bordure)
                panneauDroit.frame(width: 300).background(Theme.panneau)
            }
        }
        .onAppear { synchroniser() }
        .onChange(of: serie?.id) { _ in synchroniser() }
        .onReceive(etat.ordresLoupedeck) { recevoirLoupedeck($0) }
        .onChange(of: signatureLoupedeck) { _ in publierLoupedeck() }
        .onAppear(perform: publierLoupedeck)
        .onDisappear { etat.infoSerieLoupedeck = nil; etat.photoLoupedeck = nil }
        .sheet(isPresented: $montrer00) { Liste00View(moteur: moteur).environmentObject(etat) }
        .sheet(item: $enGrand) { d in
            Visionneuse(elements: photosEnGrand, depart: d.id,
                        choisie: { Int64($0).map { selection.contains($0) } ?? false },
                        basculer: { if let id = Int64($0), serie?.photos.contains(where: { $0.id == id }) == true { basculer(id) } })
        }
    }

    // MARK: - Loupedeck CT

    private var normales: [SerieAValider] { series.filter { $0.genre != .rush } }

    private var signatureLoupedeck: String {
        "\(serie?.id ?? "")|\(series.count)|\(selection.count)|\(saisie)"
    }

    private func publierLoupedeck() {
        guard let s = serie else { etat.infoSerieLoupedeck = nil; etat.photoLoupedeck = nil; return }
        let l = series
        etat.infoSerieLoupedeck = EtatLoupedeck.Serie(
            position: (l.firstIndex { $0.id == s.id } ?? 0) + 1, total: l.count, code: s.code,
            proposition: codeSaisi?.texte ?? s.proposition, photos: selection.count, photoCode: s.genre == .photoCode)
        etat.photoLoupedeck = s.photoCode?.id ?? s.photos.first { selection.contains($0.id) }?.id ?? s.photos.first?.id
    }

    /// Boutons du Loupedeck : série suivante / précédente, Valider (comme Entrée), Ignorer (comme Échap).
    private func recevoirLoupedeck(_ o: OrdreLoupedeck) {
        let l = series
        switch o.nom {
        case "serie", "photo":
            guard !l.isEmpty else { return }
            let i = l.firstIndex { $0.id == serie?.id } ?? 0
            choisie = l[min(max(0, i + o.pas), l.count - 1)].id
        case "serie.ouvrir":
            choisie = normales.first?.id ?? l.first?.id
        case "valider":
            if let s = serie { valider(s) }
        case "ignorer":
            guard let s = serie else { return }
            if s.genre == .photoCode {
                if let pc = s.photoCode { moteur.utiliserPhotoCode(pc, pour: []); traitee(s) }
            } else if !selection.isEmpty {
                traitee(s)
                etat.noterSerieValidee(Array(selection), titre: "\(selection.count) photo\(selection.count > 1 ? "s" : "") gardée\(selection.count > 1 ? "s" : "") en \(s.code.isEmpty ? "sans code" : s.code) · \(s.boitier)")
                moteur.garderCodePhotographe(Array(selection))
            }
        default: break
        }
    }

    /// Nouvelle série affichée : sélection et code proposés d'office.
    private func synchroniser() {
        guard let s = serie else { return }
        if serieDeLaSelection != s.id {
            serieDeLaSelection = s.id
            selection = s.preselection
            saisie = s.proposition
        }
    }

    // MARK: - Liste des séries

    private var listeSeries: some View {
        VStack(alignment: .leading, spacing: 8) {
            let normales = series.filter { $0.genre != .rush }
            let rushs = series.filter { $0.genre == .rush }
            HStack {
                Text("Séries à valider").font(.system(size: 14, weight: .semibold))
                Spacer()
                Pastille(texte: "\(normales.count) en attente", genre: normales.isEmpty ? .neutre : .attention)
            }
            if r.aValider > 0 {
                Button("Rush : tout envoyer, je reprends au calme") { moteur.rushToutEnvoyer() }
                    .buttonStyle(BoutonStyle())
                    .help("Toutes les photos partent tout de suite au serveur avec le code du photographe. Les propositions du chrono restent ci-dessous, à reprendre plus tard.")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(normales) { s in
                        Button { choisie = s.id } label: { ligneSerie(s, active: s.id == serie?.id) }
                            .buttonStyle(BoutonPlat())
                    }
                    if !rushs.isEmpty {
                        Text("À reprendre au calme (\(r.aReprendre) photo\(r.aReprendre > 1 ? "s" : ""), déjà envoyées)")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.texteDiscret)
                            .padding(.top, 10)
                        ForEach(rushs) { s in
                            Button { choisie = s.id } label: { ligneSerie(s, active: s.id == serie?.id) }
                                .buttonStyle(BoutonPlat())
                        }
                    }
                }
            }
        }
        .padding(14)
    }

    private func ligneSerie(_ s: SerieAValider, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(s.genre == .photoCode ? "Photo de code" : "\(s.photos.count) photo\(s.photos.count > 1 ? "s" : "")")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(s.confiance) %").font(.system(size: 11)).foregroundStyle(s.confiance >= 90 ? Theme.ok : Theme.attention)
            }
            HStack(spacing: 6) {
                Text(s.code.isEmpty ? (s.genre == .photoCode ? "…" : "sans code") : s.code)
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.texteDiscret)
                Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Theme.texteTresDiscret)
                Text(s.proposition).font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            Text(s.boitier).font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret).lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? Theme.selection : Theme.carte, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Détail d'une série

    /// Les photos de la série en grand : la photo de code d'abord s'il y en a une.
    private var photosEnGrand: [ElementVisionneuse] {
        guard let s = serie else { return [] }
        return ([s.photoCode].compactMap { $0 } + s.photos).map(\.elementVisionneuse)
    }

    @ViewBuilder
    private func detail(_ s: SerieAValider) -> some View {
        let couple = CodePassage.lire(s.proposition).flatMap { etat.concours?.couple(pour: $0) }
        Carte(titre: s.genre == .photoCode ? "Photo de code \(s.proposition) · \(s.boitier)"
                                           : "\(s.photos.count) photo\(s.photos.count > 1 ? "s" : "")\(s.genre == .rush ? " envoyée\(s.photos.count > 1 ? "s" : "") en rush" : "") · \(s.boitier)",
              sousTitre: s.genre == .rush ? "Déjà sur le serveur avec le code du photographe. Valider refait la copie et les métadonnées avec le bon code." : nil) {
            HStack(alignment: .top, spacing: 16) {
                if s.genre == .photoCode, let pc = s.photoCode {
                    VignettePhoto(chemins: [pc.chemin], cote: 400).frame(width: 220, height: 146)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onTapGesture(count: 2) { enGrand = DepartVisionneuse(id: String(pc.id)) }
                        .help("Double-clic : en grand")
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if !s.code.isEmpty {
                            Text(s.code).font(.system(size: 20, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.texteDiscret)
                            Image(systemName: "arrow.right").foregroundStyle(Theme.texteTresDiscret)
                        }
                        Text(s.proposition).font(.system(size: 20, weight: .semibold, design: .monospaced))
                    }
                    if let couple {
                        Text("\(couple.cavalier) · \(couple.cheval)").font(.system(size: 13))
                    }
                    Text("Indice de confiance : \(s.confiance) %\(s.confiance >= 90 ? " · très sûr" : "")")
                        .font(.system(size: 12)).foregroundStyle(s.confiance >= 90 ? Theme.ok : Theme.attention)
                    Text("Pourquoi : \(s.raison)").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        Carte(titre: "Code à appliquer", sousTitre: "Le nom s'affiche dès que le code est tapé, pour vérifier.") {
            HStack {
                TextField("Code, ou nom du cavalier / du cheval", text: $saisie)
                    .textFieldStyle(.roundedBorder).frame(width: 300)
                    .onSubmit { valider(s) }
                Text(nomPourSaisie ?? "Code inconnu").font(.system(size: 12))
                    .foregroundStyle(nomPourSaisie == nil ? Theme.attention : Theme.texteDiscret)
                Spacer()
            }
        }
        Carte(titre: s.genre == .photoCode ? "Les 15 photos avant la photo de code" : "Les photos de la série",
              sousTitre: "Clique sur une photo pour l'ajouter ou la retirer · \(selection.count) sélectionnée\(selection.count > 1 ? "s" : "")") {
            HStack {
                Text("Double-clic sur une photo : en grand (← → pour avancer, Espace pour la choisir)")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
                Spacer()
                SelecteurVue(galerie: choixVue($enGrand) {
                    (s.photos.first { selection.contains($0.id) } ?? s.photos.first).map { String($0.id) }
                })
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                ForEach(s.photos, id: \.id) { f in
                    Button { basculer(f.id) } label: { vignette(f, choisie: selection.contains(f.id)) }
                        .buttonStyle(BoutonPlat())
                        .simultaneousGesture(TapGesture(count: 2).onEnded { enGrand = DepartVisionneuse(id: String(f.id)) })
                }
            }
        }
        HStack {
            Button("Valider la série") { valider(s) }
                .buttonStyle(BoutonStyle(principal: true))
                .keyboardShortcut(.defaultAction)
                .disabled(codeSaisi == nil || selection.isEmpty)
            if s.genre == .photoCode {
                Button("Ignorer la photo de code") { if let pc = s.photoCode { moteur.utiliserPhotoCode(pc, pour: []); traitee(s) } }
                    .buttonStyle(BoutonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Ce n'est pas une photo de code") { if let pc = s.photoCode { moteur.pasUnePhotoDeCode(pc); traitee(s) } }
                    .buttonStyle(BoutonStyle())
            } else {
                Button("Refuser (garder le code du photographe)") {
                    etat.noterSerieValidee(Array(selection), titre: "\(selection.count) photo\(selection.count > 1 ? "s" : "") gardée\(selection.count > 1 ? "s" : "") en \(s.code.isEmpty ? "sans code" : s.code) · \(s.boitier)")
                    moteur.garderCodePhotographe(Array(selection))
                    traitee(s)
                }
                    .buttonStyle(BoutonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            Text("Entrée valide · Échap refuse · le code d'origine reste dans « Identifiant de la tâche »")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
        }
    }

    private func vignette(_ f: FichePhoto, choisie: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            VignettePhoto(chemins: [f.copie, f.chemin], cote: 260)
                .frame(height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(choisie ? Theme.accent : Theme.bordure, lineWidth: choisie ? 3 : 1))
            Text(f.prise.map { $0.formatted(date: .omitted, time: .standard) } ?? "?").font(.system(size: 10))
                .foregroundStyle(Theme.texteDiscret)
            Text(f.codeRetenu.isEmpty ? "sans code" : f.codeRetenu).font(.system(size: 11, design: .monospaced))
            if choisie, let c = codeSaisi, c.texte != f.codeRetenu {
                Text("devient \(c.texte)").font(.system(size: 10)).foregroundStyle(Theme.accent)
            }
        }
    }

    private func basculer(_ id: Int64) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func valider(_ s: SerieAValider) {
        guard let c = codeSaisi, !selection.isEmpty else { return }
        etat.noterSerieValidee(Array(selection), titre: "\(selection.count) photo\(selection.count > 1 ? "s" : "") → \(c.texte) · \(s.boitier)")
        if s.genre == .photoCode, let pc = s.photoCode {
            if c.texte == pc.code {
                moteur.utiliserPhotoCode(pc, pour: Array(selection))
            } else {
                moteur.appliquer(code: c.texte, a: Array(selection))
                moteur.utiliserPhotoCode(pc, pour: [])
            }
        } else {
            moteur.appliquer(code: c.texte, a: Array(selection))
        }
        traitee(s)
    }

    // MARK: - Saisie : code ou nom

    /// Le code tapé, ou retrouvé d'après un nom de cavalier ou de cheval (dans l'épreuve proposée d'abord).
    private var codeSaisi: CodePassage? {
        let t = saisie.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        if t.contains("_") || t.contains("#") || t.first?.isNumber == true { return CodePassage.lire(t) }
        guard let concours = etat.concours else { return nil }
        let epreuvePref = CodePassage.lire(serie?.proposition ?? "")?.epreuve
        let bas = t.lowercased()
        var trouves: [(Epreuve, Engage)] = []
        for e in concours.epreuves {
            for g in e.engages where g.cavalier.lowercased().contains(bas) || g.cheval.lowercased().contains(bas) {
                trouves.append((e, g))
            }
        }
        if let p = epreuvePref, let m = trouves.filter({ $0.0.cle == p }).first, trouves.filter({ $0.0.cle == p }).count == 1 {
            return CodePassage(epreuve: m.0.numero, dossard: m.1.dossard)
        }
        if trouves.count == 1 { return CodePassage(epreuve: trouves[0].0.numero, dossard: trouves[0].1.dossard) }
        return nil
    }

    private var nomPourSaisie: String? {
        guard let c = codeSaisi else { return nil }
        if c.special == .inconnu { return "\(c.texte) · engagé terrain / inconnu" }
        if c.special == .remiseDesPrix { return "\(c.texte) · remise des prix" }
        guard let g = etat.concours?.couple(pour: c) else { return "\(c.texte) · pas dans le fichier FFE" }
        return "\(c.texte) · \(g.cavalier) · \(g.cheval)"
    }

    // MARK: - _00 et panneau de droite

    /// Les séries déjà validées : un clic les ouvre dans la revue pour les trier (bonne, floue, sol, supprimer…).
    @ViewBuilder
    private var carteValidees: some View {
        if !etat.seriesValidees.isEmpty {
            Carte(titre: "Séries validées", sousTitre: "Pour les revoir et les trier dans la Revue, quand c'est calme.") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(etat.seriesValidees.prefix(10).enumerated()), id: \.offset) { _, v in
                        HStack {
                            Text(v.heure.formatted(date: .omitted, time: .shortened)).font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.texteDiscret)
                            Text(v.titre).font(.system(size: 12))
                            Spacer()
                            Button("Revoir et trier") { etat.voirPhotos(v.ids, titre: "Série validée : \(v.titre)") }
                                .buttonStyle(BoutonStyle())
                        }
                    }
                }
            }
        }
    }

    private var carte00: some View {
        Carte(titre: "\(r.sans00.count) photo\(r.sans00.count > 1 ? "s" : "") en _00 ou sans code aujourd'hui",
              sousTitre: "À attribuer en quelques clics avec les passages du chrono.") {
            Button("Ouvrir la liste des _00") { montrer00 = true }
                .buttonStyle(BoutonStyle())
                .disabled(r.sans00.isEmpty)
        }
    }

    private var panneauDroit: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Passages du chrono").font(.system(size: 14, weight: .semibold))
                if r.passagesRecents.isEmpty {
                    Text(r.chrono == nil ? "Pas de chrono réglé." : "Aucun passage pour l'instant.")
                        .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                }
                ForEach(Array(r.passagesRecents.prefix(25).enumerated()), id: \.offset) { _, p in
                    HStack(alignment: .top) {
                        Text(Self.heures(p)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.texteDiscret)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("#\(p.epreuve)_\(p.dossard)").font(.system(size: 12, weight: .semibold, design: .monospaced))
                            Text(p.cavalier).font(.system(size: 11)).foregroundStyle(Theme.texteDiscret).lineLimit(1)
                        }
                    }
                }
                Text("Les photos d'un cavalier prises juste après son arrivée restent à lui (fin de tour, tolérance normale).")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
                if let s = serie, let f = s.photos.first(where: { selection.contains($0.id) }) ?? s.photoCode {
                    Divider().overlay(Theme.bordure)
                    Text("Historique des codes · \(f.origine)").font(.system(size: 13, weight: .semibold))
                    Text(f.historique.isEmpty ? "—" : f.historique).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.texteDiscret)
                }
            }
            .padding(14)
        }
    }

    static func heures(_ p: Passage) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let debut = f.string(from: Date(timeIntervalSince1970: p.debut))
        return p.fin.map { "\(debut)–\(f.string(from: Date(timeIntervalSince1970: $0)))" } ?? "\(debut)–…"
    }
}

/// Liste des photos parties en _00 ou sans code : on en choisit, on tape (ou choisit) le bon code.
struct Liste00View: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var moteur: Moteur
    @Environment(\.dismiss) private var fermer
    @State private var selection: Set<Int64> = []
    @State private var saisie = ""
    @State private var enGrand: DepartVisionneuse?
    @State private var supprimees: [[Int64]] = []         // pour « Annuler la suppression »
    @State private var gardees: [[Int64]] = []            // « OK, on garde comme ça » : pour les remettre

    /// Épreuve des photos choisies (« #07_00 » → 07) : les noms trouvés dans cette épreuve passent devant.
    private var epreuveChoisie: String? {
        let eps = Set(moteur.resume.sans00.filter { selection.contains($0.id) }.compactMap { CodePassage.lire($0.codeRetenu)?.epreuve })
        return eps.count == 1 ? eps.first : nil
    }

    /// Recherche par nom (HUGO 26/11 : « sur les _00 on ne sait pas quel code ») : on tape une partie du nom du
    /// cavalier ou du cheval lu sur l'écran du terrain ou reconnu sur la photo, l'app donne les codes possibles.
    private struct Candidat: Identifiable {
        var code: CodePassage
        var cavalier: String
        var cheval: String
        var id: String { code.texte }
    }

    private var candidats: [Candidat] {
        let t = saisie.trimmingCharacters(in: .whitespaces).lowercased()
        guard t.count >= 2, !t.contains("_"), !t.contains("#"), let concours = etat.concours else { return [] }
        if t.allSatisfy(\.isNumber) {
            // un dossard seul (« 34 ») : dans l'épreuve des photos choisies d'abord, sinon partout
            let l = concours.epreuves.compactMap { e in e.engage(dossard: t).map { (e, $0) } }
            let pref = l.filter { $0.0.cle == epreuveChoisie }
            return (pref.isEmpty ? l : pref).prefix(8).map { Candidat(code: CodePassage(epreuve: $0.0.numero, dossard: $0.1.dossard), cavalier: $0.1.cavalier, cheval: $0.1.cheval) }
        }
        var l: [(Epreuve, Engage)] = []
        for e in concours.epreuves {
            for g in e.engages where g.cavalier.lowercased().contains(t) || g.cheval.lowercased().contains(t) { l.append((e, g)) }
        }
        l.sort { ($0.0.cle == epreuveChoisie ? 0 : 1) < ($1.0.cle == epreuveChoisie ? 0 : 1) }
        return l.prefix(8).map { Candidat(code: CodePassage(epreuve: $0.0.numero, dossard: $0.1.dossard), cavalier: $0.1.cavalier, cheval: $0.1.cheval) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Photos en _00 ou sans code").font(.system(size: 16, weight: .semibold))
                Spacer()
                SelecteurVue(galerie: choixVue($enGrand) {
                    (moteur.resume.sans00.first { selection.contains($0.id) } ?? moteur.resume.sans00.first).map { String($0.id) }
                })
                Button("Fermer") { fermer() }.buttonStyle(BoutonStyle()).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                    ForEach(moteur.resume.sans00, id: \.id) { f in
                        Button {
                            if selection.contains(f.id) { selection.remove(f.id) } else { selection.insert(f.id) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                VignettePhoto(chemins: [f.copie, f.chemin], cote: 260).frame(height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(RoundedRectangle(cornerRadius: 4)
                                        .stroke(selection.contains(f.id) ? Theme.accent : Theme.bordure, lineWidth: selection.contains(f.id) ? 3 : 1))
                                // le code complet de la photo (HUGO 26/11), puis l'heure et le boîtier
                                Text(f.codeRetenu.isEmpty ? "sans code" : f.codeRetenu)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(f.codeRetenu.isEmpty ? Theme.attention : Theme.texte)
                                Text("\(f.prise.map { $0.formatted(date: .omitted, time: .standard) } ?? "?") · \(f.boitier)")
                                    .font(.system(size: 10)).foregroundStyle(Theme.texteDiscret).lineLimit(1)
                            }
                        }
                        .buttonStyle(BoutonPlat())
                        .simultaneousGesture(TapGesture(count: 2).onEnded { enGrand = DepartVisionneuse(id: String(f.id)) })
                    }
                }
            }
            .frame(height: 360)
            Text("Passages du chrono (clic : prendre ce code)").font(.system(size: 13, weight: .semibold))
            ScrollView(.horizontal) {
                HStack {
                    ForEach(Array(moteur.resume.passagesRecents.enumerated()), id: \.offset) { _, p in
                        Button("\(AValiderView.heures(p)) · #\(p.epreuve)_\(p.dossard) \(p.cavalier)") {
                            saisie = p.code.texte
                        }
                        .buttonStyle(BoutonStyle())
                    }
                }
            }
            if !candidats.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(candidats) { c in
                            Button("\(c.code.texte) · \(c.cavalier) · \(c.cheval)") { saisie = c.code.texte }
                                .buttonStyle(BoutonStyle())
                        }
                    }
                }
            }
            HStack {
                TextField("Code (#08_14), dossard ou nom", text: $saisie).textFieldStyle(.roundedBorder).frame(width: 220)
                if let c = CodePassage.lire(saisie), let g = etat.concours?.couple(pour: c) {
                    Text("\(g.cavalier) · \(g.cheval)").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                }
                Spacer()
                if !supprimees.isEmpty {
                    Button("Annuler la suppression") { moteur.annulerSuppression(supprimees.removeLast()) }
                        .buttonStyle(BoutonStyle())
                }
                if !gardees.isEmpty {
                    Button("Remettre dans la liste") { moteur.garder00(gardees.removeLast(), false) }
                        .buttonStyle(BoutonStyle())
                }
                Button("OK, on garde comme ça") {
                    let ids = Array(selection)
                    moteur.garder00(ids)
                    gardees.append(ids)
                    selection = []
                }
                .buttonStyle(BoutonStyle())
                .disabled(selection.isEmpty)
                .help("Ces photos restent avec leur code actuel (_00 ou sans code) et quittent cette liste. Rien n'est déplacé.")
                Button("Supprimer") {
                    let ids = Array(selection)
                    moteur.supprimer(ids)
                    supprimees.append(ids)
                    selection = []
                }
                .buttonStyle(BoutonStyle())
                .disabled(selection.isEmpty)
                .help("Retire la copie du serveur local et de la galerie en ligne, original à la Corbeille. « Annuler la suppression » la remet.")
                Button("Appliquer à \(selection.count) photo\(selection.count > 1 ? "s" : "")") {
                    if let c = CodePassage.lire(saisie) { moteur.appliquer(code: c.texte, a: Array(selection)) }
                    selection = []
                }
                .buttonStyle(BoutonStyle(principal: true))
                .disabled(CodePassage.lire(saisie) == nil || selection.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 900)
        .background(Theme.fond)
        .foregroundStyle(Theme.texte)
        .sheet(item: $enGrand) { d in
            Visionneuse(elements: moteur.resume.sans00.map(\.elementVisionneuse), depart: d.id,
                        choisie: { Int64($0).map { selection.contains($0) } ?? false },
                        basculer: { if let id = Int64($0) { if selection.contains(id) { selection.remove(id) } else { selection.insert(id) } } })
        }
    }
}
