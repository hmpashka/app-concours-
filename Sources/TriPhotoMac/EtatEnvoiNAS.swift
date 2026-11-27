import AppKit
import Foundation
import TriPhotoCommun
import TriPhotoMoteur

/// « Au bureau » › Envoyer sur le NAS : la file des concours, l'avancée, les photos « À décider ».
@MainActor
final class EtatEnvoiNAS: ObservableObject {
    let moteur: EnvoyeurNAS
    @Published private(set) var taches: [TacheEnvoi] = []
    /// L'envoi montré au centre (celui en cours, sinon le dernier choisi).
    @Published var choisie: String?
    @Published private(set) var fichiers: [FichierEnvoi] = []
    @Published private(set) var reseau: EnvoyeurNAS.Reseau = .ok
    @Published private(set) var debit: Double = 0
    @Published private(set) var fichierEnCours = ""
    /// Dossiers de concours choisis, pas encore lancés.
    @Published var aEnvoyer: [URL] = []
    /// Dossier de l'année sur le NAS.
    @Published var annee: String = UserDefaults.standard.string(forKey: "envoiAnnee") ?? "" {
        didSet { UserDefaults.standard.set(annee, forKey: "envoiAnnee") }
    }
    @Published var joindreCSV = UserDefaults.standard.object(forKey: "envoiCSV") as? Bool ?? true {
        didSet { UserDefaults.standard.set(joindreCSV, forKey: "envoiCSV") }
    }
    @Published var verifier = UserDefaults.standard.object(forKey: "envoiVerifier") as? Bool ?? true {
        didSet { UserDefaults.standard.set(verifier, forKey: "envoiVerifier") }
    }
    @Published var doux = UserDefaults.standard.object(forKey: "envoiDoux") as? Bool ?? true {
        didSet { UserDefaults.standard.set(doux, forKey: "envoiDoux"); moteur.debitMax = doux ? 30_000_000 : 0 }
    }
    @Published var laNuit = UserDefaults.standard.bool(forKey: "envoiNuit") {
        didSet { UserDefaults.standard.set(laNuit, forKey: "envoiNuit"); moteur.seulementLaNuit = laNuit }
    }
    @Published var enPause = false {
        didSet { moteur.enPause = enPause || pauseConcours }
    }
    /// Un concours tourne sur ce Mac : l'envoi attend, le concours passe avant tout.
    @Published var pauseConcours = false {
        didSet { moteur.enPause = enPause || pauseConcours }
    }
    @Published var message = ""

    /// Le dossier des CSV d'attribution (réglé dans la recherche).
    var dossierCSV: () -> String = { "" }
    /// Un concours fini : l'index des archives se met à jour.
    var surFin: (TacheEnvoi) -> Void = { _ in }

    init() {
        moteur = EnvoyeurNAS(dossier: EtatBureau.dossier.appendingPathComponent("Envois", isDirectory: true))
        moteur.debitMax = doux ? 30_000_000 : 0
        moteur.seulementLaNuit = laNuit
        moteur.surAvancee = { [weak self] a in
            Task { @MainActor [weak self] in self?.recu(a) }
        }
        moteur.surFin = { [weak self] t in
            Task { @MainActor [weak self] in self?.surFin(t) }
        }
        relire()
        choisie = taches.last(where: { $0.etat == .enCours })?.id ?? taches.last?.id
        relireFichiers()
        // des envois restés en route (app quittée, Mac redémarré) : ils reprennent tout seuls
        if taches.contains(where: { $0.etat == .attente }) { moteur.lancer() }
    }

    private func relire() { taches = moteur.taches }

    private func relireFichiers() { fichiers = choisie.map { moteur.fichiers($0) } ?? [] }

    private func recu(_ a: EnvoyeurNAS.Avancee) {
        relire()
        reseau = a.reseau
        debit = a.debit
        fichierEnCours = a.fichier
        if a.tache.etat == .enCours, choisie != a.tache.id,
           taches.first(where: { $0.id == choisie })?.etat != .enCours { choisie = a.tache.id }
        if choisie == a.tache.id { relireFichiers() }
    }

    var tacheChoisie: TacheEnvoi? { taches.first { $0.id == choisie } }
    var bilan: BilanEnvoi { BilanEnvoi(fichiers) }

    func choisir(_ id: String) {
        choisie = id
        relireFichiers()
    }

    // MARK: - Préparer un envoi

