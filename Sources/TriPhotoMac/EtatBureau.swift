import AppKit
import Foundation
import TriPhotoCommun
import TriPhotoMoteur

/// L'onglet « Au bureau » : les archives des années passées, leur index, la recherche et les copies sur le Bureau.
/// Les archives ne sont jamais modifiées : on lit, on copie.
@MainActor
final class EtatBureau: ObservableObject {
    @Published private(set) var archives: [ArchiveAnnee] = []
    @Published private(set) var progression: [String: IndexeurArchives.Progression] = [:]
    @Published private(set) var comptes: [String: (photos: Int, concours: Int)] = [:]
    @Published private(set) var presents: Set<String> = []
    @Published var recherche = RechercheArchives() {
        didSet { if recherche != oldValue { chercherBientot() } }
    }
    @Published private(set) var resultats: [PhotoArchive] = []
    @Published private(set) var total = 0
    @Published private(set) var dureeRecherche: TimeInterval = 0
    @Published var choisie: PhotoArchive?
    /// Photos à copier sur le Bureau (dans l'ordre où elles ont été ajoutées).
    @Published private(set) var panier: [PhotoArchive] = []
    @Published var nomDossierCopie = ""
    @Published var message = ""
    @Published private(set) var dernierDossierCopie: URL?
    @Published private(set) var copieEnCours = false
    @Published private(set) var enAttente = 0
    @Published private(set) var listeConcours: [String] = []
    @Published private(set) var tailles: (index: Int64, vignettes: Int64) = (0, 0)
    /// Pause demandée par HUGO (en plus de la pause automatique pendant un concours).
    @Published var pauseMain = false {
        didSet { reglerPause() }
    }
    @Published private(set) var pauseAuto = false
    /// Dossier des fichiers CSV d'attribution (cavalier et cheval de chaque code), vide : aucun.
    @Published private(set) var dossierCSV = UserDefaults.standard.string(forKey: "bureauDossierCSV") ?? ""

    let index: IndexArchives?
    let indexeur: IndexeurArchives?
    /// « Envoyer sur le NAS » (sauvegarde des concours, HUGO 26/11/2026).
    let envoi: EtatEnvoiNAS
    /// Vrai pendant un concours (le tri tourne) : l'indexation se met en pause, le concours passe avant tout.
    var concoursEnCours: () -> Bool = { false }

    private var minuteur: Timer?
    private var tacheRecherche: Task<Void, Never>?
    private var dejaOuvert = false
    private var derniereTaille = Date.distantPast

    static var dossier: URL { Stockage.dossier.appendingPathComponent("Au bureau", isDirectory: true) }

