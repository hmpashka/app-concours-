import Foundation

/// Surveille le dossier de travail de Lightroom (liste des fichiers seulement, toutes les 15 s, priorité basse) :
/// - photo rangée ou déplacée par Lightroom : on retient où elle est ;
/// - photo modifiée (Lightroom a écrit ses métadonnées, par exemple un nouveau code) : signalée une fois que le
///   fichier ne bouge plus ;
/// - photo disparue deux fois de suite : signalée comme supprimée dans Lightroom.
/// Si le dossier lui-même est introuvable (disque débranché), rien n'est signalé.
final class SuiviLightroom {
    struct Constat {
        var vues: [(String, URL)] = []          // nom → emplacement (nouvelles ou déplacées)
        var modifiees: [(String, URL)] = []
        var disparues: [String] = []
    }

    private struct Vu: Equatable {
        var url: URL
        var date: Date
        var taille: Int
    }

    let dossier: URL
    private let fil = DispatchQueue(label: "tri-photo.suivi-lightroom", qos: .utility)
    private var connus: [String: Vu] = [:]          // clé : nom en minuscules
    private var aConfirmer: [String: Vu] = [:]      // modifiés au tour précédent : signalés s'ils n'ont plus bougé
    private var absents: [String: Int] = [:]
    private var occupe = false

    init(dossier: URL) { self.dossier = dossier }

    func examiner(_ fini: @escaping (Constat) -> Void) {
        fil.async { [self] in
            guard !occupe else { return }
            occupe = true
            defer { occupe = false }
            var estDossier: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dossier.path, isDirectory: &estDossier), estDossier.boolValue else { return }
            let actuels = lister()
            var c = Constat()
            for (cle, v) in actuels {
                if let ancien = connus[cle] {
                    if ancien.url != v.url { c.vues.append((v.url.lastPathComponent, v.url)) }
                    if ancien.date != v.date || ancien.taille != v.taille {
                        aConfirmer[cle] = v                       // vient de changer : on attend qu'il ne bouge plus
                    } else if let a = aConfirmer[cle], a == v {
                        aConfirmer[cle] = nil
                        c.modifiees.append((v.url.lastPathComponent, v.url))
                    }
                } else {
                    c.vues.append((v.url.lastPathComponent, v.url))     // nouvelle (ou premier tour)
                }
                absents[cle] = nil
            }
            for cle in connus.keys where actuels[cle] == nil {
                let n = (absents[cle] ?? 0) + 1
                absents[cle] = n
                if n >= 2 {
                    c.disparues.append(connus[cle]!.url.lastPathComponent)
                    absents[cle] = nil
                    connus[cle] = nil
                    aConfirmer[cle] = nil
                }
            }
            // les absents d'un tour restent « connus » jusqu'à confirmation
            for (cle, v) in actuels { connus[cle] = v }
            if !c.vues.isEmpty || !c.modifiees.isEmpty || !c.disparues.isEmpty { fini(c) }
        }
    }

    private func lister() -> [String: Vu] {
        let cles: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let e = FileManager.default.enumerator(at: dossier, includingPropertiesForKeys: cles,
                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [:] }
        var l: [String: Vu] = [:]
        for case let u as URL in e {
            let ext = u.pathExtension.lowercased()
            guard ext == "jpg" || ext == "jpeg" else { continue }
            let r = try? u.resourceValues(forKeys: Set(cles))
            l[u.lastPathComponent.lowercased()] = Vu(url: u, date: r?.contentModificationDate ?? .distantPast, taille: r?.fileSize ?? 0)
        }
        return l
    }
}