    func ajouterDossiers() {
        let p = NSOpenPanel()
        p.title = "Concours à envoyer sur le NAS"
        p.message = "Choisis un ou plusieurs dossiers de concours sur ce Mac (⌘-clic pour en prendre plusieurs)."
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = true
        p.prompt = "Ajouter"
        guard p.runModal() == .OK else { return }
        deposer(p.urls)
    }

    /// Glisser-déposer ou choix : seuls les dossiers comptent.
    func deposer(_ urls: [URL]) {
        for u in urls {
            var dossier: ObjCBool = false
            guard FileManager.default.fileExists(atPath: u.path, isDirectory: &dossier), dossier.boolValue,
                  !aEnvoyer.contains(u) else { continue }
            aEnvoyer.append(u)
        }
    }

    func retirer(_ u: URL) { aEnvoyer.removeAll { $0 == u } }

    func choisirAnnee() {
        let p = NSOpenPanel()
        p.title = "Année sur le NAS"
        p.message = "Choisis le dossier de l'année sur le NAS (par exemple « CONCOURS 2026 »)."
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.prompt = "Choisir"
        guard p.runModal() == .OK, let u = p.url else { return }
        annee = u.path
    }

    var anneePresente: Bool {
        var d: ObjCBool = false
        return !annee.isEmpty && FileManager.default.fileExists(atPath: annee, isDirectory: &d) && d.boolValue
    }

    /// Le CSV d'attribution qui va avec ce concours, s'il y en a un dans le dossier des CSV.
    func csvPour(_ concours: URL) -> URL? {
        let d = dossierCSV()
        guard joindreCSV, !d.isEmpty,
              let e = FileManager.default.enumerator(at: URL(fileURLWithPath: d, isDirectory: true), includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles]) else { return nil }
        let csvs = e.compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "csv" }
        return RapprochementCSV.meilleur(concours: concours.lastPathComponent, parmi: csvs)
    }

    func envoyer() {
        guard !aEnvoyer.isEmpty else { return }
        guard anneePresente else { message = "Le dossier de l'année sur le NAS n'est pas joignable : branche le NAS ou choisis l'année."; return }
        let annee = URL(fileURLWithPath: self.annee, isDirectory: true)
        let t = aEnvoyer.map { TacheEnvoi(source: $0, annee: annee, csv: csvPour($0), verifier: verifier) }
        moteur.ajouter(t)
        aEnvoyer.removeAll()
        relire()
        if choisie == nil || tacheChoisie?.etat == .fini { choisir(t[0].id) }
        message = t.count == 1 ? "« \(t[0].nom) » part sur le NAS." : "\(t.count) concours partent sur le NAS, l'un après l'autre."
    }

    // MARK: - Pendant et après

    func arreter(_ id: String) { moteur.arreter(id); relire() }
    func reprendre(_ id: String) { moteur.reprendre(id); relire() }
    func oublier(_ id: String) {
        moteur.oublier(id)
        relire()
        if choisie == id { choisie = taches.last?.id; relireFichiers() }
    }

    func decider(_ f: FichierEnvoi, _ c: FichierEnvoi.Choix) {
        guard let id = choisie else { return }
        moteur.decider(id, chemin: f.chemin, c)
        relire()
        relireFichiers()
    }

    func libererLaPlace(_ t: TacheEnvoi) {
        let b = BilanEnvoi(moteur.fichiers(t.id))
        let alerte = NSAlert()
        alerte.messageText = "Mettre « \(t.nom) » à la Corbeille du Mac ?"
        alerte.informativeText = "Les \(b.total) fichiers sont sur le NAS et vérifiés identiques. Le dossier du Mac part à la Corbeille : tu peux l'y reprendre tant qu'elle n'est pas vidée."
        alerte.addButton(withTitle: "Mettre à la Corbeille")
        alerte.addButton(withTitle: "Annuler")
        guard alerte.runModal() == .alertFirstButtonReturn else { return }
        do {
            try moteur.libererLaPlace(t.id)
            message = "« \(t.nom) » est dans la Corbeille du Mac (\(ByteCountFormatter.string(fromByteCount: b.octetsTotal, countStyle: .file)) libérés quand tu la videras)."
        } catch {
            message = error.localizedDescription
        }
        relire()
    }

    func montrerSurLeNAS(_ t: TacheEnvoi) {
        NSWorkspace.shared.activateFileViewerSelecting([t.destination])
    }
}
