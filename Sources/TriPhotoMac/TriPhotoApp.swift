import AppKit
import SwiftUI

@main
struct TriPhotoApp: App {
    @NSApplicationDelegateAdaptor(Delegue.self) private var delegue
    @StateObject private var etat = Etat()

    var body: some Scene {
        WindowGroup("Tri-photo", id: "principale") {
            ContentView()
                .environmentObject(etat)
        }
        .defaultSize(width: 1280, height: 820)
        .commands { MenusTriPhoto(etat: etat, raccourcis: etat.raccourcis) }
    }
}

/// Lancement depuis le Terminal (pendant le développement) : l'app passe quand même au premier plan avec son menu.
final class Delegue: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
            Button("Mémoire") { etat.ecran = .memoire }.raccourci(raccourcis[.memoire])
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
