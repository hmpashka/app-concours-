import AppKit
import SwiftUI

/// Vignettes des photos, décodées à petite taille en arrière-plan (priorité basse) et gardées en mémoire.
/// Pour une photo déjà envoyée, la copie du serveur (1500 px) est lue de préférence : plus légère que l'original.
/// Une vignette qui sort de l'écran avant d'être lue est abandonnée : défiler vite dans une galerie ne charge
/// que ce qu'on regarde (Lightroom garde le processeur).
final class CacheVignettes {
    static let partage = CacheVignettes()
    private let cache = NSCache<NSString, NSImage>()
    private let fil = OperationQueue()

    init() {
        cache.countLimit = 600
        fil.qualityOfService = .utility
        fil.maxConcurrentOperationCount = 4
    }

    /// Clé du cache : le premier chemin NON VIDE. Avant (essai du 26/11), toutes les photos sans copie sur le serveur
    /// partageaient la clé « 260| » : la galerie montrait la même image pour toutes, ou restait vide.
    static func cle(_ chemins: [String], cote: Int) -> NSString {
        "\(cote)|\(chemins.first { !$0.isEmpty } ?? "")" as NSString
    }

    func image(_ chemins: [String], cote: Int) -> NSImage? { cache.object(forKey: Self.cle(chemins, cote: cote)) }

    /// Lit la vignette en arrière-plan. Rend l'opération, pour pouvoir l'abandonner si la vignette disparaît.
    @discardableResult
    func charger(_ chemins: [String], cote: Int, fini: @escaping (NSImage?) -> Void) -> Operation? {
        let cle = Self.cle(chemins, cote: cote)
        if let im = cache.object(forKey: cle) { fini(im); return nil }
        let op = BlockOperation()
        op.addExecutionBlock { [weak op, cache] in
            if op?.isCancelled ?? true { return }
            var im: NSImage?
            for c in chemins where !c.isEmpty && FileManager.default.fileExists(atPath: c) {
                im = Vignette.charger(c, cote: cote)
                if im != nil { break }
            }
            if let im { cache.setObject(im, forKey: cle) }
            DispatchQueue.main.async { fini(im) }
        }
        fil.addOperation(op)
        return op
    }
}

/// Une vignette de photo : la copie du serveur si elle existe, sinon l'original.
/// Elle prend toujours exactement la place qu'on lui donne (jamais plus) : `entiere` montre la photo en entier
/// (portrait ou paysage, sans rien couper), sinon elle remplit la case en coupant les bords.
struct VignettePhoto: View {
    var chemins: [String]
    var cote = 320
    var entiere = false
    @State private var image: NSImage?
    @State private var lecture: Operation?
    @State private var visible = false
    @State private var essais = 0                        // fichier pas encore là (iCloud qui télécharge) : on réessaie
    @State private var introuvable = false               // plus de fichier à lire : on le dit au lieu de tourner

    var body: some View {
        Rectangle().fill(entiere ? Color.clear : Theme.carte)
            .overlay {
                if let image {
                    if entiere {
                        Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    } else {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    }
                } else if introuvable {
                    Image(systemName: "photo.badge.exclamationmark").foregroundStyle(Theme.texteTresDiscret)
                        .help("Photo introuvable pour l'instant (déplacée, supprimée, ou serveur débranché).")
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .clipped()
            .onAppear { visible = true; lire(chemins) }
            .onDisappear { visible = false; lecture?.cancel(); lecture = nil }
            .onChange(of: chemins) { nouveaux in
                image = nil
                essais = 0
                introuvable = false
                lire(nouveaux)
            }
    }

    private func lire(_ l: [String]) {
        guard image == nil else { return }
        image = CacheVignettes.partage.image(l, cote: cote)
        guard image == nil else { return }
        lecture?.cancel()
        lecture = CacheVignettes.partage.charger(l, cote: cote) { im in
            image = im
            guard im == nil, visible else { return }
            // Photo pas encore lisible (iCloud qui télécharge, transfert pas fini, serveur lent) : on réessaie un moment.
            // Au bout d'un moment, ou si aucun fichier n'existe, un symbole remplace la roue (essai du 26/11 :
            // des vignettes tournaient pour toujours).
            let existe = l.contains { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) }
            guard essais < (existe ? 10 : 3) else { introuvable = true; return }
            essais += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if visible, image == nil, chemins == l { lire(l) }
            }
        }
    }
}
