import Foundation
import TriPhotoCommun
import TriPhotoMoteur

/// Nouveau concours (HUGO 26/11/2026) : à tout moment, même si le concours en cours n'est pas fini à 100 %, on le
/// RANGE (rien n'est effacé) et on repart à zéro. La Mémoire n'est jamais touchée, les réglages du Mac sont gardés.
/// Un concours rangé se rouvre pour le finir (galerie, fichier de fin…).

/// Ce que la fenêtre doit faire.
enum DemandeNouveauConcours: Identifiable {
    case nouveau
    case rouvrir(ConcoursRange)
    var id: String {
        switch self {
        case .nouveau: return "nouveau"
        case .rouvrir(let c): return "rouvrir-" + c.id
        }
    }
}

/// Un concours rangé : un dossier dans Application Support › Tri-photo › Concours rangés, avec son journal, son
/// fichier FFE lu, ses engagés terrain, le suivi de sa galerie… et ce fichier de description.
struct ConcoursRange: Codable, Identifiable, Hashable {
    var id: String                      // nom du dossier
    var nom: String
    var debut: Date
    var fin: Date
    var rangeLe: Date
    var photos: Int?
    var galerieRestantes: Int?
    var aValider: Int?
    /// Photos pas finies mises de côté dans la réception (« Restes – … »), et ce dossier.
    var restes: Int = 0
    var dossierRestes: String = ""
    // Réglages propres au concours, remis en place à la réouverture.
    var nomConcours: String
    var nombreJours: Int
    var cheminFFE: String
    var epreuvesForcees: [String: String] = [:]        // chrono → épreuve choisie à la main

    var pasFini: Bool { (galerieRestantes ?? 0) > 0 || restes > 0 || (aValider ?? 0) > 0 }

