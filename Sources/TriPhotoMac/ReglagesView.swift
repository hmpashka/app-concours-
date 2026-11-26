import AppKit
import SwiftUI
import TriPhotoCommun
import TriPhotoMoteur
import UniformTypeIdentifiers

enum SectionReglages: String, CaseIterable, Identifiable {
    case concours = "1. Concours"
    case dossiers = "2. Dossiers"
    case copies = "3. Copies (.cube)"
    case lightroom = "4. Lightroom, tampon"
    case envois = "5. Envois"
    case cloture = "6. Clôture"
    case memoire = "7. Mémoire, remises des prix"
    case commandes = "8. Commandes de pack photo"
    case apparence = "9. Apparence, son et notifications"
    case protection = "10. Licence et antivol"
    case iphone = "11. Notifications iPhone"
    case raccourcis = "Raccourcis clavier"
    case modeles = "Modèles de concours"
    var id: String { rawValue }

    static let debut: [SectionReglages] = [.concours, .dossiers, .copies, .lightroom, .envois, .cloture, .memoire, .commandes, .apparence, .protection, .iphone]
    static let preferences: [SectionReglages] = [.raccourcis, .modeles]
}

/// Écran Réglages (maquette 4a) : sections à gauche, réglages au centre, « Prêt à démarrer ? » à droite.
struct ReglagesView: View {
    @EnvironmentObject var etat: Etat
    @State private var testStand: (ok: Bool, texte: String)?
    @State private var testStandEnCours = false
    @State private var section: SectionReglages = .concours
    @State private var montrerEpreuves = false
    @State private var testGalerie = ""
    @State private var testGalerieOK: Bool?
    @State private var testEnCours = false
    @State private var testFTPEnCours = false
    @State private var envoiDossier = ""
    @State private var envoiDossierOK: Bool?
    @State private var envoiDossierEnCours = false

    var body: some View {
        HStack(spacing: 0) {
            if etat.panneauGauche {
                panneauSections
                    .frame(width: 220)
                    .background(Theme.panneau)
                Divider().overlay(Theme.bordure)
            }
            centre
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if etat.panneauDroit {
                Divider().overlay(Theme.bordure)
                PretADemarrer()
                    .frame(width: 280)
                    .background(Theme.panneau)
            }
        }
        .sheet(isPresented: $montrerEpreuves) { EpreuvesView(concours: etat.concours) }
        .sheet(isPresented: $etat.montrerCapture) {
            if let i = etat.reglages.chronos.firstIndex(where: { $0.id.uuidString == etat.captureChoisie }) {
                CaptureView(capture: etat.capture(pour: etat.captureChoisie), chrono: $etat.reglages.chronos[i])
                    .environmentObject(etat)
            }
        }
    }

    // MARK: - Panneau de gauche

