import AppKit
import SwiftUI

/// Vignettes des photos, décodées à petite taille en arrière-plan (priorité basse) et gardées en mémoire.
/// Pour une photo déjà envoyée, la copie du serveur (1500 px) est lue de préférence : plus légère que l'original.
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

    func charger(_ chemins: [String], cote: Int, fini: @escaping (NSImage?) -> Void) {
        let cle = "\(cote)|\(chemins.first ?? "")" as NSString
        if let im = cache.object(forKey: cle) { return fini(im) }
        fil.addOperation { [cache] in
            var im: NSImage?
            for c in chemins where !c.isEmpty && FileManager.default.fileExists(atPath: c) {
                im = Vignette.charger(c, cote: cote)
                if im != nil { break }
            }
            if let im { cache.setObject(im, forKey: cle) }
            DispatchQueue.main.async { fini(im) }
        }
    }
}

/// Une vignette de photo : la copie du serveur si elle existe, sinon l'original.
struct VignettePhoto: View {
    var chemins: [String]
    var cote = 320
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.carte)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .clipped()
        .onAppear {
            if image == nil {
                image = CacheVignettes.partage.image(chemins.first ?? "", cote: cote)
                if image == nil { CacheVignettes.partage.charger(chemins, cote: cote) { image = $0 } }
            }
        }
        .onChange(of: chemins) { nouveaux in
            image = nil
            CacheVignettes.partage.charger(nouveaux, cote: cote) { image = $0 }
        }
    }
}
