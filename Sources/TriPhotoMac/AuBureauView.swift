import AppKit
import ImageIO
import SwiftUI
import TriPhotoCommun
import TriPhotoMoteur

/// Onglet « Au bureau » (HUGO 26/11/2026) : à gauche les archives (une par année), au centre la recherche et la
/// grille des photos trouvées, à droite la photo choisie. En bas : les photos à copier sur le Bureau.
struct AuBureauView: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var bureau: EtatBureau
    @AppStorage("bureauTaille") private var taille = 170.0
    @State private var avecDates = false
    @State private var du = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var au = Date()

    var body: some View {
        HStack(spacing: 0) {
            if etat.panneauGauche {
                gauche.frame(width: 290).background(Theme.panneau)
                Divider().overlay(Theme.bordure)
            }
            VStack(spacing: 0) {
                barreRecherche
                Divider().overlay(Theme.bordure)
                infos
                Divider().overlay(Theme.bordure)
                grille
                if !bureau.panier.isEmpty || bureau.enAttente > 0 || !bureau.message.isEmpty {
                    Divider().overlay(Theme.accent)
                    barreCopie
                }
            }
            .frame(maxWidth: .infinity)
            if etat.panneauDroit {
                Divider().overlay(Theme.bordure)
                droite.frame(width: 320).background(Theme.panneau)
            }
        }
        .onAppear { bureau.auPremierAffichage() }
    }

    // MARK: - Gauche : les années

    private var gauche: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MES ARCHIVES (UNE PAR ANNÉE)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(bureau.archives) { a in CarteAnnee(bureau: bureau, archive: a) }
                    Button { bureau.ajouterAnnee() } label: {
                        Label("Ajouter une année", systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .buttonStyle(BoutonPlat())
                    .help("Choisis le dossier d'une année (sur le disque réseau ou un disque). Il ne sera jamais modifié.")
                }
            }
            Spacer(minLength: 0)
            Text("FICHIERS CSV DES CONCOURS").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(bureau.dossierCSV.isEmpty ? "Aucun : la recherche par cavalier ou cheval ne marche que sur les photos qui ont des mots-clés."
                                           : (bureau.dossierCSV as NSString).abbreviatingWithTildeInPath)
                .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret).lineLimit(3).truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
            Button(bureau.dossierCSV.isEmpty ? "Choisir le dossier des CSV…" : "Changer de dossier…") { bureau.choisirDossierCSV() }
                .buttonStyle(BoutonStyle())
                .help("Chaque CSV d'attribution est relié à son concours par la date et le nom : le code de chaque photo donne alors le cavalier et le cheval.")
            Text("INDEX SUR CE MAC").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
            let photos = bureau.comptes.values.reduce(0) { $0 + $1.photos }
            Text("Fiches : \(octets(bureau.tailles.index)) · Vignettes : \(octets(bureau.tailles.vignettes))\n\(photos.formatted()) photos, dans Bibliothèque › Application Support")
                .font(.system(size: 11.5)).foregroundStyle(Theme.texteDiscret).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button { bureau.chercherNouveautes() } label: {
                    Label("Chercher les nouveautés", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(BoutonStyle())
                .help("Relit les dossiers des années branchées. Seules les photos nouvelles ou changées sont lues.")
                Button { bureau.pauseMain.toggle() } label: {
                    Image(systemName: bureau.pauseMain ? "play.fill" : "pause.fill")
                }
                .buttonStyle(BoutonStyle())
                .help(bureau.pauseMain ? "Reprendre l'indexation" : "Mettre l'indexation en pause")
            }
            if bureau.pauseAuto {
                Text("Indexation en pause : un concours est en cours sur ce Mac.")
                    .font(.system(size: 11)).foregroundStyle(Theme.attention).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
    }

    // MARK: - Recherche

    private var barreRecherche: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.accent)
                TextField("Cavalier, cheval, concours, nom de fichier, copyright, code #12_45…", text: $bureau.recherche.texte)
                    .textFieldStyle(.plain).font(.system(size: 14))
                if !bureau.recherche.texte.isEmpty {
                    Button { bureau.recherche.texte = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(BoutonPlat()).foregroundStyle(Theme.texteDiscret)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.fond, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent))
            HStack(spacing: 10) {
                Picker("Chercher dans", selection: $bureau.recherche.champ) {
                    ForEach(RechercheArchives.Champ.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 210)
                Picker("Année", selection: $bureau.recherche.archive) {
                    Text("Toutes").tag(String?.none)
                    ForEach(bureau.archives) { Text($0.annee).tag(Optional($0.id)) }
                }
                .frame(width: 150)
                Picker("Concours", selection: $bureau.recherche.concours) {
                    Text("Tous").tag(String?.none)
                    ForEach(bureau.listeConcours, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .frame(width: 260)
                TextField("Épreuve (n° ou nom)", text: $bureau.recherche.epreuve)
                    .textFieldStyle(.roundedBorder).frame(width: 150)
                Toggle("Entre deux dates", isOn: $avecDates).toggleStyle(.checkbox)
                if avecDates {
                    DatePicker("", selection: $du, displayedComponents: .date).labelsHidden().frame(width: 110)
                    Text("et").foregroundStyle(Theme.texteDiscret)
                    DatePicker("", selection: $au, displayedComponents: .date).labelsHidden().frame(width: 110)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .onChange(of: avecDates) { _ in reglerDates() }
            .onChange(of: du) { _ in reglerDates() }
            .onChange(of: au) { _ in reglerDates() }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.panneau)
    }

    private func reglerDates() {
        bureau.recherche.du = avecDates ? du : nil
        bureau.recherche.au = avecDates ? au : nil
    }

    private var infos: some View {
        HStack(spacing: 12) {
            if bureau.archives.isEmpty {
                Text("Ajoute une année à gauche pour commencer.").foregroundStyle(Theme.texteDiscret)
            } else {
                Text("**\(bureau.total.formatted()) photo\(bureau.total > 1 ? "s" : "")** trouvée\(bureau.total > 1 ? "s" : "") en \(String(format: "%.1f", bureau.dureeRecherche)) s")
                if bureau.total > bureau.resultats.count {
                    Text("(les \(bureau.resultats.count.formatted()) premières sont montrées : précise la recherche)")
                        .foregroundStyle(Theme.attention)
                }
            }
            Spacer()
            if !bureau.resultats.isEmpty {
                Button("Tout ajouter à la copie") { bureau.toutAjouter() }.buttonStyle(BoutonStyle())
            }
            Text("Taille").foregroundStyle(Theme.texteDiscret)
            Slider(value: $taille, in: 110...320).frame(width: 110)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16).padding(.vertical, 7)
    }

    // MARK: - Grille

    private var grille: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: taille, maximum: taille * 1.5), spacing: 10)], spacing: 10) {
                ForEach(bureau.resultats) { p in
                    TuileArchive(bureau: bureau, photo: p, choisie: bureau.choisie?.id == p.id,
                                 present: bureau.presents.contains(p.archive),
                                 annee: bureau.archive(p.archive)?.annee ?? "")
                        .onTapGesture(count: 2) { bureau.basculer(p) }
                        .onTapGesture { bureau.choisie = p }
                }
            }
            .padding(16)
        }
        .background(Theme.fond)
    }

    // MARK: - Copie

    private var barreCopie: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.plus").font(.system(size: 18)).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                if !bureau.panier.isEmpty {
                    Text("**À copier : \(bureau.panier.count) photo\(bureau.panier.count > 1 ? "s" : "")** (originaux, \(octets(bureau.taillePanier)))")
                    HStack(spacing: 4) {
                        Text("vers Bureau › Groom Pix Copies ›").foregroundStyle(Theme.texteDiscret)
                        TextField(bureau.dossierCopie.lastPathComponent, text: $bureau.nomDossierCopie)
                            .textFieldStyle(.roundedBorder).frame(width: 240)
                    }
                    .font(.system(size: 11.5))
                }
                if !bureau.message.isEmpty {
                    Text(bureau.message).font(.system(size: 11.5)).foregroundStyle(Theme.texteDiscret).lineLimit(2)
                }
                if bureau.enAttente > 0 {
                    Text("\(bureau.enAttente) copie\(bureau.enAttente > 1 ? "s" : "") en attente d'un disque débranché : elles se feront toutes seules à son retour.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.attention)
                }
            }
            Spacer()
            if bureau.dernierDossierCopie != nil {
                Button("Montrer les copies") { bureau.montrerDossierCopie() }.buttonStyle(BoutonStyle())
            }
            if !bureau.panier.isEmpty {
                Button("Vider") { bureau.viderPanier() }.buttonStyle(BoutonStyle())
                Button(bureau.copieEnCours ? "Copie en cours…" : "Copier les originaux sur le Bureau") { bureau.copier() }
                    .buttonStyle(BoutonStyle(principal: true)).disabled(bureau.copieEnCours)
            }
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.panneau)
    }

    // MARK: - Droite : la photo choisie

    private var droite: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                Text("PHOTO CHOISIE").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                if let p = bureau.choisie {
                    let a = bureau.archive(p.archive)
                    ApercuArchive(bureau: bureau, photo: p, present: bureau.presents.contains(p.archive))
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 5) {
                        ligne("Fichier", p.nom)
                        ligne("Année", a?.annee ?? "")
                        ligne("Concours", p.concours)
                        if !p.epreuve.isEmpty { ligne("Épreuve", p.epreuve) }
                        if !p.code.isEmpty { ligne("Code", p.code) }
                        HStack(alignment: .top, spacing: 8) {
                            Text("Mots-clés").foregroundStyle(Theme.texteTresDiscret).frame(width: 78, alignment: .leading)
                            if p.motsCles.isEmpty { Text("aucun").foregroundStyle(Theme.texteTresDiscret) } else {
                                VStack(alignment: .leading, spacing: 3) {
                                    ForEach(p.motsCles, id: \.self) { m in
                                        Text(m).padding(.horizontal, 6).padding(.vertical, 1)
                                            .background(Theme.selection, in: RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                            }
                        }
                        if !p.copyright.isEmpty { ligne("Copyright", p.copyright) }
                        if let d = p.prise { ligne("Prise le", d.formatted(date: .numeric, time: .standard)) }
                        ligne("Taille", octets(p.taille))
                    }
                    .font(.system(size: 12))
                    Text("/" + (a.map { ($0.chemin as NSString).lastPathComponent } ?? "") + "/" + p.chemin)
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.texteDiscret)
                        .textSelection(.enabled)
                        .padding(7).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.fond, in: RoundedRectangle(cornerRadius: 5))
                    if !bureau.presents.contains(p.archive) {
                        Label("Disque absent : la copie se fera à son retour.", systemImage: "eject")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.attention)
                    }
                    Button { bureau.copier([p]) } label: { Text("Copier cette photo sur le Bureau").frame(maxWidth: .infinity) }
                        .buttonStyle(BoutonStyle(principal: true)).disabled(bureau.copieEnCours)
                    Button { bureau.basculer(p) } label: {
                        Text(bureau.dansLePanier(p) ? "Retirer de la copie" : "Ajouter à la copie (double-clic)").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BoutonStyle())
                    Button { bureau.montrerDansLeFinder(p) } label: { Text("Montrer dans le Finder").frame(maxWidth: .infinity) }
                        .buttonStyle(BoutonStyle()).disabled(!bureau.presents.contains(p.archive))
                } else {
                    Text("Clique sur une photo pour la voir ici.").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                }
            }
            .padding(14)
        }
    }

    private func ligne(_ titre: String, _ valeur: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(titre).foregroundStyle(Theme.texteTresDiscret).frame(width: 78, alignment: .leading)
            Text(valeur).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private func octets(_ n: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}

/// Carte d'une année, à gauche : disque branché ou non, avancée de l'indexation.
private struct CarteAnnee: View {
    @ObservedObject var bureau: EtatBureau
    var archive: ArchiveAnnee
    @State private var annee = ""

    var body: some View {
        let p = bureau.progression[archive.id]
        let present = bureau.presents.contains(archive.id)
        let c = bureau.comptes[archive.id] ?? (photos: 0, concours: 0)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Année", text: $annee, onCommit: { bureau.changerAnnee(archive.id, annee) })
                    .textFieldStyle(.plain).font(.system(size: 15, weight: .bold)).frame(width: 90)
                Spacer()
                badge(p, present: present)
            }
            Text(archive.remontage.isEmpty ? archive.chemin : archive.remontage)
                .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret).lineLimit(1).truncationMode(.middle)
                .help(archive.chemin)
            if let p, p.etape == .lecture || p.etape == .pause || p.etape == .liste {
                // total connu d'un tour précédent : vraie barre ; premier tour : barre qui défile
                if c.photos > p.trouvees {
                    ProgressView(value: Double(p.trouvees), total: Double(c.photos)).tint(Theme.accent)
                } else {
                    ProgressView().progressViewStyle(.linear).tint(Theme.accent)
                }
                Text("\(p.trouvees.formatted()) photos vues · \(p.lues.formatted()) nouvelles lues · priorité basse · reprend où elle s'est arrêtée")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret).fixedSize(horizontal: false, vertical: true)
            }
            Text("\(c.photos.formatted()) photos · \(c.concours) concours" + (bureau.index?.derniereVerification(archive: archive.id)
                .map { " · vérifié le " + $0.formatted(date: .abbreviated, time: .shortened) } ?? ""))
                .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret).fixedSize(horizontal: false, vertical: true)
            if !present {
                Text("Recherche possible · copie au retour du disque").font(.system(size: 11)).foregroundStyle(Theme.attention)
            }
            if let p, p.erreurs > 0 {
                Text("\(p.erreurs) dossier\(p.erreurs > 1 ? "s" : "") ou photo\(p.erreurs > 1 ? "s" : "") illisible\(p.erreurs > 1 ? "s" : "")")
                    .font(.system(size: 11)).foregroundStyle(Theme.erreur)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bureau.recherche.archive == archive.id ? Theme.selection : Theme.carte, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.bordure))
        .contentShape(Rectangle())
        .onTapGesture { bureau.recherche.archive = bureau.recherche.archive == archive.id ? nil : archive.id }
        .contextMenu {
            if present { Button("Chercher les nouveautés de \(archive.annee)") { bureau.chercherNouveautes(archive) } }
            else { Button("Rebrancher le disque") { bureau.rebrancher(archive) } }
            Divider()
            Button("Retirer cette année de Groom Pix…") { bureau.retirer(archive) }
        }
        .onAppear { annee = archive.annee }
        .help("Clic : chercher seulement dans \(archive.annee). Clic droit : nouveautés, rebrancher, retirer.")
    }

    @ViewBuilder
    private func badge(_ p: IndexeurArchives.Progression?, present: Bool) -> some View {
        let b: (texte: String, couleur: Color, fond: Color) = {
            if !present { return ("disque absent", Theme.texteDiscret, Theme.bordure) }
            switch p?.etape {
            case .lecture?, .liste?: return ("indexation…", Theme.attention, Theme.attentionFond)
            case .pause?: return ("en pause", Theme.attention, Theme.attentionFond)
            case .absent?: return ("disque absent", Theme.texteDiscret, Theme.bordure)
            case .erreur?: return ("erreur", Theme.erreur, Theme.attentionFond)
            default: return ("à jour", Theme.ok, Theme.okFond)
            }
        }()
        if !present && !archive.remontage.isEmpty {
            Button { bureau.rebrancher(archive) } label: {
                Label("rebrancher", systemImage: "eject").font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2).foregroundStyle(b.couleur).background(b.fond, in: Capsule())
            }
            .buttonStyle(BoutonPlat())
            .help("Disque absent. Clic : le rebrancher (le Finder le monte).")
        } else {
            Text(b.texte).font(.system(size: 10.5, weight: .semibold))
                .padding(.horizontal, 7).padding(.vertical, 2).foregroundStyle(b.couleur).background(b.fond, in: Capsule())
        }
    }
}