    init() {
        index = try? IndexArchives(dossier: EtatBureau.dossier)
        indexeur = index.map { IndexeurArchives(index: $0) }
        envoi = EtatEnvoiNAS()
        if !dossierCSV.isEmpty { indexeur?.dossierCSV = URL(fileURLWithPath: dossierCSV, isDirectory: true) }
        archives = Stockage.lire([ArchiveAnnee].self, nom: "au-bureau.json") ?? []
        indexeur?.surProgression = { [weak self] id, p in
            Task { @MainActor [weak self] in self?.recu(id, p) }
        }
        envoi.dossierCSV = { [weak self] in self?.dossierCSV ?? "" }
        envoi.surFin = { [weak self] t in
            // le concours est sur le NAS : l'année correspondante se met à jour dans l'index
            guard let self, let a = self.archives.first(where: { t.annee.hasPrefix($0.chemin) || $0.chemin.hasPrefix(t.annee) }) else { return }
            self.chercherNouveautes(a)
        }
        relireComptes()
        verifierDisques()
        enAttente = index?.enAttente().count ?? 0
        minuteur = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tic() }
        }
    }

    // MARK: - Archives (une par année)

    private func garder() {
        archives.sort { $0.annee > $1.annee }
        Stockage.ecrire(archives, nom: "au-bureau.json")
    }

    func archive(_ id: String) -> ArchiveAnnee? { archives.first { $0.id == id } }

    func ajouterAnnee() {
        let p = NSOpenPanel()
        p.title = "Ajouter une année"
        p.message = "Choisis le dossier d'une année d'archives (sur le disque réseau ou un disque). Il ne sera jamais modifié."
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = true
        p.prompt = "Ajouter"
        guard p.runModal() == .OK else { return }
        var nouvelles: [ArchiveAnnee] = []
        for u in p.urls {
            guard !archives.contains(where: { $0.chemin == u.path }) else { continue }
            let v = try? u.resourceValues(forKeys: [.volumeURLForRemountingKey, .volumeLocalizedNameKey])
            let a = ArchiveAnnee(annee: ArchiveAnnee.anneeDevinee(u.lastPathComponent), chemin: u.path,
                                 remontage: v?.volumeURLForRemounting?.absoluteString ?? "",
                                 nomDisque: v?.volumeLocalizedName ?? "")
            nouvelles.append(a)
        }
        guard !nouvelles.isEmpty else { return }
        archives += nouvelles
        garder()
        verifierDisques()
        indexeur?.lancer(nouvelles)
        message = nouvelles.count == 1 ? "Année \(nouvelles[0].annee) ajoutée : l'indexation commence (priorité basse)."
                                       : "\(nouvelles.count) années ajoutées : l'indexation commence (priorité basse)."
    }

    func changerAnnee(_ id: String, _ annee: String) {
        guard let i = archives.firstIndex(where: { $0.id == id }) else { return }
        let t = annee.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t != archives[i].annee else { return }
        archives[i].annee = t
        garder()
    }

    /// Retire une année de l'app : l'index et les vignettes sont effacés de ce Mac, le disque n'est pas touché.
    func retirer(_ a: ArchiveAnnee) {
        let alerte = NSAlert()
        alerte.messageText = "Retirer l'année \(a.annee) de Groom Pix ?"
        alerte.informativeText = "Les photos du disque ne sont pas touchées. Seul l'index de ce Mac est effacé : il faudra tout réindexer pour la remettre."
        alerte.addButton(withTitle: "Retirer")
        alerte.addButton(withTitle: "Annuler")
        guard alerte.runModal() == .alertFirstButtonReturn else { return }
        archives.removeAll { $0.id == a.id }
        garder()
        progression[a.id] = nil
        let idx = index
        Task.detached(priority: .utility) {
            idx?.oublier(archive: a.id)
            await MainActor.run { [weak self] in self?.relireComptes(); self?.chercherBientot() }
        }
    }

    /// Choisit le dossier des CSV d'attribution. Les noms sont réappliqués à l'index sans relire les photos.
    func choisirDossierCSV() {
        let p = NSOpenPanel()
        p.title = "Fichiers CSV des concours"
        p.message = "Choisis le dossier où sont rangés tes fichiers CSV d'attribution (sous-dossiers compris). Ils ne seront jamais modifiés."
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.prompt = "Choisir"
        guard p.runModal() == .OK, let u = p.url else { return }
        dossierCSV = u.path
        UserDefaults.standard.set(u.path, forKey: "bureauDossierCSV")
        indexeur?.dossierCSV = u
        indexeur?.lancer(archives.filter(\.present))
        message = "Fichiers CSV : les cavaliers et chevaux sont ajoutés à l'index (sans relire les photos)."
    }

    /// Rebranche un disque réseau (le Finder le monte, avec le mot de passe déjà gardé dans le trousseau).
    func rebrancher(_ a: ArchiveAnnee) {
        if let u = URL(string: a.remontage), !a.remontage.isEmpty {
            NSWorkspace.shared.open(u)
        } else {
            message = "Branche le disque « \(a.nomDisque.isEmpty ? a.annee : a.nomDisque) »."
        }
    }

    /// « Chercher les nouveautés » : relit les dossiers des années branchées (seules les photos nouvelles ou
    /// changées sont lues).
    func chercherNouveautes(_ seulement: ArchiveAnnee? = nil) {
        let l = seulement.map { [$0] } ?? archives.filter(\.present)
        indexeur?.lancer(l)
    }

    /// Première ouverture de l'onglet : les années pas vérifiées depuis plus d'une heure sont relues.
    func auPremierAffichage() {
        guard !dejaOuvert else { return }
        dejaOuvert = true
        let vieilles = archives.filter { a in
            a.present && (index?.derniereVerification(archive: a.id).map { Date().timeIntervalSince($0) > 3600 } ?? true)
        }
        indexeur?.lancer(vieilles)
        chercherBientot(tout: true)
        taillesBientot(forcer: true)
    }

    private func recu(_ id: String, _ p: IndexeurArchives.Progression) {
        progression[id] = p
        if p.etape == .fini || p.etape == .absent {
            if p.dansICloud > 0 && p.message.isEmpty {
                message = "\(p.dansICloud) photo\(p.dansICloud > 1 ? "s" : "") restée\(p.dansICloud > 1 ? "s" : "") dans iCloud (pas sur ce Mac) : pas lue\(p.dansICloud > 1 ? "s" : ""), pour ne pas tout télécharger."
            }
            relireComptes()
            chercherBientot()
            taillesBientot(forcer: true)
            if !p.message.isEmpty { message = p.message }
        } else if p.etape == .lecture, p.lues % 500 == 0 {
            relireComptes()
        }
    }

    private func relireComptes() {
        guard let index else { return }
        var c: [String: (photos: Int, concours: Int)] = [:]
        for a in archives { c[a.id] = index.compte(archive: a.id) }
        comptes = c
        listeConcours = index.concours(archive: recherche.archive)
    }

    private func verifierDisques() {
        presents = Set(archives.filter(\.present).map(\.id))
    }

    private func reglerPause() {
        indexeur?.enPause = pauseMain || pauseAuto
    }

    /// Toutes les 15 s : disques branchés, pause pendant un concours, copies en attente, vérification de nuit.
    private func tic() {
        let avant = presents
        verifierDisques()
        let auto = concoursEnCours()
        if auto != pauseAuto { pauseAuto = auto; reglerPause() }
        if envoi.pauseConcours != auto { envoi.pauseConcours = auto }
        if presents != avant || enAttente > 0 { copierEnAttente() }
        // la nuit (1 h à 5 h) : chaque année branchée est revérifiée une fois
        let h = Calendar.current.component(.hour, from: Date())
        if (1...5).contains(h), !(indexeur?.occupe ?? true) {
            let aRevoir = archives.filter { a in
                a.present && (index?.derniereVerification(archive: a.id).map { Date().timeIntervalSince($0) > 20 * 3600 } ?? true)
            }
            if !aRevoir.isEmpty { indexeur?.lancer(aRevoir) }
        }
    }

    func taillesBientot(forcer: Bool = false) {
        guard forcer || Date().timeIntervalSince(derniereTaille) > 60, let idx = index else { return }
        derniereTaille = Date()
        Task.detached(priority: .background) {
            let t = idx.taillesSurLeMac()
            await MainActor.run { [weak self] in self?.tailles = t }
        }
    }

    // MARK: - Recherche

    /// Relance la recherche un quart de seconde après la dernière touche.
    func chercherBientot(tout: Bool = false) {
        tacheRecherche?.cancel()
        guard let idx = index else { return }
        let r = recherche
        listeConcours = idx.concours(archive: r.archive)
        if r.concours != nil, !listeConcours.contains(r.concours!) { recherche.concours = nil; return }
        tacheRecherche = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let debut = Date()
            let (photos, total) = await Task.detached(priority: .userInitiated) { idx.chercher(r) }.value
            guard !Task.isCancelled, let self else { return }
            self.resultats = photos
            self.total = total
            self.dureeRecherche = Date().timeIntervalSince(debut)
            if let c = self.choisie, !photos.contains(where: { $0.id == c.id }) { self.choisie = photos.first }
            if self.choisie == nil { self.choisie = photos.first }
        }
    }

    /// Depuis l'écran Commandes : recherche toute prête et dossier de copie au nom du client.
    func ouvrir(recherche texte: String, dossier: String) {
        var r = RechercheArchives(texte: texte)
        r.archive = nil
        recherche = r
        nomDossierCopie = dossier
    }

    // MARK: - Copies

    func dansLePanier(_ p: PhotoArchive) -> Bool { panier.contains { $0.id == p.id } }

    func basculer(_ p: PhotoArchive) {
        if let i = panier.firstIndex(where: { $0.id == p.id }) { panier.remove(at: i) } else { panier.append(p) }
    }

    func toutAjouter() {
        let deja = Set(panier.map(\.id))
        panier += resultats.filter { !deja.contains($0.id) }
    }

    func viderPanier() { panier.removeAll() }

    var taillePanier: Int64 { panier.reduce(0) { $0 + $1.taille } }

    /// Le dossier des copies : Bureau › Groom Pix Copies › <nom choisi, sinon la recherche, sinon la date>.
    var dossierCopie: URL {
        var nom = NomDossier.nettoyer(nomDossierCopie.trimmingCharacters(in: .whitespaces))
        if nom.isEmpty { nom = NomDossier.nettoyer(recherche.texte.trimmingCharacters(in: .whitespaces)) }
        if nom.isEmpty {
            let f = DateFormatter()
            f.dateFormat = "dd-MM-yyyy HH'h'mm"
            nom = "Copies du \(f.string(from: Date()))"
        }
        let bureau = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        return bureau.appendingPathComponent("Groom Pix Copies", isDirectory: true).appendingPathComponent(nom, isDirectory: true)
    }

    /// Copie les originaux sur le Bureau. Une photo dont le disque est débranché est mise en attente : elle sera
    /// copiée toute seule dès que le disque revient.
    func copier(_ photos: [PhotoArchive]? = nil) {
        let liste = photos ?? panier
        guard !liste.isEmpty, !copieEnCours, let idx = index else { return }
        let dossier = dossierCopie
        let archivesParId = Dictionary(uniqueKeysWithValues: archives.map { ($0.id, $0) })
        copieEnCours = true
        message = "Copie de \(liste.count) photo\(liste.count > 1 ? "s" : "")…"
        Task.detached(priority: .utility) {
            var copiees = 0, attente = 0
            var erreurs: [String] = []
            for p in liste {
                guard let a = archivesParId[p.archive] else { continue }
                if a.present {
                    do { try CopieArchive.copier(p.url(dans: a), vers: dossier); copiees += 1 } catch {
                        if a.present { erreurs.append(p.nom) } else { idx.mettreEnAttente(p, destination: dossier); attente += 1 }
                    }
                } else {
                    idx.mettreEnAttente(p, destination: dossier)
                    attente += 1
                }
            }
            let resume = [copiees > 0 ? "\(copiees) copiée\(copiees > 1 ? "s" : "") dans Bureau › Groom Pix Copies › \(dossier.lastPathComponent)" : nil,
                          attente > 0 ? "\(attente) en attente du disque (copiée\(attente > 1 ? "s" : "") dès son retour)" : nil,
                          erreurs.isEmpty ? nil : "\(erreurs.count) impossible\(erreurs.count > 1 ? "s" : "") : \(erreurs.prefix(3).joined(separator: ", "))"]
                .compactMap { $0 }.joined(separator: " · ")
            let n = idx.enAttente().count
            let nbCopiees = copiees
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.copieEnCours = false
                self.message = resume.isEmpty ? "Rien à copier." : resume + "."
                self.enAttente = n
                if nbCopiees > 0 {
                    self.dernierDossierCopie = dossier
                    if photos == nil { self.panier.removeAll() }
                }
            }
        }
    }

    /// Fait les copies qui attendaient un disque débranché.
    private func copierEnAttente() {
        guard let idx = index, !copieEnCours else { return }
        let archivesParId = Dictionary(uniqueKeysWithValues: archives.map { ($0.id, $0) })
        copieEnCours = true
        Task.detached(priority: .utility) {
            var faites = 0
            var dossier: URL?
            for (cle, p, d) in idx.enAttente() {
                guard let a = archivesParId[p.archive], a.present else { continue }
                if (try? CopieArchive.copier(p.url(dans: a), vers: d)) != nil {
                    faites += 1
                    dossier = d
                    idx.retirerAttente(cle)
                }
            }
            let n = idx.enAttente().count
            let (nbFaites, dernier) = (faites, dossier)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.copieEnCours = false
                self.enAttente = n
                if nbFaites > 0, let dossier = dernier {
                    self.dernierDossierCopie = dossier
                    self.message = "Disque revenu : \(nbFaites) photo\(nbFaites > 1 ? "s" : "") en attente copiée\(nbFaites > 1 ? "s" : "") dans \(dossier.lastPathComponent)."
                }
            }
        }
    }

    func montrerDansLeFinder(_ p: PhotoArchive) {
        guard let a = archive(p.archive), a.present else { message = "Le disque de \(archive(p.archive)?.annee ?? "cette année") est débranché."; return }
        NSWorkspace.shared.activateFileViewerSelecting([p.url(dans: a)])
    }

    func montrerDossierCopie() {
        if let d = dernierDossierCopie { NSWorkspace.shared.activateFileViewerSelecting([d]) }
    }
}