    private var panneauSections: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Début de concours").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.texteTresDiscret)
                .padding(.bottom, 4)
            ForEach(SectionReglages.debut) { s in boutonSection(s, etat: etatSection(s)) }
            Text("Préférences de l'app").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.texteTresDiscret)
                .padding(.top, 16).padding(.bottom, 4)
            ForEach(SectionReglages.preferences) { s in boutonSection(s, etat: nil) }
            Spacer()
        }
        .padding(14)
    }

    private func etatSection(_ s: SectionReglages) -> Bool? {
        let v = etat.verifications
        func ok(_ ids: [String]) -> Bool { v.filter { ids.contains($0.id) }.allSatisfy(\.ok) }
        switch s {
        case .concours: return etat.concours != nil
        case .dossiers: return ok(["Dossier de réception", "Import Lightroom", "Travail Lightroom", "Serveur local"])
        case .copies: return ok(["Fichier .cube"])
        case .lightroom: return ok(["Dossier tampon"])
        default: return nil
        }
    }

    private func boutonSection(_ s: SectionReglages, etat ok: Bool?) -> some View {
        Button { section = s } label: {
            HStack {
                Text(s.rawValue).font(.system(size: 13))
                    .foregroundStyle(section == s ? Theme.texte : Theme.texteSection)
                Spacer()
                if let ok {
                    Text(ok ? "OK" : "À faire").font(.system(size: 12, weight: ok ? .regular : .semibold))
                        .foregroundStyle(ok ? Theme.ok : Theme.attention)
                }
            }
            .padding(8)
            .contentShape(Rectangle())
            .background(section == s ? Theme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(BoutonPlat())
    }

    // MARK: - Centre

    @ViewBuilder
    private var centre: some View {
        switch section {
        case .raccourcis:
            ScrollView { RaccourcisView(raccourcis: etat.raccourcis).padding(24) }
        case .modeles:
            ScrollView { ModelesView().padding(24) }
        default:
            ScrollViewReader { lecteur in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Réglages du concours").font(.system(size: 18, weight: .semibold))
                            Text("Gardés d'un jour à l'autre pour un concours sur plusieurs jours.")
                                .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                        }
                        carteConcours.id(SectionReglages.concours)
                        carteDossiers.id(SectionReglages.dossiers)
                        carteCopies.id(SectionReglages.copies)
                        carteLightroom.id(SectionReglages.lightroom)
                        carteEnvois.id(SectionReglages.envois)
                        carteCloture.id(SectionReglages.cloture)
                        carteMemoire.id(SectionReglages.memoire)
                        carteCommandes.id(SectionReglages.commandes)
                        CarteApparence().id(SectionReglages.apparence)
                        CarteLicence().id(SectionReglages.protection)
                        CarteNotificationsIphone().id(SectionReglages.iphone)
                    }
                    .padding(24)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: section) { s in lecteur.scrollTo(s, anchor: .top) }   // sans animation : le clic suivant tombe juste
                .onAppear { lecteur.scrollTo(section, anchor: .top) }
            }
        }
    }

    private var carteConcours: some View {
        Carte(titre: SectionReglages.concours.rawValue) {
            Group {
            Ligne("Nom du concours") {
                TextField("ex. Haras de la Vallée", text: $etat.reglages.nomConcours).textFieldStyle(.roundedBorder)
            }
            Ligne("Durée") {
                Stepper("\(etat.reglages.nombreJours) jour\(etat.reglages.nombreJours > 1 ? "s" : "")",
                        value: $etat.reglages.nombreJours, in: 1...10)
            }
            Divider().overlay(Theme.bordure)
            if let c = etat.concours {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fichier FFE : \((etat.reglages.cheminFFE as NSString).lastPathComponent)")
                            .font(.system(size: 13))
                        Text("\(c.format.rawValue) · \(c.epreuves.count) épreuves · \(c.nombreEngages) engagés")
                            .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                    }
                    Spacer()
                    Button("Recharger") { etat.rechargerFFE() }.buttonStyle(BoutonStyle())
                    Button("Remplacer…") { etat.choisirFichierFFE() }.buttonStyle(BoutonStyle())
                    Button("Voir les épreuves") { montrerEpreuves = true }.buttonStyle(BoutonStyle(principal: true))
                }
            } else {
                HStack {
                    Text("Aucun fichier FFE chargé (SIF ou FFE Compet, reconnu tout seul).")
                        .font(.system(size: 13)).foregroundStyle(Theme.texteDiscret)
                    Spacer()
                    Button("Charger le fichier FFE…") { etat.choisirFichierFFE() }.buttonStyle(BoutonStyle(principal: true))
                }
            }
            if let e = etat.erreurFFE {
                Text(e).font(.system(size: 12)).foregroundStyle(Theme.erreur)
            }
            }
            Divider().overlay(Theme.bordure)
            ConcoursRangesView()
            Divider().overlay(Theme.bordure)
            // ① Les chronos du concours (maquette « Pistes et chronos » validée par HUGO le 25/11/2026)
            Text("Les chronos du concours").font(.system(size: 13, weight: .semibold))
            Text("Un chrono = un ordinateur HM Timing (une ou plusieurs pistes), ou une page d'incrustation Horse & Comp (une piste). Ajoute-en autant qu'il y en a sur le terrain.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            ForEach($etat.reglages.chronos) { $c in
                LigneChrono(chrono: $c, moteur: etat.moteur)
            }
            HStack {
                Button("＋ Ajouter un HM Timing") {
                    etat.reglages.chronos.append(.init(genre: .hmTiming, nom: etat.reglages.nomLibre(.hmTiming)))
                }
                .buttonStyle(BoutonStyle())
                Button("＋ Ajouter un Horse & Comp") {
                    etat.reglages.chronos.append(.init(genre: .horseComp, nom: etat.reglages.nomLibre(.horseComp)))
                }
                .buttonStyle(BoutonStyle())
            }
            Ligne("Fin de tour tolérée") {
                Stepper("\(etat.reglages.finDeTourSecondes) s après l'arrivée", value: $etat.reglages.finDeTourSecondes, in: 0...60, step: 5)
            }
            Ligne("Latence au changement") {
                Stepper("\(etat.reglages.latenceSecondes) s", value: $etat.reglages.latenceSecondes, in: 0...30)
            }
            Ligne("Attente du chrono") {
                Stepper("\(etat.reglages.attenteChronoMinutes) min au plus, puis la photo part avec son code",
                        value: $etat.reglages.attenteChronoMinutes, in: 1...15)
            }
            Ligne("Photos en _00") {
                Stepper("attendent \(etat.reglages.attente00Minutes) min une photo de code", value: $etat.reglages.attente00Minutes, in: 0...10)
            }
            Ligne("Rush automatique") {
                Stepper(etat.reglages.rushAutoPhotos == 0 ? "jamais tout seul (bouton « Rush » seulement)"
                        : "dès \(etat.reglages.rushAutoPhotos) photos à valider, tout part avec le code du photographe",
                        value: $etat.reglages.rushAutoPhotos, in: 0...200, step: 10)
                    .help("Les propositions du chrono restent dans « À valider › À reprendre au calme ».")
            }
            Ligne("Photos traitées en même temps") {
                Stepper(etat.reglages.photosEnMemeTemps == 0
                        ? "automatique : jusqu'à \(RegleRegulateur.plafond(reglage: 0)) sur ce Mac pendant une rafale"
                        : "jusqu'à \(etat.reglages.photosEnMemeTemps) pendant une rafale",
                        value: $etat.reglages.photosEnMemeTemps, in: 0...16)
                    .help("Pendant une rafale, toutes ces files travaillent ensemble, en priorité basse : Lightroom passe toujours avant. Au calme, l'app en garde moins pour laisser le Mac léger. Pris en compte au prochain démarrage du tri.")
            }
            ChoixChemin(titre: "Passages pour le mode entraînement (facultatif)",
                        aide: "Fichier JSON des passages d'un ancien concours : remplace les HM Timing pour s'entraîner.",
                        chemin: $etat.reglages.fichierPassagesEntrainement, fichier: true, types: [.json])
            Text("Aucune correction n'est appliquée seule : chaque proposition du chrono va dans « À valider ».")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)

            // ② Les pistes : chacune choisit son chrono, et sa piste dans ce chrono
            Divider().overlay(Theme.bordure)
            Text("Les pistes").font(.system(size: 13, weight: .semibold))
            Text("Pour chaque piste, choisis son chrono. Si un HM Timing chronomètre plusieurs pistes, choisis aussi laquelle.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            HStack {
                Text("Piste").frame(minWidth: 90, maxWidth: 160, alignment: .leading)
                Text("Photographe").frame(minWidth: 90, maxWidth: 150, alignment: .leading)
                Text("Chrono").frame(minWidth: 140, maxWidth: 210, alignment: .leading)
                Text("Piste dans ce chrono").frame(minWidth: 130, maxWidth: 190, alignment: .leading)
                Spacer()
            }
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.texteDiscret)
            ForEach($etat.reglages.pistes) { $piste in
                HStack {
                    TextField("Piste", text: $piste.nom).textFieldStyle(.roundedBorder).frame(minWidth: 90, maxWidth: 160)
                    TextField("Photographe", text: $piste.photographe).textFieldStyle(.roundedBorder).frame(minWidth: 90, maxWidth: 150)
                    Picker("", selection: $piste.chrono) {
                        Text(etat.reglages.chronos.count == 1 ? etat.reglages.chronos[0].nom : "Trouvé tout seul").tag("")
                        ForEach(etat.reglages.chronos) { c in Text("\(c.genre == .horseComp ? "H&C" : "HM") · \(c.nom)").tag(c.id.uuidString) }
                        Text("Aucun chrono").tag(ReglagesConcours.Piste.aucun)
                    }
                    .labelsHidden().frame(minWidth: 140, maxWidth: 210)
                    .onChange(of: piste.chrono) { _ in piste.sourceChrono = "" }
                    pisteDansChrono($piste).frame(minWidth: 130, maxWidth: 190, alignment: .leading)
                    Spacer()
                    Button("Retirer") { etat.reglages.pistes.removeAll { $0.id == piste.id } }
                        .buttonStyle(BoutonStyle()).fixedSize()
                        .disabled(etat.reglages.pistes.count <= 1)
                }
            }
            Text("Les iPhone de l'app Piste voient ces pistes. Si un chrono tombe, seules ses pistes passent « sans vérification » ; les autres continuent.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            Button("＋ Ajouter une piste") {
                etat.reglages.pistes.append(.init(nom: "Piste \(etat.reglages.pistes.count + 1)", photographe: ""))
            }
            .buttonStyle(BoutonStyle())
        }
    }

    /// « Piste dans ce chrono » : les pistes vues dans le HM Timing choisi ; une seule pour Horse & Comp.
    @ViewBuilder
    private func pisteDansChrono(_ piste: Binding<ReglagesConcours.Piste>) -> some View {
        let p = piste.wrappedValue
        if p.chrono == ReglagesConcours.Piste.aucun {
            Text("photos gardées avec leur code").font(.system(size: 12)).foregroundStyle(Theme.texteTresDiscret)
        } else if let c = etat.reglages.chronoDe(p), c.genre == .horseComp {
            Text("une seule piste").font(.system(size: 12)).foregroundStyle(Theme.texteTresDiscret)
        } else {
            Picker("", selection: piste.sourceChrono) {
                Text("Trouvée toute seule").tag("")
                ForEach(etat.sourcesChrono(etat.reglages.chronoDe(p), plus: p.sourceChrono), id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
        }
    }

    private var carteDossiers: some View {
        Carte(titre: SectionReglages.dossiers.rawValue,
              sousTitre: "Les sous-dossiers du serveur local prennent le nom des épreuves FFE, nettoyé (sans parenthèses ni tirets).") {
            ChoixChemin(titre: "Dossier de réception", aide: "Là où les boîtiers déposent les photos.",
                        chemin: $etat.reglages.dossierReception)
            ChoixChemin(titre: "Import Lightroom", aide: "Dossier surveillé par l'import automatique de Lightroom.",
                        chemin: $etat.reglages.dossierImportLightroom)
            ChoixChemin(titre: "Travail Lightroom", aide: "Là où Lightroom range les photos importées.",
                        chemin: $etat.reglages.dossierTravailLightroom)
            ChoixChemin(titre: "Serveur local", aide: "Partage SMB monté sur le Mac (ex. /Volumes/DATA).",
                        chemin: $etat.reglages.dossierServeurLocal)
        }
    }

    private var carteCopies: some View {
        Carte(titre: SectionReglages.copies.rawValue,
              sousTitre: "Copies faites à partir de l'original, qui n'est jamais recompressé.") {
            Group {
            Text("Serveur local").font(.system(size: 13, weight: .semibold))
            ChoixChemin(titre: "Fichier .cube", aide: nil, chemin: $etat.reglages.cubeServeur,
                        fichier: true, types: [UTType(filenameExtension: "cube") ?? .data])
            Ligne("Côté le plus long") {
                Stepper("\(etat.reglages.coteServeur) px", value: $etat.reglages.coteServeur, in: 800...4000, step: 100)
            }
            Ligne("Qualité JPEG") {
                Stepper("\(etat.reglages.qualiteServeur) %", value: $etat.reglages.qualiteServeur, in: 30...100, step: 2)
            }
            }
            Divider().overlay(Theme.bordure)
            Text("Galerie en ligne").font(.system(size: 13, weight: .semibold))
            Toggle("Même fichier .cube que le serveur local", isOn: $etat.reglages.cubeGalerieIdentique)
            if !etat.reglages.cubeGalerieIdentique {
                ChoixChemin(titre: "Fichier .cube galerie", aide: nil, chemin: $etat.reglages.cubeGalerie,
                            fichier: true, types: [UTType(filenameExtension: "cube") ?? .data])
            }
            Ligne("Côté le plus long") {
                Stepper("\(etat.reglages.coteGalerie) px", value: $etat.reglages.coteGalerie, in: 800...4000, step: 100)
            }
            Ligne("Qualité JPEG") {
                Stepper("\(etat.reglages.qualiteGalerie) %", value: $etat.reglages.qualiteGalerie, in: 30...100, step: 2)
            }
            Toggle("Numéro incrusté en haut à gauche (galerie seulement)", isOn: $etat.reglages.numeroIncruste)
            Text("Métadonnées gardées sur la galerie : copyright et auteur.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
        }
    }

    private var carteLightroom: some View {
        Carte(titre: SectionReglages.lightroom.rawValue) {
            Toggle("Utiliser le dossier tampon (originaux envoyés à Lightroom par lots)", isOn: $etat.reglages.tamponActif)
            if etat.reglages.tamponActif {
                ChoixChemin(titre: "Dossier tampon", aide: nil, chemin: $etat.reglages.dossierTampon)
                Ligne("Taille d'un lot") {
                    Stepper("\(etat.reglages.tailleLot) photos", value: $etat.reglages.tailleLot, in: 5...200, step: 5)
                }
                Ligne("Import forcé si un boîtier se tait") {
                    Stepper("\(etat.reglages.silenceBoitierMinutes) min", value: $etat.reglages.silenceBoitierMinutes, in: 1...30)
                }
                Toggle("Retarder le lot si Lightroom est occupé", isOn: $etat.reglages.retarderSiLightroomOccupe)
            }
            Text("Avant le déplacement : écriture IPTC dans l'original (code, cavalier, cheval, épreuve, CHUTE), sans toucher l'image.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            Divider().overlay(Theme.bordure)
            HStack {
                Button("Créer les collections dynamiques Lightroom") {
                    if let u = etat.creerCollectionsLightroom() { etat.montrerDansLeFinder(u) }
                }
                .buttonStyle(BoutonStyle()).disabled(etat.reglages.cheminFFE.isEmpty)
                .help("Une collection par épreuve (code #NN_ dans un champ, pas rejetée, prise pendant le concours), comme l'ancien outil.")
            }
            Text("Dans Lightroom : clic droit sur « Collections » › Importer des paramètres de collection dynamique, puis choisir les fichiers .lrsmcol.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
        }
    }

    private var carteCommandes: some View {
        Carte(titre: SectionReglages.commandes.rawValue,
              sousTitre: "Les listings de chaque concours et les commandes sont gardés dans un dossier partagé par iCloud entre les Mac du stand. Le prix se règle par concours, dans l'écran Commandes.") {
            ChoixChemin(titre: "Dossier des listings et commandes", aide: "Pas choisi : iCloud Drive › Tri-photo Listings",
                        chemin: $etat.reglages.dossierListings)
            if !etat.reglages.dossierListings.isEmpty {
                Button("Revenir à iCloud Drive › Tri-photo Listings") { etat.reglages.dossierListings = "" }.buttonStyle(BoutonStyle())
            }
            Text(etat.archives.message.isEmpty ? "En changeant de dossier, tout son contenu y est déplacé. \(etat.archives.listings.count) concours gardés, \(etat.archives.commandes.count) commandes."
                                               : etat.archives.message)
                .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
        }
    }

    private var carteMemoire: some View {
        Carte(titre: SectionReglages.memoire.rawValue,
              sousTitre: "La mémoire (vignettes seulement) est partagée entre les stands par iCloud et n'est jamais remise à zéro. Les détections tournent au calme et ne font que proposer.") {
            ChoixChemin(titre: "Dossier de la mémoire", aide: "Pas choisi : iCloud Drive › Tri-photo Mémoire",
                        chemin: $etat.reglages.dossierMemoire)
            HStack {
                if !etat.reglages.dossierMemoire.isEmpty {
                    Button("Revenir à iCloud Drive › Tri-photo Mémoire") { etat.reglages.dossierMemoire = "" }.buttonStyle(BoutonStyle())
                }
                if etat.ancienDossierMemoire != nil {
                    Button("Finir le déplacement") { etat.finirDeplacementMemoire() }.buttonStyle(BoutonStyle())
                }
            }
            Text(etat.messageMemoire.isEmpty ? "En changeant de dossier, tout le contenu de la mémoire actuelle y est déplacé (rien n'est perdu ni doublé)."
                                             : etat.messageMemoire)
                .font(.system(size: 11)).foregroundStyle(etat.messageMemoire.isEmpty ? Theme.texteTresDiscret : Theme.texteDiscret)
            Toggle("Détections en tâche de fond pendant le tri", isOn: $etat.reglages.detectionsActives)
            Divider().overlay(Theme.bordure)
            Toggle("Copier les meilleures photos de chaque remise des prix (_99) dans Google Drive", isOn: $etat.reglages.remisesActives)
            if etat.reglages.remisesActives {
                ChoixChemin(titre: "Dossier Google Drive", aide: "Un dossier de Google Drive sur ce Mac (app Google Drive), partagé avec l'organisation",
                            chemin: $etat.reglages.dossierRemises)
                Ligne("Photos par remise") {
                    Stepper("\(etat.reglages.photosParRemise) photos", value: $etat.reglages.photosParRemise, in: 1...60)
                }
                Ligne("Remise finie après") {
                    Stepper("\(etat.reglages.attenteRemiseMinutes) min sans nouvelle photo _99", value: $etat.reglages.attenteRemiseMinutes, in: 2...60)
                }
                Text("Choix : netteté, visages (nets, yeux ouverts), ressemblance aux « Meilleures » de la mémoire ; les photos floues, du sol ou de code sont écartées, celles que tu marques « Meilleure » (M) passent d'abord. Ce sont les copies du serveur (avec le .cube) qui partent, une seule fois, un dossier par épreuve.")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
                if !etat.moteur.resume.remises.message.isEmpty {
                    Text(etat.moteur.resume.remises.message).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                }
            }
        }
    }

    private var carteEnvois: some View {
        Carte(titre: SectionReglages.envois.rawValue) {
            Ligne("Serveur local") {
                Picker("", selection: $etat.reglages.protocoleServeur) {
                    ForEach(ReglagesConcours.Protocole.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 160)
                .disabled(true)
                .help("SMB pour l'instant ; le FTP viendra plus tard si besoin.")
            }
            Ligne("Galerie du stand (serveur local)") {
                TextField("https://190.160.40.5 (vide : pas de rafraîchissement)", text: $etat.reglages.urlGalerieStand)
                    .textFieldStyle(.roundedBorder)
            }
            if !etat.reglages.urlGalerieStand.isEmpty {
                Ligne("Identifiant · mot de passe") {
                    TextField("Identifiant", text: $etat.reglages.identifiantGalerieStand).textFieldStyle(.roundedBorder).frame(width: 180)
                    SecureField("Mot de passe (gardé dans le trousseau)", text: Binding(
                        get: { etat.motDePasseGalerie },
                        set: { etat.motDePasseGalerie = $0 }))
                        .textFieldStyle(.roundedBorder)
                }
                Ligne("Rafraîchir la galerie") {
                    Stepper(etat.reglages.minutesGalerieStand == 0
                            ? "en direct : toutes les 30 s pendant une rafale, et 10 s après la dernière photo"
                            : "toutes les \(etat.reglages.minutesGalerieStand) min au plus, et à la fin de chaque rafale",
                            value: $etat.reglages.minutesGalerieStand, in: 0...30)
                        .help("Tout en bas (0) : en direct. Seuls les dossiers qui ont reçu des photos sont relus, jamais à chaque photo.")
                }
                HStack {
                    Button(testStandEnCours ? "Essai en cours…" : "Tester la connexion") {
                        guard let c = etat.configGalerieStand() else { return }
                        testStandEnCours = true
                        testStand = nil
                        EssaiGalerieStand.tester(c) { ok, m in
                            Task { @MainActor in testStandEnCours = false; testStand = (ok, m) }
                        }
                    }
                    .buttonStyle(BoutonStyle()).disabled(testStandEnCours)
                    Button("Rafraîchir maintenant") {
                        if etat.moteur.actif {
                            etat.moteur.rafraichirGalerie()
                        } else if let c = etat.configGalerieStand() {
                            // Sans tri en cours : on demande tout de suite à la galerie de chercher les nouveaux dossiers.
                            testStandEnCours = true
                            testStand = nil
                            EssaiGalerieStand.chercherNouveauxDossiers(c) { ok, m in
                                Task { @MainActor in testStandEnCours = false; testStand = (ok, m) }
                            }
                        }
                    }
                    .buttonStyle(BoutonStyle()).disabled(testStandEnCours)
                    if !etat.reglages.empreinteGalerieStand.isEmpty {
                        Button("Oublier le certificat du serveur") { etat.reglages.empreinteGalerieStand = "" }
                            .buttonStyle(BoutonStyle())
                            .help("À faire seulement si le serveur du stand a changé de certificat.")
                    }
                    if let t = testStand {
                        Text(t.ok ? "✓ " + t.texte : t.texte).font(.system(size: 11))
                            .foregroundStyle(t.ok ? Theme.ok : Theme.erreur)
                    } else if let g = etat.moteur.resume.galerie, !g.message.isEmpty {
                        Text(g.message).font(.system(size: 11)).foregroundStyle(g.ok == false ? Theme.erreur : Theme.texteDiscret)
                    }
                }
                Text("Les copies partent au fil de l'eau ; la galerie ne relit que les dossiers qui ont reçu des photos, toutes les X minutes au plus. Pas de requête à chaque photo.")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            }
            Divider().overlay(Theme.bordure)
            galerieEnLigne
            Divider().overlay(Theme.bordure)
            RegulateurUniFiView()
            Divider().overlay(Theme.bordure)
            accesDistance
            Divider().overlay(Theme.bordure)
            Toggle("Loupedeck CT : piloter Groom Pix et afficher l'état du stand (ce Mac seulement)",
                   isOn: Binding(get: { etat.loupedeckActif }, set: { etat.loupedeckActif = $0 }))
            Text("Le module « Groom Pix » du logiciel Loupedeck lit l'état chaque seconde, sans réseau. Le couper ne change rien au tri.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            Divider().overlay(Theme.bordure)
            Toggle("Sauvegarde des originaux sur un 2e disque (option)", isOn: $etat.reglages.sauvegardeActive)
            if etat.reglages.sauvegardeActive {
                ChoixChemin(titre: "Disque de sauvegarde",
                            aide: "Chaque original, tel qu'il arrive du boîtier, y est copié sous son nouveau nom, dans un dossier par jour.",
                            chemin: $etat.reglages.dossierSauvegarde)
            }
        }
    }

    private var carteCloture: some View {
        Carte(titre: SectionReglages.cloture.rawValue,
              sousTitre: "Chaque soir : « Clôturer la journée ». Le dernier jour : « Clôturer le concours ». L'app vérifie que tous les envois vers la galerie sont finis, puis produit le fichier d'attribution des cavaliers.") {
            ChoixChemin(titre: "Fichier d'attribution dans", aide: "Pas choisi : dans le dossier « Clôtures » de l'app.",
                        chemin: $etat.reglages.dossierClotures)
            HStack {
                Button("Créer le fichier d'attribution de début") {
                    if let u = etat.creerFichierDebut() { etat.montrerDansLeFinder(u) }
                }
                .buttonStyle(BoutonStyle()).disabled(etat.reglages.cheminFFE.isEmpty)
                .help("Fait tout seul au démarrage de la journée s'il n'existe pas encore.")
                Button("Engagés terrain…") { etat.montrerTerrain = true }.buttonStyle(BoutonStyle())
                Text("\(etat.engagesTerrain.count) engagés terrain").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
            }
            Text("Début : « \(etat.fichierDebut.lastPathComponent) » (lignes 80, 00 et 99 comprises). Fin : « \(etat.fichierFin.lastPathComponent) », au format HMV, avec les engagés terrain.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            if !etat.messageAttribution.isEmpty {
                Text(etat.messageAttribution).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
            }
            HStack {
                Button(GenreCloture.journee.rawValue + "…") { etat.cloture = .journee }.buttonStyle(BoutonStyle())
                Button(GenreCloture.finale.rawValue + "…") { etat.cloture = .finale }.buttonStyle(BoutonStyle())
            }
        }
    }

    /// Galerie en ligne : réglée comme un site dans FileZilla, ou écrite dans un dossier du Mac (sans connexion).
    @ViewBuilder
    private var galerieEnLigne: some View {
        let versDossier = etat.reglages.galerieVersDossier
        Text("Galerie en ligne").font(.system(size: 13, weight: .semibold))
        Ligne("Envoi") {
            Picker("", selection: $etat.reglages.galerieVersDossier) {
                Text("Par internet (FTP)").tag(false)
                Text("Dans un dossier du Mac").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 320)
        }
        if versDossier {
            ChoixChemin(titre: "Dossier de la galerie",
                        aide: "Pas encore choisi : rien n'est écrit. Un disque externe convient.",
                        chemin: $etat.reglages.dossierLocalGalerie)
            Text("Pas de connexion au concours : les copies de la galerie (même taille, même .cube, numéro incrusté) sont écrites dans ce dossier, à plat, et il est tenu à jour comme la galerie en ligne (ajouts, remplacements, photos retirées mises à la Corbeille). Au bureau, il suffit de l'envoyer en ligne.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            HStack {
                Button(testEnCours ? "Essai en cours…" : "Tester le dossier") { testerGalerie() }
                    .buttonStyle(BoutonStyle()).disabled(testEnCours || etat.reglages.dossierLocalGalerie.isEmpty)
                Button("Mettre à jour maintenant") { etat.moteur.envoyerGalerieMaintenant() }
                    .buttonStyle(BoutonStyle()).disabled(!etat.moteur.actif)
                if !etat.reglages.dossierLocalGalerie.isEmpty {
                    Button("Ouvrir") { etat.montrerDansLeFinder(URL(fileURLWithPath: etat.reglages.dossierLocalGalerie)) }
                        .buttonStyle(BoutonStyle())
                }
                if !testGalerie.isEmpty {
                    Text(testGalerie).font(.system(size: 11)).foregroundStyle(testGalerieOK == false ? Theme.erreur : Theme.ok)
                } else if let g = etat.moteur.resume.galerieEnLigne {
                    Text(g.aFaire == 0 ? "\(g.enLigne) photos dans le dossier, à jour." : g.message)
                        .font(.system(size: 11)).foregroundStyle(g.ok == false ? Theme.erreur : Theme.texteDiscret)
                }
            }
            Ligne("Auteur par défaut") {
                TextField("Écrit dans la photo si le boîtier n'a pas de photographe (photo de synchro)", text: $etat.reglages.auteurGalerie)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Envoyer ce dossier en ligne (au bureau)").font(.system(size: 13, weight: .semibold)).padding(.top, 6)
            Text("Avec la connexion ci-dessous : seules les photos nouvelles ou remplacées partent, celles retirées du dossier sont supprimées en ligne. Un envoi coupé reprend où il s'était arrêté.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
        }
        connexionGalerie(versDossier: versDossier)
    }

    /// La connexion FTP / SFTP (comme dans FileZilla) : pour la galerie en ligne, ou pour envoyer le dossier au bureau.
    @ViewBuilder
    private func connexionGalerie(versDossier: Bool) -> some View {
        Ligne("Protocole") {
            Picker("", selection: $etat.reglages.protocoleGalerie) {
                ForEach(ConfigGalerieEnLigne.Protocole.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden().frame(width: 220)
            Text("comme dans FileZilla (Gestionnaire de sites › Protocole / Chiffrement)")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
        }
        Ligne("Hôte · port") {
            TextField(versDossier ? "ftp.mon-site.fr" : "ftp.mon-site.fr (vide : pas d'envoi)", text: $etat.reglages.adresseFTPGalerie)
                .textFieldStyle(.roundedBorder)
            TextField("\(etat.reglages.protocoleGalerie.portParDefaut)", value: $etat.reglages.portGalerie, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder).frame(width: 70)
                .help("Vide ou 0 : port habituel (\(etat.reglages.protocoleGalerie.portParDefaut)).")
        }
        if !etat.reglages.adresseFTPGalerie.isEmpty {
            Ligne("Identifiant · mot de passe") {
                TextField("Identifiant", text: $etat.reglages.identifiantGalerie).textFieldStyle(.roundedBorder).frame(width: 180)
                SecureField("Mot de passe (gardé dans le trousseau)", text: Binding(
                    get: { etat.motDePasseGalerieEnLigne },
                    set: { etat.motDePasseGalerieEnLigne = $0 }))
                    .textFieldStyle(.roundedBorder)
            }
            Ligne("Dossier distant") {
                TextField("/www/album (toutes les photos à plat dans ce dossier)", text: $etat.reglages.dossierGalerie)
                    .textFieldStyle(.roundedBorder)
            }
            if etat.reglages.protocoleGalerie == .ftpsExplicite || etat.reglages.protocoleGalerie == .ftpsImplicite {
                Toggle("Accepter le certificat du serveur même s'il n'est pas reconnu", isOn: $etat.reglages.accepterCertificatGalerie)
            }
            if !versDossier {
                Ligne("Quand envoyer") {
                    Picker("", selection: $etat.reglages.galerieLaNuit) {
                        Text("Au fil de l'eau").tag(false)
                        Text("La nuit").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                    if etat.reglages.galerieLaNuit {
                        Stepper("à partir de \(etat.reglages.heureNuitGalerie) h", value: $etat.reglages.heureNuitGalerie, in: 0...23)
                        Stepper("jusqu'à \(etat.reglages.heureMatinGalerie) h", value: $etat.reglages.heureMatinGalerie, in: 0...23)
                    }
                }
            }
            Ligne("Débit maximum") {
                Stepper(etat.reglages.limiteKoGalerie == 0 ? "sans limite" : "\(etat.reglages.limiteKoGalerie) Ko/s",
                        value: $etat.reglages.limiteKoGalerie, in: 0...20_000, step: 250)
            }
            if versDossier {
                HStack {
                    Button(testFTPEnCours ? "Essai en cours…" : "Tester la connexion") { testerConnexionFTP() }
                        .buttonStyle(BoutonStyle()).disabled(testFTPEnCours || envoiDossierEnCours)
                    Button(envoiDossierEnCours ? "Envoi en cours…" : "Envoyer ce dossier en ligne") { envoyerDossierEnLigne() }
                        .buttonStyle(BoutonStyle(principal: true))
                        .disabled(envoiDossierEnCours || etat.reglages.dossierLocalGalerie.isEmpty)
                    if !envoiDossier.isEmpty {
                        Text(envoiDossier).font(.system(size: 11))
                            .foregroundStyle(envoiDossierOK == false ? Theme.erreur : (envoiDossierOK == true ? Theme.ok : Theme.texteDiscret))
                    }
                }
            } else {
                Ligne("Auteur par défaut") {
                    TextField("Écrit dans la photo si le boîtier n'a pas de photographe (photo de synchro)", text: $etat.reglages.auteurGalerie)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Button(testEnCours ? "Essai en cours…" : "Tester la connexion") { testerGalerie() }
                        .buttonStyle(BoutonStyle()).disabled(testEnCours)
                    Button("Envoyer maintenant") { etat.moteur.envoyerGalerieMaintenant() }
                        .buttonStyle(BoutonStyle()).disabled(!etat.moteur.actif)
                        .help("Sans attendre la nuit.")
                    if !testGalerie.isEmpty {
                        Text(testGalerie).font(.system(size: 11)).foregroundStyle(testGalerieOK == false ? Theme.erreur : Theme.ok)
                    } else if let g = etat.moteur.resume.galerieEnLigne {
                        Text(g.aFaire == 0 ? "\(g.enLigne) photos en ligne, à jour." : (g.attendLaNuit ? "\(g.aFaire) photos attendent la nuit." : g.message))
                            .font(.system(size: 11)).foregroundStyle(g.ok == false ? Theme.erreur : Theme.texteDiscret)
                    }
                }
                Text("Une photo qui existe déjà en ligne est remplacée, une nouvelle est ajoutée, une photo supprimée dans Lightroom est supprimée en ligne. Seules les photos envoyées par l'app sont touchées.")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            }
        }
    }

    private func testerConnexionFTP() {
        guard let g = etat.configGalerieFTP() else { return }
        testFTPEnCours = true
        envoiDossier = "Essai de la connexion…"
        envoiDossierOK = nil
        etat.moteur.testerGalerieEnLigne(g) { ok, message in
            Task { @MainActor in
                testFTPEnCours = false
                envoiDossierOK = ok
                envoiDossier = message
            }
        }
    }

    private func envoyerDossierEnLigne() {
        guard let g = etat.configGalerieFTP() else { return }
        envoiDossierEnCours = true
        envoiDossierOK = nil
        envoiDossier = "Comparaison du dossier avec ce qui est déjà en ligne…"
        GalerieEnLigne.envoyerDossier(URL(fileURLWithPath: etat.reglages.dossierLocalGalerie, isDirectory: true),
                                      config: g, etat: etat.fichierEnvoiDossier) { _, _, message, fini, ok in
            Task { @MainActor in
                envoiDossier = message
                if fini {
                    envoiDossierEnCours = false
                    envoiDossierOK = ok
                }
            }
        }
    }

    /// Accès à distance : page web en lecture seule (tableau de bord + revue), protégée par un code.
    @ViewBuilder
    private var accesDistance: some View {
        Text("Accès à distance").font(.system(size: 13, weight: .semibold))
        Toggle("Montrer le tableau de bord et la revue à un autre Mac ou un PC (lecture seule)", isOn: $etat.reglages.accesDistance)
        if etat.reglages.accesDistance {
            Ligne("Code d'accès · port") {
                TextField("6 chiffres", text: $etat.reglages.codeAccesDistance).textFieldStyle(.roundedBorder).frame(width: 110)
                Button("Nouveau code") { etat.reglages.codeAccesDistance = String(Int.random(in: 100_000...999_999)) }
                    .buttonStyle(BoutonStyle())
                TextField("8090", value: $etat.reglages.portAccesDistance, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).frame(width: 70)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Dans le navigateur de l'autre ordinateur, sur le même réseau que ce Mac :")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
                ForEach(AccesDistance.adresses(port: etat.reglages.portAccesDistance), id: \.self) { a in
                    Text(a).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                }
                Text("puis le code. Rien ne peut être réglé ni changé depuis cette page.")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
                if !etat.etatAccesDistance.isEmpty {
                    Text(etat.etatAccesDistance).font(.system(size: 11))
                        .foregroundStyle(etat.etatAccesDistance.hasPrefix("En marche") ? Theme.ok : Theme.erreur)
                }
            }
        }
    }

    private func testerGalerie() {
        guard let g = etat.configGalerieEnLigne() else { return }
        testEnCours = true
        testGalerie = ""
        etat.moteur.testerGalerieEnLigne(g) { ok, message in
            Task { @MainActor in
                testEnCours = false
                testGalerieOK = ok
                testGalerie = message
            }
        }
    }
}

/// Une ligne « libellé : réglage ».
struct Ligne<Contenu: View>: View {
    var libelle: String
    @ViewBuilder var contenu: () -> Contenu

    init(_ libelle: String, @ViewBuilder contenu: @escaping () -> Contenu) {
        self.libelle = libelle
        self.contenu = contenu
    }

    var body: some View {
        HStack {
            Text(libelle).font(.system(size: 13)).foregroundStyle(Theme.texteDiscret).frame(width: 220, alignment: .leading)
            contenu()
            Spacer(minLength: 0)
        }
    }
}

/// Choix d'un dossier (ou d'un fichier) avec son chemin et son état.
struct ChoixChemin: View {
    var titre: String
    var aide: String?
    @Binding var chemin: String
    var fichier = false
    var types: [UTType] = []

    private var existe: Bool {
        var estDossier: ObjCBool = false
        return !chemin.isEmpty && FileManager.default.fileExists(atPath: chemin, isDirectory: &estDossier)
            && estDossier.boolValue != fichier
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titre).font(.system(size: 13))
                Text(chemin.isEmpty ? (aide ?? "Pas encore choisi") : (chemin as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if !chemin.isEmpty {
                Pastille(texte: existe ? "Trouvé" : "Introuvable", genre: existe ? .ok : .attention)
            }
            Button("Choisir…", action: choisir).buttonStyle(BoutonStyle())
        }
    }

    private func choisir() {
        let p = NSOpenPanel()
        p.title = titre
        p.canChooseDirectories = !fichier
        p.canChooseFiles = fichier
        p.canCreateDirectories = !fichier
        p.allowsMultipleSelection = false
        if fichier && !types.isEmpty { p.allowedContentTypes = types }
        if !chemin.isEmpty { p.directoryURL = URL(fileURLWithPath: chemin).deletingLastPathComponent() }
        if p.runModal() == .OK, let url = p.url { chemin = url.path }
    }
}

/// Panneau de droite : ce qui manque avant de démarrer la journée.
struct PretADemarrer: View {
    @EnvironmentObject var etat: Etat
    @State private var moteurActif = false

    var body: some View {
        let v = etat.verifications
        VStack(alignment: .leading, spacing: 12) {
            Text("Prêt à démarrer ?").font(.system(size: 14, weight: .semibold))
            ForEach(v) { c in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(c.ok ? Theme.ok : Theme.orange).frame(width: 8, height: 8).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.id).font(.system(size: 13))
                        Text(c.detail).font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
                    }
                }
            }
            if moteurActif {
                Button("Arrêter le tri") { etat.arreterJournee() }
                    .buttonStyle(BoutonStyle())
                    .padding(.top, 8)
                Text("Le tri tourne. Les photos en cours finissent proprement.")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            } else {
                Button("Démarrer la journée") { etat.demarrerJournee() }
                    .buttonStyle(BoutonStyle(principal: true))
                    .padding(.top, 8)
                Text("Le démarrage reste possible avec un point orange (le .cube est facultatif) ; les dossiers, eux, sont obligatoires.")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            }
            if let e = etat.erreurDemarrage {
                Text(e).font(.system(size: 12)).foregroundStyle(Theme.erreur)
            }
            Divider().overlay(Theme.bordure).padding(.vertical, 4)
            Text("Mode entraînement").font(.system(size: 13, weight: .semibold))
            Text("Rejouer les photos d'un ancien concours dans le dossier de réception, pour tester sans risque.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
            Button("Ouvrir le mode entraînement…") { etat.montrerEntrainement = true }
                .buttonStyle(BoutonStyle())
            Spacer()
        }
        .padding(16)
        .onReceive(etat.moteur.$actif) { moteurActif = $0 }
    }
}

/// Liste des épreuves du fichier FFE, avec le nom du dossier qui sera créé sur le serveur local.
struct EpreuvesView: View {
    var concours: Concours?
    @Environment(\.dismiss) private var fermer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(concours?.nom ?? "Aucun concours").font(.system(size: 16, weight: .semibold))
                    if let c = concours {
                        Text("\(c.format.rawValue) · n° \(c.numero) · \(c.epreuves.count) épreuves · \(c.nombreEngages) engagés")
                            .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                    }
                }
                Spacer()
                Button("Fermer") { fermer() }.buttonStyle(BoutonStyle()).keyboardShortcut(.cancelAction)
            }
            Table(concours?.epreuves ?? []) {
                TableColumn("N°") { e in Text(e.numero) }.width(40)
                TableColumn("Épreuve") { e in Text(e.nom) }
                TableColumn("Date") { e in Text(e.date) }.width(90)
                TableColumn("Heure") { e in Text(e.heure) }.width(50)
                TableColumn("Piste") { e in Text(e.piste) }.width(120)
                TableColumn("Engagés") { e in Text("\(e.engages.count)") }.width(60)
                TableColumn("Dossier sur le serveur") { e in Text(e.nomDossier).foregroundStyle(Theme.texteDiscret) }
            }
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 500)
        .background(Theme.fond)
    }
}

/// Modèles de concours : enregistrer les réglages actuels (« CSO 4 pistes ») ou repartir d'un modèle.
struct ModelesView: View {
    @EnvironmentObject var etat: Etat
    @State private var nom = ""
    @State private var modeles: [String] = Stockage.modeles()
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Modèles de concours").font(.system(size: 18, weight: .semibold))
            Carte(titre: "Enregistrer les réglages actuels comme modèle",
                  sousTitre: "Tout est gardé sauf le nom du concours et le fichier FFE.") {
                HStack {
                    TextField("ex. CSO 4 pistes", text: $nom).textFieldStyle(.roundedBorder).frame(width: 260)
                    Button("Enregistrer") {
                        etat.enregistrerModele(nom: nom)
                        message = "Modèle « \(NomDossier.nettoyer(nom)) » enregistré."
                        nom = ""
                        modeles = Stockage.modeles()
                    }
                    .buttonStyle(BoutonStyle(principal: true))
                    .disabled(NomDossier.nettoyer(nom).isEmpty)
                }
            }
            Carte(titre: "Repartir d'un modèle") {
                if modeles.isEmpty {
                    Text("Aucun modèle pour l'instant.").font(.system(size: 13)).foregroundStyle(Theme.texteDiscret)
                }
                ForEach(modeles, id: \.self) { m in
                    HStack {
                        Text(m).font(.system(size: 13))
                        Spacer()
                        Button("Charger") {
                            etat.chargerModele(nom: m)
                            message = "Réglages du modèle « \(m) » chargés."
                        }
                        .buttonStyle(BoutonStyle())
                    }
                }
            }
            if !message.isEmpty {
                Text(message).font(.system(size: 12)).foregroundStyle(Theme.ok)
            }
        }
    }
}

/// Un chrono dans les réglages : HM Timing (nom, adresse, codes) ou Horse & Comp (nom, page, zones), avec son voyant.
struct LigneChrono: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject private var moteur: Moteur
    @Binding var chrono: ReglagesConcours.ChronoConcours
    @State private var test: (ok: Bool, texte: String)?
    @State private var enTest = false

    init(chrono: Binding<ReglagesConcours.ChronoConcours>, moteur: Moteur) {
        _chrono = chrono
        _moteur = ObservedObject(wrappedValue: moteur)
    }

    var body: some View {
        // deux lignes : les champs, puis le voyant et les boutons (rien n'est écrasé dans une fenêtre moyenne)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(chrono.genre == .hmTiming ? "HM TIMING" : "HORSE & COMP")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.surAccent)
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(chrono.genre == .hmTiming ? Theme.accent : Theme.orange, in: RoundedRectangle(cornerRadius: 4))
                TextField("Nom du chrono", text: $chrono.nom).textFieldStyle(.roundedBorder).frame(minWidth: 120, maxWidth: 200)
                if chrono.genre == .hmTiming {
                    TextField("Adresse (192.168.1.20:8080)", text: $chrono.adresse).textFieldStyle(.roundedBorder)
                        .frame(minWidth: 150, maxWidth: 240)
                    SecureField("Code régie", text: $chrono.codeRegie).textFieldStyle(.roundedBorder).frame(minWidth: 80, maxWidth: 110)
                    SecureField("Code tech", text: $chrono.codeTech).textFieldStyle(.roundedBorder).frame(minWidth: 80, maxWidth: 110)
                } else {
                    Text(chrono.urlIncrustation.isEmpty ? "Page d'incrustation à régler" : chrono.urlIncrustation)
                        .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                        .frame(minWidth: 120, maxWidth: 300, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                voyant
                Spacer(minLength: 8)
                if chrono.genre == .hmTiming {
                    Button(enTest ? "Test en cours…" : "Tester") { tester() }
                        .buttonStyle(BoutonStyle()).fixedSize()
                        .disabled(enTest || !chrono.pret)
                } else {
                    Button(chrono.zones["dossard"] == nil ? "Régler la page et les zones…" : "Page et zones…") {
                        etat.captureChoisie = chrono.id.uuidString
                        etat.montrerCapture = true
                    }
                    .buttonStyle(BoutonStyle(principal: chrono.zones["dossard"] == nil)).fixedSize()
                }
                Button("Retirer") { etat.reglages.chronos.removeAll { $0.id == chrono.id } }
                    .buttonStyle(BoutonStyle()).fixedSize()
                    .help("Les pistes de ce chrono passent « trouvé tout seul ».")
            }
        }
        .padding(10)
        .background(Theme.carte, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.bordure))
    }

    /// Vert : répond ; orange : ne répond pas ; gris : pas encore interrogé (tri arrêté).
    private var voyant: some View {
        let e = moteur.resume.chrono?.liens.first { $0.id == chrono.id.uuidString }
        let v: (Color, String) = {
            if let e {
                switch e.ok {
                case .some(true): return (Theme.ok, "répond" + (e.sources.isEmpty ? "" : " · " + e.sources.joined(separator: ", ")))
                case .some(false): return (Theme.orange, e.erreur.isEmpty ? "ne répond pas" : e.erreur)
                case .none: return (Theme.texteTresDiscret, "en attente…")
                }
            }
            if let t = test { return (t.ok ? Theme.ok : Theme.orange, t.texte) }
            if chrono.genre == .horseComp {
                let cap = etat.captures[chrono.id.uuidString]
                return (cap?.ouverte == true ? Theme.ok : Theme.texteTresDiscret, cap?.etatPage ?? (chrono.zones["dossard"] == nil ? "zones à dessiner" : "page fermée"))
            }
            return (Theme.texteTresDiscret, chrono.pret ? "pas encore testé" : "adresse à régler")
        }()
        return HStack(spacing: 5) {
            Circle().fill(v.0).frame(width: 8, height: 8)
            Text(v.1).font(.system(size: 12)).foregroundStyle(v.0)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tester() {
        enTest = true
        test = nil
        TestChrono.tester(etat.reglages.lien(chrono)) { ok, texte in
            Task { @MainActor in
                test = (ok, texte)
                enTest = false
            }
        }
    }
}
