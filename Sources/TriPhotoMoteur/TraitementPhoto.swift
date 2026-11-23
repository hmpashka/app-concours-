import CoreImage
import Foundation
import ImageIO
import TriPhotoCommun
import UniformTypeIdentifiers

/// Ce que le moteur lit dans l'en-tête d'une photo (sans décoder l'image).
struct InfosPhoto {
    var priseEXIF: String?        // « 2026:11:29 14:32:07 », heure de l'appareil
    var prise: Date?
    var boitier: String           // modèle + numéro de série
    var copyright: String         // là où le photographe met son code
}

enum TraitementPhoto {
    enum Erreur: Error, LocalizedError {
        case illisible(String)
        case ecriture(String)
        var errorDescription: String? {
            switch self {
            case .illisible(let s): return "Photo illisible : \(s)"
            case .ecriture(let s): return "Écriture impossible : \(s)"
            }
        }
    }

    // MARK: - Lecture

    static func infos(_ url: URL) -> InfosPhoto? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
        let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let iptc = p[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
        let aux = p[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]

        let priseEXIF = (exif[kCGImagePropertyExifDateTimeOriginal] as? String) ?? (tiff[kCGImagePropertyTIFFDateTime] as? String)
        var prise: Date?
        if let t = priseEXIF {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            prise = f.date(from: t)
            if let sub = exif[kCGImagePropertyExifSubsecTimeOriginal] as? String, let v = Double("0." + sub) { prise? += v }
        }
        let modele = (tiff[kCGImagePropertyTIFFModel] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let serie = ((exif[kCGImagePropertyExifBodySerialNumber] as? String) ?? (aux[kCGImagePropertyExifAuxSerialNumber] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let boitier = [modele, serie].filter { !$0.isEmpty }.joined(separator: " ")
        let copyright = ((tiff[kCGImagePropertyTIFFCopyright] as? String) ?? (iptc[kCGImagePropertyIPTCCopyrightNotice] as? String) ?? "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        return InfosPhoto(priseEXIF: priseEXIF, prise: prise, boitier: boitier.isEmpty ? "Appareil inconnu" : boitier,
                          copyright: copyright)
    }

    /// Photo mal transférée ? Fin de fichier JPEG absente, ou image impossible à décoder.
    /// Le décodage se fait en petit (vignette de 256 px) : rapide et sans charger la photo entière.
    static func estAbimee(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return true }
        defer { try? h.close() }
        let taille = (try? h.seekToEnd()) ?? 0
        guard taille > 1024 else { return true }
        // Les deux derniers octets d'un JPEG complet sont FF D9 (parfois suivis de quelques octets de bourrage).
        try? h.seek(toOffset: taille - 32)
        let fin = (try? h.read(upToCount: 32)) ?? Data()
        let bytes = [UInt8](fin)
        let finTrouvee = bytes.indices.dropLast().contains { bytes[$0] == 0xFF && bytes[$0 + 1] == 0xD9 }
        if !finTrouvee { return true }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetStatus(src) == .statusComplete else { return true }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 256,
                                     kCGImageSourceShouldCache: false]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) == nil
    }

    // MARK: - Copie compressée (.cube)

