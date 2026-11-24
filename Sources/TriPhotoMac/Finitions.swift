import AppKit
import SwiftUI
import TriPhotoMoteur

/// Racine de la fenêtre : thème (l'écran est redessiné quand il change), animation d'ouverture, protection.
struct RacineMac: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var prefs = Preferences.partagees
    @ObservedObject var protection = Protection.partagee
    @State private var ouverture = true

    var body: some View {
        ZStack {
            if protection.bloque {
                EcranBloque()
            } else {
                ContentView().id(prefs.theme)
            }
            if ouverture && prefs.ouverture && !protection.bloque {
                EcranOuverture { withAnimation(.easeOut(duration: 0.3)) { ouverture = false } }
                    .transition(.opacity)
            }
        }
        .background(Theme.fond)
        .sheet(isPresented: Binding(get: { protection.demanderInternet && !ouverture }, set: { _ in })) {
            DemandeInternet()
        }
        .onAppear {
            Theme.mettreIconeDuDock()
            if !prefs.ouverture { ouverture = false }
            protection.demarrer()
        }
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

/// Écran de blocage (Mac déclaré volé).
struct EcranBloque: View {
    var body: some View {
        ZStack {
            RadialGradient(colors: [Theme.panneau, Theme.fond], center: .center, startRadius: 0, endRadius: 700)
            VStack(spacing: 14) {
                if let i = Theme.image { Image(nsImage: i).resizable().frame(width: 96, height: 96) }
                (Text("GROOM ").foregroundColor(Theme.texte) + Text("PIX").foregroundColor(Theme.accent)
                 + Text(" EST BLOQUÉ").foregroundColor(Theme.texte)).font(Theme.titre(40))
                Text("Ce Mac a été déclaré volé par son propriétaire.\nLes mots de passe enregistrés par l'app ont été effacés de ce Mac.")
                    .multilineTextAlignment(.center).font(.system(size: 14)).foregroundStyle(Theme.texteDiscret)
                Text("Contact : HM Photographie").font(.system(size: 12)).foregroundStyle(Theme.texteTresDiscret)
            }
        }
        .ignoresSafeArea()
    }
}

/// Plus de 30 jours sans nouvelles du site.
struct DemandeInternet: View {
    @ObservedObject var protection = Protection.partagee
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connecte ce Mac à internet").font(.system(size: 17, weight: .semibold))
            Text("Groom Pix n'a pas pu joindre live.hmphotographie.fr depuis plus de \(Int(Protection.joursHorsLigne)) jours. Une connexion suffit pour vérifier que ce Mac est toujours autorisé.")
                .font(.system(size: 13)).foregroundStyle(Theme.texteDiscret)
            HStack {
                Button("Réessayer") { protection.verifier() }.buttonStyle(BoutonStyle(principal: true))
                if protection.sursis > 0 {
                    Button("Continuer quand même (encore \(protection.sursis) fois)") { protection.continuerSansInternet() }
                        .buttonStyle(BoutonStyle())
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Theme.panneau)
        .interactiveDismissDisabled(protection.sursis == 0)
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

struct CarteProtection: View {
    @ObservedObject var p = Protection.partagee
    @State private var phrase = ""
    @State private var phrase2 = ""
    @State private var action: ActionAdmin?
    @State private var nouveauNom = ""

    enum ActionAdmin: Identifiable {
        case activer, bloquer(Protection.MacProtege, Bool), renommer(Protection.MacProtege), retirer(Protection.MacProtege)
        var id: String {
            switch self {
            case .activer: return "activer"
            case .bloquer(let m, let b): return "b\(m.id)\(b)"
            case .renommer(let m): return "r\(m.id)"
            case .retirer(let m): return "x\(m.id)"
            }
        }
    }

    var body: some View {
        Carte(titre: SectionReglages.protection.rawValue,
              sousTitre: "Chaque Mac est activé une fois. Un Mac volé se bloque depuis un autre Mac. Sans internet, rien ne s'arrête. Active aussi « Localiser » d'Apple sur chaque Mac : c'est le vrai antivol, il bloque tout le Mac.") {
            Ligne("Ce Mac") {
                Text("\(Protection.nomCeMac) · \(p.actif ? (p.ceMac?.bloque == true ? "bloqué" : "protégé") : "pas encore activé")")
                    .font(.system(size: 13)).foregroundStyle(p.actif ? Theme.ok : Theme.attention)
            }
            if let d = p.derniereVerif {
                Ligne("Dernière vérification") {
                    Text(d.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 13))
                }
            }
            Ligne("Adresse du fichier") { TextField("", text: $p.reglage.adresse).textFieldStyle(.roundedBorder) }
            Ligne("Connexion au site") {
                Picker("", selection: $p.reglage.protocole) {
                    ForEach(ConfigGalerieEnLigne.Protocole.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().frame(width: 200)
            }
            Ligne("Serveur") { TextField("ftp.hmphotographie.fr", text: $p.reglage.hote).textFieldStyle(.roundedBorder) }
            Ligne("Identifiant") { TextField("", text: $p.reglage.identifiant).textFieldStyle(.roundedBorder) }
            Ligne("Mot de passe (trousseau)") {
                SecureField("", text: Binding(get: { p.motDePasseSite }, set: { p.motDePasseSite = $0 })).textFieldStyle(.roundedBorder)
            }
            Ligne("Dossier du fichier sur le site") { TextField("/groompix", text: $p.reglage.dossier).textFieldStyle(.roundedBorder) }
            HStack {
                Button("Tester la connexion") { p.testerConnexion() }.buttonStyle(BoutonStyle()).disabled(p.occupe)
                Button(p.actif ? "Réactiver ce Mac" : "Activer la protection sur ce Mac") { action = .activer }
                    .buttonStyle(BoutonStyle(principal: true)).disabled(p.occupe || p.reglage.hote.isEmpty)
                Button("Relire le site") { p.verifier() }.buttonStyle(BoutonStyle()).disabled(!p.actif || p.occupe)
            }
            if !p.macs.isEmpty {
                Divider().overlay(Theme.bordure)
                Text("Tous tes Mac").font(.system(size: 13, weight: .semibold))
                ForEach(p.macs) { m in
                    HStack {
                        Text(m.nom + (m.id == Protection.idCeMac ? " (ce Mac)" : "")).font(.system(size: 12.5))
                        Spacer()
                        Text("activé le \(m.activeLe.formatted(date: .abbreviated, time: .omitted))").font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
                        Pastille(texte: m.bloque ? "Bloqué" : "Autorisé", genre: m.bloque ? .attention : .ok)
                        Button("Renommer") { nouveauNom = m.nom; action = .renommer(m) }.buttonStyle(BoutonStyle())
                        Button(m.bloque ? "Débloquer" : "Bloquer") { action = .bloquer(m, !m.bloque) }.buttonStyle(BoutonStyle())
                        Button("Retirer") { action = .retirer(m) }.buttonStyle(BoutonStyle())
                    }
                }
            }
            if !p.message.isEmpty { Text(p.message).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret) }
            Text("La phrase d'administration protège la clé qui signe le fichier : c'est toi qui la choisis et la tapes, elle n'est gardée nulle part. Perdue, il faut effacer le fichier du site et réactiver chaque Mac.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
        }
        .sheet(item: $action) { a in feuille(a) }
    }

    @ViewBuilder
    private func feuille(_ a: ActionAdmin) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch a {
            case .activer:
                Text("Activer la protection sur « \(Protection.nomCeMac) »").font(.system(size: 15, weight: .semibold))
                Text("Premier Mac : choisis une phrase d'administration (8 caractères au moins) et tape-la deux fois. Mac suivants : la même phrase.")
                    .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
            case .bloquer(let m, let b):
                Text(b ? "Bloquer « \(m.nom) » ?" : "Débloquer « \(m.nom) » ?").font(.system(size: 15, weight: .semibold))
                if b {
                    Text("Au prochain lancement (ou dans l'heure s'il a internet), l'app s'y bloque et efface ses mots de passe. Débloquer reste possible.")
                        .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                }
            case .renommer(let m):
                Text("Renommer « \(m.nom) »").font(.system(size: 15, weight: .semibold))
                TextField("Nouveau nom", text: $nouveauNom).textFieldStyle(.roundedBorder)
            case .retirer(let m):
                Text("Retirer « \(m.nom) » de la liste ?").font(.system(size: 15, weight: .semibold))
            }
            SecureField("Phrase d'administration", text: $phrase).textFieldStyle(.roundedBorder)
            if case .activer = a, p.macs.isEmpty {
                SecureField("La même phrase, encore une fois", text: $phrase2).textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Annuler") { fermer() }.buttonStyle(BoutonStyle())
                Button("Valider") {
                    switch a {
                    case .activer:
                        if p.macs.isEmpty && phrase2 != phrase { p.message = "Les deux phrases ne sont pas pareilles."; return }
                        p.activer(phrase: phrase)
                    case .bloquer(let m, let b): p.bloquer(m, oui: b, phrase: phrase)
                    case .renommer(let m): p.renommer(m, en: nouveauNom, phrase: phrase)
                    case .retirer(let m): p.retirer(m, phrase: phrase)
                    }
                    fermer()
                }
                .buttonStyle(BoutonStyle(principal: true)).disabled(phrase.count < 8)
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(Theme.panneau)
    }

    private func fermer() { phrase = ""; phrase2 = ""; action = nil }
}