/// Une photo de la grille : sa vignette (gardée sur le Mac), son nom, son code.
private struct TuileArchive: View {
    @ObservedObject var bureau: EtatBureau
    var photo: PhotoArchive
    var choisie: Bool
    var present: Bool
    var annee: String

    var body: some View {
        VStack(spacing: 0) {
            VignetteArchive(bureau: bureau, photo: photo, present: present)
                .aspectRatio(3 / 2, contentMode: .fit)
                .saturation(present ? 1 : 0.15)
                .brightness(present ? 0 : -0.15)
                .overlay(alignment: .topTrailing) {
                    Button { bureau.basculer(photo) } label: {
                        Image(systemName: bureau.dansLePanier(photo) ? "checkmark.square.fill" : "square")
                            .font(.system(size: 17)).foregroundStyle(bureau.dansLePanier(photo) ? Theme.accent : Color.white.opacity(0.8))
                            .shadow(radius: 2).padding(6)
                    }
                    .buttonStyle(BoutonPlat())
                    .help("Ajouter à la copie (ou double-clic sur la photo)")
                }
                .overlay(alignment: .bottomLeading) {
                    if !present {
                        Label("disque absent · \(annee)", systemImage: "eject").font(.system(size: 10))
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(Color.white).padding(6)
                    }
                }
                .clipped()
            HStack {
                Text(photo.nom).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text(photo.code.isEmpty ? annee : photo.code).foregroundStyle(Theme.texteTresDiscret)
            }
            .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
            .padding(.horizontal, 7).padding(.vertical, 5)
        }
        .background(Theme.carte)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(choisie ? Theme.accent : Theme.bordure, lineWidth: choisie ? 2 : 1))
        .contentShape(Rectangle())
        .help(photo.chemin)
    }
}

