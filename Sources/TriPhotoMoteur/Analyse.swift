import CoreGraphics
import Foundation
import ImageIO

/// Analyse rapide d'une photo sur un aperçu de 384 px (quelques millisecondes), reprise de la v00 :
/// netteté de la zone la plus nette (le sujet), et reconnaissance d'une photo « vide » :
/// ciel, arbres sur le ciel ou plafond clair = photo de code ; sable, herbe, terre = photo du sol.
/// Rien n'est décidé ici : le tri propose, HUGO décide.
public struct Analyse: Sendable, Equatable {
    public enum Scene: String, Sendable { case normale = "", code, sol }

    public var nettete: Double
    public var texture: Double
    public var uniforme: Bool
    public var bleu: Bool
    public var gris: Bool
    public var luminosite: Double

    public var scene: Scene {
        guard uniforme else { return .normale }
        return (bleu || (gris && texture < 1.5)) ? .code : .sol
    }

    static let cote = 384

    public static func analyser(_ url: URL) -> Analyse? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: cote,
                                     kCGImageSourceShouldCacheImmediately: false]
        guard let im = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return analyser(im)
    }

    static func analyser(_ im: CGImage) -> Analyse? {
        let w = im.width, h = im.height
        guard w >= 16, h >= 16 else { return nil }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.draw(im, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }

        // gris, puis laplacien (netteté locale)
        var g = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            g[i] = (0.299 * Float(px[i * 4]) + 0.587 * Float(px[i * 4 + 1]) + 0.114 * Float(px[i * 4 + 2])) / 255
        }
        let lw = w - 2, lh = h - 2
        var lap = [Float](repeating: 0, count: lw * lh)
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let c = g[y * w + x]
                lap[(y - 1) * lw + (x - 1)] = 4 * c - g[(y - 1) * w + x] - g[(y + 1) * w + x] - g[y * w + x - 1] - g[y * w + x + 1]
            }
        }
        func variances(_ n: Int) -> [Double] {
            var v: [Double] = []
            for i in 0..<n {
                for j in 0..<n {
                    let y0 = i * lh / n, y1 = (i + 1) * lh / n, x0 = j * lw / n, x1 = (j + 1) * lw / n
                    var s = 0.0, s2 = 0.0, k = 0.0
                    for y in y0..<y1 {
                        for x in x0..<x1 {
                            let a = Double(lap[y * lw + x])
                            s += a; s2 += a * a; k += 1
                        }
                    }
                    v.append(k > 0 ? max(0, s2 / k - (s / k) * (s / k)) : 0)
                }
            }
            return v
        }
        let v6 = variances(6).sorted(by: >)
        let nettete = (v6.prefix(3).reduce(0, +) / 3) * 1e4
        let texture = v6[v6.count / 2] * 1e4

        // couleurs moyennes de 4 × 4 zones
        var couleurs: [(Double, Double, Double)] = []
        for i in 0..<4 {
            for j in 0..<4 {
                let y0 = i * h / 4, y1 = (i + 1) * h / 4, x0 = j * w / 4, x1 = (j + 1) * w / 4
                var r = 0.0, gg = 0.0, b = 0.0, k = 0.0
                for y in stride(from: y0, to: y1, by: 2) {
                    for x in stride(from: x0, to: x1, by: 2) {
                        let o = (y * w + x) * 4
                        r += Double(px[o]); gg += Double(px[o + 1]); b += Double(px[o + 2]); k += 1
                    }
                }
                couleurs.append((r / k / 255, gg / k / 255, b / k / 255))
            }
        }
        let n = Double(couleurs.count)
        let moy = (couleurs.map(\.0).reduce(0, +) / n, couleurs.map(\.1).reduce(0, +) / n, couleurs.map(\.2).reduce(0, +) / n)
        func ecartType(_ l: [Double], _ m: Double) -> Double { (l.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(l.count)).squareRoot() }
        let dispersion = (ecartType(couleurs.map(\.0), moy.0) + ecartType(couleurs.map(\.1), moy.1) + ecartType(couleurs.map(\.2), moy.2)) / 3
        let saturation = couleurs.map { max($0.0, $0.1, $0.2) - min($0.0, $0.1, $0.2) }.reduce(0, +) / n
        let lum = (moy.0 + moy.1 + moy.2) / 3
        return Analyse(nettete: nettete, texture: texture,
                       uniforme: dispersion < 0.06 && nettete < 4 * max(texture, 0.05),
                       bleu: moy.2 >= moy.0 - 0.02,
                       gris: saturation < 0.08 && lum > 0.45,
                       luminosite: lum)
    }
}
