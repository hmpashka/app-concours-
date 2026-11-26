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
        fil.maxConcurrentOperationCount = 2
    }

    func image(_ chemin: String, cote: Int) -> NSImage? { cache.object(forKey: "\(cote)|\(chemin)" as NSString) }

    /// Lit la vignette en arrière-plan. Rend l'opération, pour pouvoir l'abandonner si la vignette disparaît.
    @discardableResult
    func charger(_ chemins: [String], cote: Int, fini: @escaping (NSImage?) -> Void) -> Operation? {
        let cle = "\(cote)|\(chemins.first ?? "")" as NSString
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

    var body: some View {
        Rectangle().fill(entiere ? Color.clear : Theme.carte)
            .overlay {
                if let image {
                    if entiere {
                        Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    } else {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    }
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
                lire(nouveaux)
            }
    }

    private func lire(_ l: [String]) {
        guard image == nil else { return }
        image = CacheVignettes.partage.image(l.first ?? "", cote: cote)
        guard image == nil else { return }
        lecture?.cancel()
        lecture = CacheVignettes.partage.charger(l, cote: cote) { im in
            image = im
            // Photo pas encore lisible (mémoire iCloud en cours de téléchargement sur ce Mac) : on réessaie un moment
            // au lieu de tourner pour toujours (essai du 26/11).
            guard im == nil, visible, essais < 40,
                  !l.contains(where: { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) }) else { return }
            essais += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if visible, image == nil, chemins == l { lire(l) }
            }
        }
    }
}
