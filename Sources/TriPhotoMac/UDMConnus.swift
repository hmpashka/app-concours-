import Foundation
import Network
import SwiftUI
import TriPhotoMoteur

/// Les UDM Pro connus de ce Mac (un par remorque) et celui du réseau où le Mac est branché en ce moment.
/// La liste est celle du Mac (pas d'un concours) ; les clés API sont dans le trousseau (« unifi-<adresse MAC> »).
@MainActor
final class StandsUniFi: ObservableObject {
    static let partages = StandsUniFi()
    nonisolated private static let cleListe = "udmsConnus"
    nonisolated private static let cleIgnores = "udmsIgnores"

    @Published var udms: [UDMConnu] = StandsUniFi.lireListe() {
        didSet {
            guard udms != oldValue else { return }
            if let d = try? JSONEncoder().encode(udms) { UserDefaults.standard.set(d, forKey: StandsUniFi.cleListe) }
            Etat.courant?.galerieEnLigneChangee()
        }
    }
    /// Le routeur du réseau actuel (nil : pas de réseau).
    @Published private(set) var routeur: RouteurVu?
    /// Routeur inconnu qui est bien une console UniFi : à proposer (bandeau).
    @Published private(set) var nouvelUDM: RouteurVu?
    /// Routeurs qui ne sont pas des UDM du stand (« Ce n'est pas un UDM du stand »), ou remis à plus tard.
    @Published private(set) var ignores: Set<String> = Set(UserDefaults.standard.stringArray(forKey: StandsUniFi.cleIgnores) ?? [])
    private var plusTard: Set<String> = []
    private var dejaRegarde: [String: Bool] = [:]       // adresse MAC → console UniFi ?
    private var minuterie: Timer?
    private var surveillance: NWPathMonitor?
    private var enCours = false

    /// L'UDM connu du réseau actuel.
    var udmIci: UDMConnu? { routeur.flatMap { r in udms.first { $0.mac == r.mac } } }

    func cle(_ mac: String) -> String { Trousseau.lire("unifi-" + mac) }
    func ecrireCle(_ mac: String, _ cle: String) {
        Trousseau.ecrire("unifi-" + mac, cle)
        Etat.courant?.galerieEnLigneChangee()
    }

