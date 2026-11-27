import Foundation
import XCTest
@testable import TriPhotoMoteur

/// Galerie écrite dans un dossier du Mac (pas de connexion au concours) : ajout, remplacement, retrait.
final class GalerieDossierTests: XCTestCase {
    private func config(_ dossier: URL) -> ConfigGalerieEnLigne {
        ConfigGalerieEnLigne(protocole: .ftp, hote: "", port: 0, identifiant: "", motDePasse: "", dossier: "",
                             accepterCertificat: false, laNuit: true, heureNuit: 22, heureMatin: 7, limiteKo: 0,
                             cote: 1200, qualite: 56, cube: nil, cubeDuServeur: false, numero: true, auteurParDefaut: "",
                             depuis: Date(), fichierEtat: dossier.appendingPathComponent("etat.json"),
                             dossierLocal: dossier.path)
    }

    /// Le dossier du concours (« 26-11-29_LAMOTTE ») est créé dans le dossier choisi ; le dossier choisi, lui, jamais.
    func testDossierDuConcours() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("galerie-concours-\(UUID().uuidString)")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        var c = config(base)
        c.sousDossierLocal = "26-11-29_LAMOTTE"
        let t = Transfert(config: c)
        let a = base.appendingPathComponent("a.jpg")
        try Data("un".utf8).write(to: a)
        try t.envoyer([(a, "IMG_1-32.JPG")])
        XCTAssertTrue(fm.fileExists(atPath: base.appendingPathComponent("26-11-29_LAMOTTE/IMG_1-32.JPG").path))

        var absent = config(base.appendingPathComponent("debranche"))
        absent.sousDossierLocal = "26-11-29_LAMOTTE"
        XCTAssertThrowsError(try Transfert(config: absent).envoyer([(a, "IMG_1-32.JPG")]))
        XCTAssertFalse(fm.fileExists(atPath: base.appendingPathComponent("debranche").path))
    }

    func testCopieRemplaceRetire() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("galerie-dossier-\(UUID().uuidString)")
        let dest = base.appendingPathComponent("galerie")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        let c = config(dest)
        XCTAssertTrue(c.versDossier)
        XCTAssertTrue(c.estRegle)
        let t = Transfert(config: c)
        XCTAssertNoThrow(try t.tester())

        let a = base.appendingPathComponent("a.jpg")
        try Data("un".utf8).write(to: a)
        try t.envoyer([(a, "IMG_1-32.JPG")])
        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("IMG_1-32.JPG")), Data("un".utf8))

        try Data("deux".utf8).write(to: a)
        try t.envoyer([(a, "IMG_1-32.JPG")])
        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("IMG_1-32.JPG")), Data("deux".utf8))
        let restes = try fm.contentsOfDirectory(atPath: dest.path)
        XCTAssertEqual(restes, ["IMG_1-32.JPG"], "aucun fichier temporaire laissé")

        try t.supprimer(["IMG_1-32.JPG", "absente.JPG"])
        XCTAssertFalse(fm.fileExists(atPath: dest.appendingPathComponent("IMG_1-32.JPG").path))
    }

    func testDisqueDebrancheJamaisRecree() {
        let absent = FileManager.default.temporaryDirectory.appendingPathComponent("absent-\(UUID().uuidString)")
        let t = Transfert(config: config(absent))
        XCTAssertThrowsError(try t.tester())
        XCTAssertThrowsError(try t.envoyer([(absent, "x.JPG")]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: absent.path))
    }
}
