import Foundation
import XCTest
import TriPhotoCommun
@testable import TriPhotoMoteur

/// Photos à décider (HUGO 28/11) : réglages des catégories et dossier d'attente sur le serveur.
final class PhotosADeciderTests: XCTestCase {
    func testReglagesParDefautEtPartages() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("memoire-\(UUID().uuidString)")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        let m = Memoire(dossier: base.appendingPathComponent("Tri-photo Mémoire"))
        m.creer()
        XCTAssertTrue(m.reglage("floue").supprimer)
        XCTAssertTrue(m.reglage("sol").supprimer)
        XCTAssertTrue(m.reglage("ratee").supprimer)
        XCTAssertFalse(m.reglage("ratee").detection)
        XCTAssertFalse(m.reglage("bonne").supprimer)
        XCTAssertEqual(m.reglage("floue").jauge, 0)
        // le fichier de réglages n'est jamais pris pour une catégorie
        m.changerReglage("tapis rose") { $0.supprimer = true; $0.jauge = 90 }
        m.compterDecision("sol", juste: true)
        m.compterDecision("sol", juste: false)
        XCTAssertFalse(m.categories().contains { $0.cle.hasPrefix(".") })
        XCTAssertTrue(m.categories().contains { $0.cle == "ratee" })
        // relu par un autre Mac (autre objet, même dossier)
        let autre = Memoire(dossier: m.dossier)
        XCTAssertEqual(autre.reglage("tapis rose").jauge, 90)
        XCTAssertEqual(autre.reglage("sol").validees, 1)
        XCTAssertEqual(autre.reglage("sol").fausses, 1)
        XCTAssertEqual(autre.reglage("sol").justes, 50)
        m.compterDecision("sol", juste: false, annuler: true)
        XCTAssertEqual(Memoire(dossier: m.dossier).reglage("sol").fausses, 0)
    }

    func testDossierAttenteHorsDesEpreuves() {
        let serveur = URL(fileURLWithPath: "/Volumes/Serveur/Concours")
        let c = ConfigMoteur(reception: URL(fileURLWithPath: "/tmp/r"), importLightroom: URL(fileURLWithPath: "/tmp/i"),
                             tampon: nil, serveur: serveur, cote: 1500, qualite: 56, cube: nil, concours: nil,
                             tailleLot: 10, silenceMinutes: 5, retarderSiOccupe: false, journal: URL(fileURLWithPath: "/tmp/j.sqlite"))
        let code = CodePassage.lire("#08_14")
        let normal = Moteur.dossierServeur(pour: code, config: c)
        let attente = Moteur.dossierAttente(pour: code, config: c)
        XCTAssertEqual(attente.path, serveur.appendingPathComponent("_À décider").appendingPathComponent(normal.lastPathComponent).path)
        XCTAssertEqual(Moteur.dossierAttente(pour: nil, config: c).path,
                       serveur.appendingPathComponent("_À décider/À attribuer").path)
    }
}
