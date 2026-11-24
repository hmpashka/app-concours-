import AppKit
import SwiftUI
import TriPhotoCommun
import TriPhotoMoteur
import UniformTypeIdentifiers

/// Écran « Commandes » (maquette du 24/11) : à gauche le client et les commandes, au centre ses chevaux et ses
/// concours, à droite la commande. Une commande = un concours. Prix : pack + cheval de plus (tarif du concours).
struct CommandesView: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var archives: Archives
    @State private var recherche = ""
    @State private var clients: [ClientTrouve] = []
    @State private var client: ClientTrouve?
    @State private var choix: Set<String> = []                 // participations cochées
    @State private var remiseMain: [String: Bool] = [:]        // oui / non dit à la main
    @State private var commande: Commande?                     // en cours d'écriture (nouvelle ou ancienne)
    @State private var prixTexte = ""
    @State private var prixTouche = false
    @State private var filtre: Commande.Statut?
    @State private var tousConcours = false
    @State private var message = ""

    var body: some View {
        HStack(spacing: 0) {
            if etat.panneauGauche {
                gauche.frame(width: 300).background(Theme.panneau)
                Divider().overlay(Theme.bordure)
            }
            centre.frame(maxWidth: .infinity, maxHeight: .infinity)
            if etat.panneauDroit {
                Divider().overlay(Theme.bordure)
                droite.frame(width: 330).background(Theme.panneau)
            }
        }
        .onAppear { archives.relire() }
        .onChange(of: recherche) { t in chercher(t) }
    }

    private func chercher(_ t: String) {
        let texte = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard texte == recherche else { return }           // on attend la fin de la frappe
            clients = etat.chercherClients(texte)
        }
    }

    // MARK: - Gauche : client et commandes

    private var commandesAffichees: [Commande] {
        let l = tousConcours ? archives.commandes : archives.commandes(concours: etat.idConcours)
        return filtre.map { f in l.filter { $0.statut == f } } ?? l
    }

    private var gauche: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Client").font(.system(size: 14, weight: .semibold))
            TextField("Nom, prénom ou cheval", text: $recherche).textFieldStyle(.roundedBorder)
            Text("Cherche dans tous les concours gardés (\(archives.listings.count)).")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(clients) { c in
                        Button { choisir(c) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(c.nom) \(c.prenom)").font(.system(size: 13, weight: .semibold))
                                Text("\(c.chevaux.joined(separator: " · ")) · \(c.concours.count) concours")
                                    .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(client?.id == c.id ? Theme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if !recherche.isEmpty && clients.isEmpty {
                        Text("Personne trouvé.").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                    }
                }
            }
            .frame(maxHeight: 220)
            Divider().overlay(Theme.bordure)
            HStack {
                Text("Commandes").font(.system(size: 14, weight: .semibold))
                Spacer()
                Toggle("Tous concours", isOn: $tousConcours).font(.system(size: 11)).toggleStyle(.checkbox)
            }
            Picker("", selection: $filtre) {
                Text("Toutes").tag(Commande.Statut?.none)
                ForEach(Commande.Statut.allCases) { s in Text(s.rawValue).tag(Commande.Statut?.some(s)) }
            }
            .pickerStyle(.segmented).labelsHidden()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(commandesAffichees) { k in
                        Button { ouvrir(k) } label: {
                            HStack(spacing: 6) {
                                PastilleStatut(statut: k.statut)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(k.client) · \(Commande.euros(k.prix))").font(.system(size: 12))
                                    Text(tousConcours ? k.nomConcours : k.chevaux.joined(separator: " · "))
                                        .font(.system(size: 10)).foregroundStyle(Theme.texteDiscret).lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(6)
                            .background(commande?.id == k.id ? Theme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("\(commandesAffichees.count) commandes · \(Commande.euros(commandesAffichees.reduce(0) { $0 + $1.prix }))")
                .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
        }
        .padding(14)
    }

    // MARK: - Centre : chevaux et concours

    private var participations: [Participation] { client?.participations ?? [] }
    private var concoursChoisi: String? { participations.first { choix.contains($0.id) }?.concours }

    private var centre: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let c = client {
                Text("\(c.nom) \(c.prenom) — choisir les chevaux et le concours").font(.system(size: 17, weight: .semibold))
                Text("Une commande = un concours. Cocher une ligne d'un autre concours change de concours.")
                    .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                Carte(titre: "Chevaux") {
                    HStack(spacing: 16) {
                        ForEach(c.chevaux, id: \.self) { ch in
                            Toggle(ch, isOn: Binding(get: { chevalCoche(ch) }, set: { cocherCheval(ch, $0) }))
                                .toggleStyle(.checkbox)
                        }
                    }
                }
                ScrollView {
                    Carte {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            GridRow {
                                Text("")
                                ForEach(["Concours", "Épreuve", "Cheval", "Remise des prix", "Photos"], id: \.self) {
                                    Text($0).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                                }
                            }
                            ForEach(participations) { p in
                                GridRow {
                                    Toggle("", isOn: Binding(get: { choix.contains(p.id) }, set: { cocher(p, $0) }))
                                        .toggleStyle(.checkbox).labelsHidden()
                                    Text(p.nomConcours).font(.system(size: 12))
                                    Text("\(p.epreuve) · \(p.nomEpreuve)").font(.system(size: 12)).lineLimit(2)
                                    Text(p.cheval).font(.system(size: 12))
                                    remiseVue(p)
                                    Text(p.photos.map(String.init) ?? "—").font(.system(size: 12, design: .monospaced))
                                }
                            }
                        }
                    }
                    if let id = concoursChoisi, let l = archives.listing(id) { tarif(l) }
                }
                Text("Remise des prix : cochée toute seule si le cavalier est classé (résultats du fichier FFE) ; sinon oui / non à la main.")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            } else {
                Spacer()
                VStack(spacing: 10) {
                    Text("Tape le nom du client, un prénom ou un cheval à gauche.").foregroundStyle(Theme.texteDiscret)
                    Button("Ajouter un ancien concours (fichier FFE)…", action: importer).buttonStyle(BoutonStyle())
                    Text("Le concours en cours est gardé tout seul (au chargement du fichier FFE et à la clôture, avec les engagés terrain).")
                        .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
                    if !archives.message.isEmpty { Text(archives.message).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret) }
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func remiseVue(_ p: Participation) -> some View {
        if let r = p.remise {
            Pastille(texte: r ? "Oui (classé)" : "Non", genre: r ? .ok : .neutre)
        } else {
            Picker("", selection: Binding(get: { remiseMain[p.id] }, set: { remiseMain[p.id] = $0; recalculer() })) {
                Text("?").tag(Bool?.none)
                Text("Oui").tag(Bool?.some(true))
                Text("Non").tag(Bool?.some(false))
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 130)
        }
    }

    private func tarif(_ l: ListingConcours) -> some View {
        Carte(titre: "Prix de « \(l.nom) »") {
            HStack {
                Text("Pack (un couple)").font(.system(size: 12))
                TextField("", value: Binding(get: { l.tarif.pack }, set: {
                    archives.changerTarif(l.id, TarifConcours(pack: $0, chevalEnPlus: l.tarif.chevalEnPlus)); recalculer()
                }), format: .number).textFieldStyle(.roundedBorder).frame(width: 70)
                Text("€  ·  cheval de plus").font(.system(size: 12))
                TextField("", value: Binding(get: { l.tarif.chevalEnPlus }, set: {
                    archives.changerTarif(l.id, TarifConcours(pack: l.tarif.pack, chevalEnPlus: $0)); recalculer()
                }), format: .number).textFieldStyle(.roundedBorder).frame(width: 60)
                Text("€").font(.system(size: 12))
            }
        }
    }

    private func chevalCoche(_ ch: String) -> Bool {
        let l = participations.filter { $0.cheval == ch && $0.concours == (concoursChoisi ?? participations.first?.concours) }
        return !l.isEmpty && l.allSatisfy { choix.contains($0.id) }
    }

    private func cocherCheval(_ ch: String, _ oui: Bool) {
        let c = concoursChoisi ?? participations.first { $0.cheval == ch }?.concours
        for p in participations where p.cheval == ch && p.concours == c { cocher(p, oui) }
    }

    private func cocher(_ p: Participation, _ oui: Bool) {
        if oui {
            if let c = concoursChoisi, c != p.concours {
                choix = []                                     // une commande = un concours
                message = "Commande passée sur « \(p.nomConcours) »."
            }
            choix.insert(p.id)
        } else {
            choix.remove(p.id)
        }
        if commande.map({ k in archives.commandes.contains { $0.id == k.id } }) ?? false { commande = nil }
        nouvelleCommande()
    }

    private func choisir(_ c: ClientTrouve) {
        client = c
        choix = []
        remiseMain = [:]
        message = ""
        commande = nil
        prixTouche = false
        // d'office : tous les passages du concours le plus récent
        if let premier = c.participations.first?.concours {
            choix = Set(c.participations.filter { $0.concours == premier }.map(\.id))
        }
        nouvelleCommande()
    }

    /// (Re)calcule la commande en cours d'écriture d'après les cases cochées. Ce qui est déjà tapé (téléphone,
    /// mail…) est gardé ; le prix suit le tarif du concours tant qu'il n'a pas été changé à la main.
    private func nouvelleCommande() {
        guard var c = client else { return }
        for l in archives.listings { c.tarifs[l.id] = l.tarif }       // tarif à jour (il peut changer à l'écran)
        let l = participations.filter { choix.contains($0.id) }.map { p -> Participation in
            var q = p
            if q.remise == nil { q.remise = remiseMain[p.id] }
            return q
        }
        let ancien = commande
        guard var k = Commande.nouvelle(c, choix: l, par: "Mac") else {
            if var a = ancien { a.lignes = []; commande = a }             // rien de coché : on garde ce qui est tapé
            return
        }
        if let a = ancien {
            k.id = a.id; k.telephone = a.telephone; k.mail = a.mail; k.reglement = a.reglement
            k.statut = a.statut; k.note = a.note
            if prixTouche && a.concours == k.concours { k.prix = a.prix } else { prixTouche = false }
        }
        commande = k
        prixTexte = Commande.euros(k.prix).replacingOccurrences(of: " €", with: "")
    }

    private func recalculer() {
        guard let k = commande, !archives.commandes.contains(where: { $0.id == k.id }) else { return }
        nouvelleCommande()
    }

    /// Une commande déjà enregistrée : on change ses infos (statut, téléphone, prix…), pas ses passages.
    private func ouvrir(_ k: Commande) {
        client = nil
        choix = []
        commande = k
        prixTexte = Commande.euros(k.prix).replacingOccurrences(of: " €", with: "")
        prixTouche = true
    }

    private func importer() {
        let p = NSOpenPanel()
        p.title = "Ancien concours"
        p.message = "Choisis le fichier FFE (SIF ou FFE Compet) d'un ancien concours : son listing sera gardé."
        p.allowedContentTypes = [.xml]
        p.allowsMultipleSelection = true
        guard p.runModal() == .OK else { return }
        for u in p.urls { archives.importer(fichierFFE: u) }
    }

    // MARK: - Droite : la commande

    private var droite: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Commande").font(.system(size: 14, weight: .semibold))
                if let k = commande {
                    let existante = archives.commandes.contains { $0.id == k.id }
                    Text("\(k.client) · \(k.nomConcours)").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                    champ("Pack") {
                        Text(k.chevaux.count <= 1 ? "Pack couple (\(k.chevaux.first ?? "—"))"
                             : "Pack + \(k.chevaux.count - 1) cheval\(k.chevaux.count > 2 ? "aux" : "") de plus")
                            .font(.system(size: 13))
                    }
                    champ("Prix (€)") {
                        TextField("", text: Binding(get: { prixTexte }, set: { t in
                            prixTexte = t
                            if let v = Double(t.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")) {
                                commande?.prix = v
                                prixTouche = true
                            }
                        })).textFieldStyle(.roundedBorder)
                    }
                    champ("Téléphone") { TextField("", text: lien(\.telephone)).textFieldStyle(.roundedBorder) }
                    champ("Mail") { TextField("", text: lien(\.mail)).textFieldStyle(.roundedBorder) }
                    champ("Règlement") {
                        Picker("", selection: lien(\.reglement)) {
                            ForEach(Commande.Reglement.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                    }
                    champ("Statut") {
                        Picker("", selection: lien(\.statut)) {
                            ForEach(Commande.Statut.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                    }
                    champ("Note") { TextField("", text: lien(\.note), axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder) }
                    champ("Remise des prix") {
                        Text(k.remise == true ? "Oui" : k.remise == false ? "Non" : "Pas connue").font(.system(size: 13))
                    }
                    HStack {
                        Button(existante ? "Enregistrer les changements" : "Enregistrer la commande") {
                            if var n = commande {
                                n.lignes = n.lignes.map { l in
                                    var m = l
                                    if m.remise == nil, let p = participations.first(where: { $0.epreuve == l.epreuve && $0.dossard == l.dossard && $0.concours == n.concours }) {
                                        m.remise = remiseMain[p.id]
                                    }
                                    return m
                                }
                                archives.enregistrer(n)
                                commande = n
                                message = "Commande de \(n.client) enregistrée."
                            }
                        }
                        .buttonStyle(BoutonStyle(principal: true)).disabled(k.lignes.isEmpty)
                        Button("Annuler") { commande = nil; client = nil; choix = [] }.buttonStyle(BoutonStyle())
                    }
                    if existante {
                        Button("Supprimer (corbeille)") { archives.supprimer(k); commande = nil }.buttonStyle(BoutonStyle())
                    }
                } else {
                    Text("Choisis un client, ou une commande à gauche.").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                }
                if !message.isEmpty { Text(message).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret) }
                Text("Enregistrée dans le dossier « Tri-photo Listings » (iCloud) : visible sur les autres Mac et sur les iPhone du stand.")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            }
            .padding(14)
        }
    }

    private static let vide = Commande(concours: "", nomConcours: "", nom: "", prenom: "", lignes: [], prix: 0)

    private func lien<T>(_ k: WritableKeyPath<Commande, T>) -> Binding<T> {
        Binding(get: { (commande ?? CommandesView.vide)[keyPath: k] }, set: { commande?[keyPath: k] = $0 })
    }

    private func champ<C: View>(_ titre: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(titre).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
            c()
        }
    }
}

/// Statut d'une commande en couleur : à faire (orange), en cours (gris), envoyé (vert).
struct PastilleStatut: View {
    var statut: Commande.Statut
    var body: some View {
        Pastille(texte: statut.rawValue, genre: statut == .envoye ? .ok : statut == .aFaire ? .attention : .neutre)
    }
}
