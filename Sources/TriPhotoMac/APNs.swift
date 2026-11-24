import AppKit
import CryptoKit
import Foundation
import TriPhotoCommun

/// Notifications et écran verrouillé des iPhone, même quand l'app Piste est fermée ou l'iPhone verrouillé.
/// Le Mac parle DIRECTEMENT au service d'Apple (APNs), sans relais : jeton signé avec la clé .p8 de HUGO,
/// gardée dans le trousseau du Mac. Il faut internet sur le Mac (quelques octets par envoi).
@MainActor
final class APNs: ObservableObject {
    static let partage = APNs()

    /// Un iPhone connu : ses jetons, gardés même quand il n'est plus connecté.
    struct Iphone: Codable, Identifiable, Equatable {
        var id: String { appareil + "|" + nom }
        var nom: String
        var appareil: String
        var piste: String
        var notifications: String = ""
        var activite: String = ""
        var demarrage: String = ""
        var production = false
        var vu = Date()
    }

    @Published private(set) var iphones: [Iphone] = []
    @Published private(set) var dernierEtat = ""
    @Published var keyID: String { didSet { UserDefaults.standard.set(keyID.trimmingCharacters(in: .whitespaces), forKey: "apnsKeyID") } }
    @Published var teamID: String { didSet { UserDefaults.standard.set(teamID.trimmingCharacters(in: .whitespaces), forKey: "apnsTeamID") } }
    @Published private(set) var cleEnregistree: Bool

