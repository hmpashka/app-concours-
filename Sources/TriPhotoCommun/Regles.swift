import Foundation

/// Quand vider le dossier tampon vers l'import Lightroom (option « dossier tampon »).
public enum RegleTampon {
    public enum Decision: Equatable {
        case attendre
        case envoyer(raison: String)
    }

    /// - Parameters:
    ///   - derniereParBoitier: pour chaque boîtier qui a des photos dans le tampon, l'heure de sa dernière photo reçue.
    ///   - premiereEnAttente: heure d'arrivée de la plus ancienne photo du tampon.
    public static func decider(enAttente: Int, tailleLot: Int, derniereParBoitier: [String: Date],
                               premiereEnAttente: Date?, maintenant: Date, silenceMinutes: Int,
                               lightroomOccupe: Bool, retarderSiOccupe: Bool) -> Decision {
        guard enAttente > 0 else { return .attendre }
        let silence = TimeInterval(max(silenceMinutes, 1) * 60)
        var raison: String?
        if enAttente >= max(tailleLot, 1) {
            raison = "lot complet (\(enAttente) photos)"
        } else if let muet = derniereParBoitier.first(where: { maintenant.timeIntervalSince($0.value) >= silence }) {
            raison = "boîtier silencieux depuis \(silenceMinutes) min (\(muet.key))"
        }
        guard let raison else { return .attendre }
        // Lightroom occupé : on retarde le lot, mais jamais une photo ne reste bloquée plus de 2 fois le délai.
        if lightroomOccupe && retarderSiOccupe,
           let p = premiereEnAttente, maintenant.timeIntervalSince(p) < 2 * silence {
            return .attendre
        }
        return .envoyer(raison: raison)
    }
}

/// Nombre de photos traitées en même temps, selon le travail de Lightroom (régulateur de performances).
/// Test de vitesse du 23/11 : 3 en parallèle suffisent largement (≈ 320 photos/min seul, 225 à 255 avec
/// Lightroom à fond) pour un besoin de 100 par minute.
public enum RegleRegulateur {
    /// - Parameter chargeLightroom: part du Mac utilisée par Lightroom, de 0 (rien) à 1 (tous les cœurs).
    ///   - plafond: photos traitées en même temps au plus (voir `plafond(reglage:)`).
    /// Rafale (des photos attendent) : toutes les files sont ouvertes, même si Lightroom travaille — le tri est en
    /// priorité basse, macOS donne toujours la main à Lightroom d'abord. Au calme : moins de files, Mac plus léger.
    public static func ouvriers(chargeLightroom: Double, fileEnRetard: Bool, plafond: Int = 3) -> Int {
        let p = max(1, plafond)
        if fileEnRetard { return p }
        switch chargeLightroom {
        case ..<0.15: return max(1, min(p, max(3, p / 2)))
        case ..<0.45: return max(1, min(p, 2))
        default: return 1
        }
    }

    /// Plafond de photos traitées en même temps : le réglage s'il est donné (2 à 16), sinon selon le Mac :
    /// cœurs moins 2 (Lightroom et macOS), entre 3 et 8 (au-delà, le disque et le serveur ne suivent plus).
    public static func plafond(reglage: Int, coeurs: Int = ProcessInfo.processInfo.activeProcessorCount) -> Int {
        if reglage > 0 { return min(16, max(1, reglage)) }
        return min(8, max(3, coeurs - 2))
    }

    /// Lightroom est-il « occupé » (import, aperçus, export) ?
    public static func lightroomOccupe(chargeLightroom: Double) -> Bool { chargeLightroom >= 0.25 }
}
