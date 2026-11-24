import AppKit
import SwiftUI
import TriPhotoMoteur

/// Racine de la fenêtre : thème (l'écran est redessiné quand il change), animation d'ouverture, licence.
struct RacineMac: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var prefs = Preferences.partagees
    @ObservedObject var licence = Licence.partagee
    @State private var ouverture = true

    var body: some View {
        ZStack {
            if licence.ecranBloque, licence.verdict == .aConnecter {
                EcranLicence()
            } else if licence.ecranBloque, case .bloque(let raison, let efface) = licence.verdict {
                EcranBloque(raison: raison, efface: efface)
            } else {
                VStack(spacing: 0) {
                    if case .avertissement(let jours) = licence.verdict { BandeauLicence(jours: jours) }
                    ContentView().id(prefs.theme)
                }
            }
            if ouverture && prefs.ouverture {
                EcranOuverture { withAnimation(.easeOut(duration: 0.3)) { ouverture = false } }
                    .transition(.opacity)
            }
        }
        .background(Theme.fond)
        .onAppear {
            Theme.mettreIconeDuDock()
            if !prefs.ouverture { ouverture = false }
            let moteur = etat.moteur
            licence.triActif = { moteur.actif }
            licence.demarrer()
        }
        .onReceive(etat.moteur.$actif) { _ in DispatchQueue.main.async { licence.triChange() } }
        .onChange(of: prefs.theme) { _ in
            Theme.mettreIconeDuDock()
            etat.serveur.themeChange()
        }
    }
}

extension Theme {
    /// L'icône du Dock suit le thème (S2 pour Bleu et or, S3 pour Graphite).
    static func mettreIconeDuDock() {
        let nom = "Icone-\(ChoixTheme.courant.code)"
        if let u = Bundle.main.url(forResource: nom, withExtension: "png"), let i = NSImage(contentsOf: u) {
            NSApp.applicationIconImage = i
        }
    }

    static var image: NSImage? {
        Bundle.main.url(forResource: "Icone-\(ChoixTheme.courant.code)", withExtension: "png").flatMap(NSImage.init(contentsOf:))
            ?? NSApp.applicationIconImage
    }

    static func titre(_ taille: CGFloat) -> Font { .system(size: taille, weight: .heavy).italic().width(.condensed) }
}

/// Nom de l'app : « GROOM » dans la couleur du texte, « PIX » dans l'accent.
struct NomApp: View {
    var taille: CGFloat = 46
    var body: some View {
        (Text("GROOM ").foregroundColor(Theme.texte) + Text("PIX").foregroundColor(Theme.accent))
            .font(Theme.titre(taille))
    }
}

/// Ouverture : 2,5 s, un clic ou une touche la passe. Son seulement si choisi dans les réglages.
struct EcranOuverture: View {
    var fini: () -> Void
    @State private var logo = false
    @State private var nom = false
    @State private var barre = 0.0

    var body: some View {
        ZStack {
            RadialGradient(colors: [Theme.panneau, Theme.fond], center: .center, startRadius: 0, endRadius: 700)
            VStack(spacing: 14) {
                if let i = Theme.image {
                    Image(nsImage: i).resizable().frame(width: 128, height: 128)
                        .scaleEffect(logo ? 1 : 0.82).opacity(logo ? 1 : 0)
                }
                NomApp(taille: 50).offset(y: nom ? 0 : 12).opacity(nom ? 1 : 0)
                Text("L'ASSISTANT DU STAND PHOTO").font(.system(size: 12, weight: .medium)).tracking(3)
                    .foregroundStyle(Theme.texteDiscret).opacity(nom ? 1 : 0)
                Capsule().fill(Theme.bordure).frame(width: 220, height: 3)
                    .overlay(alignment: .leading) { Capsule().fill(Theme.accent).frame(width: 220 * barre, height: 3) }
                    .padding(.top, 6)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { fini() }
        .onAppear {
            if Preferences.partagees.sonOuverture { Notifieur.partage.jouer("Glass") }
            // 2,5 s (HUGO, 24/11) : le temps de lire le logo et de voir la barre se remplir
            withAnimation(.easeOut(duration: 0.7)) { logo = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.5)) { nom = true }
            withAnimation(.easeInOut(duration: 1.5).delay(0.8)) { barre = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { fini() }
        }
        .background(ToucheQuelconque(action: fini))
    }
}

/// Une touche du clavier passe l'ouverture.
private struct ToucheQuelconque: NSViewRepresentable {
    var action: () -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.moniteur = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            action()
            return e
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let m = coordinator.moniteur { NSEvent.removeMonitor(m) }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var moniteur: Any? }
}

/// Écran de blocage : licence suspendue, Mac bloqué, essai ou abonnement fini, ou 6 jours sans internet.
struct EcranBloque: View {
    var raison: String
    var efface: Bool
    @ObservedObject var licence = Licence.partagee

