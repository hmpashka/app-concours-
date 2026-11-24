import SwiftUI
import TriPhotoCommun

/// Maquette « Nouvelle commande » (24/11) : chercher le client, toucher ses passages (chevaux, épreuves) d'UN concours,
/// remise des prix cochée toute seule si classé (sinon oui / non), prix d'après le tarif du concours, infos client,
/// ENREGISTRER. En bas, les commandes du concours (toucher le statut le fait avancer).
struct CommandesPisteView: View {
    @EnvironmentObject var liaison: Liaison
    @Environment(\.dismiss) private var fermer
    @State private var texte = ""
    @State private var choix: [String: Participation] = [:]       // passages touchés, par id
    @State private var client: ClientTrouve?
    @State private var prix = ""
    @State private var prixTouche = false
    @State private var telephone = ""
    @State private var mail = ""
    @State private var reglement: Commande.Reglement = .cb
    @State private var statut: Commande.Statut = .aFaire
    @State private var note = ""
    @State private var info = ""
    @FocusState private var clavier: Bool

    private var concours: String? { choix.values.first?.concours }

    var body: some View {
        ZStack {
            Style.fond
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(choix.values.first?.nomConcours ?? "Pack photo").font(.system(size: 13)).foregroundStyle(Style.cremeDiscret)
                        Text("NOUVELLE").font(Style.titre(38)).foregroundStyle(Style.creme)
                        Text("COMMANDE").font(Style.titre(38)).foregroundStyle(Style.or)
                    }
                    Spacer()
                    Button { fermer() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Style.creme)
                            .frame(width: 44, height: 44).background(Style.voile.opacity(0.08), in: Circle())
                    }
                }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        recherche
                        if !liaison.connecte {
                            Text("Groom Pix pas joint : la recherche a besoin du Mac.").font(.system(size: 13)).foregroundStyle(Style.orangeClair)
                        }
                        ForEach(liaison.clients) { c in resultats(c) }
                        if liaison.clients.isEmpty && liaison.rechercheFaite.count >= 2 && texte == liaison.rechercheFaite {
                            Text("Personne trouvé dans les listings gardés.").font(.system(size: 13)).foregroundStyle(Style.cremeDiscret)
                        }
                        if !choix.isEmpty { formulaire; boutonEnregistrer }
                        if !info.isEmpty {
                            Text(info).font(.system(size: 14, weight: .semibold)).foregroundStyle(Style.vertTexte)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !liaison.commandes.isEmpty { dejaPrises }
                    }
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboardCompat()
            }
            .padding(.horizontal, 18).padding(.top, 14)
        }
        .foregroundStyle(Style.creme)
        .onChange(of: texte) { t in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if t == texte { liaison.chercher(client: t) } }
        }
    }

    // MARK: - Recherche

    private var recherche: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Style.cremeDiscret)
            TextField("", text: $texte, prompt: Text("Nom, prénom ou cheval").foregroundColor(Style.cremeDiscret))
                .font(.system(size: 19)).foregroundStyle(Style.creme)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .focused($clavier)
            if !texte.isEmpty {
                Button { texte = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Style.cremeDiscret) }
            }
        }
        .padding(.horizontal, 16).frame(minHeight: 54)
        .background(Style.voile.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }

    /// Les passages du client : concours le plus récent d'abord ; on n'en garde qu'un par commande.
    private func resultats(_ c: ClientTrouve) -> some View {
        ForEach(c.participations) { p in
            let coche = choix[p.id] != nil
            Button { toucher(p, de: c) } label: {
                Bloc(bord: coche ? Style.or : Style.voile.opacity(0.10), fond: coche ? Style.or.opacity(0.14) : Style.voile.opacity(0.06),
                     largeurBord: coche ? 2 : 1) {
                    VStack(alignment: .leading, spacing: 5) {
                        (Text("\(c.nom) \(c.prenom)").fontWeight(.bold) + Text(" · \(p.cheval)"))
                            .font(.system(size: 17)).foregroundStyle(Style.creme)
                        Text("\(p.nomConcours) · \(p.epreuve) \(p.nomEpreuve)").font(.system(size: 14))
                            .foregroundStyle(Style.cremeDiscret).lineLimit(2).multilineTextAlignment(.leading)
                        HStack(spacing: 10) {
                            remise(p, coche: coche)
                            if let n = p.photos { Text("\(n) photo\(n > 1 ? "s" : "")").font(.system(size: 16)).foregroundStyle(Style.creme) }
                            Spacer()
                            Image(systemName: coche ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22)).foregroundStyle(coche ? Style.or : Style.fleche)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func remise(_ p: Participation, coche: Bool) -> some View {
        let r = choix[p.id]?.remise ?? p.remise
        if p.remise != nil || !coche {
            if r == true {
                Label("Remise des prix", systemImage: "checkmark").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Style.nuit).padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Style.or, in: RoundedRectangle(cornerRadius: 7))
            }
        } else {
            // pas de résultats connus : oui / non à la main
            HStack(spacing: 4) {
                Text("Remise ?").font(.system(size: 13)).foregroundStyle(Style.cremeDiscret)
                ForEach([true, false], id: \.self) { v in
                    Button(v ? "Oui" : "Non") { choix[p.id]?.remise = (r == v ? nil : v); recalculer() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(r == v ? Style.nuit : Style.creme)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(r == v ? Style.or : Style.voile.opacity(0.10), in: Capsule())
                }
            }
        }
    }

    private func toucher(_ p: Participation, de c: ClientTrouve) {
        clavier = false
        info = ""
        if choix[p.id] != nil {
            choix[p.id] = nil
        } else {
            if (concours != nil && concours != p.concours) || (client != nil && client?.id != c.id) {
                choix = [:]                                        // une commande = un client, un concours
                prixTouche = false
            }
            choix[p.id] = p
            client = c
        }
        if choix.isEmpty { client = nil }
        recalculer()
    }

    private var commande: Commande? {
        guard let c = client else { return nil }
        let l = c.participations.compactMap { choix[$0.id] }          // dans l'ordre de la liste
        return Commande.nouvelle(c, choix: l, par: liaison.nom)
    }

    private func recalculer() {
        guard !prixTouche, let k = commande else { return }
        prix = Commande.euros(k.prix).replacingOccurrences(of: " €", with: "")
    }

    // MARK: - Formulaire

    private var formulaire: some View {
        Bloc(marge: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
            VStack(alignment: .leading, spacing: 12) {
                if let k = commande {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pack · prix").font(.system(size: 14)).foregroundStyle(Style.cremeDiscret)
                        HStack(spacing: 6) {
                            Text(k.chevaux.count <= 1 ? "Pack \(k.chevaux.first ?? "")" : "Pack \(k.chevaux.count) chevaux")
                                .font(.system(size: 18, weight: .bold)).lineLimit(1)
                            Text("·").font(.system(size: 18, weight: .bold))
                            champ($prix, "Prix", clavier: .decimalPad).frame(width: 90)
                                .onChange(of: prix) { _ in prixTouche = prix != (commande.map { Commande.euros($0.prix).replacingOccurrences(of: " €", with: "") } ?? "") }
                            Text("€").font(.system(size: 18, weight: .bold))
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Téléphone · mail").font(.system(size: 14)).foregroundStyle(Style.cremeDiscret)
                    champ($telephone, "06 00 00 00 00", clavier: .phonePad)
                    champ($mail, "client@exemple.fr", clavier: .emailAddress)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Règlement · statut").font(.system(size: 14)).foregroundStyle(Style.cremeDiscret)
                    pastilles(Commande.Reglement.allCases, $reglement)
                    pastilles(Commande.Statut.allCases, $statut)
                }
                champ($note, "Note (facultatif)")
            }
        }
    }

    private func champ(_ t: Binding<String>, _ aide: String, clavier: UIKeyboardType = .default) -> some View {
        TextField("", text: t, prompt: Text(aide).foregroundColor(Style.fleche))
            .keyboardType(clavier).autocorrectionDisabled().textInputAutocapitalization(.never)
            .font(.system(size: 18)).foregroundStyle(Style.creme)
            .padding(.horizontal, 10).frame(minHeight: 40)
            .background(Style.voile.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            .focused($clavier)
    }

    private func pastilles<T: Hashable & Identifiable & RawRepresentable>(_ l: [T], _ v: Binding<T>) -> some View where T.RawValue == String {
        HStack(spacing: 6) {
            ForEach(l) { x in
                Button(x.rawValue) { v.wrappedValue = x }
                    .font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundStyle(v.wrappedValue == x ? Style.nuit : Style.creme)
                    .padding(.horizontal, 10).frame(minHeight: 34)
                    .background(v.wrappedValue == x ? Style.or : Style.voile.opacity(0.08), in: Capsule())
            }
        }
    }

    private var boutonEnregistrer: some View {
        Button {
            guard var k = commande else { return }
            if let v = Double(prix.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")) { k.prix = v }
            k.telephone = telephone.trimmingCharacters(in: .whitespaces)
            k.mail = mail.trimmingCharacters(in: .whitespaces)
            k.reglement = reglement
            k.statut = statut
            k.note = note
            liaison.enregistrer(k)
            info = liaison.connecte ? "Commande de \(k.client) envoyée au stand (\(Commande.euros(k.prix)))."
                                    : "Commande de \(k.client) gardée : elle partira dès que Groom Pix sera joint."
            vider()
        } label: {
            Text("ENREGISTRER").font(Style.titre(26)).foregroundStyle(Style.nuit)
                .frame(maxWidth: .infinity, minHeight: 60).background(Style.or, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(commande == nil)
    }

    private func vider() {
        choix = [:]; client = nil; prix = ""; prixTouche = false
        telephone = ""; mail = ""; reglement = .cb; statut = .aFaire; note = ""; texte = ""
        clavier = false
    }

    // MARK: - Commandes déjà prises (ce concours)

    private var dejaPrises: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMMANDES DU CONCOURS").font(Style.titre(20)).foregroundStyle(Style.or).padding(.top, 8)
            ForEach(liaison.commandes) { k in
                Bloc {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(k.client) · \(Commande.euros(k.prix))").font(.system(size: 16, weight: .semibold))
                            Text(k.chevaux.joined(separator: " · ") + (k.telephone.isEmpty ? "" : " · \(k.telephone)"))
                                .font(.system(size: 13)).foregroundStyle(Style.cremeDiscret).lineLimit(1)
                        }
                        Spacer()
                        Button {
                            var n = k
                            let tous = Commande.Statut.allCases
                            n.statut = tous[((tous.firstIndex(of: k.statut) ?? 0) + 1) % tous.count]
                            liaison.enregistrer(n)
                        } label: {
                            Text(k.statut.rawValue).font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(k.statut == .envoye ? Style.vertTexte : k.statut == .aFaire ? Style.orangeClair : Style.creme)
                                .padding(.horizontal, 10).frame(minHeight: 32)
                                .background(Style.voile.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("Toucher le statut le fait avancer : à faire › en cours › envoyé.").font(.system(size: 12)).foregroundStyle(Style.cremeDiscret)
        }
    }
}

private extension View {
    @ViewBuilder
    func scrollDismissesKeyboardCompat() -> some View {
        if #available(iOS 16.0, *) { scrollDismissesKeyboard(.interactively) } else { self }
    }
}
