import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TriPhotoCommun
import TriPhotoMoteur

/// « Au bureau » › Envoyer un concours sur le NAS (maquette envoi-nas.png validée par HUGO 26/11/2026).
/// À gauche : les concours à envoyer et les réglages. Au centre : l'envoi en cours. À droite : les derniers envois,
/// les photos « À décider » et « Libérer la place sur le Mac ».
struct EnvoiNASView: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var envoi: EtatEnvoiNAS
    @ObservedObject var bureau: EtatBureau
    @State private var survol = false

    var body: some View {
        HStack(spacing: 0) {
            if etat.panneauGauche {
                gauche.frame(width: 300).background(Theme.panneau)
                Divider().overlay(Theme.bordure)
            }
            centre.frame(maxWidth: .infinity)
            if etat.panneauDroit {
                Divider().overlay(Theme.bordure)
                droite.frame(width: 320).background(Theme.panneau)
            }
        }
    }

    private func titre(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
    }

    // MARK: - Gauche : préparer

    private var gauche: some View {
        VStack(alignment: .leading, spacing: 10) {
            titre("CONCOURS À ENVOYER")
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(envoi.aEnvoyer, id: \.self) { u in
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(u.lastPathComponent).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                                if envoi.joindreCSV {
                                    Text(envoi.csvPour(u).map { "CSV : \($0.lastPathComponent)" } ?? "Pas de CSV trouvé")
                                        .font(.system(size: 10.5)).foregroundStyle(Theme.texteDiscret).lineLimit(1).truncationMode(.middle)
                                }
                            }
                            Spacer(minLength: 0)
                            Button { envoi.retirer(u) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(BoutonPlat()).foregroundStyle(Theme.texteDiscret).help("Retirer de la liste")
                        }
                        .padding(8).background(Theme.carte, in: RoundedRectangle(cornerRadius: 7))
                    }
                    Button { envoi.ajouterDossiers() } label: {
                        VStack(spacing: 4) {
                            Label("Ajouter des concours", systemImage: "plus").font(.system(size: 13, weight: .semibold))
                            Text("ou glisse les dossiers ici").font(.system(size: 11))
                        }
                        .foregroundStyle(Theme.accent).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(survol ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .buttonStyle(BoutonPlat())
                    .help("Choisis un ou plusieurs dossiers de concours (⌘-clic). Ils partent l'un après l'autre.")
                }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $survol) { fournisseurs in
                let envoi = self.envoi
                for f in fournisseurs {
                    _ = f.loadObject(ofClass: URL.self) { u, _ in
                        guard let u else { return }
                        Task { @MainActor in envoi.deposer([u]) }
                    }
                }
                return true
            }

            titre("SUR LE NAS, DANS L'ANNÉE")
            Menu {
                ForEach(bureau.archives) { a in
                    Button("\(a.annee) · \(URL(fileURLWithPath: a.chemin).lastPathComponent)") { envoi.annee = a.chemin }
                }
                if !bureau.archives.isEmpty { Divider() }
                Button("Choisir un autre dossier…") { envoi.choisirAnnee() }
            } label: {
                Text(envoi.annee.isEmpty ? "Choisir l'année…" : URL(fileURLWithPath: envoi.annee).lastPathComponent).lineLimit(1)
            }
            .help("Le concours est copié dans ce dossier, sous son propre nom.")
            if !envoi.annee.isEmpty && !envoi.anneePresente {
                Text("NAS pas joignable pour le moment.").font(.system(size: 11)).foregroundStyle(Theme.attention)
            }

            titre("RÉGLAGES")
            Toggle("Joindre le CSV d'attribution", isOn: $envoi.joindreCSV)
                .help("Le CSV du concours (trouvé dans ton dossier des CSV par la date et le nom) est copié avec les photos.")
            Toggle("Vérifier chaque photo sur le NAS", isOn: $envoi.verifier)
                .help("Chaque photo est relue sur le NAS et comparée à celle du Mac. Plus long, mais c'est la seule garantie.")
            Toggle("Envoyer doucement (30 Mo/s au plus)", isOn: $envoi.doux)
                .help("Laisse de la place au réseau et au Mac.")
            Toggle("Seulement la nuit (22 h – 7 h)", isOn: $envoi.laNuit)
            Spacer(minLength: 0)
            Button {
                envoi.envoyer()
            } label: {
                Label(envoi.aEnvoyer.count > 1 ? "Envoyer les \(envoi.aEnvoyer.count) concours" : "Envoyer sur le NAS",
                      systemImage: "arrow.up.to.line").frame(maxWidth: .infinity)
            }
            .buttonStyle(BoutonStyle(principal: true))
            .disabled(envoi.aEnvoyer.isEmpty || envoi.annee.isEmpty)
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 12.5))
        .padding(14)
    }

    // MARK: - Centre : l'envoi choisi

    @ViewBuilder private var centre: some View {
        if let t = envoi.tacheChoisie {
            let b = envoi.bilan
            VStack(alignment: .leading, spacing: 12) {
                bandeauReseau(t)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.nom).font(.system(size: 20, weight: .semibold))
                        Text("→ \((t.destination.path as NSString).abbreviatingWithTildeInPath)")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.texteDiscret).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    boutons(t)
                }
                barre("Envoi", fait: b.envoyes, total: b.total, couleur: Theme.accent)
                if t.verifier { barre("Vérification", fait: b.verifies, total: b.total, couleur: Theme.ok) }
                HStack(spacing: 16) {
                    chiffre("\(b.total.formatted())", "photos et fichiers")
                    chiffre(ByteCountFormatter.string(fromByteCount: b.octetsTotal, countStyle: .file), "en tout")
                    chiffre("\(b.dejaLa.formatted())", "déjà sur le NAS")
                    if b.aDecider > 0 { chiffre("\(b.aDecider)", "à décider", Theme.attention) }
                    if b.erreurs > 0 { chiffre("\(b.erreurs)", "en erreur", Theme.erreur) }
                    if t.etat == .enCours && envoi.debit > 0 {
                        chiffre(ByteCountFormatter.string(fromByteCount: Int64(envoi.debit), countStyle: .file) + "/s", resteTemps(b))
                    }
                }
                if t.etat == .enCours && !envoi.fichierEnCours.isEmpty {
                    Text("En ce moment : \(envoi.fichierEnCours)").font(.system(size: 11)).foregroundStyle(Theme.texteDiscret).lineLimit(1)
                }
                Divider().overlay(Theme.bordure)
                Text("PAR ÉPREUVE").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(b.epreuves) { e in
                            HStack(spacing: 10) {
                                Image(systemName: e.verifies == e.total && e.total > 0 ? "checkmark.circle.fill"
                                      : e.erreurs > 0 ? "exclamationmark.triangle.fill"
                                      : e.aDecider > 0 ? "questionmark.circle.fill" : e.fini ? "arrow.up.circle.fill" : "circle.dotted")
                                    .foregroundStyle(e.erreurs > 0 ? Theme.erreur : e.aDecider > 0 ? Theme.attention
                                                     : e.verifies == e.total ? Theme.ok : Theme.accent)
                                Text(e.nom).font(.system(size: 12.5)).lineLimit(1)
                                Spacer()
                                Text("\(e.envoyes)/\(e.total)" + (t.verifier ? " · \(e.verifies) vérifiées" : ""))
                                    .font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.texteDiscret)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Theme.carte, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                let erreurs = envoi.fichiers.filter { $0.etat == .erreur }
                if !erreurs.isEmpty {
                    Text("Erreurs (renvoyées au prochain passage) : " + erreurs.prefix(3).map { "\(URL(fileURLWithPath: $0.chemin).lastPathComponent) (\($0.message))" }.joined(separator: ", "))
                        .font(.system(size: 11)).foregroundStyle(Theme.erreur).lineLimit(2)
                }
                if !envoi.message.isEmpty {
                    Text(envoi.message).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                }
            }
            .padding(18)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "externaldrive.badge.icloud").font(.system(size: 40)).foregroundStyle(Theme.accent)
                Text("Ajoute un ou plusieurs concours à gauche, choisis l'année sur le NAS, puis « Envoyer ».")
                    .font(.system(size: 13)).foregroundStyle(Theme.texteDiscret).multilineTextAlignment(.center)
                Text("Si le réseau coupe, l'envoi reprend tout seul là où il en était. Rien n'est jamais écrasé sur le NAS.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.texteTresDiscret).multilineTextAlignment(.center)
                if !envoi.message.isEmpty { Text(envoi.message).font(.system(size: 12)).foregroundStyle(Theme.texteDiscret) }
            }
            .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func bandeauReseau(_ t: TacheEnvoi) -> some View {
        let r: (texte: String, couleur: Color, fond: Color)? = {
            guard t.etat == .enCours || t.etat == .attente else { return nil }
            if envoi.pauseConcours { return ("En pause : un concours tourne sur ce Mac, l'envoi reprendra ensuite.", Theme.attention, Theme.attentionFond) }
            switch envoi.reseau {
            case .ok: return t.etat == .attente ? ("En attente : il part après les concours précédents.", Theme.texteDiscret, Theme.carte) : nil
            case .coupe(let depuis, let prochain):
                let f = DateFormatter(); f.timeStyle = .short
                return ("Le NAS ne répond plus depuis \(f.string(from: depuis)). Nouvel essai à \(f.string(from: prochain)) : l'envoi reprendra là où il en était.",
                        Theme.attention, Theme.attentionFond)
            case .attenteNuit: return ("En attente de la nuit (22 h).", Theme.texteDiscret, Theme.carte)
            case .pause: return ("En pause.", Theme.attention, Theme.attentionFond)
            }
        }()
        if let r {
            Text(r.texte).font(.system(size: 12, weight: .medium)).foregroundStyle(r.couleur)
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(r.fond, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder private func boutons(_ t: TacheEnvoi) -> some View {
        HStack(spacing: 6) {
            switch t.etat {
            case .enCours, .attente:
                Button(envoi.enPause ? "Reprendre" : "Pause") { envoi.enPause.toggle() }.buttonStyle(BoutonStyle())
                    .help("Met tous les envois en pause (le fichier en cours s'arrête proprement).")
                Button("Arrêter") { envoi.arreter(t.id) }.buttonStyle(BoutonStyle())
                    .help("Arrête cet envoi. « Reprendre » le relancera là où il en était.")
            case .arrete:
                Button("Reprendre") { envoi.reprendre(t.id) }.buttonStyle(BoutonStyle(principal: true))
            case .fini:
                Button("Montrer sur le NAS") { envoi.montrerSurLeNAS(t) }.buttonStyle(BoutonStyle())
                Button("Revérifier") { envoi.reprendre(t.id) }.buttonStyle(BoutonStyle())
                    .help("Relit le dossier du Mac : ce qui manque ou a changé est envoyé, le reste est passé.")
            }
        }
    }

    private func barre(_ nom: String, fait: Int, total: Int, couleur: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(nom).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(fait.formatted()) / \(total.formatted())").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.texteDiscret)
            }
            ProgressView(value: Double(fait), total: Double(max(total, 1))).tint(couleur)
        }
    }

    private func chiffre(_ v: String, _ l: String, _ c: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(c ?? Theme.texte)
            Text(l).font(.system(size: 10.5)).foregroundStyle(Theme.texteDiscret)
        }
    }

    private func resteTemps(_ b: BilanEnvoi) -> String {
        let reste = Double(max(b.octetsTotal - b.octetsFaits, 0)) / max(envoi.debit, 1)
        let m = Int(reste / 60)
        return m < 1 ? "moins d'une minute" : m < 60 ? "encore \(m) min" : "encore \(m / 60) h \(m % 60) min"
    }

    // MARK: - Droite : derniers envois, à décider, libérer la place

    private var droite: some View {
        VStack(alignment: .leading, spacing: 10) {
            titre("DERNIERS ENVOIS")
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(envoi.taches.reversed()) { t in carte(t) }
                    if envoi.taches.isEmpty {
                        Text("Aucun envoi pour le moment.").font(.system(size: 11.5)).foregroundStyle(Theme.texteDiscret)
                    }
                }
            }
            .frame(maxHeight: 260)
            let aDecider = envoi.fichiers.filter { $0.etat == .aDecider }
            if !aDecider.isEmpty {
                titre("À DÉCIDER (\(aDecider.count))")
                Text("Même nom dans la même épreuve, mais la photo n'est pas la même que sur le NAS.")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret).fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(aDecider) { f in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(f.epreuve) › \(URL(fileURLWithPath: f.chemin).lastPathComponent)").font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                                HStack(spacing: 4) {
                                    Button("Garder les deux") { envoi.decider(f, .garderLesDeux) }
                                        .help("Envoyée avec un nom libre (-2) à côté de celle du NAS.")
                                    Button("Remplacer") { envoi.decider(f, .remplacer) }
                                        .help("Celle du Mac remplace celle du NAS.")
                                    Button("Ne pas envoyer") { envoi.decider(f, .nePasEnvoyer) }
                                }
                                .buttonStyle(BoutonStyle()).font(.system(size: 11))
                            }
                            .padding(8).background(Theme.attentionFond, in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if let t = envoi.tacheChoisie, t.etat == .fini, !t.placeLiberee {
                let pret = envoi.bilan.toutVerifie
                titre("LIBÉRER LA PLACE SUR LE MAC")
                Text(pret ? "Tout est sur le NAS et vérifié identique. Le dossier du Mac peut partir à la Corbeille."
                          : "Possible seulement quand chaque fichier est vérifié identique sur le NAS.")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret).fixedSize(horizontal: false, vertical: true)
                Button { envoi.libererLaPlace(t) } label: {
                    Label("Mettre « \(t.nom) » à la Corbeille", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(BoutonStyle()).disabled(!pret)
            }
        }
        .padding(14)
    }

    private func carte(_ t: TacheEnvoi) -> some View {
        let choisie = envoi.choisie == t.id
        let (icone, couleur): (String, Color) = {
            switch t.etat {
            case .enCours: return ("arrow.up.circle.fill", Theme.accent)
            case .attente: return ("clock", Theme.texteDiscret)
            case .fini: return ("checkmark.circle.fill", Theme.ok)
            case .arrete: return ("stop.circle", Theme.attention)
            }
        }()
        return Button { envoi.choisir(t.id) } label: {
            HStack(spacing: 8) {
                Image(systemName: icone).foregroundStyle(couleur)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.nom).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Text(sousTitre(t)).font(.system(size: 10.5)).foregroundStyle(Theme.texteDiscret).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(choisie ? Theme.selection : Theme.carte, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(BoutonPlat())
        .contextMenu {
            if t.etat == .arrete || t.etat == .fini { Button("Reprendre / revérifier") { envoi.reprendre(t.id) } }
            if t.etat != .enCours { Button("Retirer de la liste") { envoi.oublier(t.id) } }
        }
    }

    private func sousTitre(_ t: TacheEnvoi) -> String {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        switch t.etat {
        case .fini: return "Fini le \(f.string(from: t.finiLe ?? t.creeLe))" + (t.placeLiberee ? " · place libérée" : "")
        case .enCours: return "En cours"
        case .attente: return "En attente"
        case .arrete: return "Arrêté (à reprendre)"
        }
    }
}
