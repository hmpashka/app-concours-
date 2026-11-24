import AppKit
import SwiftUI
import TriPhotoCommun
import TriPhotoMoteur

/// Écran « Revue » (maquette 3) : une photo à la fois, par épreuve, pour reclasser vite (bonne, floue, sol, code),
/// marquer une chute ou changer un code. ← → pour avancer, une lettre pour classer. Rien n'est supprimé ici.
struct RevueView: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var moteur: Moteur
    @State private var epreuve: String = ""          // vide : toutes
    @State private var boitier: String = ""          // vide : tous
    @State private var douteusesDabord = true
    @State private var photos: [FichePhoto] = []
    @State private var index = 0
    @State private var nouveauCode = ""
    @State private var changerCode = false
    @State private var corrections: [String] = []

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
        .onChange(of: douteusesDabord) { _ in charger() }
        .onChange(of: etat.momentRevue?.heure) { _ in charger() }
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

    /// Les photos à regarder d'abord (détection code / sol, ou floue dans sa rafale), pas encore classées.
    /// Rafales calculées boîtier par boîtier, photos triées par heure : rapide même sur des milliers de photos.
    static func douteuses(_ l: [FichePhoto]) -> Set<Int64> {
        var marques: Set<Int64> = []
        for (_, liste) in Dictionary(grouping: l.filter { $0.prise != nil }, by: \.boitier) {
            let t = liste.sorted { $0.prise! < $1.prise! }
            var debut = 0
            for (i, f) in t.enumerated() {
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

    private func charger() {
        let ep = epreuve.isEmpty ? nil : epreuve
        let b = boitier
        let dabord = douteusesDabord
        let moment = etat.momentRevue?.heure
        DispatchQueue.global(qos: .userInitiated).async {
            var l = moment.map { moteur.photosAutour($0) } ?? moteur.photosRevue(epreuve: ep)
            if !b.isEmpty { l = l.filter { $0.boitier == b } }
            if dabord {
                let marques = RevueView.douteuses(l)
                l = l.filter { marques.contains($0.id) } + l.filter { !marques.contains($0.id) }
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
            Toggle("Montrer d'abord les photos dont la détection est incertaine", isOn: $douteusesDabord)
                .font(.system(size: 12))
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
                    Text("← → pour avancer · la lettre pour classer · X : chute").font(.system(size: 11))
                        .foregroundStyle(Theme.texteTresDiscret)
                    Spacer()
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
                    Spacer()
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
                        .buttonStyle(.plain)
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
                Text("Le classement (bonne, floue, sol, code) est gardé pour la mémoire de l'étape 5 ; rien n'est retiré du serveur ici.")
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
        corrections.insert("\(f.origine) → \(f.classe == cle ? "sans classe" : cle)", at: 0)
        photos[index].classe = f.classe == cle ? "" : cle
        avancer(1)
    }

    private func basculerChute() {
        guard let f = courante else { return }
        moteur.marquerChute(f.id, !f.chute)
        photos[index].chute.toggle()
        corrections.insert("\(f.origine) : \(f.chute ? "plus de chute" : "CHUTE")", at: 0)
    }

    private func appliquerCode() {
        guard let f = courante, let c = CodePassage.lire(nouveauCode) else { return }
        moteur.appliquer(code: c.texte, a: [f.id])
        corrections.insert("\(f.origine) : \(f.codeRetenu.isEmpty ? "sans code" : f.codeRetenu) → \(c.texte)", at: 0)
        photos[index].codeFinal = c.texte
        changerCode = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { rafraichirCourante() }
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
        }
        .opacity(0)
        .disabled(changerCode)
    }
}
