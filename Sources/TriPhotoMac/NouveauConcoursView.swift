import AppKit
import SwiftUI
import TriPhotoMoteur

/// Fenêtre « Commencer un nouveau concours » (maquette nouveau-concours.png validée par HUGO le 26/11/2026) :
/// ce qui n'est pas fini, ce qui repart à zéro, ce qui est gardé. Sert aussi à rouvrir un concours rangé.
struct NouveauConcoursView: View {
    @EnvironmentObject var etat: Etat
    var demande: DemandeNouveauConcours
    @Environment(\.dismiss) private var fermer

    @State private var bilan = BilanConcours()
    @State private var envoyerAValider = true
    @State private var enCours = false
    @State private var avancement = ""
    @State private var fini = ""
    @State private var erreur = ""
    @StateObject private var arret = Drapeau()
    private let minuterie = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    final class Drapeau: ObservableObject { @Published var leve = false }

    private var aRouvrir: ConcoursRange? {
        if case .rouvrir(let c) = demande { return c }
        return nil
    }
    private var rienEnCours: Bool {
        etat.concours == nil && etat.reglages.cheminFFE.isEmpty && !etat.moteur.actif && bilan.rien && bilan.photos == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(aRouvrir.map { "Rouvrir « \($0.nom) »" } ?? "Commencer un nouveau concours")
                        .font(.system(size: 19, weight: .bold))
                    Text(intro).font(.system(size: 13)).foregroundStyle(Theme.texteDiscret)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !enCours { Button(fini.isEmpty ? "Annuler" : "Fermer") { fermer() }.buttonStyle(BoutonStyle()).keyboardShortcut(.cancelAction) }
            }