    /// Un contexte Core Image partagé (carte graphique), créé une seule fois.
    static let contexte = CIContext(options: [.cacheIntermediates: false, .priorityRequestLow: true])
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Copie pour le serveur local : redressée, côté le plus long = cote, .cube appliqué, sRGB, JPEG qualité %.
    /// Métadonnées gardées : Copyright (le code) et date de prise de vue. L'original n'est pas touché.
    static func fabriquerCopie(de url: URL, vers final: URL, cote: Int, qualite: Int, cube: FichierCube?,
                               copyright: String, priseEXIF: String?) throws {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw Erreur.illisible(url.lastPathComponent) }
        // Décodage directement à la bonne taille, orientation appliquée.
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: cote,
                                     kCGImageSourceShouldCacheImmediately: false]
        guard let petite = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        else { throw Erreur.illisible(url.lastPathComponent) }

        var image = CIImage(cgImage: petite)
        if let cube {
            let filtre = CIFilter(name: "CIColorCubeWithColorSpace")!
            filtre.setValue(cube.taille, forKey: "inputCubeDimension")
            filtre.setValue(cube.valeurs.withUnsafeBufferPointer { Data(buffer: $0) }, forKey: "inputCubeData")
            filtre.setValue(srgb, forKey: "inputColorSpace")
            filtre.setValue(image, forKey: kCIInputImageKey)
            if let sortie = filtre.outputImage { image = sortie }
        }
        guard let rendu = contexte.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: srgb)
        else { throw Erreur.ecriture("rendu de \(url.lastPathComponent)") }

        var tiff: [CFString: Any] = [:]
        if !copyright.isEmpty { tiff[kCGImagePropertyTIFFCopyright] = copyright }
        var exif: [CFString: Any] = [:]
        if let p = priseEXIF { exif[kCGImagePropertyExifDateTimeOriginal] = p }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: Double(qualite) / 100,
                                      kCGImagePropertyTIFFDictionary: tiff,
                                      kCGImagePropertyExifDictionary: exif]
        try ecrireSansJamaisDemiFichier(final) { provisoire in
            guard let dest = CGImageDestinationCreateWithURL(provisoire as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
            else { throw Erreur.ecriture(provisoire.path) }
            CGImageDestinationAddImage(dest, rendu, props as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw Erreur.ecriture(final.path) }
        }
    }

    // MARK: - IPTC dans l'original, sans recompression

    /// Écrit l'original vers `final` avec les champs IPTC, sans décoder ni recompresser l'image : seules les
    /// métadonnées changent (CGImageDestinationCopyImageSource). Le fichier de départ n'est pas modifié.
    /// `copyright` : le code validé par HUGO, écrit à la place de celui du photographe (nil : on ne touche pas).
    static func copierAvecIPTC(de url: URL, vers final: URL, motsCles: [String], codeOrigine: String,
                               copyright: String? = nil) throws {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw Erreur.illisible(url.lastPathComponent) }
        let meta = CGImageSourceCopyMetadataAtIndex(src, 0, nil).flatMap { CGImageMetadataCreateMutableCopy($0) }
            ?? CGImageMetadataCreateMutable()
        if let copyright, !copyright.isEmpty {
            CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyTIFFDictionary,
                                                         kCGImagePropertyTIFFCopyright, copyright as CFString)
            CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyIPTCDictionary,
                                                         kCGImagePropertyIPTCCopyrightNotice, copyright as CFString)
        }
        if !motsCles.isEmpty {
            CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyIPTCDictionary,
                                                         kCGImagePropertyIPTCKeywords, motsCles as CFArray)
        }
        if !codeOrigine.isEmpty {
            // « Identifiant de la tâche » (Job Identifier) dans Lightroom : garde le code d'origine du photographe.
            CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyIPTCDictionary,
                                                         kCGImagePropertyIPTCOriginalTransmissionReference,
                                                         codeOrigine as CFString)
        }
        guard let type = CGImageSourceGetType(src) else { throw Erreur.illisible(url.lastPathComponent) }
        try ecrireSansJamaisDemiFichier(final) { provisoire in
            guard let dest = CGImageDestinationCreateWithURL(provisoire as CFURL, type, 1, nil)
            else { throw Erreur.ecriture(provisoire.path) }
            let opts: [CFString: Any] = [kCGImageDestinationMetadata: meta,
                                         kCGImageDestinationMergeMetadata: true]
            var err: Unmanaged<CFError>?
            guard CGImageDestinationCopyImageSource(dest, src, opts as CFDictionary, &err) else {
                throw Erreur.ecriture(err?.takeRetainedValue().localizedDescription ?? final.path)
            }
        }
    }

    /// Réécrit les métadonnées d'une photo là où elle est (import, tampon ou dossier de travail de Lightroom),
    /// sans toucher l'image : nouvelle version écrite à côté, puis remplacement.
    static func reecrireMetadonnees(_ url: URL, motsCles: [String], codeOrigine: String, copyright: String?) throws {
        try copierAvecIPTC(de: url, vers: url, motsCles: motsCles, codeOrigine: codeOrigine, copyright: copyright)
    }

    // MARK: - Outils

    /// Écrit dans un fichier caché « .nom.part » du même dossier, puis le renomme : ni Lightroom ni le serveur ne
    /// voient jamais un fichier à moitié écrit.
    static func ecrireSansJamaisDemiFichier(_ final: URL, _ ecrire: (URL) throws -> Void) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: final.deletingLastPathComponent(), withIntermediateDirectories: true)
        let provisoire = final.deletingLastPathComponent().appendingPathComponent(".\(final.lastPathComponent).part")
        try? fm.removeItem(at: provisoire)
        do {
            try ecrire(provisoire)
            if fm.fileExists(atPath: final.path) { try fm.removeItem(at: final) }
            try fm.moveItem(at: provisoire, to: final)
        } catch {
            try? fm.removeItem(at: provisoire)
            throw error
        }
    }
}
