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
    public static func ouvriers(chargeLightroom: Double, fileEnRetard: Bool) -> Int {
        if fileEnRetard { return 3 }            // la file prend du retard : on rattrape, la priorité basse protège Lightroom
        switch chargeLightroom {
        case ..<0.15: return 3
        case ..<0.45: return 2
        default: return 1
        }
    }

    /// Lightroom est-il « occupé » (import, aperçus, export) ?
    public static func lightroomOccupe(chargeLightroom: Double) -> Bool { chargeLightroom >= 0.25 }
}
