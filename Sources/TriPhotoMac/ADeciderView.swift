import AppKit
import SwiftUI
import TriPhotoCommun
import TriPhotoMoteur

/// Carte « Photos à décider » de l'écran À valider (HUGO 28/11) : les photos que la mémoire soupçonne (floue, sol,
/// ratée d'avant le sol…) attendent dans « _À décider » sur le serveur (jamais rafraîchi, jamais en ligne).
/// Quatre gestes, sur une photo ou plusieurs :
/// - Bonne détection : la photo entre dans la mémoire dans la catégorie détectée (sol → Sol et la photo d'avant →
///   Ratée), puis l'action de la catégorie s'applique (supprimer du concours, ou garder) ;
/// - Fausse détection : la photo retourne dans son épreuve, la mémoire n'apprend rien ;
/// - Corriger : rangée dans une autre catégorie (mémoire), puis l'action de cette catégorie ;
/// - Supprimer : quitte le concours, la mémoire n'apprend rien.
/// Tout s'annule (⌘Z ou bouton Annuler).
struct ADeciderView: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var moteur: Moteur
    @State private var photos: [FichePhoto] = []
    @State private var auto: [FichePhoto] = []
    @State private var selection: Set<Int64> = []
    @State private var annulations: [Annulation] = []
    @State private var enGrand: DepartVisionneuse?
    @State private var cachees: [Int64: Date] = [:]          // traitées : cachées le temps que le moteur suive

    /// Ce qu'il faut défaire pour annuler un geste.
    private struct Annulation {
        var supprimees: [Int64] = []          // à remettre (annulerSuppression), puis en attente
        var gardees: [Int64] = []             // à remettre en attente
        var memoire: [(FichePhoto, String)] = []
        var comptes: [(String, Bool)] = []    // décisions comptées pour la jauge (catégorie, juste)
        var texte = ""
    }

    private var visibles: [FichePhoto] {
        let t = Date()
        return photos.filter { f in cachees[f.id].map { t.timeIntervalSince($0) > 6 } ?? true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !visibles.isEmpty || !auto.isEmpty || !annulations.isEmpty {
                Carte(titre: "Photos à décider (\(visibles.count))",
                      sousTitre: "La mémoire les soupçonne : elles attendent dans « \(Moteur.dossierADecider) » sur le serveur, hors galerie. Rien n'est supprimé sans toi.") {
                    contenu
                }
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .onAppear(perform: charger)
        .onChange(of: moteur.resume.versionJournal) { _ in charger() }
        .sheet(item: $enGrand) { d in
            Visionneuse(elements: visibles.map { ElementVisionneuse(id: String($0.id), chemins: [$0.copie, $0.chemin],
                                                                     titre: soupcon($0), detail: $0.origine) },
                        depart: d.id, choisie: { id in Int64(id).map { selection.contains($0) } ?? false },
                        basculer: { id in
                            guard let i = Int64(id) else { return }
                            if selection.contains(i) { selection.remove(i) } else { selection.insert(i) }
                        })
        }
    }

    @ViewBuilder
    private var contenu: some View {
        if !visibles.isEmpty {
            HStack {
                Text(selection.isEmpty ? "Clic : choisir une photo · ⇧ ou ⌘ clic : plusieurs · double-clic : en grand"
                     : "\(selection.count) choisie\(selection.count > 1 ? "s" : "")")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
                Spacer()
                Button("Tout choisir") { selection = Set(visibles.map(\.id)) }.buttonStyle(BoutonStyle())
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(visibles, id: \.id) { f in tuile(f) }
                }
            }
            .frame(maxHeight: 380)
            boutons
        }
        if let a = annulations.last {
            HStack {
                Text(a.texte).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                Spacer()
                Button("Annuler (⌘Z)") { annuler() }.buttonStyle(BoutonStyle()).keyboardShortcut("z", modifiers: .command)
            }
        }
        if !auto.isEmpty {
            Divider().overlay(Theme.bordure)
            Text("Supprimées toutes seules par une jauge (\(auto.count))").font(.system(size: 13, weight: .semibold))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(auto.prefix(40), id: \.id) { f in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.origine).font(.system(size: 11, weight: .semibold))
                            Text(soupcon(f)).font(.system(size: 10)).foregroundStyle(Theme.texteDiscret)
                            Button("Remettre") { moteur.annulerSuppression([f.id]); cachees[f.id] = Date() }
                                .buttonStyle(BoutonStyle())
                        }
                        .padding(6)
                        .background(Theme.carte, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
    }

    private func tuile(_ f: FichePhoto) -> some View {
        let choisie = selection.contains(f.id)
        return Button {
            if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                if choisie { selection.remove(f.id) } else { selection.insert(f.id) }
            } else {
                selection = choisie && selection.count == 1 ? [] : [f.id]
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                VignettePhoto(chemins: [f.copie, f.chemin], cote: 300).frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(choisie ? Theme.accent : Theme.bordure, lineWidth: choisie ? 3 : 1))
                Text(soupcon(f)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.attention).lineLimit(1)
                Text("\(f.origine) · \(f.boitier) · \(f.prise.map { $0.formatted(date: .omitted, time: .shortened) } ?? "?")")
                    .font(.system(size: 10)).foregroundStyle(Theme.texteDiscret).lineLimit(1)
            }
        }
        .buttonStyle(BoutonPlat())
        .simultaneousGesture(TapGesture(count: 2).onEnded { enGrand = DepartVisionneuse(id: String(f.id)) })
    }

    private var boutons: some View {
        let rien = selection.isEmpty
        return HStack(spacing: 8) {
            Button("Bonne détection") { bonneDetection() }
                .buttonStyle(BoutonStyle(principal: true)).disabled(rien)
                .help("La mémoire avait raison : la photo entre dans la catégorie détectée (une photo du sol entraîne celle d'avant en « Ratée »), puis l'action de la catégorie s'applique.")
            Button("Fausse détection") { fausseDetection() }
                .buttonStyle(BoutonStyle()).disabled(rien)
                .help("Rien à corriger : la photo retourne dans son épreuve. La mémoire n'apprend rien.")
            Menu("Corriger…") {
                ForEach(etat.memoire.categories()) { c in
                    let r = etat.memoire.reglage(c.cle)
                    Button("\(c.nom)\(r.supprimer ? " (supprime du concours)" : "")") { corriger(c.cle) }
                }
            }
            .fixedSize().disabled(rien)
            Spacer()
            Button("Supprimer") { supprimer() }
                .buttonStyle(BoutonStyle()).disabled(rien)
                .help("La photo quitte le concours (serveur, galerie en ligne, original à la Corbeille). La mémoire n'apprend rien.")
        }
    }

    // MARK: - Données

    private func charger() {
        let m = moteur
        DispatchQueue.global(qos: .userInitiated).async {
            let l = m.photosADecider()
            let a = m.photosAutoSupprimees()
            DispatchQueue.main.async {
                if photos != l { photos = l }
                if auto != a { auto = a }
                let ids = Set(l.map(\.id))
                selection = selection.intersection(ids)
                cachees = cachees.filter { Date().timeIntervalSince($0.value) < 30 }
            }
        }
    }

    /// Catégorie soupçonnée : « ratee » pour la photo d'avant un sol, sinon la première détection qui supprime.
    private func categorieDetectee(_ f: FichePhoto) -> String {
        if f.a(Moteur.avantSol) { return "ratee" }
        let l = f.detection.split(separator: "|").map(String.init)
        return l.first { etat.memoire.reglage($0).supprimer } ?? l.first ?? ""
    }

    private func soupcon(_ f: FichePhoto) -> String {
        if f.a(Moteur.avantSol) { return "Ratée ? (sol juste après)" }
        let c = categorieDetectee(f)
        guard !c.isEmpty, c != "-", c != "?" else { return "À décider" }
        return "\(Memoire.nom(de: c)) ?\(f.confianceDetection > 0 ? " \(f.confianceDetection) %" : "")"
    }

    /// Les photos choisies, plus la photo d'avant (ratée) de chaque photo du sol choisie : elles vont ensemble.
    private var choisies: [FichePhoto] {
        var l = visibles.filter { selection.contains($0.id) }
        for f in l where categorieDetectee(f) == "sol" {
            if let p = paireAvant(f), !l.contains(where: { $0.id == p.id }) { l.append(p) }
        }
        return l
    }

    /// La photo d'avant (même boîtier, marquée « ratée ») d'une photo du sol en attente.
    private func paireAvant(_ sol: FichePhoto) -> FichePhoto? {
        guard let p = sol.prise else { return nil }
        return photos.filter { $0.a(Moteur.avantSol) && $0.boitier == sol.boitier && ($0.prise ?? .distantFuture) <= p }
            .max { ($0.prise ?? .distantPast) < ($1.prise ?? .distantPast) }
    }

    // MARK: - Gestes

    private func bonneDetection() {
        let l = choisies.map { ($0, categorieDetectee($0)) }.filter { !$0.1.isEmpty && $0.1 != "-" && $0.1 != "?" }
        appliquer(l, juste: true, texte: "\(l.count) photo\(l.count > 1 ? "s" : "") : bonne détection")
    }

    private func corriger(_ cle: String) {
        let l = choisies.filter { !$0.a(Moteur.avantSol) || selection.contains($0.id) }.map { ($0, cle) }
        appliquer(l, juste: false, texte: "\(l.count) photo\(l.count > 1 ? "s" : "") → \(Memoire.nom(de: cle))")
    }

    /// Range dans la mémoire, compte la décision pour la jauge, puis applique l'action de chaque catégorie.
    private func appliquer(_ l: [(FichePhoto, String)], juste: Bool, texte: String) {
        guard !l.isEmpty, !Visite.partagee.bloque("rien n'est rangé") else { return }
        let m = etat.memoire
        var a = Annulation(texte: texte)
        a.memoire = l
        for (f, cat) in l {
            let detectee = categorieDetectee(f)
            if !detectee.isEmpty {
                let ok = juste || detectee == cat
                m.compterDecision(detectee, juste: ok)
                a.comptes.append((detectee, ok))
            }
            moteur.classer(f.id, cat)
        }
        let aSupprimer = l.filter { m.reglage($0.1).supprimer }.map { $0.0.id }
        let aGarder = l.filter { !m.reglage($0.1).supprimer }.map { $0.0.id }
        a.supprimees = aSupprimer
        a.gardees = aGarder
        let mo = moteur
        etat.noterDansLaMemoire(l) {
            if !aSupprimer.isEmpty { mo.deciderSuppression(aSupprimer) }
            if !aGarder.isEmpty { mo.garderApresDecision(aGarder) }
        }
        fini(l.map { $0.0.id }, a)
    }

    private func fausseDetection() {
        let l = choisies
        guard !l.isEmpty else { return }
        var a = Annulation(texte: "\(l.count) photo\(l.count > 1 ? "s" : "") : fausse détection, remise\(l.count > 1 ? "s" : "") dans l'épreuve")
        for f in l {
            let c = categorieDetectee(f)
            if !c.isEmpty { etat.memoire.compterDecision(c, juste: false); a.comptes.append((c, false)) }
        }
        a.gardees = l.map(\.id)
        moteur.garderApresDecision(a.gardees)
        fini(a.gardees, a)
    }

    private func supprimer() {
        let l = visibles.filter { selection.contains($0.id) }
        guard !l.isEmpty, !Visite.partagee.bloque("rien n'est supprimé") else { return }
        let a = Annulation(supprimees: l.map(\.id), texte: "\(l.count) photo\(l.count > 1 ? "s" : "") supprimée\(l.count > 1 ? "s" : "") du concours")
        moteur.deciderSuppression(a.supprimees)
        fini(a.supprimees, a)
    }

    private func fini(_ ids: [Int64], _ a: Annulation) {
        let t = Date()
        for id in ids { cachees[id] = t }
        selection = []
        annulations.append(a)
        if annulations.count > 20 { annulations.removeFirst() }
    }

    private func annuler() {
        guard let a = annulations.popLast() else { return }
        let m = etat.memoire
        if !a.supprimees.isEmpty { moteur.annulerSuppression(a.supprimees) }
        for (f, cat) in a.memoire {
            etat.noterDansLaMemoire(f, categorie: cat, ajouter: false)
            moteur.classer(f.id, cat)          // bascule : la photo n'a plus de classe
        }
        for (c, juste) in a.comptes { m.compterDecision(c, juste: juste, annuler: true) }
        let remettre = a.supprimees + a.gardees
        if !remettre.isEmpty { moteur.remettreADecider(remettre) }
        for id in remettre { cachees[id] = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { charger() }
    }
}
