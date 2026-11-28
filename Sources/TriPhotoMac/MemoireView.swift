import AppKit
import SwiftUI
import TriPhotoMoteur
import UniformTypeIdentifiers

/// Écran « Mémoire » : les exemples partagés entre les stands, par catégorie. On ajoute des photos (depuis la revue
/// ou un dossier), on en retire (corbeille, annulable), on crée une catégorie. Jamais de remise à zéro.
struct MemoireView: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var moteur: Moteur
    @State private var categories: [CategorieMemoire] = []
    @State private var choisie = "bonne"
    @State private var exemples: [ExempleMemoire] = []
    @State private var selection: Set<String> = []
    @State private var retires: [(corbeille: URL, exemple: ExempleMemoire)] = []
    @State private var nouvelle = ""
    @State private var creer = false
    @State private var message = ""
    @State private var travail = false
    @State private var enGrand: DepartVisionneuse?
    @State private var gros = 0                           // exemples trop gros (photos entières au lieu de vignettes)
    @State private var reglage = ReglageCategorie()       // action sur le concours, détection, jauge (HUGO 28/11)
    @State private var nouvelleSupprime = false

    private var memoire: Memoire { etat.memoire }

    var body: some View {
        HStack(spacing: 0) {
            if etat.panneauGauche {
                panneauCategories.frame(width: 250).background(Theme.panneau).repere("memoire.categories")
                Divider().overlay(Theme.bordure)
            }
            centre.frame(maxWidth: .infinity, maxHeight: .infinity).repere("memoire.centre")
            if etat.panneauDroit {
                Divider().overlay(Theme.bordure)
                panneauDroit.frame(width: 290).background(Theme.panneau).repere("memoire.droite")
            }
        }
        .onAppear { memoire.creer(); charger(); lireReglage() }
        .onChange(of: choisie) { _ in selection = []; chargerExemples(); lireReglage(); Visite.partagee.signaler("memoire.categorie") }
        .onChange(of: etat.reglages.dossierMemoire) { _ in charger() }
        .sheet(item: $enGrand) { d in
            Visionneuse(elements: exemples.map { ElementVisionneuse(id: $0.id, chemins: [$0.url.path], titre: Memoire.nom(de: $0.categorie), detail: $0.nom) },
                        depart: d.id, choisie: { selection.contains($0) },
                        basculer: { if selection.contains($0) { selection.remove($0) } else { selection.insert($0) } })
        }
    }

    // MARK: - Données

    private func charger() {
        let m = memoire
        DispatchQueue.global(qos: .userInitiated).async {
            let c = m.categories()
            let g = m.tropGros()
            DispatchQueue.main.async {
                categories = c
                gros = g
                if !c.contains(where: { $0.cle == choisie }) { choisie = c.first?.cle ?? "bonne" }
                chargerExemples()
            }
        }
    }

    private func chargerExemples() {
        let m = memoire, cle = choisie
        DispatchQueue.global(qos: .userInitiated).async {
            let l = m.exemples(cle)
            DispatchQueue.main.async { if cle == choisie { exemples = l } }
        }
    }

    // MARK: - Catégories

    private var panneauCategories: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Catégories").font(.system(size: 14, weight: .semibold))
            Text("Une catégorie sert aux détections dès \(Memoire.minimumExemples) exemples.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(categories) { c in
                        Button { choisie = c.cle } label: {
                            HStack {
                                Text(c.nom).font(.system(size: 13, weight: choisie == c.cle ? .semibold : .regular))
                                Spacer()
                                Text("\(c.exemples)").font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(c.prete ? Theme.ok : Theme.texteDiscret)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(choisie == c.cle ? Theme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(BoutonPlat())
                    }
                }
            }
            if creer {
                TextField("Nom de la catégorie", text: $nouvelle).textFieldStyle(.roundedBorder).onSubmit(creerCategorie)
                Picker("Sur le concours", selection: $nouvelleSupprime) {
                    Text("Garder la photo").tag(false)
                    Text("Supprimer du concours").tag(true)
                }
                .font(.system(size: 12))
                HStack {
                    Button("Créer", action: creerCategorie).buttonStyle(BoutonStyle(principal: true))
                        .disabled(nouvelle.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Annuler") { creer = false; nouvelle = "" }.buttonStyle(BoutonStyle())
                }
            } else {
                Button("Nouvelle catégorie…") { creer = true }.buttonStyle(BoutonStyle())
            }
            Divider().overlay(Theme.bordure).padding(.vertical, 6)
            Text("Dossier partagé").font(.system(size: 12, weight: .semibold))
            Text((memoire.dossier.path as NSString).abbreviatingWithTildeInPath)
                .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret).lineLimit(2).truncationMode(.middle)
            if !memoire.accessible {
                Text("Dossier introuvable : iCloud Drive est-il activé sur ce Mac ?").font(.system(size: 11)).foregroundStyle(Theme.erreur)
            }
            Button("Montrer dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([memoire.dossier]) }
                .buttonStyle(BoutonStyle())
            if gros > 0 {
                // essai du 26/11 : des photos entières (4 à 7 Mo) dans la mémoire, lentes à télécharger sur chaque Mac
                Text("\(gros) exemple\(gros > 1 ? "s sont des photos entières" : " est une photo entière") au lieu de vignettes : la mémoire est lente à s'afficher et à se partager.")
                    .font(.system(size: 11)).foregroundStyle(Theme.attention)
                Button(travail ? "Allègement…" : "Alléger la mémoire") { alleger() }
                    .buttonStyle(BoutonStyle(principal: true)).disabled(travail)
                    .help("Chaque photo entière est remplacée par sa vignette de 360 px. La photo entière part à la Corbeille.")
            }
        }
        .padding(14)
    }

    private func alleger() {
        let m = memoire
        travail = true
        DispatchQueue.global(qos: .utility).async {
            let r = m.alleger()
            DispatchQueue.main.async {
                travail = false
                message = "\(r.allegees) photo\(r.allegees > 1 ? "s" : "") remplacée\(r.allegees > 1 ? "s" : "") par leur vignette (photos entières à la Corbeille)."
                    + (r.enAttente > 0 ? " \(r.enAttente) encore illisible\(r.enAttente > 1 ? "s" : "") : à refaire plus tard." : "")
                charger()
            }
        }
    }

    private func creerCategorie() {
        if let c = memoire.creerCategorie(nouvelle) {
            let s = nouvelleSupprime
            memoire.changerReglage(c) { $0.supprimer = s }
            choisie = c
            lireReglage()
        }
        creer = false
        nouvelle = ""
        nouvelleSupprime = false
        charger()
    }

    // MARK: - Centre : les exemples

    private var centre: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Memoire.nom(de: choisie)).font(.system(size: 16, weight: .semibold))
                Text("\(exemples.count) exemples").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                Spacer()
                SelecteurVue(galerie: choixVue($enGrand) {
                    (exemples.first { selection.contains($0.id) } ?? exemples.first)?.id
                })
                if !selection.isEmpty {
                    Menu("Déplacer vers") {
                        ForEach(categories.filter { $0.cle != choisie }) { c in Button(c.nom) { deplacer(vers: c.cle) } }
                    }
                    .fixedSize()
                    Button("Retirer de la mémoire (\(selection.count))", action: retirer).buttonStyle(BoutonStyle())
                }
                if !retires.isEmpty { Button("Annuler le retrait", action: annuler).buttonStyle(BoutonStyle()) }
                Button("Ajouter des photos…", action: ajouterPhotos).buttonStyle(BoutonStyle(principal: true)).disabled(travail)
            }
            if !message.isEmpty { Text(message).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret) }
            if exemples.isEmpty {
                Spacer()
                Text("Pas encore d'exemple. Classe des photos dans la Revue (B, F, S, C, X, M, R) ou ajoute des photos d'anciens concours.")
                    .font(.system(size: 13)).foregroundStyle(Theme.texteDiscret).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 8)], spacing: 8) {
                        ForEach(exemples) { e in tuile(e) }
                    }
                }
            }
        }
        .padding(20)
    }

    private func tuile(_ e: ExempleMemoire) -> some View {
        let choisi = selection.contains(e.id)
        return Button {
            if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                if choisi { selection.remove(e.id) } else { selection.insert(e.id) }
            } else {
                selection = choisi && selection.count == 1 ? [] : [e.id]
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                if e.dansLeNuage {
                    Rectangle().fill(Theme.carte).overlay(Text("dans iCloud…").font(.system(size: 11)).foregroundStyle(Theme.texteDiscret))
                } else {
                    VignettePhoto(chemins: [e.url.path], cote: 360)
                }
                Text(e.nom).font(.system(size: 9)).lineLimit(1).padding(3)
                    .background(Color.black.opacity(0.55)).foregroundStyle(Color.white)
            }
            .aspectRatio(3 / 2, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(choisi ? Theme.accent : Color.clear, lineWidth: 2))
        }
        .buttonStyle(BoutonPlat())
        .simultaneousGesture(TapGesture(count: 2).onEnded { enGrand = DepartVisionneuse(id: e.id) })
    }

    // MARK: - Actions

    private var choisis: [ExempleMemoire] { exemples.filter { selection.contains($0.id) } }

    private func retirer() {
        let l = choisis
        retires = l.compactMap { e in memoire.retirer(e).map { (corbeille: $0, exemple: e) } }
        message = "\(l.count) exemple\(l.count > 1 ? "s" : "") mis à la corbeille."
        selection = []
        charger()
    }

    private func annuler() {
        for r in retires { memoire.remettre(r.corbeille, dans: r.exemple) }
        message = "\(retires.count) exemple\(retires.count > 1 ? "s" : "") remis."
        retires = []
        charger()
    }

    private func deplacer(vers cle: String) {
        let l = choisis
        for e in l { memoire.deplacer(e, vers: cle) }
        message = "\(l.count) exemple\(l.count > 1 ? "s" : "") déplacé\(l.count > 1 ? "s" : "") vers « \(Memoire.nom(de: cle)) »."
        selection = []
        charger()
    }

    /// Photos d'anciens concours : seules des vignettes de 360 px vont dans la mémoire, les photos ne bougent pas.
    private func ajouterPhotos() {
        let p = NSOpenPanel()
        p.title = "Ajouter à « \(Memoire.nom(de: choisie)) »"
        p.message = "Choisis des photos (ou un dossier) : seules de petites vignettes vont dans la mémoire partagée."
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        p.allowedContentTypes = [.jpeg, .heic, .png, .tiff]
        guard p.runModal() == .OK else { return }
        let urls = p.urls, m = memoire, cle = choisie
        travail = true
        message = "Ajout en cours…"
        DispatchQueue.global(qos: .utility).async {
            var photos: [URL] = []
            let fm = FileManager.default
            for u in urls {
                var d: ObjCBool = false
                if fm.fileExists(atPath: u.path, isDirectory: &d), d.boolValue {
                    let e = fm.enumerator(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                    while let x = e?.nextObject() as? URL {
                        if ["jpg", "jpeg", "heic", "png", "tif", "tiff"].contains(x.pathExtension.lowercased()) { photos.append(x) }
                    }
                } else {
                    photos.append(u)
                }
            }
            var ok = 0
            for u in photos where (try? m.ajouter(photo: u, categorie: cle)) != nil { ok += 1 }
            let n = ok
            DispatchQueue.main.async {
                travail = false
                message = "\(n) photo\(n > 1 ? "s" : "") ajoutée\(n > 1 ? "s" : "") à « \(Memoire.nom(de: cle)) »."
                charger()
            }
        }
    }

    // MARK: - Panneau de droite

    private func lireReglage() {
        let m = memoire, cle = choisie
        DispatchQueue.global(qos: .userInitiated).async {
            let r = m.reglage(cle)
            DispatchQueue.main.async { if cle == choisie { reglage = r } }
        }
    }

    private func changer(_ f: @escaping (inout ReglageCategorie) -> Void) {
        f(&reglage)
        memoire.changerReglage(choisie, f)
    }

    /// Ce que fait la catégorie choisie : action sur le concours, détection, jauge, et les chiffres pour la choisir.
    private var carteReglage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Catégorie « \(Memoire.nom(de: choisie)) »").font(.system(size: 14, weight: .semibold))
            Picker("Sur le concours", selection: Binding(get: { reglage.supprimer }, set: { v in changer { $0.supprimer = v } })) {
                Text("Garder la photo").tag(false)
                Text("Supprimer du concours").tag(true)
            }
            .font(.system(size: 12))
            Text(reglage.supprimer
                 ? "Une photo rangée ici (Revue, ou « Bonne détection » dans À valider) entre dans la mémoire puis quitte le concours : serveur, galerie en ligne, original à la Corbeille. ⌘Z la remet."
                 : "Une photo rangée ici entre dans la mémoire et reste dans le concours.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            Toggle("Sert à la détection", isOn: Binding(get: { reglage.detection }, set: { v in changer { $0.detection = v } }))
                .font(.system(size: 12))
            Text("Non : les exemples sont gardés dans la mémoire mais ne servent pas à reconnaître les photos.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            if reglage.supprimer {
                Toggle("Action toute seule au-dessus de la jauge",
                       isOn: Binding(get: { reglage.jauge > 0 }, set: { v in changer { $0.jauge = v ? max($0.jauge, 95) : 0 } }))
                    .font(.system(size: 12))
                if reglage.jauge > 0 {
                    HStack {
                        Slider(value: Binding(get: { Double(reglage.jauge) }, set: { v in changer { $0.jauge = Int(v) } }),
                               in: 60...100, step: 5)
                        Text("\(reglage.jauge) %").font(.system(size: 12, design: .monospaced)).frame(width: 44)
                    }
                    Text("Détectée à \(reglage.jauge) % ou plus : supprimée sans passer par À valider (elle reste visible dans « Supprimées toutes seules » pour la remettre).")
                        .font(.system(size: 11)).foregroundStyle(Theme.attention)
                } else {
                    Text("Coupé : chaque détection attend ta décision dans À valider.")
                        .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
                }
            }
            let t = reglage.validees + reglage.fausses
            Text(t == 0 ? "Pas encore de détection décidée."
                 : "Détections décidées : \(reglage.validees) justes, \(reglage.fausses) fausses (\(reglage.justes ?? 0) % justes).")
                .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
        }
    }

    private var panneauDroit: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                carteReglage
                Divider().overlay(Theme.bordure)
                Text("Détections").font(.system(size: 14, weight: .semibold))
                let d = moteur.resume.detections
                if !moteur.actif {
                    Text("Elles tournent pendant le tri, au calme seulement.").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                } else {
                    Pastille(texte: d.prete ? "Mémoire prête" : "Pas encore assez d'exemples", genre: d.prete ? .ok : .attention)
                    Text(d.message).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                    Text("\(d.regardees) photos regardées · \(d.enAttente) à regarder").font(.system(size: 12))
                }
                Toggle("Détections en tâche de fond", isOn: $etat.reglages.detectionsActives).font(.system(size: 12))
                Text("Changement pris en compte au prochain démarrage du tri.").font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
                Button("Refaire toutes les détections") { moteur.refaireDetections() }
                    .buttonStyle(BoutonStyle()).disabled(!moteur.actif)
                    .help("Après avoir beaucoup changé la mémoire. Tourne au calme, sans gêner le tri.")
                Divider().overlay(Theme.bordure)
                Text("Comment ça marche").font(.system(size: 13, weight: .semibold))
                Text("""
                Chaque photo est comparée aux exemples de la mémoire : les 7 plus ressemblants votent. \
                La mémoire propose : la Revue montre « Mémoire : floue (82 %) ». Une photo soupçonnée d'une catégorie \
                qui supprime attend ta décision dans À valider (sauf si sa jauge est réglée).

                Catégories de scène (une seule par photo) : bonne, floue, sol, ratée, photo de code. \
                En plus : chute, meilleures, réseaux sociaux, et celles que tu crées.

                Une erreur de la mémoire se corrige en retirant ou en déplaçant l'exemple qui la trompe.

                Partage : le dossier iCloud « Tri-photo Mémoire » se partage depuis le Finder (clic droit › Partager) avec les autres Mac des stands. Seules des vignettes de 360 px y vont.
                """)
                .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
            }
            .padding(14)
        }
    }
}
