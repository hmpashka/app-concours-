import Foundation
import ImageIO

/// Mode entraînement : rejoue les photos d'un ancien concours dans le dossier de réception, comme si les boîtiers
/// les envoyaient, pour tester Groom Pix sans risque. Les photos de départ ne sont jamais modifiées : ce sont
/// des copies qui arrivent dans le dossier de réception.
@MainActor
final class Entrainement: ObservableObject {
    enum Rythme: Hashable {
        /// Respecte les écarts entre les heures de prise de vue, accélérés (×1 = temps réel).
        case commeAuConcours(acceleration: Double)
        /// Cadence fixe, en photos par minute.
        case cadence(parMinute: Double)
    }

    struct Photo {
        let url: URL
        let prise: Date?
    }

    @Published var dossierSource: URL?
    @Published var dossierCible: URL?
    @Published private(set) var photos: [Photo] = []
    @Published private(set) var envoyees = 0
    @Published private(set) var enCours = false
    @Published private(set) var message = ""
    @Published private(set) var debut: Date?

    private var tache: Task<Void, Never>?

    var total: Int { photos.count }

    /// Photos par minute réellement envoyées depuis le départ.
    var cadenceReelle: Double {
        guard let debut, envoyees > 0 else { return 0 }
        let minutes = Date().timeIntervalSince(debut) / 60
        return minutes > 0 ? Double(envoyees) / minutes : 0
    }

    /// Liste les JPEG du dossier choisi (sous-dossiers compris), dans l'ordre de prise de vue.
    func preparer(source: URL) {
        dossierSource = source
        message = "Lecture des photos…"
        photos = []
        Task.detached(priority: .utility) {
            let liste = Entrainement.lister(source)
            await MainActor.run {
                self.photos = liste
                self.envoyees = 0
                self.message = liste.isEmpty ? "Aucune photo JPEG dans ce dossier." : "\(liste.count) photos prêtes."
            }
        }
    }

    func demarrer(rythme: Rythme) {
        guard !enCours, let cible = dossierCible, !photos.isEmpty else { return }
        if cible.standardizedFileURL == dossierSource?.standardizedFileURL {
            message = "Le dossier de réception doit être différent du dossier des photos à rejouer."
            return
        }
        enCours = true
        debut = Date()
        message = ""
        let aEnvoyer = Array(photos.dropFirst(envoyees))
        tache = Task.detached(priority: .utility) { [weak self] in
            var precedente: Date?
            for photo in aEnvoyer {
                if Task.isCancelled { break }
                let attente = Entrainement.attente(rythme: rythme, prise: photo.prise, precedente: precedente)
                precedente = photo.prise ?? precedente
                if attente > 0 { try? await Task.sleep(nanoseconds: UInt64(attente * 1_000_000_000)) }
                if Task.isCancelled { break }
                let erreur = Entrainement.deposer(photo.url, dans: cible)
                await MainActor.run {
                    guard let self else { return }
                    if let erreur { self.message = erreur } else { self.envoyees += 1 }
                }
            }
            await MainActor.run {
                guard let self else { return }
                self.enCours = false
                if self.envoyees >= self.total { self.message = "Terminé : \(self.envoyees) photos rejouées." }
            }
        }
    }

    func arreter() {
        tache?.cancel()
        tache = nil
        enCours = false
        message = "En pause après \(envoyees) photos. « Démarrer » reprend où on s'était arrêté."
    }

    func recommencer() {
        arreter()
        envoyees = 0
        message = "\(photos.count) photos prêtes."
    }

    // MARK: - Travail en arrière-plan

    nonisolated static func attente(rythme: Rythme, prise: Date?, precedente: Date?) -> Double {
        switch rythme {
        case .cadence(let parMinute):
            return parMinute > 0 ? 60 / parMinute : 0
        case .commeAuConcours(let acceleration):
            guard let prise, let precedente, acceleration > 0 else { return 0 }
            // une pause de plus de 2 minutes entre deux photos (entre deux épreuves) est ramenée à 2 minutes
            return min(max(prise.timeIntervalSince(precedente), 0), 120) / acceleration
        }
    }

    /// Copie sous un nom provisoire puis renommage : Groom Pix ne voit jamais une photo à moitié écrite.
    nonisolated static func deposer(_ url: URL, dans cible: URL) -> String? {
        let fm = FileManager.default
        let final = cible.appendingPathComponent(url.lastPathComponent)
        if fm.fileExists(atPath: final.path) { return nil } // déjà rejouée : on passe à la suivante
        let provisoire = cible.appendingPathComponent(".\(url.lastPathComponent).part")
        do {
            try? fm.removeItem(at: provisoire)
            try fm.copyItem(at: url, to: provisoire)
            try fm.moveItem(at: provisoire, to: final)
            return nil
        } catch {
            return "Copie impossible de \(url.lastPathComponent) : \(error.localizedDescription)"
        }
    }

    nonisolated static func lister(_ dossier: URL) -> [Photo] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: dossier, includingPropertiesForKeys: [.isRegularFileKey],
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var liste: [Photo] = []
        for case let url as URL in e {
            let ext = url.pathExtension.lowercased()
            guard ext == "jpg" || ext == "jpeg" else { continue }
            liste.append(Photo(url: url, prise: heureDePrise(url)))
        }
        return liste.sorted {
            switch ($0.prise, $1.prise) {
            case let (a?, b?) where a != b: return a < b
            default: return $0.url.lastPathComponent < $1.url.lastPathComponent
            }
        }
    }

    /// Heure de prise de vue (EXIF), lue dans l'en-tête seulement : l'image n'est pas décodée.
    nonisolated static func heureDePrise(_ url: URL) -> Date? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let texte = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard var date = f.date(from: texte) else { return nil }
        if let sub = exif[kCGImagePropertyExifSubsecTimeOriginal] as? String, let v = Double("0." + sub) {
            date += v
        }
        return date
    }
}
