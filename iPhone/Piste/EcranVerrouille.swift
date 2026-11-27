// Bouton « Afficher sur l'écran verrouillé » : le direct de ma piste sur l'écran verrouillé et dans la Dynamic Island.
// L'app le met à jour tant qu'elle est ouverte ; ensuite c'est le Mac, par le service d'Apple, avec le jeton donné ici.
import ActivityKit
import SwiftUI
import TriPhotoCommun
import UIKit
import UserNotifications

@MainActor
final class SuiviEcran: ObservableObject {
    static let partage = SuiviEcran()
    @Published private(set) var actif = false
    @Published var message = ""
    private var suivis = Set<String>()

    private init() {
        for a in Activity<GroomAttributs>.activities { suivre(a) }
        actif = Activity<GroomAttributs>.activities.contains { $0.activityState == .active }
        Task { [weak self] in
            for await a in Activity<GroomAttributs>.activityUpdates {
                await MainActor.run { self?.suivre(a); self?.actif = true }
            }
        }
    }

    func demarrer(nom: String, piste: String, direct: DirectPiste?) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = "Active « Activités en direct » dans Réglages › Groom Pix."
            return
        }
        await arreter()
        let etat = direct.map(EcranVerrouille.init) ?? EcranVerrouille(piste: piste)
        do {
            let a = try Activity.request(attributes: GroomAttributs(nom: nom, piste: piste),
                                         content: ActivityContent(state: etat, staleDate: Date().addingTimeInterval(4 * 3600)),
                                         pushType: .token)
            suivre(a)
            actif = true
            message = "C'est parti : verrouille l'iPhone pour le voir."
        } catch {
            message = "Impossible d'afficher sur l'écran verrouillé : \(error.localizedDescription)"
        }
    }

    func arreter() async {
        for a in Activity<GroomAttributs>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        actif = false
        Liaison.courante?.envoyerJeton("fin", "")
    }

    /// App ouverte : mise à jour tout de suite, sans attendre le Mac.
    func mettreAJour(_ d: DirectPiste) {
        let etat = EcranVerrouille(d)
        for a in Activity<GroomAttributs>.activities
        where a.activityState == .active && a.attributes.piste == d.piste && a.content.state != etat {
            Task { await a.update(ActivityContent(state: etat, staleDate: Date().addingTimeInterval(4 * 3600))) }
        }
    }

    /// Piste changée : l'écran verrouillé suit la nouvelle piste.
    func pisteChangee(nom: String, piste: String) {
        guard actif, !piste.isEmpty,
              Activity<GroomAttributs>.activities.contains(where: { $0.attributes.piste != piste }) else { return }
        Task { await demarrer(nom: nom, piste: piste, direct: nil) }
    }

    private func suivre(_ a: Activity<GroomAttributs>) {
        guard !suivis.contains(a.id) else { return }
        suivis.insert(a.id)
        Task {
            for await jeton in a.pushTokenUpdates {
                let hex = jeton.map { String(format: "%02x", $0) }.joined()
                await MainActor.run { Liaison.courante?.envoyerJeton("activite", hex) }
            }
        }
        Task { [weak self] in
            for await e in a.activityStateUpdates where e == .ended || e == .dismissed {
                await MainActor.run {
                    self?.actif = Activity<GroomAttributs>.activities.contains { $0.activityState == .active }
                    if self?.actif == false { Liaison.courante?.envoyerJeton("fin", "") }
                }
            }
        }
    }
}

/// Délégué de l'app : jeton des notifications (bulles par le service d'Apple).
final class DelegueApp: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
            if ok { DispatchQueue.main.async { application.registerForRemoteNotifications() } }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in Liaison.courante?.envoyerJeton("notifications", hex) }
    }
}

/// Le bouton doré, comme dans l'app Piste de HM Timing.
struct BoutonEcranVerrouille: View {
    @EnvironmentObject var liaison: Liaison
    @ObservedObject var suivi = SuiviEcran.partage

    var body: some View {
        VStack(spacing: 6) {
            Button {
                Task {
                    if suivi.actif { await suivi.arreter() }
                    else { await suivi.demarrer(nom: liaison.nom, piste: liaison.piste, direct: liaison.direct) }
                }
            } label: {
                Label(suivi.actif ? "Retirer de l'écran verrouillé" : "Afficher sur l'écran verrouillé",
                      systemImage: suivi.actif ? "lock.slash" : "lock.iphone")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(suivi.actif ? Style.voile.opacity(0.12) : Style.or, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(suivi.actif ? Style.creme : Style.nuit)
            }
            .buttonStyle(.plain)
            if !suivi.message.isEmpty {
                Text(suivi.message).font(.system(size: 12)).foregroundStyle(Style.cremeDiscret).multilineTextAlignment(.center)
            }
        }
    }
}
