import AppKit
import ImageIO
import SwiftUI
import TriPhotoMoteur

/// Les deux photos d'un doublon côte à côte : la première reçue et la dernière reçue, pour choisir.
struct ComparerDoublon: View {
    let doublon: FichePhoto
    @ObservedObject var moteur: Moteur
    @Environment(\.dismiss) private var fermer
    @State private var premiere: FichePhoto?
    @State private var imagePremiere: NSImage?
    @State private var imageDerniere: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Doublon : \(doublon.nom)").font(.system(size: 16, weight: .semibold))
                    Text("Deux photos portent le même nom. Rien n'est envoyé tant que tu n'as pas choisi.")
                        .font(.system(size: 12)).foregroundStyle(Theme.texteDiscret)
                }
                Spacer()
                Button("Fermer") { fermer() }.buttonStyle(BoutonStyle()).keyboardShortcut(.cancelAction)
            }
            HStack(alignment: .top, spacing: 16) {
                colonne(titre: "Première reçue (déjà envoyée)", image: imagePremiere, fiche: premiere)
                colonne(titre: "Dernière reçue (en attente)", image: imageDerniere, fiche: doublon)
            }
            HStack {
                Spacer()
                Button("Jeter la dernière") { moteur.jeterDoublon(doublon); fermer() }
                    .buttonStyle(BoutonStyle())
                Button("Garder les deux (autre nom)") { moteur.garderDoublon(doublon); fermer() }
                    .buttonStyle(BoutonStyle())
                Button("Remplacer la première par la dernière") { moteur.remplacerPremiere(par: doublon); fermer() }
                    .buttonStyle(BoutonStyle(principal: true))
                    .disabled(premiere == nil)
            }
            Text("Remplacer : la copie du serveur et l'original sont remplacés ; l'ancien original part à la corbeille du Mac (récupérable).")
                .font(.system(size: 11)).foregroundStyle(Theme.texteTresDiscret)
        }
        .padding(20)
        .frame(width: 980)
        .background(Theme.fond)
        .foregroundStyle(Theme.texte)
        .preferredColorScheme(.dark)
        .task {
            let p = moteur.premiere(pour: doublon)
            premiere = p
            // vignettes en arrière-plan, priorité basse : la copie du serveur suffit pour la première
            let cheminPremiere = p.map { $0.copie.isEmpty ? $0.chemin : $0.copie }
            let cheminDerniere = doublon.chemin
            let (a, b) = await Task.detached(priority: .utility) {
                (cheminPremiere.flatMap { Vignette.charger($0, cote: 900) }, Vignette.charger(cheminDerniere, cote: 900))
            }.value
            imagePremiere = a
            imageDerniere = b
        }
    }

    private func colonne(titre: String, image: NSImage?, fiche: FichePhoto?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titre).font(.system(size: 13, weight: .semibold))
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Theme.carte)
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Text(fiche == nil ? "Introuvable" : "Chargement…").foregroundStyle(Theme.texteDiscret)
                }
            }
            .frame(height: 300)
            if let f = fiche {
                Text("\(f.origine) · \(f.code.isEmpty ? "sans code" : f.code)").font(.system(size: 12))
                Text("\(f.boitier) · prise \(f.prise.map { $0.formatted(date: .omitted, time: .standard) } ?? "?") · reçue \(f.recue.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 11)).foregroundStyle(Theme.texteDiscret)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Petite image d'une photo, décodée directement à la bonne taille (rapide, peu de mémoire).
enum Vignette {
    static func charger(_ chemin: String, cote: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: chemin) as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: cote]
        guard let im = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: im, size: NSSize(width: im.width, height: im.height))
    }
}
