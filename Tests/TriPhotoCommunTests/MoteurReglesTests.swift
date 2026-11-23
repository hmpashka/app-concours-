import XCTest
@testable import TriPhotoCommun

final class RenommageTests: XCTestCase {
    func testNomAvecMinuteDePriseDeVue() {
        XCTAssertEqual(Renommage.nom(origine: "IMG_4410.JPG", priseEXIF: "2026:11:29 14:32:07"), "IMG_4410_1432.JPG")
        XCTAssertEqual(Renommage.nom(origine: "_MG_0001.jpg", priseEXIF: "2026:11:29 09:05:59"), "_MG_0001_0905.jpg")
    }

    func testSansDateEXIF() {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 29; c.hour = 8; c.minute = 7
        let d = Calendar.current.date(from: c)!
        XCTAssertEqual(Renommage.nom(origine: "IMG_1.JPG", priseEXIF: nil, secours: d), "IMG_1_0807.JPG")
        XCTAssertEqual(Renommage.nom(origine: "IMG_1.JPG", priseEXIF: "abîmée"), "IMG_1_0000.JPG")
    }

    func testNomLibre() {
        let pris: Set = ["A_1432.JPG", "A_1432-2.JPG"]
        XCTAssertEqual(Renommage.libre("A_1432.JPG") { pris.contains($0) }, "A_1432-3.JPG")
        XCTAssertEqual(Renommage.libre("B.JPG") { pris.contains($0) }, "B.JPG")
    }
}

final class FichierCubeTests: XCTestCase {
    func testLectureEtOrdre() throws {
        let texte = """
        TITLE "essai"
        # commentaire
        LUT_3D_SIZE 2
        0 0 0
        1 0 0
        0 1 0
        1 1 0
        0 0 1
        1 0 1
        0 1 1
        1 1 1
        """
        let c = try FichierCube(texte: texte)
        XCTAssertEqual(c.taille, 2)
        XCTAssertEqual(c.valeurs.count, 2 * 2 * 2 * 4)
        XCTAssertEqual(Array(c.valeurs[4..<8]), [1, 0, 0, 1])     // le rouge varie le plus vite
        XCTAssertEqual(Array(c.valeurs[28..<32]), [1, 1, 1, 1])
    }

    func testDomaine() throws {
        let c = try FichierCube(texte: "LUT_3D_SIZE 2\nDOMAIN_MIN 0 0 0\nDOMAIN_MAX 2 2 2\n" + String(repeating: "2 1 0\n", count: 8))
        XCTAssertEqual(Array(c.valeurs[0..<4]), [1, 0.5, 0, 1])
    }

    func testErreurs() {
        XCTAssertThrowsError(try FichierCube(texte: "LUT_1D_SIZE 4\n0 0 0"))
        XCTAssertThrowsError(try FichierCube(texte: "LUT_3D_SIZE 2\n0 0 0\n1 1 1")) { e in
            XCTAssertEqual(e as? FichierCube.Erreur, .incomplet(lues: 2, attendues: 8))
        }
        XCTAssertThrowsError(try FichierCube(texte: "0 0 0"))
    }
}

final class ReglesTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testTamponLotComplet() {
        let d = RegleTampon.decider(enAttente: 20, tailleLot: 20, derniereParBoitier: ["R5": t0], premiereEnAttente: t0,
                                    maintenant: t0.addingTimeInterval(10), silenceMinutes: 5,
                                    lightroomOccupe: false, retarderSiOccupe: true)
        XCTAssertEqual(d, .envoyer(raison: "lot complet (20 photos)"))
    }

    func testTamponUnBoitierSilencieuxSuffit() {
        let maintenant = t0.addingTimeInterval(400)
        let d = RegleTampon.decider(enAttente: 3, tailleLot: 20,
                                    derniereParBoitier: ["R5": t0, "R6": maintenant.addingTimeInterval(-5)],
                                    premiereEnAttente: t0, maintenant: maintenant, silenceMinutes: 5,
                                    lightroomOccupe: false, retarderSiOccupe: true)
        guard case .envoyer = d else { return XCTFail("le tampon aurait dû partir") }
    }

    func testTamponAttend() {
        let d = RegleTampon.decider(enAttente: 3, tailleLot: 20, derniereParBoitier: ["R5": t0], premiereEnAttente: t0,
                                    maintenant: t0.addingTimeInterval(60), silenceMinutes: 5,
                                    lightroomOccupe: false, retarderSiOccupe: true)
        XCTAssertEqual(d, .attendre)
        XCTAssertEqual(RegleTampon.decider(enAttente: 0, tailleLot: 1, derniereParBoitier: [:], premiereEnAttente: nil,
                                           maintenant: t0, silenceMinutes: 5, lightroomOccupe: false, retarderSiOccupe: true),
                       .attendre)
    }

    func testLightroomOccupeRetardeMaisJamaisBloque() {
        let base: (Date) -> RegleTampon.Decision = { m in
            RegleTampon.decider(enAttente: 20, tailleLot: 20, derniereParBoitier: ["R5": m], premiereEnAttente: self.t0,
                                maintenant: m, silenceMinutes: 5, lightroomOccupe: true, retarderSiOccupe: true)
        }
        XCTAssertEqual(base(t0.addingTimeInterval(60)), .attendre)
        guard case .envoyer = base(t0.addingTimeInterval(601)) else { return XCTFail("10 min max de retard") }
    }

    func testRegulateur() {
        XCTAssertEqual(RegleRegulateur.ouvriers(chargeLightroom: 0.05, fileEnRetard: false), 3)
        XCTAssertEqual(RegleRegulateur.ouvriers(chargeLightroom: 0.3, fileEnRetard: false), 2)
        XCTAssertEqual(RegleRegulateur.ouvriers(chargeLightroom: 0.8, fileEnRetard: false), 1)
        XCTAssertEqual(RegleRegulateur.ouvriers(chargeLightroom: 0.8, fileEnRetard: true), 3)
    }
}