    var body: some View {
        ZStack {
            RadialGradient(colors: [Theme.panneau, Theme.fond], center: .center, startRadius: 0, endRadius: 700)
            VStack(spacing: 14) {
                if let i = Theme.image { Image(nsImage: i).resizable().frame(width: 96, height: 96) }
                (Text("GROOM ").foregroundColor(Theme.texte) + Text("PIX").foregroundColor(Theme.accent)
                 + Text(" EST BLOQUÉ").foregroundColor(Theme.texte)).font(Theme.titre(40))
                Text(raison).multilineTextAlignment(.center).font(.system(size: 14)).foregroundStyle(Theme.texteDiscret)
                    .frame(maxWidth: 520)
                if efface {
                    Text("Les mots de passe enregistrés par l'app ont été effacés de ce Mac.")
                        .font(.system(size: 12)).foregroundStyle(Theme.texteTresDiscret)
                }
                HStack {
                    Button("Vérifier à nouveau") { licence.signaler() }.buttonStyle(BoutonStyle(principal: true))
                    Button("Changer de compte") { licence.deconnecter() }.buttonStyle(BoutonStyle())
                }
                .padding(.top, 6)
                if !licence.message.isEmpty {
                    Text(licence.message).font(.system(size: 12)).foregroundStyle(Theme.attention)
                }
                Text("Contact : HM Photographie · live.hmphotographie.fr").font(.system(size: 12)).foregroundStyle(Theme.texteTresDiscret)
            }
            .padding(30)
        }
        .ignoresSafeArea()
    }
}

/// Première ouverture (ou session fermée) : se connecter au compte, ou le créer.
struct EcranLicence: View {
    @ObservedObject var licence = Licence.partagee
    @State private var creer = false
    @State private var mail = ""
    @State private var motDePasse = ""
    @State private var nom = ""

    var body: some View {
        ZStack {
            RadialGradient(colors: [Theme.panneau, Theme.fond], center: .center, startRadius: 0, endRadius: 700)
            VStack(spacing: 14) {
                if let i = Theme.image { Image(nsImage: i).resizable().frame(width: 88, height: 88) }
                NomApp(taille: 40)
                Text("L'ASSISTANT DU STAND PHOTO").font(.system(size: 11, weight: .medium)).tracking(3)
                    .foregroundStyle(Theme.texteDiscret)
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: $creer) {
                        Text("J'ai déjà un compte").tag(false)
                        Text("Créer un compte").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    if creer {
                        TextField("Nom du stand ou de la société", text: $nom).textFieldStyle(.roundedBorder)
                    }
                    TextField("Mail", text: $mail).textFieldStyle(.roundedBorder).textContentType(.username)
                    SecureField("Mot de passe (8 caractères au moins)", text: $motDePasse).textFieldStyle(.roundedBorder)
                        .onSubmit(valider)
                    Button(creer ? "Créer le compte (48 h d'essai)" : "Se connecter", action: valider)
                        .buttonStyle(BoutonStyle(principal: true))
                        .disabled(licence.occupe || mail.isEmpty || motDePasse.count < 8 || (creer && nom.isEmpty))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    if !licence.message.isEmpty {
                        Text(licence.message).font(.system(size: 12)).foregroundStyle(Theme.attention)
                    }
                    Text("Le même compte que sur live.hmphotographie.fr. Ce Mac se signale au site toutes les 5 minutes ; sans internet, Groom Pix continue 6 jours.")
                        .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
                }
                .padding(20)
                .frame(width: 400)
                .background(Theme.carte, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.bordure, lineWidth: 1))
            }
        }
        .ignoresSafeArea()
    }

    private func valider() {
        guard !licence.occupe, !mail.isEmpty, motDePasse.count >= 8 else { return }
        licence.connecter(mail: mail.trimmingCharacters(in: .whitespaces), motDePasse: motDePasse,
                          creerAvecNom: creer ? nom.trimmingCharacters(in: .whitespaces) : nil)
        motDePasse = ""
    }
}

/// Après 4 jours sans contact avec le site : bandeau en haut de la fenêtre.
struct BandeauLicence: View {
    var jours: Int
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
            Text("Pas de contact avec live.hmphotographie.fr depuis \(jours) jours. Connecte ce Mac à internet avant \(Int(Licence.joursMax)) jours, sinon Groom Pix se bloquera (jamais pendant un tri).")
            Spacer()
            Button("Réessayer") { Licence.partagee.signaler() }.buttonStyle(BoutonStyle())
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.attention)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(Theme.attentionFond)
    }
}

// MARK: - Réglages 9 et 10

struct CarteApparence: View {
    @ObservedObject var prefs = Preferences.partagees