    /// Regarde le routeur toutes les 30 s, et tout de suite quand le réseau change (câble, wifi).
    func demarrer() {
        guard minuterie == nil else { return }
        regarder()
        minuterie = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in StandsUniFi.partages.regarder() }
        }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { _ in
            // Laisse le temps au Mac d'obtenir son adresse sur le nouveau réseau.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { Task { @MainActor in StandsUniFi.partages.regarder() } }
        }
        m.start(queue: DispatchQueue(label: "groompix.reseau"))
        surveillance = m
    }

    func regarder() {
        guard !enCours else { return }
        enCours = true
        Task.detached(priority: .utility) {
            let r = DetectionUDM.routeurActuel()
            await MainActor.run { StandsUniFi.partages.vu(r) }
        }
    }

    private func vu(_ r: RouteurVu?) {
        enCours = false
        if routeur != r { routeur = r }
        guard let r, !r.mac.isEmpty else { nouvelUDM = nil; return }
        if let i = udms.firstIndex(where: { $0.mac == r.mac }) {
            if udms[i].derniereAdresse != r.adresse { udms[i].derniereAdresse = r.adresse }
            nouvelUDM = nil
            return
        }
        if migrer(r) { return }
        guard !ignores.contains(r.mac), !plusTard.contains(r.mac) else { nouvelUDM = nil; return }
        if let u = dejaRegarde[r.mac] {
            nouvelUDM = u ? r : nil
            return
        }
        DetectionUDM.estUniFi(r.adresse) { reponse in
            Task { @MainActor in
                let s = StandsUniFi.partages
                // Pas de réponse : on ne retient rien, nouvel essai au prochain coup d'œil (30 s).
                guard let oui = reponse else { return }
                s.dejaRegarde[r.mac] = oui
                if s.routeur == r, !s.udms.contains(where: { $0.mac == r.mac }) { s.nouvelUDM = oui ? r : nil }
            }
        }
    }

    /// Ancien réglage (une adresse + la clé « unifi ») : devient le premier UDM connu, sans rien ressaisir,
    /// dès que le Mac est sur ce réseau.
    private func migrer(_ r: RouteurVu) -> Bool {
        guard let etat = Etat.courant else { return false }
        let ancienne = Etat.hoteSeul(etat.reglages.adresseUniFi.trimmingCharacters(in: .whitespaces))
            .replacingOccurrences(of: "https://", with: "")
        let cleAncienne = Trousseau.lire("unifi")
        guard udms.isEmpty, !ancienne.isEmpty, !cleAncienne.isEmpty, ancienne == r.adresse else { return false }
        Trousseau.ecrire("unifi-" + r.mac, cleAncienne)
        Trousseau.ecrire("unifi", "")
        udms = [UDMConnu(mac: r.mac, nom: "Mon UDM", montantMbit: etat.reglages.montantMbitLigne,
                         empreinte: etat.reglages.empreinteUniFi, derniereAdresse: r.adresse)]
        etat.reglages.adresseUniFi = ""
        etat.reglages.empreinteUniFi = ""
        nouvelUDM = nil
        return true
    }

    func ajouter(_ u: UDMConnu, cle: String) {
        Trousseau.ecrire("unifi-" + u.mac, cle)
        if let i = udms.firstIndex(where: { $0.mac == u.mac }) { udms[i] = u } else { udms.append(u) }
        if nouvelUDM?.mac == u.mac { nouvelUDM = nil }
        Etat.courant?.galerieEnLigneChangee()
    }

    func oublier(_ u: UDMConnu) {
        Trousseau.ecrire("unifi-" + u.mac, "")
        udms.removeAll { $0.mac == u.mac }
        dejaRegarde[u.mac] = nil
        regarder()
    }

    /// « Plus tard » : le bandeau revient au prochain lancement. « Pas un UDM du stand » : plus jamais proposé.
    func repousser(_ r: RouteurVu, definitivement: Bool) {
        if definitivement {
            ignores.insert(r.mac)
            UserDefaults.standard.set(Array(ignores), forKey: StandsUniFi.cleIgnores)
        } else {
            plusTard.insert(r.mac)
        }
        nouvelUDM = nil
    }

    func neplusIgnorer() {
        ignores = []
        plusTard = []
        UserDefaults.standard.removeObject(forKey: StandsUniFi.cleIgnores)
        regarder()
    }

    func retenirEmpreinte(mac: String, _ emp: String) {
        guard let i = udms.firstIndex(where: { $0.mac == mac }), udms[i].empreinte.isEmpty else { return }
        udms[i].empreinte = emp
    }

    /// Pour le moteur : nil s'il n'y a aucun UDM connu (pas de régulateur).
    func configUniFi(seuil: Int) -> ConfigUniFi? {
        guard !udms.isEmpty else { return nil }
        var cles: [String: String] = [:]
        for u in udms { cles[u.mac] = cle(u.mac) }
        return ConfigUniFi(udms: udms, cles: cles, seuil: Double(seuil) / 100,
                           sauverEmpreinte: { mac, emp in
                               Task { @MainActor in StandsUniFi.partages.retenirEmpreinte(mac: mac, emp) }
                           })
    }

    /// Ce qui compte pour le moteur (un changement le règle à nouveau).
    var signature: String { udms.map { "\($0.mac):\($0.montantMbit):\($0.empreinte)" }.joined(separator: ",") }

    nonisolated private static func lireListe() -> [UDMConnu] {
        guard let d = UserDefaults.standard.data(forKey: cleListe) else { return [] }
        return (try? JSONDecoder().decode([UDMConnu].self, from: d)) ?? []
    }

    /// Mac bloqué (licence) : toutes les clés UniFi effacées du trousseau.
    nonisolated static func effacerToutesLesCles() {
        Trousseau.ecrire("unifi", "")
        for u in lireListe() { Trousseau.ecrire("unifi-" + u.mac, "") }
    }
}