    static var racine: URL {
        let d = Stockage.dossier.appendingPathComponent("Concours rangés", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static let fichierDescription = "concours-range.json"
    var dossier: URL { ConcoursRange.racine.appendingPathComponent(id, isDirectory: true) }

    static func tous() -> [ConcoursRange] {
        let fm = FileManager.default
        let dossiers = (try? fm.contentsOfDirectory(at: racine, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dossiers.compactMap { d in
            (try? Data(contentsOf: d.appendingPathComponent(fichierDescription))).flatMap { try? dec.decode(ConcoursRange.self, from: $0) }
        }
        .sorted { $0.rangeLe > $1.rangeLe }
    }

    /// Fichiers de l'app qui tiennent au concours en cours (tout le reste reste en place : réglages, modèles,
    /// iPhone connus, raccourcis, empreintes de la Mémoire, clôtures, « Au bureau »…).
    static func tientAuConcours(_ nom: String) -> Bool {
        if nom.hasPrefix("galerie-dossier-envoye-") { return false }        // envoi manuel d'un dossier : gardé
        return nom.hasPrefix("journal.sqlite") || nom == "concours.json" || nom == "boitiers-synchro.json"
            || nom.hasPrefix("engages-terrain-") || nom.hasPrefix("galerie-en-ligne-") || nom.hasPrefix("galerie-dossier-")
            || nom.hasPrefix("remises-") || nom.hasPrefix("passages-capture") || nom.hasPrefix("messages-")
    }
}

/// Ce qui n'est pas fini dans le concours en cours (pour la fenêtre).
struct BilanConcours {
    var nom = ""
    var triEnCours = false
    var aValider = 0
    var tampon = 0
    /// Photos encore dans la réception (pas triées, doublons, photos de code…), hors « À valider ».
    var reception = 0
    var galerie: Int?
    var photos: Int?
    var rien: Bool { aValider == 0 && tampon == 0 && reception == 0 && (galerie ?? 0) == 0 }
}

extension Etat {
    var nomConcoursRange: String {
        let n = nomConcoursFichier.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Concours sans nom" : n.capitalized
    }

    func bilanConcours() -> BilanConcours {
        var b = BilanConcours(nom: nomConcoursRange, triEnCours: moteur.actif)
        let r = reglages
        let reception = r.dossierReception.isEmpty ? nil : URL(fileURLWithPath: r.dossierReception, isDirectory: true)
        // Le journal reste ouvert après « Arrêter le tri » : galerie et photos du concours se lisent encore.
        let e = moteur.etatCloture(depuis: debutConcours)
        b.galerie = e.galerie?.aFaire
        b.photos = e.photosDuConcours > 0 ? e.photosDuConcours : nil
        if moteur.actif {
            b.aValider = e.aValider
            b.tampon = e.dansTampon
        } else {
            if let u = reception { b.aValider = Moteur.nombreDePhotos(dans: u.appendingPathComponent(Moteur.dossierAValider), toutCompter: true) }
            if r.tamponActif && !r.dossierTampon.isEmpty {
                b.tampon = Moteur.nombreDePhotos(dans: URL(fileURLWithPath: r.dossierTampon, isDirectory: true), toutCompter: true)
            }
        }
        if let u = reception {
            let aValiderSurDisque = Moteur.nombreDePhotos(dans: u.appendingPathComponent(Moteur.dossierAValider), toutCompter: true)
            b.reception = max(0, Moteur.nombreDePhotos(dans: u, toutCompter: true) - aValiderSurDisque)
        }
        return b
    }

    /// Range le concours en cours et repart à zéro. `envoyerAValider` : les photos « À valider » partent dans
    /// Lightroom avec le code du photographe (comme le rush), sinon elles restent de côté avec les restes.
    /// `sansAttendre` : HUGO a cliqué « Ranger sans attendre ». Rien n'est jamais effacé.
    func rangerConcours(envoyerAValider: Bool, sansAttendre: @escaping () -> Bool,
                        avancement: @escaping (String) -> Void) async -> ConcoursRange? {
        let r = reglages
        let debut = debutConcours, fin = finConcours
        var bilan = bilanConcours()

        // 1. Tri en cours : ce qui est en route part dans Lightroom (tampon vidé, À valider envoyées si choisi).
        if moteur.actif {
            let reception = URL(fileURLWithPath: r.dossierReception, isDirectory: true)
            if envoyerAValider && bilan.aValider > 0 { moteur.rushToutEnvoyer() }
            let limite = Date().addingTimeInterval(300)
            var premier = true
            while Date() < limite && !sansAttendre() {
                moteur.viderTampon()
                try? await Task.sleep(nanoseconds: premier ? 2_000_000_000 : 1_000_000_000)
                premier = false
                let e = moteur.etatCloture(depuis: debut)
                let surDisque = Moteur.nombreDePhotos(dans: reception)
                let reste = e.enReception + e.dansTampon + (envoyerAValider ? e.aValider : 0) + surDisque
                if reste == 0 { break }
                avancement("Photos en route vers Lightroom : encore \(reste)…")
            }
            bilan = bilanConcours()
            garderListing()
        }

        // 2. Le tri s'arrête et oublie le concours (journal fermé, galerie arrêtée).
        avancement("Arrêt du tri…")
        let m = moteur
        await Task.detached { m.fermerConcours() }.value

        // 3. Les fichiers : tampon → Lightroom, restes de la réception mis de côté, fichiers du concours rangés.
        avancement("Rangement du concours…")
        let nom = bilan.nom
        let horodatage: String = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "fr_FR")
            f.dateFormat = "yyyy-MM-dd HH'h'mm"
            return f.string(from: Date())
        }()
        let idRange = horodatage + " " + NomDossier.nettoyer(nom)
        var fiche = ConcoursRange(id: idRange, nom: nom, debut: debut, fin: fin, rangeLe: Date(), photos: bilan.photos,
                                  galerieRestantes: bilan.galerie, aValider: envoyerAValider ? 0 : bilan.aValider,
                                  nomConcours: r.nomConcours, nombreJours: r.nombreJours, cheminFFE: r.cheminFFE,
                                  epreuvesForcees: Dictionary(uniqueKeysWithValues: r.chronos.map { ($0.id.uuidString, $0.epreuveForcee) }))
        let fiche2 = fiche
        let (restes, dossierRestes) = await Task.detached { () -> (Int, String) in
            let fm = FileManager.default
            if r.tamponActif && !r.dossierTampon.isEmpty && !r.dossierImportLightroom.isEmpty {
                Etat.deplacerPhotos(de: URL(fileURLWithPath: r.dossierTampon, isDirectory: true),
                                    vers: URL(fileURLWithPath: r.dossierImportLightroom, isDirectory: true))
            }
            var restes = 0, dossierRestes = ""
            if !r.dossierReception.isEmpty {
                let reception = URL(fileURLWithPath: r.dossierReception, isDirectory: true)
                let elements = ((try? fm.contentsOfDirectory(at: reception, includingPropertiesForKeys: nil,
                                                             options: [.skipsHiddenFiles])) ?? [])
                    .filter { !$0.lastPathComponent.hasPrefix(Moteur.prefixeRestes) }
                if !elements.isEmpty {
                    let d = reception.appendingPathComponent(Moteur.prefixeRestes + NomDossier.nettoyer(nom) + " (" + horodatage + ")",
                                                             isDirectory: true)
                    try? fm.createDirectory(at: d, withIntermediateDirectories: true)
                    for u in elements { try? fm.moveItem(at: u, to: d.appendingPathComponent(u.lastPathComponent)) }
                    restes = Moteur.nombreDePhotos(dans: d, toutCompter: true)
                    dossierRestes = d.path
                    if restes == 0 && ((try? fm.contentsOfDirectory(atPath: d.path)) ?? []).isEmpty {
                        try? fm.removeItem(at: d)       // dossier vide créé à l'instant
                        dossierRestes = ""
                    }
                }
            }
            try? fm.createDirectory(at: fiche2.dossier, withIntermediateDirectories: true)
            for u in (try? fm.contentsOfDirectory(at: Stockage.dossier, includingPropertiesForKeys: nil)) ?? []
            where ConcoursRange.tientAuConcours(u.lastPathComponent) {
                try? fm.moveItem(at: u, to: fiche2.dossier.appendingPathComponent(u.lastPathComponent))
            }
            return (restes, dossierRestes)
        }.value
        fiche.restes = restes
        fiche.dossierRestes = dossierRestes
        ecrireFiche(fiche)

        // 4. L'app repart à zéro (réglages du Mac gardés).
        oublierConcoursEnCours()
        concoursRanges = ConcoursRange.tous()
        return fiche
    }

    /// Rouvre un concours rangé : le concours en cours est d'abord rangé de la même façon (par l'appelant).
    func rouvrir(_ c: ConcoursRange) async -> String? {
        let fm = FileManager.default
        let r = reglages
        let echec: String? = await Task.detached { () -> String? in
            for u in (try? fm.contentsOfDirectory(at: c.dossier, includingPropertiesForKeys: nil)) ?? []
            where u.lastPathComponent != ConcoursRange.fichierDescription {
                let cible = Stockage.dossier.appendingPathComponent(u.lastPathComponent)
                if fm.fileExists(atPath: cible.path) { continue }
                do { try fm.moveItem(at: u, to: cible) } catch { return error.localizedDescription }
            }
            // Les restes reviennent dans la réception, là où le journal les attend.
            if !c.dossierRestes.isEmpty, !r.dossierReception.isEmpty, fm.fileExists(atPath: c.dossierRestes) {
                Etat.fusionner(URL(fileURLWithPath: c.dossierRestes, isDirectory: true),
                               dans: URL(fileURLWithPath: r.dossierReception, isDirectory: true))
            }
            // Dossier du concours rangé : retiré s'il ne reste que sa fiche (sinon gardé, rien n'est perdu).
            let reste = ((try? fm.contentsOfDirectory(atPath: c.dossier.path)) ?? []).filter { $0 != ConcoursRange.fichierDescription }
            if reste.isEmpty { try? fm.removeItem(at: c.dossier) }
            return nil
        }.value
        if let e = echec { concoursRanges = ConcoursRange.tous(); return e }
        var nr = reglages
        nr.nomConcours = c.nomConcours
        nr.nombreJours = c.nombreJours
        nr.cheminFFE = c.cheminFFE
        for i in nr.chronos.indices { nr.chronos[i].epreuveForcee = c.epreuvesForcees[nr.chronos[i].id.uuidString] ?? "" }
        reglages = nr
        remplacerConcours(Stockage.lire(Concours.self, nom: "concours.json"))
        terrainHorsTri = fichierTerrain.map { Moteur.engagesTerrain(fichier: $0) } ?? []
        for cap in captures.values { cap.relirePassages() }
        serveur.relireMessages()
        concoursRanges = ConcoursRange.tous()
        ecran = .reglages
        return nil
    }

    /// Tout ce que l'app garde en tête du concours en cours est oublié (ses fichiers viennent d'être rangés).
    private func oublierConcoursEnCours() {
        var nr = reglages
        nr.nomConcours = ""
        nr.nombreJours = 1
        nr.cheminFFE = ""
        for i in nr.chronos.indices { nr.chronos[i].epreuveForcee = "" }
        reglages = nr
        remplacerConcours(nil)
        erreurFFE = nil
        terrainHorsTri = []
        seriesValidees = []
        photosRevue = nil
        momentRevue = nil
        revuePhotoId = nil
        messageAttribution = ""
        for cap in captures.values {
            if cap.ouverte { cap.fermer() }
            cap.oublierPassages()
        }
        serveur.relireMessages()        // fichier du jour rangé : liste vide
        ecran = .reglages
    }

    private func ecrireFiche(_ c: ConcoursRange) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: c.dossier, withIntermediateDirectories: true)
        if let d = try? enc.encode(c) { try? d.write(to: c.dossier.appendingPathComponent(ConcoursRange.fichierDescription), options: .atomic) }
    }

