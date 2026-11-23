import AppKit
import Darwin
import Foundation
import TriPhotoCommun

/// Surveille en direct le travail de Lightroom (temps processeur utilisé) pour que Tri-photo lui laisse la place.
final class Regulateur {
    private var dernierTemps: UInt64 = 0          // temps processeur cumulé de Lightroom, en nanosecondes
    private var derniereMesure = Date()
    private var pid: pid_t = 0
    private let coeurs = Double(ProcessInfo.processInfo.activeProcessorCount)
    private let echelle: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info.denom == 0 ? 1 : Double(info.numer) / Double(info.denom)
    }()

    /// Part du Mac utilisée par Lightroom depuis la dernière mesure (0 = rien, 1 = tous les cœurs).
    /// 0 si Lightroom n'est pas ouvert.
    func chargeLightroom() -> Double {
        guard let p = pidLightroom() else {
            pid = 0
            return 0
        }
        var info = proc_taskinfo()
        let taille = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(p, PROC_PIDTASKINFO, 0, &info, taille) == taille else { return 0 }
        // Sur les puces Apple, ces temps sont en unités de l'horloge machine ; sur Intel, l'échelle vaut 1.
        let temps = UInt64(Double(info.pti_total_user + info.pti_total_system) * echelle)
        let maintenant = Date()
        defer { dernierTemps = temps; derniereMesure = maintenant; pid = p }
        guard p == pid, dernierTemps > 0, temps >= dernierTemps else { return 0 }
        let ecoule = maintenant.timeIntervalSince(derniereMesure)
        guard ecoule > 0.2 else { return 0 }
        return min(Double(temps - dernierTemps) / 1e9 / ecoule / coeurs, 1)
    }

    private func pidLightroom() -> pid_t? {
        NSWorkspace.shared.runningApplications.first {
            ($0.bundleIdentifier ?? "").hasPrefix("com.adobe.Lightroom")
        }?.processIdentifier
    }
}