            if fini.isEmpty {
                if !rienEnCours {
                    bloc(titre: "⚠ Pas fini dans ce concours", couleur: Theme.attention) {
                        if bilan.rien {
                            ligne("checkmark", Theme.ok, "Tout est fini", "Plus aucune photo en route.")
                        }
                        if let g = bilan.galerie, g > 0 {
                            ligne("exclamationmark", Theme.attention, "Galerie : \(g) photo\(g > 1 ? "s" : "") pas encore envoyée\(g > 1 ? "s" : "")",
                                  "Elles attendent, rien n'est perdu. Rouvre le concours plus tard pour les envoyer.")
                        } else if !bilan.triEnCours {
                            ligne("info", Theme.texteDiscret, "Galerie", "Son suivi est rangé avec le concours : en le rouvrant, l'envoi reprend où il en était.")
                        }
                        if bilan.aValider > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                ligne("exclamationmark", Theme.attention, "À valider : \(bilan.aValider) photo\(bilan.aValider > 1 ? "s" : "")", nil)
                                Picker("", selection: $envoyerAValider) {
                                    Text("Les envoyer à Lightroom maintenant avec le code du photographe (comme le rush)").tag(true)
                                    Text("Les laisser de côté, dans « Restes – \(bilan.nom) » (dossier de réception)").tag(false)
                                }
                                .pickerStyle(.radioGroup).labelsHidden().font(.system(size: 12))
                                .padding(.leading, 26)
                                .disabled(!bilan.triEnCours)
                                if !bilan.triEnCours {
                                    Text("Le tri est arrêté : elles sont mises de côté (« Démarrer » d'abord pour les envoyer).")
                                        .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret).padding(.leading, 26)
                                }
                            }
                        }
                        if bilan.tampon > 0 {
                            ligne("exclamationmark", Theme.attention, "Dossier tampon : \(bilan.tampon) photo\(bilan.tampon > 1 ? "s" : "")",
                                  "Envoyées à Lightroom tout de suite, comme à la clôture.")
                        }
                        if bilan.reception > 0 {
                            ligne("exclamationmark", Theme.attention, "Réception : \(bilan.reception) photo\(bilan.reception > 1 ? "s" : "") pas finie\(bilan.reception > 1 ? "s" : "")",
                                  "Pas encore triées, doublons, photos de code… Rangées dans « Restes – \(bilan.nom) » pour ne pas se mélanger au nouveau concours.")
                        }
                    }
                }

                bloc(titre: "↺ Remis à zéro" + (aRouvrir == nil ? " pour le nouveau concours" : ""), couleur: Theme.accent) {
                    grille([
                        "Fichier FFE, nom et jours du concours", "Accueil, À valider, Revue : vides",
                        "Engagés terrain", "Suivi de la galerie (repart de 0)",
                        "Synchro QR des boîtiers", "Remises des prix, passages capturés",
                        "Messages des iPhone", "Épreuve choisie à la main sur les chronos",
                    ], symbole: "arrow.counterclockwise", couleur: Theme.accent)
                }

                bloc(titre: "✓ Gardé tel quel", couleur: Theme.ok) {
                    Label("La Mémoire (apprentissage) : jamais touchée", systemImage: "checkmark")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ok)
                    grille([
                        "Tous les réglages : dossiers, serveur, galerie, chronos, UDM", "Pistes, photographes, iPhone connus",
                        "Modèles, commandes, listings, raccourcis, licence", "Fichiers de début et de fin déjà écrits",
                        "Photos originales, Lightroom, serveur local, galerie en ligne : rien n'est effacé",
                    ], symbole: "checkmark", couleur: Theme.ok)
                }
            } else {
                bloc(titre: "✓ C'est fait", couleur: Theme.ok) {
                    Text(fini).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                }
            }

            if !erreur.isEmpty { Text(erreur).font(.system(size: 12)).foregroundStyle(Theme.erreur) }

            HStack(spacing: 10) {
                if enCours {
                    ProgressView().controlSize(.small)
                    Text(avancement.isEmpty ? "Rangement…" : avancement).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                    Spacer()
                    if bilan.triEnCours && !arret.leve {
                        Button("Ranger sans attendre") { arret.leve = true }.buttonStyle(BoutonStyle())
                            .help("Les photos encore en route vont dans « Restes – … » au lieu d'attendre Lightroom.")
                    }
                } else if fini.isEmpty {
                    Text(aRouvrir == nil ? "Le tri s'arrête ; tu charges le nouveau fichier FFE puis « Démarrer »."
                                         : "Le concours en cours est d'abord rangé de la même façon.")
                        .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                    Spacer()
                    Button(boutonPrincipal) { lancer() }.buttonStyle(BoutonStyle(principal: true)).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22)
        .frame(width: 760)
        .background(Theme.fond)
        .onAppear { bilan = etat.bilanConcours() }
        .onReceive(minuterie) { _ in if !enCours && fini.isEmpty { bilan = etat.bilanConcours() } }
    }

    private var intro: String {
        let pasFini = !bilan.rien
        let debut = rienEnCours ? "Aucun concours en cours."
            : "« \(bilan.nom) »" + (pasFini ? " n'est pas fini à 100 %." : " est fini.")
            + " Rien n'est effacé : il est rangé dans « Concours rangés » avec tout son suivi, et tu pourras le rouvrir pour le finir (galerie, fichier de fin…)."
        if let c = aRouvrir { return debut + " Puis « \(c.nom) » revient tel qu'il était rangé." }
        return debut
    }

    private var boutonPrincipal: String {
        if let c = aRouvrir { return rienEnCours ? "Rouvrir « \(c.nom) »" : "Ranger ce concours et rouvrir « \(c.nom) »" }
        return "Ranger ce concours et repartir à zéro"
    }

    private func lancer() {
        enCours = true
        erreur = ""
        let drapeau = arret
        Task { @MainActor in
            var range: ConcoursRange?
            if !rienEnCours {
                range = await etat.rangerConcours(envoyerAValider: envoyerAValider && bilan.triEnCours,
                                                  sansAttendre: { drapeau.leve },
                                                  avancement: { avancement = $0 })
            }
            var texte = ""
            if let r = range {
                texte = "« \(r.nom) » est rangé."
                if r.restes > 0 { texte += " \(r.restes) photo\(r.restes > 1 ? "s" : "") mise\(r.restes > 1 ? "s" : "") de côté dans « \((r.dossierRestes as NSString).lastPathComponent) »." }
            }
            if let c = aRouvrir {
                avancement = "Réouverture de « \(c.nom) »…"
                if let e = await etat.rouvrir(c) {
                    erreur = "Réouverture impossible : \(e)"
                } else {
                    texte += (texte.isEmpty ? "" : " ") + "« \(c.nom) » est rouvert : vérifie les réglages puis « Démarrer » pour le finir."
                }
            } else {
                texte += (texte.isEmpty ? "" : " ") + "L'app est à zéro : charge le nouveau fichier FFE puis « Démarrer »."
            }
            fini = texte
            enCours = false
        }
    }

    // MARK: - Morceaux

    private func bloc<C: View>(titre: String, couleur: Color, @ViewBuilder _ contenu: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titre.uppercased()).font(.system(size: 11, weight: .semibold)).kerning(0.8).foregroundStyle(couleur)
            contenu()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.carte))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.bordure))
    }

    private func ligne(_ symbole: String, _ couleur: Color, _ titre: String, _ detail: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbole).foregroundStyle(couleur).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(titre).font(.system(size: 13, weight: .semibold))
                if let d = detail {
                    Text(d).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func grille(_ textes: [String], symbole: String, couleur: Color) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                  alignment: .leading, spacing: 6) {
            ForEach(textes, id: \.self) { t in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: symbole).font(.system(size: 11)).foregroundStyle(couleur).frame(width: 14)
                    Text(t).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Réglages › 1. Concours : bouton « Nouveau concours… » et la liste des concours rangés à rouvrir.
struct ConcoursRangesView: View {
    @EnvironmentObject var etat: Etat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nouveau concours").font(.system(size: 13, weight: .semibold))
                    Text("Range le concours en cours (même pas fini, rien n'est effacé) et repart à zéro. La Mémoire n'est jamais touchée.")
                        .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
                }
                Spacer()
                Button("↺ Nouveau concours…") { etat.nouveauConcours = .nouveau }.buttonStyle(BoutonStyle())
            }
            if !etat.concoursRanges.isEmpty {
                Text("Concours rangés (sur ce Mac, à rouvrir pour les finir)").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                ForEach(etat.concoursRanges) { c in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.nom).font(.system(size: 13, weight: .semibold))
                            Text(details(c)).font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
                        }
                        Spacer()
                        Text(etiquette(c))
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(c.pasFini ? Theme.attentionFond : Theme.okFond))
                            .foregroundStyle(c.pasFini ? Theme.attention : Theme.ok)
                        Button("Rouvrir") { etat.nouveauConcours = .rouvrir(c) }.buttonStyle(BoutonStyle())
                        Button { NSWorkspace.shared.activateFileViewerSelecting([c.dossier]) } label: { Image(systemName: "folder") }
                            .buttonStyle(BoutonPlat()).help("Voir le dossier du concours rangé")
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.carte))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.bordure))
                }
            }
        }
    }

    private func details(_ c: ConcoursRange) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d/MM"
        var t = Calendar.current.isDate(c.debut, inSameDayAs: c.fin) ? f.string(from: c.debut) : "\(f.string(from: c.debut)) → \(f.string(from: c.fin))"
        if let p = c.photos { t += " · \(p) photos" }
        t += " · rangé le " + c.rangeLe.formatted(date: .abbreviated, time: .shortened)
        return t
    }

    private func etiquette(_ c: ConcoursRange) -> String {
        var l: [String] = []
        if let g = c.galerieRestantes, g > 0 { l.append("galerie : \(g) pas envoyées") }
        if c.restes > 0 { l.append("\(c.restes) mises de côté") }
        return l.isEmpty ? "fini" : l.joined(separator: " · ")
    }
}