/// Vignettes des archives, gardées en mémoire le temps de défiler.
private enum CacheArchives {
    static let images: NSCache<NSNumber, NSImage> = {
        let c = NSCache<NSNumber, NSImage>()
        c.countLimit = 800
        return c
    }()
    static let file: OperationQueue = {
        let f = OperationQueue()
        f.qualityOfService = .utility
        f.maxConcurrentOperationCount = 2
        return f
    }()
}

private struct VignetteArchive: View {
    @ObservedObject var bureau: EtatBureau
    var photo: PhotoArchive
    var present: Bool
    @State private var image: NSImage?
    @State private var lecture: Operation?
    @State private var rien = false

    var body: some View {
        Rectangle().fill(Theme.carte)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else if rien {
                    Image(systemName: "photo").font(.system(size: 22)).foregroundStyle(Theme.texteTresDiscret)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .clipped()
            .onAppear(perform: lire)
            .onDisappear { lecture?.cancel(); lecture = nil }
            .onChange(of: present) { p in if p && rien { rien = false; lire() } }
    }

    private func lire() {
        let cle = NSNumber(value: photo.id)
        if let im = CacheArchives.images.object(forKey: cle) { image = im; return }
        guard let index = bureau.index else { rien = true; return }
        let p = photo
        let a = bureau.archive(p.archive)
        let op = BlockOperation()
        op.addExecutionBlock { [weak op] in
            guard op?.isCancelled == false else { return }
            let im = index.vignette(p, archive: a).flatMap { NSImage(contentsOf: $0) }
            if let im { CacheArchives.images.setObject(im, forKey: cle) }
            DispatchQueue.main.async {
                if let im { image = im } else { rien = true }
            }
        }
        lecture = op
        CacheArchives.file.addOperation(op)
    }
}

/// La photo choisie, en plus grand : lue dans l'original si le disque est branché (une seule photo : ça va vite),
/// sinon sa vignette.
private struct ApercuArchive: View {
    @ObservedObject var bureau: EtatBureau
    var photo: PhotoArchive
    var present: Bool
    @State private var image: NSImage?
    @State private var pour: Int64 = -1

    var body: some View {
        Rectangle().fill(Theme.fond)
            .overlay {
                if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit) }
                else { ProgressView().controlSize(.small) }
            }
            .onAppear { charger() }
            .onChange(of: photo.id) { _ in charger() }
    }

    private func charger() {
        let p = photo
        guard pour != p.id else { return }
        pour = p.id
        image = CacheArchives.images.object(forKey: NSNumber(value: p.id))
        let a = bureau.archive(p.archive)
        let index = bureau.index
        DispatchQueue.global(qos: .userInitiated).async {
            var im: NSImage?
            if let a, a.present,
               let src = CGImageSourceCreateWithURL(p.url(dans: a) as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
               let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                   kCGImageSourceCreateThumbnailFromImageAlways: true,
                   kCGImageSourceThumbnailMaxPixelSize: 900,
                   kCGImageSourceCreateThumbnailWithTransform: true,
               ] as CFDictionary) {
                im = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            } else if let u = index?.vignette(p, archive: a) {
                im = NSImage(contentsOf: u)
            }
            DispatchQueue.main.async {
                guard pour == p.id else { return }
                if let im { image = im }
            }
        }
    }
}
