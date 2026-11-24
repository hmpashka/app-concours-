import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Un boîtier synchronisé par sa photo du QR code : son nom, sa piste, son photographe et son écart d'heure.
public struct BoitierSynchro: Codable, Identifiable, Sendable, Equatable {
    public var id: String { boitier }
    /// Boîtier tel que l'EXIF le donne (modèle + numéro de série).
    public var boitier: String
    /// Nom donné par HUGO (« Boîtier 3 »), vide : celui de l'EXIF.
    public var nom: String
    /// Piste des réglages (« Piste 1 ») et piste du chrono correspondante.
    public var piste: String
    public var source: String
    public var photographe: String
    /// Heure du boîtier − heure du chrono, en secondes (positif : le boîtier avance).
    public var ecart: Double
    public var le: Date
    public var photo: String

    public var nomAffiche: String { nom.isEmpty ? boitier : nom }

    public init(boitier: String, nom: String, piste: String, source: String, photographe: String, ecart: Double,
                le: Date, photo: String) {
        self.boitier = boitier
        self.nom = nom
        self.piste = piste
        self.source = source
        self.photographe = photographe
        self.ecart = ecart
        self.le = le
        self.photo = photo
    }

    /// « en avance de 2,3 s », « à l'heure ».
    public var ecartTexte: String {
        if abs(ecart) < 0.25 { return "à l'heure" }
        let s = String(format: "%.1f", abs(ecart)).replacingOccurrences(of: ".", with: ",")
        return (ecart > 0 ? "en avance de " : "en retard de ") + s + " s"
    }
}

/// Ce que HUGO a choisi dans la fenêtre de synchro pour le prochain boîtier photographié.
public struct DemandeSynchro: Sendable, Equatable {
    public var nom: String
    public var piste: String
    public var source: String
    public var photographe: String
    public init(nom: String, piste: String, source: String, photographe: String) {
        self.nom = nom
        self.piste = piste
        self.source = source
        self.photographe = photographe
    }
}

/// La fenêtre de synchro est-elle ouverte, et qu'a donné la dernière photo du QR ?
public struct EtatSynchro: Sendable, Equatable {
    public var ouverte = false
    public var jusqua: Date?
    public var dernier: BoitierSynchro?
    public init() {}
}

enum Synchro {
    /// Le texte du QR : « HMT:<millisecondes depuis 1970> », l'heure du chrono (comme la v00).
    static func texte(heureChrono: Double) -> String { "HMT:\(Int64((heureChrono * 1000).rounded()))" }

    static func lire(texte: String) -> Double? {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("HMT:"), let ms = Int64(t.dropFirst(4)), (12...14).contains(t.count - 4) else { return nil }
        return Double(ms) / 1000
    }

    /// Heure du chrono lue dans le QR d'une photo, ou nil (photo sans QR). Lecture sur une image réduite (1200 px).
    static func lireQR(_ url: URL) -> Double? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 1200]
        guard let im = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let r = VNDetectBarcodesRequest()
        r.symbologies = [.qr]
        try? VNImageRequestHandler(cgImage: im, options: [:]).perform([r])
        for o in r.results ?? [] {
            if let p = o.payloadStringValue, let h = lire(texte: p) { return h }
        }
        return nil
    }
}
