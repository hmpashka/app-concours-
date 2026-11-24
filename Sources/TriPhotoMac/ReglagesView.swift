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
    case raccourcis = "Raccourcis clavier"
    case modeles = "Modèles de concours"
    var id: String { rawValue }

    static let debut: [SectionReglages] = [.concours, .dossiers, .copies, .lightroom, .envois, .cloture, .memoire, .commandes, .apparence, .protection]
    static let preferences: [SectionReglages] = [.raccourcis, .modeles]
}

/// Écran Réglages (maquette 4a) : sections à gauche, réglages au centre, « Prêt à démarrer ? » à droite.
struct ReglagesView: View {
    @EnvironmentObject var etat: Etat
    @State private var section: SectionReglages = .concours
    @State private var montrerEpreuves = false
    @State private var testGalerie = ""
    @State private var testGalerieOK: Bool?
    @State private var testEnCours = false
    @State private var testUniFi = ""
    @State private var testUniFiOK: Bool?

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
        .sheet(isPresented: $etat.montrerCapture) { CaptureView(capture: etat.capture).environmentObject(etat) }
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
        .buttonStyle(.plain)
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
                    }
                    .padding(24)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: section) { s in withAnimation { lecteur.scrollTo(s, anchor: .top) } }
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
            Ligne("Chronométrage") {
                Picker("", selection: $etat.reglages.chronometrage) {
                    ForEach(ReglagesConcours.Chronometrage.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 320)
            }
            if etat.reglages.chronometrage == .hmTiming {
                Ligne("Adresse de HM Timing") {
                    TextField("192.168.1.20:8080", text: $etat.reglages.adresseHM).textFieldStyle(.roundedBorder).frame(width: 260)
                }
                Ligne("Code de régie") {
                    SecureField("", text: $etat.reglages.codeRegieHM).textFieldStyle(.roundedBorder).frame(width: 160)
                }
                Ligne("Code technicien") {
                    SecureField("", text: $etat.reglages.codeTechHM).textFieldStyle(.roundedBorder).frame(width: 160)
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
                ChoixChemin(titre: "Passages pour le mode entraînement (facultatif)",
                            aide: "Fichier JSON des passages d'un ancien concours : remplace HM Timing pour s'entraîner.",
                            chemin: $etat.reglages.fichierPassagesEntrainement, fichier: true, types: [.json])
                Text("Aucune correction n'est appliquée seule : chaque proposition du chrono va dans « À valider ».")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(etat.reglages.urlIncrustation.isEmpty ? "Page d'incrustation à régler" : etat.reglages.urlIncrustation)
                            .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                        Text("Groom Pix lit qui est en piste sur la page de Horses & Competitions, comme HM Timing.")
                            .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
                    }
                    Spacer()
                    Button("Régler la capture…") { etat.montrerCapture = true }.buttonStyle(BoutonStyle(principal: true))
                }
                Ligne("Fin de tour tolérée") {
                    Stepper("\(etat.reglages.finDeTourSecondes) s après l'arrivée", value: $etat.reglages.finDeTourSecondes, in: 0...60, step: 5)
                }
                Ligne("Latence au changement") {
                    Stepper("\(etat.reglages.latenceSecondes) s", value: $etat.reglages.latenceSecondes, in: 0...30)
                }
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
            Divider().overlay(Theme.bordure)
            Text("Pistes et photographes").font(.system(size: 13, weight: .semibold))
            ForEach($etat.reglages.pistes) { $piste in
                HStack {
                    TextField("Piste", text: $piste.nom).textFieldStyle(.roundedBorder).frame(width: 200)
                    TextField("Photographe", text: $piste.photographe).textFieldStyle(.roundedBorder)
                    Picker("", selection: $piste.sourceChrono) {
                        Text("Chrono : trouvé tout seul").tag("")
                        ForEach(etat.sourcesChrono(plus: piste.sourceChrono), id: \.self) { Text("Chrono : \($0)").tag($0) }
                    }
                    .labelsHidden().frame(width: 200)
                    Button("Retirer") { etat.reglages.pistes.removeAll { $0.id == piste.id } }
                        .buttonStyle(BoutonStyle())
                        .disabled(etat.reglages.pistes.count <= 1)
                }
            }
            Text("Les iPhone de l'app Piste voient ces pistes. « Chrono » relie chaque piste à celle du chrono (utile s'il y en a plusieurs).")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            Button("Ajouter une piste") {
                etat.reglages.pistes.append(.init(nom: "Piste \(etat.reglages.pistes.count + 1)", photographe: ""))
            }
            .buttonStyle(BoutonStyle())
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
                    Stepper("toutes les \(etat.reglages.minutesGalerieStand) min au plus, et à la fin de chaque rafale",
                            value: $etat.reglages.minutesGalerieStand, in: 1...30)
                }
                HStack {
                    Button("Rafraîchir maintenant") { etat.moteur.rafraichirGalerie() }
                        .buttonStyle(BoutonStyle()).disabled(!etat.moteur.actif)
                    if !etat.reglages.empreinteGalerieStand.isEmpty {
                        Button("Oublier le certificat du serveur") { etat.reglages.empreinteGalerieStand = "" }
                            .buttonStyle(BoutonStyle())
                            .help("À faire seulement si le serveur du stand a changé de certificat.")
                    }
                    if let g = etat.moteur.resume.galerie, !g.message.isEmpty {
                        Text(g.message).font(.system(size: 11)).foregroundStyle(g.ok == false ? Theme.erreur : Theme.texteDiscret)
                    }
                }
                Text("Les copies partent au fil de l'eau ; la galerie ne relit que les dossiers qui ont reçu des photos, toutes les X minutes au plus. Pas de requête à chaque photo.")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            }
            Divider().overlay(Theme.bordure)
            galerieEnLigne
            Divider().overlay(Theme.bordure)
            accesDistance
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

    /// Galerie en ligne : réglée comme un site dans FileZilla.
    @ViewBuilder
    private var galerieEnLigne: some View {
        Text("Galerie en ligne").font(.system(size: 13, weight: .semibold))
        Ligne("Protocole") {
            Picker("", selection: $etat.reglages.protocoleGalerie) {
                ForEach(ConfigGalerieEnLigne.Protocole.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden().frame(width: 220)
            Text("comme dans FileZilla (Gestionnaire de sites › Protocole / Chiffrement)")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
        }
        Ligne("Hôte · port") {
            TextField("ftp.mon-site.fr (vide : pas d'envoi)", text: $etat.reglages.adresseFTPGalerie)
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
            Ligne("Débit maximum") {
                Stepper(etat.reglages.limiteKoGalerie == 0 ? "sans limite" : "\(etat.reglages.limiteKoGalerie) Ko/s",
                        value: $etat.reglages.limiteKoGalerie, in: 0...20_000, step: 250)
            }
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
            regulateurReseau
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

    /// Régulateur réseau : la console UniFi (UDM Pro) dit si la ligne internet est chargée.
    @ViewBuilder
    private var regulateurReseau: some View {
        Text("Régulateur réseau (UniFi)").font(.system(size: 13, weight: .semibold)).padding(.top, 6)
        Ligne("Console UniFi") {
            TextField("192.168.1.1 (vide : pas de régulateur)", text: $etat.reglages.adresseUniFi).textFieldStyle(.roundedBorder)
        }
        if !etat.reglages.adresseUniFi.isEmpty {
            Ligne("Clé API") {
                SecureField("UniFi Network › Paramètres › Plan de contrôle › Intégrations (gardée dans le trousseau)",
                            text: Binding(get: { etat.cleUniFi }, set: { etat.cleUniFi = $0 }))
                    .textFieldStyle(.roundedBorder)
            }
            Ligne("Débit montant de la ligne") {
                Stepper("\(etat.reglages.montantMbitLigne) Mbit/s", value: $etat.reglages.montantMbitLigne, in: 1...1000)
            }
            Ligne("Pause de la galerie") {
                Stepper("quand les autres utilisent plus de \(etat.reglages.seuilUniFi) % de la ligne",
                        value: $etat.reglages.seuilUniFi, in: 30...95, step: 5)
            }
            HStack {
                Button("Tester la console") {
                    guard let c = etat.configUniFi() else { return }
                    testUniFi = "Essai en cours…"
                    testUniFiOK = nil
                    GalerieEnLigne.testerUniFi(c) { ok, m in Task { @MainActor in testUniFiOK = ok; testUniFi = m } }
                }
                .buttonStyle(BoutonStyle()).disabled(etat.cleUniFi.isEmpty)
                if !etat.reglages.empreinteUniFi.isEmpty {
                    Button("Oublier le certificat de la console") { etat.reglages.empreinteUniFi = "" }.buttonStyle(BoutonStyle())
                }
                if !testUniFi.isEmpty {
                    Text(testUniFi).font(.system(size: 11)).foregroundStyle(testUniFiOK == false ? Theme.erreur : Theme.ok)
                }
            }
            Text("Les photos des boîtiers et le serveur local passent toujours avant : seule la galerie en ligne attend, et reprend toute seule quand la ligne se libère.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
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