// MARK: - Réglages 5 : régulateur réseau

/// Rubrique « Régulateur réseau (UniFi) » : l'UDM du réseau actuel, la liste des UDM connus, le seuil.
struct RegulateurUniFiView: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var stands = StandsUniFi.partages
    @State private var fiche: FicheUDM.Mode?
    @State private var test: (mac: String, ok: Bool?, texte: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Régulateur réseau (UniFi)").font(.system(size: 13, weight: .semibold))
            etatIci
            if !stands.udms.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("UDM connus"); Text("Identifiant"); Text("Débit montant"); Text("Clé"); Text("")
                    }
                    .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
                    ForEach(stands.udms) { u in
                        let ici = stands.udmIci?.mac == u.mac
                        GridRow {
                            Text((ici ? "● " : "") + u.nom).foregroundStyle(ici ? Theme.ok : Theme.texte)
                                .fontWeight(ici ? .semibold : .regular)
                            Text(u.mac).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.texteDiscret)
                            Text("\(u.montantMbit) Mbit/s")
                            Text(stands.cle(u.mac).isEmpty ? "manquante" : "✓ au trousseau")
                                .foregroundStyle(stands.cle(u.mac).isEmpty ? Theme.erreur : Theme.texte)
                            HStack(spacing: 6) {
                                if ici {
                                    Button("Tester") { tester(u) }.buttonStyle(BoutonStyle())
                                }
                                Button("Modifier") { fiche = .modifier(u) }.buttonStyle(BoutonStyle())
                            }
                        }
                        .font(.system(size: 12))
                    }
                }
                if let t = test, !t.texte.isEmpty {
                    Text(t.texte).font(.system(size: 11))
                        .foregroundStyle(t.ok == false ? Theme.erreur : (t.ok == true ? Theme.ok : Theme.texteDiscret))
                }
            }
            if let r = stands.routeur, !r.mac.isEmpty, stands.udmIci == nil, stands.nouvelUDM == nil {
                Button("Ajouter le routeur de ce réseau comme UDM…") { fiche = .ajouter(r) }
                    .buttonStyle(BoutonStyle())
                    .help("Si l'app ne l'a pas reconnu toute seule comme une console UniFi.")
            }
            Ligne("Pause de la galerie") {
                Stepper("quand les autres utilisent plus de \(etat.reglages.seuilUniFi) % de la ligne",
                        value: $etat.reglages.seuilUniFi, in: 30...95, step: 5)
            }
            if !stands.ignores.isEmpty {
                Button("Proposer à nouveau les routeurs écartés (\(stands.ignores.count))") { stands.neplusIgnorer() }
                    .buttonStyle(BoutonStyle())
            }
            Text("Le Mac reconnaît tout seul l'UDM de la remorque où il est branché. Les photos des boîtiers et le serveur local passent toujours avant : seule la galerie en ligne attend, et reprend toute seule quand la ligne se libère.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
        }
        .sheet(item: $fiche) { m in FicheUDM(mode: m).environmentObject(etat) }
    }

    @ViewBuilder private var etatIci: some View {
        if let u = stands.udmIci {
            let mesure = etat.moteur.resume.galerieEnLigne?.reseau
            LigneEtat(couleur: Theme.ok, fond: Theme.okFond, titre: "Branché sur l'UDM « \(u.nom) »",
                      detail: "trouvé tout seul (\(stands.routeur?.adresse ?? u.derniereAdresse))"
                        + (mesure?.ok == true && mesure?.nomUDM == u.nom ? String(format: " · %.1f Mbit/s envoyés", mesure?.montantMbit ?? 0) : ""))
        } else if let n = stands.nouvelUDM {
            BandeauNouvelUDM(routeur: n, ouvrir: { fiche = .ajouter(n) })
        } else {
            if let r = stands.routeur, r.mac.isEmpty {
                LigneEtat(couleur: Theme.attention, fond: Theme.attentionFond,
                          titre: "Routeur \(r.adresse) muet",
                          detail: "autorise Groom Pix dans Réglages Système › Confidentialité et sécurité › Réseau local, puis relance l'app")
            } else {
                LigneEtat(couleur: Theme.texteDiscret, fond: Theme.carte,
                          titre: stands.routeur == nil ? "Pas de réseau" : "Ailleurs (bureau, autre wifi)",
                          detail: "aucun UDM connu : régulateur en pause, la galerie envoie normalement")
            }
        }
    }

    private func tester(_ u: UDMConnu) {
        guard let r = stands.routeur else { return }
        test = (u.mac, nil, "Essai en cours…")
        let c = CibleUniFi(mac: u.mac, nom: u.nom, adresse: r.adresse, cle: stands.cle(u.mac),
                           montantMbit: Double(u.montantMbit), empreinte: u.empreinte)
        GalerieEnLigne.testerUniFi(c) { ok, m, emp in
            Task { @MainActor in
                test = (u.mac, ok, m)
                if ok { StandsUniFi.partages.retenirEmpreinte(mac: u.mac, emp) }
            }
        }
    }
}

