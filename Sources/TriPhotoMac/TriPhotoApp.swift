import AppKit
import SwiftUI
import UserNotifications

@main
struct TriPhotoApp: App {
    @NSApplicationDelegateAdaptor(Delegue.self) private var delegue
    @StateObject private var etat = Etat()

    var body: some Scene {
        WindowGroup("Groom Pix", id: "principale") {
            RacineMac()
                .environmentObject(etat)
        }
        .defaultSize(width: 1280, height: 820)
        .commands { MenusTriPhoto(etat: etat, raccourcis: etat.raccourcis) }
    }
}

/// Lancement depuis le Terminal (pendant le développement) : l'app passe quand même au premier plan avec son menu.
final class Delegue: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Pas d'onglets de fenêtre (menu Présentation « Afficher la barre d'onglets ») : ils ne servent à rien ici.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if Bundle.main.bundleIdentifier != nil { UNUserNotificationCenter.current().delegate = self }
        // demande l'autorisation dès l'ouverture et déclare le bouton « Répondre » des bulles (sinon il n'apparaît jamais)
        MainActor.assumeIsolated { Notifieur.partage.demanderAutorisation() }
    }

    /// Clic sur une notification (message ou incident d'un iPhone) : Groom Pix s'ouvre sur l'onglet Messages.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler fin: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        // Réponse tapée dans la bulle : envoyée à l'auteur (ou à tout le monde si son message était pour tous)
        if let r = response as? UNTextInputNotificationResponse {
            if info["essai"] != nil { fin(); return }        // notification d'essai : la réponse ne part nulle part
            let texte = r.userText
            let qui = info["qui"] as? String ?? ""
            let pour = (info["pour"] as? String ?? "").isEmpty ? "" : qui
            DispatchQueue.main.async { Etat.courant?.serveur.envoyerDuStand(texte, pour: pour) }
            fin()
            return
        }
        let ecran = (info["ecran"] as? String).flatMap(Ecran.init(rawValue:)) ?? .messages
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            Etat.courant?.ecran = ecran
        }
        fin()
    }

    /// Notification pendant que Groom Pix est devant : montrée quand même, sauf sur l'onglet Messages.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler fin: @escaping (UNNotificationPresentationOptions) -> Void) {
        let surMessages = MainActor.assumeIsolated { Etat.courant?.ecran == .messages }
        fin(surMessages ? [] : [.banner, .sound])
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Menus de la barre du Mac. Chaque commande prend le raccourci choisi par HUGO (écran « Raccourcis clavier »).
struct MenusTriPhoto: Commands {
    @ObservedObject var etat: Etat
    @ObservedObject var raccourcis: Raccourcis

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Charger le fichier FFE…") { etat.choisirFichierFFE() }
                .raccourci(raccourcis[.chargerFFE])
            Button("Recharger le fichier FFE") { etat.rechargerFFE() }
                .disabled(etat.reglages.cheminFFE.isEmpty)
            Divider()
            Button("Synchroniser les boîtiers (photo du QR)…") { etat.montrerSynchro = true }
            Button("Engagés terrain…") { etat.montrerTerrain = true }
            Divider()
            Button("Clôturer la journée…") { etat.cloture = .journee }
            Button("Clôturer le concours…") { etat.cloture = .finale }
            Divider()
            Button("Mode entraînement…") { etat.montrerEntrainement = true }
                .raccourci(raccourcis[.entrainement])
        }
        CommandGroup(replacing: .appSettings) {
            Button("Réglages…") { etat.ecran = .reglages }
                .raccourci(raccourcis[.reglages])
        }
        CommandMenu("Aller") {
            Button("Accueil") { etat.ecran = .accueil }.raccourci(raccourcis[.accueil])
            Button("À valider") { etat.ecran = .aValider }.raccourci(raccourcis[.aValider])
            Button("Revue") { etat.ecran = .revue }.raccourci(raccourcis[.revue])
            Button("Messages") { etat.ecran = .messages }
            Button("Mémoire") { etat.ecran = .memoire }.raccourci(raccourcis[.memoire])
            Button("Commandes") { etat.ecran = .commandes }
            Button("Réglages") { etat.ecran = .reglages }
        }
        CommandGroup(after: .sidebar) {
            Button(etat.panneauGauche ? "Masquer le panneau de gauche" : "Afficher le panneau de gauche") {
                etat.panneauGauche.toggle()
            }
            .raccourci(raccourcis[.panneauGauche])
            Button(etat.panneauDroit ? "Masquer le panneau de droite" : "Afficher le panneau de droite") {
                etat.panneauDroit.toggle()
            }
            .raccourci(raccourcis[.panneauDroit])
            Button("Afficher / masquer tous les panneaux") { etat.basculerTousLesPanneaux() }
                .raccourci(raccourcis[.tousLesPanneaux])
            Divider()
        }
    }
}