    var body: some View {
        Carte(titre: SectionReglages.apparence.rawValue,
              sousTitre: "Thème choisi pour ce Mac et les iPhone du stand. Clair ou sombre suit l'apparence du Mac (Réglages Système › Apparence).") {
            Ligne("Thème") {
                Picker("", selection: $prefs.theme) {
                    ForEach(ChoixTheme.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 260)
            }
            Ligne("Mode") {
                Picker("", selection: $prefs.mode) {
                    Text("Silencieux").tag(ModeSon.silencieux)
                    Text("Normal").tag(ModeSon.normal)
                    Text("Rush (important seulement)").tag(ModeSon.rush)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 380)
            }
            Ligne("Volume des sons de l'app") { Slider(value: $prefs.volume, in: 0...1).frame(width: 240) }
            Toggle("Animation d'ouverture", isOn: $prefs.ouverture)
            Toggle("Son à l'ouverture", isOn: $prefs.sonOuverture).disabled(!prefs.ouverture)
            Divider().overlay(Theme.bordure)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    ForEach(["Événement", "Affichage", "Son", "En rush"], id: \.self) {
                        Text($0).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                    }
                }
                ForEach(Evenement.allCases) { e in
                    GridRow {
                        Text(e.rawValue).font(.system(size: 12.5))
                        Picker("", selection: lien(e, \.affichage)) {
                            ForEach(Affichage.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 280)
                        HStack(spacing: 4) {
                            Picker("", selection: lien(e, \.son)) {
                                Text("—").tag("")
                                ForEach(Preferences.sonsDuMac, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden().frame(width: 110)
                            Button { Notifieur.partage.jouer(prefs.reglage(e).son) } label: { Image(systemName: "play.fill") }
                                .buttonStyle(.plain).foregroundStyle(Theme.accent).disabled(prefs.reglage(e).son.isEmpty)
                        }
                        Toggle("", isOn: lien(e, \.enRush)).labelsHidden()
                    }
                }
            }
            Text("Discret : seulement la pastille dans l'app. Alerte : bannière, et l'icône du Dock rebondit jusqu'à ce que tu regardes. Trois notifications du même genre en moins d'une minute n'en font qu'une (« 10 × message »). Le mode « Ne pas déranger » du Mac reste respecté pour les bannières.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
        }
    }

    private func lien<T>(_ e: Evenement, _ k: WritableKeyPath<ReglageEvenement, T>) -> Binding<T> {
        Binding(get: { prefs.reglage(e)[keyPath: k] }, set: { var r = prefs.reglage(e); r[keyPath: k] = $0; prefs.evenements[e] = r })
    }
}

struct CarteLicence: View {
    @ObservedObject var l = Licence.partagee
    @State private var confirmer = false

    var body: some View {
        Carte(titre: SectionReglages.protection.rawValue,
              sousTitre: "Même compte et même page d'administration que tes autres logiciels : live.hmphotographie.fr/admin › Mes abonnés › Groom Pix. De là, tu vois chaque Mac (dernier signal, ville approximative) et tu peux bloquer un Mac volé ou suspendre un compte.") {
            Ligne("Ce Mac") {
                Text("\(Licence.nomCeMac) · \(Licence.poste.prefix(12))").font(.system(size: 13))
            }
            if let c = l.compte {
                Ligne("Compte") { Text(c.nom.isEmpty ? c.mail : "\(c.nom) · \(c.mail)").font(.system(size: 13)) }
                Ligne("Licence") {
                    Pastille(texte: texteStatut(c), genre: c.statut == "actif" ? .ok : .attention)
                }
            }
            if let d = l.dernierContact {
                Ligne("Dernier contact avec le site") {
                    Text(d.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 13))
                }
            }
            HStack {
                Button("Vérifier maintenant") { l.signaler() }.buttonStyle(BoutonStyle())
                Button("Ouvrir la page d'administration") { NSWorkspace.shared.open(Licence.pageAdmin) }.buttonStyle(BoutonStyle())
                Button("Déconnecter ce Mac") { confirmer = true }.buttonStyle(BoutonStyle())
            }
            if !l.message.isEmpty { Text(l.message).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret) }
            Text("Sans internet, Groom Pix continue 6 jours (avertissement dès le 4e). Un blocage ne coupe jamais un tri en cours : il attend la fin du tri. Active aussi « Localiser » d'Apple sur chaque Mac : c'est le vrai antivol, il bloque tout le Mac.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
        }
        .confirmationDialog("Déconnecter ce Mac du compte ?", isPresented: $confirmer) {
            Button("Déconnecter", role: .destructive) { l.deconnecter() }
        } message: {
            Text("Groom Pix redemandera le mail et le mot de passe.")
        }
    }

    private func texteStatut(_ c: Licence.Compte) -> String {
        func jour(_ t: Double) -> String { Date(timeIntervalSince1970: t).formatted(date: .abbreviated, time: .omitted) }
        switch c.statut {
        case "actif": return c.fin.map { "Active jusqu'au \(jour($0))" } ?? "Active, sans fin"
        case "suspendu": return "Suspendue"
        default: return c.essai_fin.map { "Essai jusqu'au \(Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .shortened))" } ?? "Essai"
        }
    }
}
