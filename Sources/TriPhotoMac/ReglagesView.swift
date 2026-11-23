import AppKit
import SwiftUI
import TriPhotoCommun
import UniformTypeIdentifiers

enum SectionReglages: String, CaseIterable, Identifiable {
    case concours = "1. Concours"
    case dossiers = "2. Dossiers"
    case copies = "3. Copies (.cube)"
    case lightroom = "4. Lightroom, tampon"
    case envois = "5. Envois"
    case cloture = "6. Clôture"
    case raccourcis = "Raccourcis clavier"
    case modeles = "Modèles de concours"
    var id: String { rawValue }

    static let debut: [SectionReglages] = [.concours, .dossiers, .copies, .lightroom, .envois, .cloture]
    static let preferences: [SectionReglages] = [.raccourcis, .modeles]
}

/// Écran Réglages (maquette 4a) : sections à gauche, réglages au centre, « Prêt à démarrer ? » à droite.
struct ReglagesView: View {
    @EnvironmentObject var etat: Etat
    @State private var section: SectionReglages = .concours
    @State private var montrerEpreuves = false

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
                    .foregroundStyle(section == s ? Color.white : Color(hex: 0xD0D0D0))
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
            Text("Le lien avec HM Timing et la Capture Horse & Comp arrivent à l'étape 2.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            Divider().overlay(Theme.bordure)
            Text("Pistes et photographes").font(.system(size: 13, weight: .semibold))
            ForEach($etat.reglages.pistes) { $piste in
                HStack {
                    TextField("Piste", text: $piste.nom).textFieldStyle(.roundedBorder).frame(width: 200)
                    TextField("Photographe", text: $piste.photographe).textFieldStyle(.roundedBorder)
                    Button("Retirer") { etat.reglages.pistes.removeAll { $0.id == piste.id } }
                        .buttonStyle(BoutonStyle())
                        .disabled(etat.reglages.pistes.count <= 1)
                }
            }
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
            Ligne("Galerie en ligne (FTP)") {
                TextField("Adresse FTP de ta galerie (étape 4)", text: $etat.reglages.adresseFTPGalerie)
                    .textFieldStyle(.roundedBorder)
            }
            Toggle("Sauvegarde des originaux sur un 2e disque (option)", isOn: $etat.reglages.sauvegardeActive)
            if etat.reglages.sauvegardeActive {
                ChoixChemin(titre: "Disque de sauvegarde", aide: nil, chemin: $etat.reglages.dossierSauvegarde)
            }
        }
    }

    private var carteCloture: some View {
        Carte(titre: SectionReglages.cloture.rawValue,
              sousTitre: "Chaque soir : « Clôturer la journée ». Le dernier jour : « Clôturer le concours ». L'app vérifie que tous les envois vers la galerie sont finis, puis produit le fichier d'attribution des cavaliers.") {
            ChoixChemin(titre: "Fichier d'attribution dans", aide: nil, chemin: $etat.reglages.dossierClotures)
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
            Button("Démarrer la journée") {}
                .buttonStyle(BoutonStyle(principal: true))
                .disabled(true)
                .padding(.top, 8)
            Text("Le démarrage du tri arrive à l'étape 1. Il restera possible avec un point orange : il sera rappelé sur l'accueil.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            Divider().overlay(Theme.bordure).padding(.vertical, 4)
            Text("Mode entraînement").font(.system(size: 13, weight: .semibold))
            Text("Rejouer les photos d'un ancien concours dans le dossier de réception, pour tester sans risque.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
            Button("Ouvrir le mode entraînement…") { etat.montrerEntrainement = true }
                .buttonStyle(BoutonStyle())
            Spacer()
        }
        .padding(16)
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
        .preferredColorScheme(.dark)
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
