import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import TriPhotoCommun
import TriPhotoMoteur

/// Photo de synchro (début de concours, comme la v00) : Tri-photo affiche un QR qui porte l'heure du chrono.
/// Chaque boîtier le photographie : la photo vérifie que le transfert marche, donne au boîtier son nom, sa piste et son
/// photographe, et règle son heure (avance ou retard). Elle n'est jamais envoyée au serveur ni à Lightroom.
struct SynchroView: View {
    @EnvironmentObject var etat: Etat
    @ObservedObject var moteur: Moteur
    @Environment(\.dismiss) private var fermer
    @State private var nom = ""
    @State private var piste = ""
    @State private var photographe = ""
    @State private var maintenant = Date()
    private let horloge = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var s: EtatSynchro { moteur.resume.synchro }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Synchroniser les boîtiers").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Fermer") { moteur.fermerSynchro(); fermer() }.buttonStyle(BoutonStyle()).keyboardShortcut(.cancelAction)
            }
            if !moteur.actif {
                Text("Démarre d'abord la journée (Réglages > Démarrer) : la photo du QR doit arriver dans le dossier de réception.")
                    .font(.system(size: 13)).foregroundStyle(Theme.attention)
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 10) {
                    qr.frame(width: 340, height: 340)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    Text(heureAffichee).font(.system(size: 22, weight: .semibold, design: .monospaced))
                    Text("Photographie cet écran avec le boîtier (1/500 s ou plus rapide), de près, le QR bien net.")
                        .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret).multilineTextAlignment(.center)
                        .frame(width: 340)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Prochain boîtier photographié").font(.system(size: 13, weight: .semibold))
                    Ligne("Nom du boîtier") {
                        TextField("ex. Boîtier 3 (facultatif)", text: $nom).textFieldStyle(.roundedBorder)
                    }
                    Ligne("Piste") {
                        Picker("", selection: $piste) {
                            Text("—").tag("")
                            ForEach(etat.reglages.pistes) { Text($0.nom).tag($0.nom) }
                        }
                        .labelsHidden()
                    }
                    Ligne("Photographe") {
                        TextField("Prénom", text: $photographe).textFieldStyle(.roundedBorder)
                    }
                    Text(s.ouverte ? "En attente d'une photo du QR… (jusqu'à \(s.jusqua?.formatted(date: .omitted, time: .shortened) ?? ""))"
                                   : "Synchro fermée.")
                        .font(.system(size: 12)).foregroundStyle(s.ouverte ? Theme.accent : Theme.texteDiscret)
                    if let d = s.dernier {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok)
                            Text("\(d.nomAffiche) synchronisé : \(d.ecartTexte)\(d.piste.isEmpty ? "" : " · \(d.piste)")\(d.photographe.isEmpty ? "" : " · \(d.photographe)")")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(10)
                        .background(Theme.okFond, in: RoundedRectangle(cornerRadius: 6))
                    }
                    Divider().overlay(Theme.bordure)
                    Text("Boîtiers synchronisés").font(.system(size: 13, weight: .semibold))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if moteur.resume.boitiersSynchro.isEmpty {
                                Text("Aucun pour l'instant.").font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                            }
                            ForEach(moteur.resume.boitiersSynchro) { b in ligne(b) }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 980, height: 600)
        .background(Theme.fond)
        .foregroundStyle(Theme.texte)
        .preferredColorScheme(.dark)
        .onAppear {
            if piste.isEmpty { piste = etat.reglages.pistes.first?.nom ?? "" }
            if photographe.isEmpty { photographe = etat.reglages.pistes.first(where: { $0.nom == piste })?.photographe ?? "" }
            ouvrir()
        }
        .onChange(of: nom) { _ in ouvrir() }
        .onChange(of: piste) { p in
            if let ph = etat.reglages.pistes.first(where: { $0.nom == p })?.photographe, !ph.isEmpty { photographe = ph }
            ouvrir()
        }
        .onChange(of: photographe) { _ in ouvrir() }
        .onChange(of: s.dernier) { _ in nom = "" }       // le nom est propre à chaque boîtier
        .onReceive(horloge) { maintenant = $0 }
    }

    private func ouvrir() { etat.demanderSynchro(nom: nom, piste: piste, photographe: photographe) }

    /// Heure du chrono (heure du Mac + écart avec HM Timing, s'il est joint).
    private var heureChrono: Double { maintenant.timeIntervalSince1970 + moteur.resume.ecartChrono }

    private var heureAffichee: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.S"
        return f.string(from: Date(timeIntervalSince1970: heureChrono))
    }

    /// Le QR « HMT:<millisecondes> », refait 10 fois par seconde.
    private var qr: some View {
        let texte = "HMT:\(Int64((heureChrono * 1000).rounded()))"
        let filtre = CIFilter.qrCodeGenerator()
        filtre.message = Data(texte.utf8)
        filtre.correctionLevel = "M"
        let contexte = CIContext()
        return Group {
            if let sortie = filtre.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
               let im = contexte.createCGImage(sortie, from: sortie.extent) {
                Image(decorative: im, scale: 1).interpolation(.none).resizable().padding(18)
            } else {
                Text("QR indisponible").foregroundStyle(Color.black)
            }
        }
    }

    private func ligne(_ b: BoitierSynchro) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(b.nomAffiche).font(.system(size: 13, weight: .semibold))
                Text([b.nom.isEmpty ? "" : b.boitier, b.piste, b.photographe, b.ecartTexte,
                      "le \(b.le.formatted(date: .abbreviated, time: .shortened))"].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
            }
            Spacer()
            Button("Oublier") { moteur.oublierBoitier(b.boitier) }.buttonStyle(BoutonStyle())
                .help("Son heure ne sera plus corrigée ; refais une photo du QR pour le resynchroniser.")
        }
        .padding(8)
        .background(Theme.carte, in: RoundedRectangle(cornerRadius: 6))
    }
}