private struct LigneEtat: View {
    var couleur: Color
    var fond: Color
    var titre: String
    var detail: String
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(couleur).frame(width: 9, height: 9)
            Text(titre).font(.system(size: 12, weight: .semibold))
            Text("· " + detail).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(fond, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.bordure))
    }
}

/// « Nouvel UDM trouvé sur ce réseau » : en haut de la fenêtre et dans les réglages.
struct BandeauNouvelUDM: View {
    var routeur: RouteurVu
    var ouvrir: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.router")
            Text("Nouvel UDM trouvé sur ce réseau (\(routeur.adresse) · \(routeur.mac)). Ajoute-le pour régler la galerie sur sa ligne internet.")
            Spacer()
            Button("Ajouter…", action: ouvrir).buttonStyle(BoutonStyle(principal: true))
            Button("Plus tard") { StandsUniFi.partages.repousser(routeur, definitivement: false) }.buttonStyle(BoutonStyle())
            Button("Pas un UDM du stand") { StandsUniFi.partages.repousser(routeur, definitivement: true) }.buttonStyle(BoutonStyle())
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.attention)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(Theme.attentionFond)
    }
}

/// Bandeau en haut de la fenêtre principale (n'importe quel écran).
struct BandeauUDMFenetre: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var stands = StandsUniFi.partages
    @State private var fiche: FicheUDM.Mode?
    var body: some View {
        if let n = stands.nouvelUDM {
            BandeauNouvelUDM(routeur: n, ouvrir: { fiche = .ajouter(n) })
                .sheet(item: $fiche) { m in FicheUDM(mode: m).environmentObject(etat) }
        }
    }
}

/// Ajout guidé d'un nouvel UDM, ou modification d'un UDM connu. La clé est tapée par HUGO.
struct FicheUDM: View {
    enum Mode: Identifiable {
        case ajouter(RouteurVu)
        case modifier(UDMConnu)
        var id: String {
            switch self {
            case .ajouter(let r): return "a" + r.mac
            case .modifier(let u): return "m" + u.mac
            }
        }
    }
    var mode: Mode
    @Environment(\.dismiss) private var fermer
    @ObservedObject var stands = StandsUniFi.partages
    @State private var nom = ""
    @State private var cle = ""
    @State private var montant = 10
    @State private var message = ""
    @State private var ok: Bool?
    @State private var enTest = false

