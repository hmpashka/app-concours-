import SwiftUI
import TriPhotoCommun
import TriPhotoMoteur

/// Clôture : un bouton pour dire que la journée (ou le concours) est finie, et être sûr qu'aucune photo n'est encore
/// en route. L'app vide le tampon vers Lightroom, attend les photos en cours, met la galerie en ligne à jour, puis
/// (clôture finale) écrit le fichier d'attribution de fin et les statistiques. Rien n'est demandé deux fois.
struct ClotureView: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var moteur: Moteur
    var genre: GenreCloture
    @Environment(\.dismiss) private var fermer

    @State private var e = EtatCloture()
    @State private var fichiers: [URL] = []
    @State private var fini = false
    @State private var terrain = false
    private let minuterie = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var galerieReglee: Bool { !etat.reglages.adresseFTPGalerie.isEmpty }
    private var galerieAFaire: Int { e.galerie?.aFaire ?? 0 }
    /// Journée d'un concours de plusieurs jours, envoi de nuit : la galerie peut attendre la nuit.
    private var galerieCetteNuit: Bool { genre == .journee && etat.reglages.galerieLaNuit && (e.galerie?.attendLaNuit ?? false) }
    private var photosEnRoute: Bool { e.enReception > 0 || e.dansTampon > 0 }
    private var toutEstParti: Bool { !photosEnRoute && (!galerieReglee || galerieAFaire == 0 || galerieCetteNuit) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(genre.rawValue).font(.system(size: 18, weight: .semibold))
                    Text(genre == .finale ? "Dernier jour : tout part, puis le fichier d'attribution de fin est écrit."
                                          : "Fin de journée : on vérifie que plus aucune photo n'est en route.")
                        .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                }
                Spacer()
                Button("Fermer") { fermer() }.buttonStyle(BoutonStyle()).keyboardShortcut(.cancelAction)
            }

            Carte {
                ligne(ok: e.enReception == 0, titre: "Photos des boîtiers traitées",
                      detail: e.enReception == 0 ? "Plus rien dans le dossier de réception."
                                                 : "\(e.enReception) photo\(e.enReception > 1 ? "s" : "") en cours ou en attente du chrono.")
                ligne(ok: e.dansTampon == 0, titre: "Dossier tampon vidé vers Lightroom",
                      detail: e.dansTampon == 0 ? "Tout est dans Lightroom." : "\(e.dansTampon) photos partent à Lightroom…")
                ligne(ok: e.aValider == 0, attention: e.aValider > 0, titre: "Photos à valider",
                      detail: e.aValider == 0 ? "Aucune." : "\(e.aValider) photos attendent ta décision dans « À valider » : elles ne partent pas avant.")
                if e.enErreur > 0 {
                    ligne(ok: false, attention: true, titre: "Photos en erreur",
                          detail: "\(e.enErreur) photos n'ont pas pu partir (serveur absent ?). Elles sont retentées toutes seules.")
                }
                if galerieReglee {
                    ligne(ok: galerieAFaire == 0, attention: galerieCetteNuit, titre: "Galerie en ligne",
                          detail: texteGalerie)
                    if galerieAFaire > 0 {
                        Button(galerieCetteNuit ? "Envoyer maintenant au lieu de cette nuit" : "Relancer l'envoi") {
                            moteur.envoyerGalerieMaintenant()
                        }
                        .buttonStyle(BoutonStyle())
                    }
                } else {
                    ligne(ok: true, titre: "Galerie en ligne", detail: "Pas réglée (Réglages › 5. Envois) : rien à envoyer.")
                }
            }

            if genre == .finale {
                Carte(titre: "Fichier d'attribution de fin et statistiques") {
                    Text("Format HMV, avec les \(etat.engagesTerrain.count) engagés terrain. Écrit dans « \(etat.dossierAttribution.path) ».")
                        .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                    HStack {
                        Button(toutEstParti ? "Écrire le fichier de fin" : "Écrire le fichier de fin sans attendre") { ecrireFin() }
                            .buttonStyle(BoutonStyle(principal: toutEstParti))
                        Button("Engagés terrain…") { terrain = true }.buttonStyle(BoutonStyle())
                        ForEach(fichiers, id: \.self) { u in
                            Button(u.lastPathComponent) { etat.montrerDansLeFinder(u) }.buttonStyle(.link)
                        }
                    }
                    if !etat.messageAttribution.isEmpty {
                        Text(etat.messageAttribution).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                    }
                }
            }

            HStack {
                if toutEstParti {
                    Text(texteFin).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ok)
                } else {
                    ProgressView().controlSize(.small)
                    Text("Clôture en cours…").font(.system(size: 13)).foregroundStyle(Theme.texteDiscret)
                }
                Spacer()
                if moteur.actif && toutEstParti {
                    Button("Arrêter le tri") { etat.arreterJournee() }.buttonStyle(BoutonStyle())
                        .help("La galerie en ligne continue d'envoyer tant que l'app reste ouverte.")
                }
            }
        }
        .padding(22)
        .frame(width: 640)
        .background(Theme.fond)
        .preferredColorScheme(.dark)
        .onAppear {
            moteur.viderTampon()
            if genre == .finale || !etat.reglages.galerieLaNuit { moteur.envoyerGalerieMaintenant() }
            rafraichir()
        }
        .onReceive(minuterie) { _ in rafraichir() }
        .sheet(isPresented: $terrain) { EngagesTerrainView(moteur: moteur).environmentObject(etat) }
    }

    private var texteGalerie: String {
        guard let g = e.galerie else { return "En attente du démarrage du tri." }
        if g.aFaire == 0 { return "À jour : \(g.enLigne) photos en ligne." }
        if galerieCetteNuit {
            return "\(g.aFaire) photos partiront cette nuit à partir de \(etat.reglages.heureNuitGalerie) h. Laisse le Mac allumé, l'app ouverte."
        }
        var t = "Encore \(g.aEnvoyer) à envoyer"
        if g.aSupprimer > 0 { t += " et \(g.aSupprimer) à supprimer" }
        if g.parMinute > 0 { t += String(format: " · %.0f par minute", g.parMinute) }
        if g.ok == false { t += " · \(g.message)" }
        return t + "."
    }

    private var texteFin: String {
        if genre == .journee {
            return galerieCetteNuit ? "Journée clôturée. La galerie se met à jour cette nuit." : "Journée clôturée : plus aucune photo en route."
        }
        return fichiers.isEmpty ? "Tout est parti." : "Concours clôturé."
    }

    private func rafraichir() {
        e = moteur.etatCloture(depuis: etat.debutConcours)
        // Clôture finale : le fichier de fin s'écrit tout seul dès que tout est parti.
        if genre == .finale && toutEstParti && !fini {
            fini = true
            ecrireFin()
        }
    }

    private func ecrireFin() {
        var l: [URL] = []
        if let u = etat.creerFichierFin() { l.append(u) }
        if let u = etat.ecrireStatistiques() { l.append(u) }
        fichiers = l
    }

    private func ligne(ok: Bool, attention: Bool = false, titre: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : attention ? "exclamationmark.circle.fill" : "circle.dotted")
                .foregroundStyle(ok ? Theme.ok : attention ? Theme.attention : Theme.texteDiscret)
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 1) {
                Text(titre).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
            }
        }
    }
}