    /// Photos d'un dossier (sous-dossiers compris) déplacées à plat dans un autre. Un nom déjà pris : laissée en place.
    nonisolated static func deplacerPhotos(de source: URL, vers cible: URL) {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        var photos: [URL] = []
        for case let u as URL in e where ["jpg", "jpeg"].contains(u.pathExtension.lowercased()) { photos.append(u) }
        for u in photos {
            let dest = cible.appendingPathComponent(u.lastPathComponent)
            if !fm.fileExists(atPath: dest.path) { try? fm.moveItem(at: u, to: dest) }
        }
    }

    /// Remet le contenu d'un dossier dans un autre (sous-dossiers fusionnés). Rien n'est écrasé : un nom déjà pris
    /// reste dans le dossier d'origine, qui n'est retiré que s'il est vide.
    nonisolated static func fusionner(_ source: URL, dans cible: URL) {
        let fm = FileManager.default
        for u in (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
            let dest = cible.appendingPathComponent(u.lastPathComponent)
            var estDossier: ObjCBool = false
            if fm.fileExists(atPath: dest.path, isDirectory: &estDossier) {
                if estDossier.boolValue, (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    fusionner(u, dans: dest)
                }
            } else {
                try? fm.moveItem(at: u, to: dest)
            }
        }
        if ((try? fm.contentsOfDirectory(atPath: source.path)) ?? []).isEmpty { try? fm.removeItem(at: source) }
    }
}
