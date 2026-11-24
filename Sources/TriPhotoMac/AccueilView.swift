import AppKit
import SwiftUI
import TriPhotoCommun
import TriPhotoMoteur

/// Accueil / tableau de bord (maquette 1), version étape 1 : chiffres du tri, boîtiers, photos à renvoyer,
/// dernières photos. Les pistes, épreuves en cours et heures de fin arrivent avec le chrono (étape 2).
struct AccueilView: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var moteur: Moteur
    @State private var comparer: FichePhoto?

    private var r: ResumeMoteur { moteur.resume }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !moteur.actif {
                        Carte(titre: "Le tri n'est pas démarré") {
                            HStack {
                                Text("Vérifie les réglages, puis démarre la journée.")
                                    .font(.system(size: 13)).foregroundStyle(Theme.texteDiscret)
                                Spacer()
                                Button("Démarrer la journée") { etat.demarrerJournee() }
                                    .buttonStyle(BoutonStyle(principal: true))
                            }
                            if let e = etat.erreurDemarrage {
                                Text(e).font(.system(size: 12)).foregroundStyle(Theme.erreur)
                            }
                        }
                    }
                    chiffres
                    if !r.alertes.isEmpty { alertes }
                    if r.chrono != nil { enPiste }
                    if !r.doublons.isEmpty { doublons }
                    if !r.photosParCode.isEmpty { courbe }
                    boitiers
                    recentes
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity)
            if etat.panneauDroit {
                Divider().overlay(Theme.bordure)
                panneauDroit.frame(width: 300).background(Theme.panneau)
            }
        }
        .sheet(item: $comparer) { f in ComparerDoublon(doublon: f, moteur: moteur) }
    }

    // MARK: - Chiffres

    private var chiffres: some View {
        HStack(spacing: 12) {
            Tuile(titre: "Photos reçues aujourd'hui", valeur: "\(r.recues)",
                  detail: "\(Int(r.parMinute.rounded())) par minute en ce moment")
            Tuile(titre: "File d'attente", valeur: "\(r.enFile)",
                  detail: r.enFile == 0 ? "Aucun retard" : "Retard : \(Self.duree(r.retardSecondes))",
                  alerte: r.retardSecondes > 60)
            Tuile(titre: "Photos à renvoyer", valeur: "\(r.aRenvoyer.count)",
                  detail: r.aRenvoyer.isEmpty ? "Tout est bien arrivé" : r.aRenvoyer.prefix(3).map(\.origine).joined(separator: ", "),
                  alerte: !r.aRenvoyer.isEmpty)
            Tuile(titre: "À valider", valeur: "\(r.aValider)",
                  detail: r.series.isEmpty ? "Rien en attente" : "\(r.series.count) série\(r.series.count > 1 ? "s" : "")"
                      + (r.enAttenteChrono > 0 ? " · \(r.enAttenteChrono) en attente du chrono" : ""),
                  alerte: !r.series.isEmpty)
            if etat.reglages.tamponActif {
                Tuile(titre: "Dossier tampon", valeur: "\(r.dansTampon)", detail: "en attente du lot pour Lightroom")
            }
        }
    }

    // MARK: - Alertes, en piste, courbe

    private var alertes: some View {
        Carte(titre: "À regarder") {
            ForEach(r.alertes, id: \.self) { a in
                Text(a).font(.system(size: 12)).foregroundStyle(Theme.attention)
            }
        }
    }

    private var enPiste: some View {
        Carte(titre: "En piste", sousTitre: chronoTexte) {
            if r.enPiste.isEmpty {
                Text("Aucun passage pour l'instant.").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
            }
            ForEach(r.enPiste) { e in
                HStack {
                    Text(e.piste.isEmpty ? "Piste" : e.piste).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                        .frame(width: 110, alignment: .leading)
                    Text("Épreuve \(e.passage.epreuve) · n° \(e.passage.dossard)").font(.system(size: 13, weight: .semibold))
                    Text([e.passage.cavalier, e.passage.cheval].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret).lineLimit(1)
                    Spacer()
                    Pastille(texte: e.termine ? "terminé" : "en piste", genre: e.termine ? .neutre : .ok)
                }
            }
        }
    }

    private var chronoTexte: String {
        guard let c = r.chrono else { return "" }
        let nom = etat.reglages.chronometrage.rawValue
        switch c.ok {
        case .none: return "\(nom) : en attente…"
        case .some(true): return "\(nom) · \(c.passages) passages\(c.erreur.isEmpty ? "" : " · " + c.erreur)"
        case .some(false): return c.erreur
        }
    }

    private var courbe: some View {
        let plusHaut = r.photosParCode.map { $0.photos }.max() ?? 1
        let tri = r.photosParCode.map { $0.photos }.sorted()
        let mediane = tri.isEmpty ? 0 : tri[tri.count / 2]
        return Carte(titre: "Photos par cavalier · épreuve \(r.epreuveCourbe)",
                     sousTitre: "Même nombre de photos à peu près pour chacun : tout va bien. Une barre orange : à regarder.") {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(r.photosParCode, id: \.code) { p in
                    let ecart = mediane > 0 && (Double(p.photos) > Double(mediane) * 2 || Double(p.photos) < Double(mediane) / 2)
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(ecart ? Theme.orange : Theme.accent)
                            .frame(width: 12, height: plusHaut > 0 ? CGFloat(p.photos) / CGFloat(plusHaut) * 70 + 2 : 2)
                            .help("\(p.code) : \(p.photos) photos")
                    }
                }
            }
            .frame(height: 76, alignment: .bottom)
        }
    }

    // MARK: - Doublons

    private var doublons: some View {
        Carte(titre: "Doublons à décider (\(r.doublons.count))",
              sousTitre: "Même nom qu'une photo déjà reçue. Rien n'est envoyé à Lightroom ni au serveur tant que tu n'as pas choisi.") {
            ForEach(r.doublons.prefix(30), id: \.id) { f in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.origine).font(.system(size: 12, design: .monospaced))
                        Text("\(f.code.isEmpty ? "sans code" : f.code) · \(f.boitier)")
                            .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
                    }
                    Spacer()
                    Button("Voir") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f.chemin)]) }
                        .buttonStyle(BoutonStyle())
                    Button("Comparer…") { comparer = f }.buttonStyle(BoutonStyle(principal: true))
                    Button("Garder (autre nom)") { moteur.garderDoublon(f) }.buttonStyle(BoutonStyle())
                    Button("Jeter") { moteur.jeterDoublon(f) }.buttonStyle(BoutonStyle())
                }
            }
        }
    }

    // MARK: - Boîtiers

    private var boitiers: some View {
        Carte(titre: "Boîtiers", sousTitre: "\(r.boitiers.count) boîtier\(r.boitiers.count > 1 ? "s" : "") aujourd'hui") {
            Button("Synchroniser les boîtiers (photo du QR)…") { etat.montrerSynchro = true }.buttonStyle(BoutonStyle())
            if r.boitiers.isEmpty {
                Text("Aucune photo reçue pour l'instant.").font(.system(size: 13)).foregroundStyle(Theme.texteDiscret)
            }
            ForEach(r.boitiers) { b in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(b.nomAffiche).font(.system(size: 13))
                        if let s = b.synchro {
                            Text([s.piste, s.photographe, s.ecartTexte].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
                        } else {
                            Text("pas de photo de synchro").font(.system(size: 11)).foregroundStyle(Theme.attention)
                        }
                    }
                    Spacer()
                    Text("\(b.photos) photos").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                    if let d = b.derniere {
                        let silence = Date().timeIntervalSince(d)
                        Pastille(texte: silence < 300 ? "dernière il y a \(Self.duree(silence))" : "silencieux depuis \(Self.duree(silence))",
                                 genre: silence < 300 ? .ok : .attention)
                    }
                }
            }
        }
    }

    // MARK: - Dernières photos

    private var recentes: some View {
        Carte(titre: "Dernières photos reçues", sousTitre: "Nom · code · boîtier") {
            ForEach(r.recentes) { p in
                HStack {
                    Text(p.nom).font(.system(size: 12, design: .monospaced))
                    Text(p.code.isEmpty ? "sans code" : p.code)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(p.code.isEmpty ? Theme.attention : Theme.texte)
                    Spacer()
                    Text(p.boitier).font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
                    Pastille(texte: Self.libelle(p.etat), genre: p.etat == .envoyee ? .ok : [.erreur, .aRenvoyer, .doublon, .aValider].contains(p.etat) ? .attention : .neutre)
                }
            }
        }
    }

    // MARK: - Panneau de droite

    private var panneauDroit: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Régulateur").font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text("Lightroom : \(Int((r.chargeLightroom * 100).rounded())) % du Mac").font(.system(size: 13))
                Text("Photos traitées en même temps : \(r.ouvriers)").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                Text(RegleRegulateur.lightroomOccupe(chargeLightroom: r.chargeLightroom)
                     ? "Lightroom travaille : Tri-photo ralentit, reprise automatique."
                     : "Lightroom est calme : Tri-photo va à pleine vitesse.")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
            }
            Divider().overlay(Theme.bordure)
            Text("Photos à renvoyer").font(.system(size: 14, weight: .semibold))
            if r.aRenvoyer.isEmpty {
                Text("Aucune.").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
            } else {
                Text("Mal transférées : à redemander au boîtier sous leur nom d'origine. Elles sont dans « _À renvoyer » du dossier de réception ; supprime-les une fois renvoyées.")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
                ForEach(r.aRenvoyer.prefix(20), id: \.id) { f in
                    HStack {
                        Text(f.origine).font(.system(size: 12, design: .monospaced))
                        Spacer()
                        Text(f.boitier).font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
                    }
                }
            }
            if r.enErreur > 0 || !r.message.isEmpty {
                Divider().overlay(Theme.bordure)
                Text("Dernier message").font(.system(size: 14, weight: .semibold))
                if r.enErreur > 0 {
                    Text("\(r.enErreur) photo\(r.enErreur > 1 ? "s" : "") en erreur, nouvel essai automatique.")
                        .font(.system(size: 12)).foregroundStyle(Theme.attention)
                }
                Text(r.message).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
            }
            Spacer()
            if moteur.actif {
                Button("Arrêter le tri") { etat.arreterJournee() }.buttonStyle(BoutonStyle())
            }
        }
        .padding(16)
    }

    // MARK: - Outils

    static func duree(_ s: Double) -> String {
        if s < 60 { return "\(Int(s)) s" }
        if s < 3600 { return "\(Int(s / 60)) min" }
        return "\(Int(s / 3600)) h \(Int(s.truncatingRemainder(dividingBy: 3600) / 60)) min"
    }

    static func libelle(_ e: EtatPhoto) -> String {
        switch e {
        case .recue: return "reçue"
        case .copiee: return "copiée"
        case .tampon: return "tampon"
        case .envoyee: return "Lightroom"
        case .aRenvoyer: return "à renvoyer"
        case .erreur: return "erreur"
        case .doublon: return "doublon"
        case .ecartee: return "jetée"
        case .aValider: return "à valider"
        case .photoCode: return "photo de code"
        case .retiree: return "retirée"
        case .synchro: return "synchro"
        }
    }
}

/// Grand chiffre de l'accueil.
struct Tuile: View {
    var titre: String
    var valeur: String
    var detail: String
    var alerte = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
            Text(valeur).font(.system(size: 28, weight: .semibold)).foregroundStyle(alerte ? Theme.attention : Theme.texte)
            Text(detail).font(.system(size: 11)).foregroundStyle(Theme.texteDiscret).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.carte, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(alerte ? Theme.attention.opacity(0.5) : Theme.bordure, lineWidth: 1))
    }
}
