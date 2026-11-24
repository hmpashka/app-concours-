import AppKit
import SwiftUI
import TriPhotoCommun
import TriPhotoMoteur
import UniformTypeIdentifiers

/// Écran « Commandes » en 3 pages (maquette validée par HUGO le 24/11) :
/// 1. on cherche et coche le ou les cavaliers ; 2. on coche leurs chevaux (un couple = toutes ses photos du
/// concours, toutes épreuves, avec ses codes #épreuve_dossard) ; 3. récapitulatif : codes, prix, infos, Enregistrer.
/// Une commande par cavalier (le tarif « cheval de plus » est par cavalier), toutes avec les mêmes infos client.
/// À gauche : les commandes déjà prises ; un clic en ouvre une pour changer son statut, son prix ou ses infos.
struct CommandesView: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var archives: Archives
    @State private var etape = 1
    @State private var recherche = ""
    @State private var trouves: [ClientTrouve] = []
    @State private var cavaliers: [ClientTrouve] = []           // cochés à la page 1
    @State private var chevaux: Set<String> = []                // « idCavalier|cheval » cochés à la page 2
    @State private var concoursChoisi: [String: String] = [:]   // idCavalier → concours (par défaut : le plus récent)
    @State private var remiseMain: [String: Bool] = [:]         // « idCavalier|cheval » → oui / non dit à la main
    @State private var prixMain: [String: Double] = [:]         // idCavalier → prix changé à la main
    @State private var infos = Commande(concours: "", nomConcours: "", nom: "", prenom: "", lignes: [], prix: 0)
    @State private var ouverte: Commande?                       // commande déjà enregistrée, en modification
    @State private var prixTexte = ""
    @State private var filtre: Commande.Statut?
    @State private var tousConcours = false
    @State private var message = ""

    var body: some View {
        HStack(spacing: 0) {
            if etat.panneauGauche {
                gauche.frame(width: 300).background(Theme.panneau)
                Divider().overlay(Theme.bordure)
            }
            VStack(spacing: 0) {
                if ouverte == nil { etapes.padding(.top, 14) }
                Group {
                    if ouverte != nil { modification }
                    else if etape == 1 { page1 }
                    else if etape == 2 { page2 }
                    else { page3 }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear { archives.relire() }
        .onChange(of: recherche) { t in chercher(t) }
    }

    private func chercher(_ t: String) {
        let texte = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard texte == recherche else { return }           // on attend la fin de la frappe
            trouves = etat.chercherClients(texte)
        }
    }

    // MARK: - Étapes

    private var etapes: some View {
        HStack(spacing: 8) {
            ForEach([(1, "Cavalier"), (2, "Chevaux"), (3, "Récapitulatif")], id: \.0) { n, t in
                Button { if n == 1 || (n == 2 && !cavaliers.isEmpty) || (n == 3 && !lignesChoisies.isEmpty) { etape = n } } label: {
                    Text("\(n) · \(t)").font(.system(size: 13, weight: etape == n ? .semibold : .regular))
                        .foregroundStyle(etape >= n ? Color.black : Theme.texteDiscret)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(etape >= n ? Theme.accent : Theme.carte, in: Capsule())
                }
                .buttonStyle(BoutonPlat())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func basDePage<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 10) { Spacer(); c() }.padding(.top, 10)
    }

    // MARK: - Page 1 : qui commande ?

    private var page1: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Qui commande ?").font(.system(size: 20, weight: .semibold))
            Text("Nom, prénom ou cheval. On peut cocher plusieurs cavaliers (famille, même client).")
                .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
            TextField("Nom, prénom ou cheval", text: $recherche).textFieldStyle(.roundedBorder).font(.system(size: 15))
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(cavaliers.filter { c in !trouves.contains { $0.id == c.id } } + trouves) { c in
                        let coche = cavaliers.contains { $0.id == c.id }
                        Button { basculerCavalier(c) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: coche ? "checkmark.square.fill" : "square").font(.system(size: 18))
                                    .foregroundStyle(coche ? Theme.accent : Theme.texteDiscret)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(c.nom) \(c.prenom)").font(.system(size: 14, weight: .semibold))
                                    let ici = participations(c)
                                    Text("\(Set(ici.map(\.cheval)).count) cheval\(Set(ici.map(\.cheval)).count > 1 ? "aux" : "") · \(ici.first?.nomConcours ?? "")")
                                        .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret).lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(coche ? Theme.selection : Theme.carte, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(BoutonPlat())
                    }
                    if !recherche.isEmpty && trouves.isEmpty {
                        Text("Personne trouvé.").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                    }
                }
            }
            Text("Pas d'épreuves ici : tous les passages du concours sont pris en compte. Cherche dans les \(archives.listings.count) concours gardés.")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            basDePage {
                Button("Ajouter un ancien concours (fichier FFE)…", action: importer).buttonStyle(BoutonStyle())
                Button("Suivant : les chevaux →") { etape = 2 }
                    .buttonStyle(BoutonStyle(principal: true)).disabled(cavaliers.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }

    private func basculerCavalier(_ c: ClientTrouve) {
        if let i = cavaliers.firstIndex(where: { $0.id == c.id }) {
            cavaliers.remove(at: i)
            chevaux = chevaux.filter { !$0.hasPrefix(c.id + "|") }
        } else {
            cavaliers.append(c)
            // d'office : tous ses chevaux du concours retenu
            for ch in Set(participations(c).map(\.cheval)) { chevaux.insert(c.id + "|" + ch) }
        }
    }

    /// Passages d'un cavalier sur le concours retenu (le concours en cours s'il y est, sinon le plus récent).
    private func participations(_ c: ClientTrouve) -> [Participation] {
        let conc = concoursChoisi[c.id] ?? (c.concours.contains(etat.idConcours) ? etat.idConcours : c.concours.first ?? "")
        return c.participations.filter { $0.concours == conc }
    }

    // MARK: - Page 2 : quels chevaux ?

    private var page2: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quels chevaux ?").font(.system(size: 20, weight: .semibold))
            Text("Un couple cavalier + cheval = toutes ses photos du concours, toutes épreuves.")
                .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(cavaliers) { c in
                        HStack {
                            Text("\(c.nom) \(c.prenom)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.texteDiscret)
                            Spacer()
                            if c.concours.count > 1 {
                                Picker("", selection: Binding(get: { participations(c).first?.concours ?? "" },
                                                              set: { concoursChoisi[c.id] = $0; recocher(c) })) {
                                    ForEach(c.concours, id: \.self) { id in
                                        Text(c.participations.first { $0.concours == id }?.nomConcours ?? id).tag(id)
                                    }
                                }
                                .labelsHidden().frame(width: 260)
                            }
                        }
                        .padding(.top, 6)
                        ForEach(Array(Set(participations(c).map(\.cheval))).sorted(), id: \.self) { ch in
                            let cle = c.id + "|" + ch
                            let passages = participations(c).filter { $0.cheval == ch }
                            let coche = chevaux.contains(cle)
                            Button { if coche { chevaux.remove(cle) } else { chevaux.insert(cle) } } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: coche ? "checkmark.square.fill" : "square").font(.system(size: 18))
                                        .foregroundStyle(coche ? Theme.accent : Theme.texteDiscret)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(ch).font(.system(size: 14, weight: .semibold))
                                        HStack(spacing: 6) {
                                            let photos = passages.compactMap(\.photos).reduce(0, +)
                                            Text("\(passages.count) passage\(passages.count > 1 ? "s" : "")\(passages.contains { $0.photos != nil } ? " · \(photos) photos" : "") ·")
                                                .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                                            Text(passages.map { CodePassage(epreuve: $0.epreuve, dossard: $0.dossard).texte }.joined(separator: " · "))
                                                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.accent)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(coche ? Theme.selection : Theme.carte, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(BoutonPlat())
                        }
                    }
                }
            }
            basDePage {
                Button("← Retour") { etape = 1 }.buttonStyle(BoutonStyle())
                Button("Suivant : récapitulatif →") { etape = 3 }
                    .buttonStyle(BoutonStyle(principal: true)).disabled(lignesChoisies.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }

    private func recocher(_ c: ClientTrouve) {
        chevaux = chevaux.filter { !$0.hasPrefix(c.id + "|") }
        for ch in Set(participations(c).map(\.cheval)) { chevaux.insert(c.id + "|" + ch) }
    }

    // MARK: - Page 3 : récapitulatif

    /// Les passages retenus, par cavalier.
    private var lignesChoisies: [(ClientTrouve, [Participation])] {
        cavaliers.compactMap { c in
            let l = participations(c).filter { chevaux.contains(c.id + "|" + $0.cheval) }.map { p -> Participation in
                var q = p
                if q.remise == nil { q.remise = remiseMain[c.id + "|" + p.cheval] }
                return q
            }
            return l.isEmpty ? nil : (c, l)
        }
    }

    /// Une commande par cavalier, avec les infos communes et le prix (tarif du concours, ou changé à la main).
    private var commandesPretes: [Commande] {
        lignesChoisies.compactMap { c, l in
            var tc = c
            for x in archives.listings { tc.tarifs[x.id] = x.tarif }
            guard var k = Commande.nouvelle(tc, choix: l, par: "Mac") else { return nil }
            if let p = prixMain[c.id] { k.prix = p }
            k.telephone = infos.telephone; k.mail = infos.mail; k.reglement = infos.reglement
            k.statut = infos.statut; k.note = infos.note
            return k
        }
    }

    private var page3: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Récapitulatif").font(.system(size: 20, weight: .semibold))
                Text("Les codes du Copyright de chaque cheval, pour retrouver les photos.")
                    .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                Carte {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                        GridRow {
                            ForEach(["Couple", "Codes", "Remise des prix", "Prix (cavalier)"], id: \.self) {
                                Text($0).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                            }
                        }
                        ForEach(Array(lignesChoisies.enumerated()), id: \.offset) { _, paire in
                            let c = paire.0
                            let l = paire.1
                            ForEach(Array(Set(l.map(\.cheval))).sorted(), id: \.self) { ch in
                                let passages = l.filter { $0.cheval == ch }
                                GridRow {
                                    Text("\(c.nom) \(c.prenom) · \(ch)").font(.system(size: 13))
                                    Text(passages.map { CodePassage(epreuve: $0.epreuve, dossard: $0.dossard).texte }.joined(separator: "  "))
                                        .font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.accent).textSelection(.enabled)
                                    remiseVue(c, ch, passages)
                                    if ch == Array(Set(l.map(\.cheval))).sorted().first {
                                        TextField("", value: Binding(get: { prixMain[c.id] ?? commandesPretes.first { $0.nom == c.nom && $0.prenom == c.prenom }?.prix ?? 0 },
                                                                     set: { prixMain[c.id] = $0 }), format: .number)
                                            .textFieldStyle(.roundedBorder).frame(width: 80)
                                    } else {
                                        Text("")
                                    }
                                }
                            }
                        }
                    }
                }
                HStack {
                    Text("Total").font(.system(size: 18, weight: .bold))
                    Spacer()
                    Text(Commande.euros(commandesPretes.reduce(0) { $0 + $1.prix })).font(.system(size: 18, weight: .bold))
                }
                if let id = lignesChoisies.first?.1.first?.concours, let l = archives.listing(id) { tarif(l) }
                champ("Téléphone") { TextField("", text: $infos.telephone).textFieldStyle(.roundedBorder) }
                champ("Mail") { TextField("", text: $infos.mail).textFieldStyle(.roundedBorder) }
                champ("Règlement") {
                    Picker("", selection: $infos.reglement) { ForEach(Commande.Reglement.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 360)
                }
                champ("Statut") {
                    Picker("", selection: $infos.statut) { ForEach(Commande.Statut.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 300)
                }
                champ("Note") { TextField("", text: $infos.note, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder) }
                if !message.isEmpty { Text(message).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret) }
                basDePage {
                    Button("← Retour") { etape = 2 }.buttonStyle(BoutonStyle())
                    Button(commandesPretes.count > 1 ? "Enregistrer les \(commandesPretes.count) commandes" : "Enregistrer la commande") {
                        enregistrerNouvelles()
                    }
                    .buttonStyle(BoutonStyle(principal: true)).disabled(commandesPretes.isEmpty).keyboardShortcut(.defaultAction)
                }
                Text("Une commande par cavalier, enregistrée dans « Tri-photo Listings » (iCloud) : visible sur les autres Mac et les iPhone du stand.")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func remiseVue(_ c: ClientTrouve, _ ch: String, _ passages: [Participation]) -> some View {
        if passages.contains(where: { $0.remise == true }) {
            Pastille(texte: "Oui (classé)", genre: .ok)
        } else if passages.allSatisfy({ $0.remise == false }) {
            Pastille(texte: "Non", genre: .neutre)
        } else {
            Picker("", selection: Binding(get: { remiseMain[c.id + "|" + ch] }, set: { remiseMain[c.id + "|" + ch] = $0 })) {
                Text("?").tag(Bool?.none)
                Text("Oui").tag(Bool?.some(true))
                Text("Non").tag(Bool?.some(false))
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 130)
        }
    }

    private func enregistrerNouvelles() {
        let l = commandesPretes
        for k in l { archives.enregistrer(k) }
        message = l.count > 1 ? "\(l.count) commandes enregistrées." : "Commande de \(l.first?.client ?? "") enregistrée."
        // prêt pour le client suivant
        cavaliers = []; chevaux = []; concoursChoisi = [:]; remiseMain = [:]; prixMain = [:]
        infos = Commande(concours: "", nomConcours: "", nom: "", prenom: "", lignes: [], prix: 0)
        recherche = ""; trouves = []
        etape = 1
    }

    private func tarif(_ l: ListingConcours) -> some View {
        Carte(titre: "Prix de « \(l.nom) »") {
            HStack {
                Text("Pack (un couple)").font(.system(size: 12))
                TextField("", value: Binding(get: { l.tarif.pack }, set: {
                    archives.changerTarif(l.id, TarifConcours(pack: $0, chevalEnPlus: l.tarif.chevalEnPlus)); prixMain = [:]
                }), format: .number).textFieldStyle(.roundedBorder).frame(width: 70)
                Text("€  ·  cheval de plus (même cavalier)").font(.system(size: 12))
                TextField("", value: Binding(get: { l.tarif.chevalEnPlus }, set: {
                    archives.changerTarif(l.id, TarifConcours(pack: l.tarif.pack, chevalEnPlus: $0)); prixMain = [:]
                }), format: .number).textFieldStyle(.roundedBorder).frame(width: 60)
                Text("€").font(.system(size: 12))
            }
        }
    }

    // MARK: - Gauche : commandes déjà prises

    private var commandesAffichees: [Commande] {
        let l = tousConcours ? archives.commandes : archives.commandes(concours: etat.idConcours)
        return filtre.map { f in l.filter { $0.statut == f } } ?? l
    }

    private var gauche: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { ouverte = nil; etape = 1 } label: {
                Label("Nouvelle commande", systemImage: "plus").font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Theme.accent.opacity(ouverte == nil ? 1 : 0.6), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(Color.black)
            }
            .buttonStyle(BoutonPlat())
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
                            .background(ouverte?.id == k.id ? Theme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(BoutonPlat())
                    }
                }
            }
            Text("\(commandesAffichees.count) commandes · \(Commande.euros(commandesAffichees.reduce(0) { $0 + $1.prix }))")
                .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
        }
        .padding(14)
    }

    private func ouvrir(_ k: Commande) {
        ouverte = k
        prixTexte = Commande.euros(k.prix).replacingOccurrences(of: " €", with: "")
        message = ""
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

    // MARK: - Modifier une commande déjà enregistrée

    private var modification: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let k = ouverte {
                    Text("\(k.client) · \(k.nomConcours)").font(.system(size: 20, weight: .semibold))
                    Carte(titre: "Couples et codes") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(k.chevaux, id: \.self) { ch in
                                HStack {
                                    Text(ch).font(.system(size: 13)).frame(width: 220, alignment: .leading)
                                    Text(k.lignes.filter { $0.cheval == ch }.map { CodePassage(epreuve: $0.epreuve, dossard: $0.dossard).texte }.joined(separator: "  "))
                                        .font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.accent).textSelection(.enabled)
                                }
                            }
                            Text("Remise des prix : \(k.remise == true ? "oui" : k.remise == false ? "non" : "pas connue")")
                                .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                        }
                    }
                    champ("Prix (€)") {
                        TextField("", text: Binding(get: { prixTexte }, set: { t in
                            prixTexte = t
                            if let v = Double(t.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")) { ouverte?.prix = v }
                        })).textFieldStyle(.roundedBorder).frame(width: 120)
                    }
                    champ("Téléphone") { TextField("", text: lien(\.telephone)).textFieldStyle(.roundedBorder) }
                    champ("Mail") { TextField("", text: lien(\.mail)).textFieldStyle(.roundedBorder) }
                    champ("Règlement") {
                        Picker("", selection: lien(\.reglement)) { ForEach(Commande.Reglement.allCases) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 360)
                    }
                    champ("Statut") {
                        Picker("", selection: lien(\.statut)) { ForEach(Commande.Statut.allCases) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 300)
                    }
                    champ("Note") { TextField("", text: lien(\.note), axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder) }
                    HStack {
                        Button("Enregistrer les changements") {
                            if let n = ouverte { archives.enregistrer(n); message = "Commande de \(n.client) enregistrée." }
                        }
                        .buttonStyle(BoutonStyle(principal: true)).keyboardShortcut(.defaultAction)
                        Button("Fermer") { ouverte = nil }.buttonStyle(BoutonStyle())
                        Spacer()
                        Button("Supprimer (corbeille)") { archives.supprimer(k); ouverte = nil }.buttonStyle(BoutonStyle())
                    }
                    if !message.isEmpty { Text(message).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret) }
                }
            }
            .padding(24)
        }
    }

    private static let vide = Commande(concours: "", nomConcours: "", nom: "", prenom: "", lignes: [], prix: 0)

    private func lien<T>(_ k: WritableKeyPath<Commande, T>) -> Binding<T> {
        Binding(get: { (ouverte ?? CommandesView.vide)[keyPath: k] }, set: { ouverte?[keyPath: k] = $0 })
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