    static let bundle = "fr.hmtimings.piste"
    private static let fichier = "iphones-apns.json"
    private var jwt = ""
    private var jwtDate = Date.distantPast
    /// Dernier état envoyé à chaque écran verrouillé, et quand.
    private var envoyes: [String: (EcranVerrouille, Date)] = [:]
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.httpMaximumConnectionsPerHost = 1          // une seule connexion HTTP/2 gardée ouverte
        return URLSession(configuration: c)
    }()

    private init() {
        keyID = UserDefaults.standard.string(forKey: "apnsKeyID") ?? ""
        teamID = UserDefaults.standard.string(forKey: "apnsTeamID") ?? "6LM4CP9824"
        cleEnregistree = !Trousseau.lire("apns-p8").isEmpty
        iphones = Stockage.lire([Iphone].self, nom: APNs.fichier) ?? []
    }

    var pret: Bool { cleEnregistree && keyID.count == 10 && teamID.count == 10 }

    // MARK: - Clé .p8

    /// HUGO choisit lui-même son fichier AuthKey_XXXXXXXXXX.p8. Le Key ID est lu dans le nom du fichier.
    func choisirCle() {
        let p = NSOpenPanel()
        p.title = "Choisir la clé .p8 du service d'Apple"
        p.allowedContentTypes = []
        p.allowsOtherFileTypes = true
        p.canChooseDirectories = false
        p.directoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop/claude")
        guard p.runModal() == .OK, let url = p.url else { return }
        guard let texte = try? String(contentsOf: url, encoding: .utf8),
              (try? P256.Signing.PrivateKey(pemRepresentation: texte)) != nil else {
            dernierEtat = "Ce fichier n'est pas une clé .p8 d'Apple."
            return
        }
        Trousseau.ecrire("apns-p8", texte)
        cleEnregistree = true
        jwt = ""
        let nom = url.deletingPathExtension().lastPathComponent
        if nom.hasPrefix("AuthKey_") { keyID = String(nom.dropFirst("AuthKey_".count)) }
        dernierEtat = "Clé enregistrée dans le trousseau du Mac."
    }

    func oublierCle() {
        Trousseau.ecrire("apns-p8", "")
        cleEnregistree = false
        jwt = ""
        dernierEtat = "Clé retirée du trousseau."
    }

    // MARK: - Jetons reçus des iPhone

    func enregistrer(sorte: String, valeur: String, production: Bool, nom: String, appareil: String, piste: String) {
        let i = iphones.firstIndex { $0.appareil == appareil && $0.nom == nom }
            ?? { iphones.append(Iphone(nom: nom, appareil: appareil, piste: piste)); return iphones.count - 1 }()
        // le même iPhone sous un autre nom : on retire l'ancien (un seul destinataire par appareil)
        iphones[i].piste = piste
        iphones[i].production = production
        iphones[i].vu = Date()
        switch sorte {
        case "notifications": iphones[i].notifications = valeur
        case "activite": iphones[i].activite = valeur
        case "fin": iphones[i].activite = ""
        case "demarrage": iphones[i].demarrage = valeur
        default: return
        }
        let garder = iphones[i]
        iphones.removeAll { $0.appareil == garder.appareil && $0.id != garder.id }
        iphones.removeAll { Date().timeIntervalSince($0.vu) > 30 * 86400 }
        Stockage.ecrire(iphones, nom: APNs.fichier)
    }

    /// Nom ou piste changés sur un iPhone connecté.
    func misAJour(nom: String, appareil: String, piste: String) {
        guard let i = iphones.firstIndex(where: { $0.appareil == appareil }) else { return }
        guard iphones[i].nom != nom || iphones[i].piste != piste else { return }
        iphones[i].nom = nom
        iphones[i].piste = piste
        Stockage.ecrire(iphones, nom: APNs.fichier)
    }

    // MARK: - Envois

    /// Bulle sur les iPhone (messages, CHANGE TON CODE…). `sauf` : appareils connectés, qui l'affichent déjà eux-mêmes.
    func bulle(titre: String, texte: String, pour: (Iphone) -> Bool, urgent: Bool = false) {
        guard pret else { return }
        for p in iphones where !p.notifications.isEmpty && pour(p) {
            let aps: [String: Any] = [
                "alert": ["title": titre, "body": String(texte.prefix(500))],
                "sound": "default",
                "thread-id": "groompix",
                "interruption-level": urgent ? "time-sensitive" : "active",
            ]
            envoyer(["aps": aps], jeton: p.notifications, sorte: "alert", priorite: 10, production: p.production, iphone: p.id)
        }
    }

    /// Écran verrouillé : envoyé seulement s'il a changé, au plus toutes les 15 s,
    /// tout de suite quand le couple en piste ou l'alerte de code change.
    func ecranVerrouille(piste: String, etat: EcranVerrouille) {
        guard pret else { return }
        for p in iphones where !p.activite.isEmpty && p.piste == piste {
            let avant = envoyes[p.activite]
            if let avant, avant.0 == etat { continue }
            let important = avant == nil || avant!.0.code != etat.code || avant!.0.alerte != etat.alerte
            if !important, let avant, Date().timeIntervalSince(avant.1) < 15 { continue }
            guard let donnees = try? JSONEncoder().encode(etat),
                  let contenu = try? JSONSerialization.jsonObject(with: donnees) else { continue }
            envoyes[p.activite] = (etat, Date())
            var aps: [String: Any] = [
                "timestamp": Int(Date().timeIntervalSince1970),
                "event": "update",
                "content-state": contenu,
                "stale-date": Int(Date().timeIntervalSince1970) + 4 * 3600,
            ]
            if let a = etat.alerte, a != avant?.0.alerte {
                aps["alert"] = ["title": "CHANGE TON CODE", "body": "Mets \(a)"]
                aps["sound"] = "default"
            }
            envoyer(["aps": aps], jeton: p.activite, sorte: "liveactivity", priorite: important ? 10 : 5,
                    production: p.production, iphone: p.id)
        }
    }

    /// Bouton « Envoyer un essai » des réglages.
    func essai() {
        guard pret else { dernierEtat = "Il manque la clé .p8 ou le Key ID."; return }
        let avec = iphones.filter { !$0.notifications.isEmpty }
        guard !avec.isEmpty else {
            dernierEtat = "Aucun iPhone connu : ouvre Groom Pix Piste une fois sur le wifi du stand."
            return
        }
        dernierEtat = "Essai envoyé à \(avec.map(\.nom).joined(separator: ", "))…"
        bulle(titre: "Essai · Groom Pix", texte: "Les notifications par internet marchent.", pour: { _ in true })
    }

    private func envoyer(_ corps: [String: Any], jeton: String, sorte: String, priorite: Int, production: Bool, iphone: String) {
        guard let entete = jetonSigne(), let donnees = try? JSONSerialization.data(withJSONObject: corps) else { return }
        let hote = production ? "api.push.apple.com" : "api.sandbox.push.apple.com"
        guard let url = URL(string: "https://\(hote)/3/device/\(jeton)") else { return }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.httpBody = donnees
        r.setValue("bearer \(entete)", forHTTPHeaderField: "authorization")
        r.setValue(sorte, forHTTPHeaderField: "apns-push-type")
        r.setValue(sorte == "liveactivity" ? "\(APNs.bundle).push-type.liveactivity" : APNs.bundle, forHTTPHeaderField: "apns-topic")
        r.setValue("\(priorite)", forHTTPHeaderField: "apns-priority")
        r.setValue("0", forHTTPHeaderField: "apns-expiration")
        session.dataTask(with: r) { d, rep, err in
            let code = (rep as? HTTPURLResponse)?.statusCode ?? 0
            let raison = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["reason"] as? String ?? ""
            Task { @MainActor in APNs.partage.reponse(code: code, raison: raison, erreur: err, jeton: jeton, iphone: iphone) }
        }.resume()
    }

    private func reponse(code: Int, raison: String, erreur: Error?, jeton: String, iphone: String) {
        if let erreur { dernierEtat = "Pas d'internet pour le service d'Apple (\(erreur.localizedDescription))."; return }
        switch code {
        case 200:
            dernierEtat = "Dernier envoi réussi à \(Date().formatted(date: .omitted, time: .shortened))."
        case 403 where raison.contains("Token") || raison == "InvalidProviderToken":
            jwt = ""
            dernierEtat = "Apple refuse la clé : vérifie le Key ID et le Team ID (\(raison))."
        case 400 where raison == "BadDeviceToken", 410:
            // jeton périmé (app réinstallée, écran verrouillé fermé) : oublié
            for i in iphones.indices where iphones[i].id == iphone {
                if iphones[i].notifications == jeton { iphones[i].notifications = "" }
                if iphones[i].activite == jeton { iphones[i].activite = "" }
                if iphones[i].demarrage == jeton { iphones[i].demarrage = "" }
            }
            Stockage.ecrire(iphones, nom: APNs.fichier)
        default:
            dernierEtat = "Apple a répondu \(code) \(raison)."
        }
    }

    /// Jeton JWT signé (ES256) avec la clé .p8, refait toutes les 50 minutes (Apple : entre 20 et 60 min).
    private func jetonSigne() -> String? {
        if !jwt.isEmpty, Date().timeIntervalSince(jwtDate) < 50 * 60 { return jwt }
        guard let cle = try? P256.Signing.PrivateKey(pemRepresentation: Trousseau.lire("apns-p8")) else {
            dernierEtat = "Clé .p8 illisible dans le trousseau."
            return nil
        }
        func b64(_ d: Data) -> String {
            d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let tete = b64(Data(#"{"alg":"ES256","kid":"\#(keyID)"}"#.utf8))
        let corps = b64(Data(#"{"iss":"\#(teamID)","iat":\#(Int(Date().timeIntervalSince1970))}"#.utf8))
        guard let sig = try? cle.signature(for: Data("\(tete).\(corps)".utf8)) else { return nil }
        jwt = "\(tete).\(corps).\(b64(sig.rawRepresentation))"
        jwtDate = Date()
        return jwt
    }
}

import SwiftUI

/// Réglages 11 : la clé du service d'Apple et les iPhone qui recevront bulles et écran verrouillé.
struct CarteNotificationsIphone: View {
    @ObservedObject var apns = APNs.partage

    var body: some View {
        Carte(titre: SectionReglages.iphone.rawValue,
              sousTitre: "Bulles et écran verrouillé sur les iPhone des pistes, même app fermée. Le Mac parle directement au service d'Apple avec ta clé .p8 (celle de HM Timing marche aussi). Il faut internet sur le Mac.") {
            Ligne("Clé .p8") {
                HStack(spacing: 10) {
                    Button(apns.cleEnregistree ? "Changer de clé .p8…" : "Choisir la clé .p8…") { apns.choisirCle() }
                    if apns.cleEnregistree {
                        Label("Enregistrée dans le trousseau", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 12)).foregroundStyle(Theme.accent)
                        Button("Retirer") { apns.oublierCle() }.buttonStyle(BoutonPlat()).foregroundStyle(Theme.texteDiscret)
                    }
                }
            }
            Ligne("Key ID (10 caractères après « AuthKey_ »)") {
                TextField("ABCDE12345", text: $apns.keyID).textFieldStyle(.roundedBorder).frame(width: 160)
            }
            Ligne("Team ID") {
                TextField("6LM4CP9824", text: $apns.teamID).textFieldStyle(.roundedBorder).frame(width: 160)
            }
            Ligne("Essai") {
                Button("Envoyer un essai aux iPhone") { apns.essai() }.disabled(!apns.pret)
            }
            if !apns.dernierEtat.isEmpty {
                Text(apns.dernierEtat).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
            }
            Divider().overlay(Theme.bordure)
            if apns.iphones.isEmpty {
                Text("Aucun iPhone encore connu. Ouvre Groom Pix Piste une fois sur le wifi du stand et accepte les notifications.")
                    .font(.system(size: 12)).foregroundStyle(Theme.texteTresDiscret)
            } else {
                ForEach(apns.iphones) { p in
                    HStack(spacing: 10) {
                        Image(systemName: "iphone").foregroundStyle(Theme.texteDiscret)
                        Text(p.nom.isEmpty ? p.appareil : "\(p.nom) · \(p.appareil)").font(.system(size: 12.5))
                        if !p.piste.isEmpty { Text(p.piste).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret) }
                        Spacer()
                        Text(p.notifications.isEmpty ? "bulles : non" : "bulles : oui").font(.system(size: 11.5))
                            .foregroundStyle(p.notifications.isEmpty ? Theme.texteTresDiscret : Theme.accent)
                        Text(p.activite.isEmpty ? "écran verrouillé : non" : "écran verrouillé : oui").font(.system(size: 11.5))
                            .foregroundStyle(p.activite.isEmpty ? Theme.texteTresDiscret : Theme.accent)
                    }
                }
            }
        }
    }
}