    private var mac: String {
        switch mode { case .ajouter(let r): return r.mac; case .modifier(let u): return u.mac }
    }
    private var existant: UDMConnu? {
        if case .modifier(let u) = mode { return u }
        return nil
    }
    /// Adresse actuelle de cette console, si le Mac est sur son réseau (sinon pas d'essai possible).
    private var adresse: String? {
        switch mode {
        case .ajouter(let r): return r.adresse
        case .modifier(let u): return stands.routeur?.mac == u.mac ? stands.routeur?.adresse : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existant == nil ? "Nouvel UDM" : "UDM « \(existant?.nom ?? "") »").font(.system(size: 15, weight: .semibold))
            Text("Identifiant : \(mac)" + (adresse.map { " · \($0)" } ?? ""))
                .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
            Ligne("Nom") {
                TextField("Remorque A", text: $nom).textFieldStyle(.roundedBorder)
            }
            Ligne("Clé API") {
                SecureField(existant == nil ? "UniFi Network › Paramètres › Plan de contrôle › Intégrations"
                                            : "vide : garder la clé actuelle", text: $cle)
                    .textFieldStyle(.roundedBorder)
            }
            Ligne("Débit montant de la ligne") {
                TextField("20", value: $montant, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).frame(width: 70)
                Text("Mbit/s")
                ForEach([5, 10, 20, 50, 100], id: \.self) { v in
                    Button("\(v)") { montant = v }.buttonStyle(BoutonStyle())
                }
            }
            Text("Le débit d'envoi de la ligne internet (4G, fibre…) : tape le chiffre ou choisis-en un.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            if !message.isEmpty {
                Text(message).font(.system(size: 11))
                    .foregroundStyle(ok == false ? Theme.erreur : (ok == true ? Theme.ok : Theme.texteDiscret))
            }
            HStack {
                if let u = existant {
                    Button("Oublier cet UDM") { stands.oublier(u); fermer() }.buttonStyle(BoutonStyle())
                }
                Spacer()
                Button("Annuler") { fermer() }.buttonStyle(BoutonStyle()).keyboardShortcut(.cancelAction)
                Button(existant == nil ? "Tester et ajouter" : "Enregistrer") { valider() }
                    .buttonStyle(BoutonStyle(principal: true)).keyboardShortcut(.defaultAction)
                    .disabled(enTest || nom.trimmingCharacters(in: .whitespaces).isEmpty || (existant == nil && cle.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 560)
        .background(Theme.fond)
        .foregroundStyle(Theme.texte)
        .onAppear {
            if let u = existant { nom = u.nom; montant = u.montantMbit }
        }
    }

    private func valider() {
        let n = nom.trimmingCharacters(in: .whitespaces)
        var u = existant ?? UDMConnu(mac: mac, nom: n, montantMbit: montant, derniereAdresse: adresse ?? "")
        u.nom = n
        u.montantMbit = max(1, min(10_000, montant))
        let cleFinale = cle.isEmpty ? stands.cle(mac) : cle
        guard let a = adresse, !cle.isEmpty || existant == nil else {
            // Modification sans nouvelle clé, ou UDM d'une autre remorque : enregistré tel quel.
            stands.ajouter(u, cle: cleFinale)
            fermer()
            return
        }
        enTest = true
        ok = nil
        message = "Essai en cours…"
        if !cle.isEmpty { u.empreinte = "" }        // nouvelle clé : on réapprend le certificat
        let c = CibleUniFi(mac: mac, nom: n, adresse: a, cle: cleFinale, montantMbit: Double(montant), empreinte: u.empreinte)
        let pret = u
        GalerieEnLigne.testerUniFi(c) { reussi, m, emp in
            Task { @MainActor in
                enTest = false
                ok = reussi
                message = m
                guard reussi else { return }
                var f = pret
                if f.empreinte.isEmpty { f.empreinte = emp }
                StandsUniFi.partages.ajouter(f, cle: cleFinale)
                fermer()
            }
        }
    }
}
