import XCTest
@testable import TriPhotoCommun

final class SuiviIncrustationTests: XCTestCase {
    let concours = Concours(numero: "1", nom: "Essai", format: .ffeCompet, epreuves: [
        Epreuve(numero: "04", nom: "CCI1*-INTRO", engages: [Engage(dossard: "124", cavalier: "TOUZAINT Nicolas", cheval: "JAVA LOUVO"),
                                                          Engage(dossard: "125", cavalier: "B", cheval: "C")]),
        Epreuve(numero: "05", nom: "Amateur 2 Grand Prix", engages: []),
    ])

    func lu(_ d: String, _ temps: String = "", ep: String = "CCI1*-INTRO") -> [String: String] {
        ["dossard": d, "nom": "N. TOUZAINT | JAVA LOUVO", "epreuve": ep, "temps": temps]
    }

    func testUnPassageApresDeuxLecturesPareilles() {
        var s = SuiviIncrustation()
        XCTAssertFalse(s.lecture(lu("124 FRA"), t: 100, concours: concours))
        XCTAssertTrue(s.lecture(lu("124 FRA"), t: 100.5, concours: concours))
        XCTAssertEqual(s.passages.count, 1)
        XCTAssertEqual(s.passages[0].code.texte, "#04_124")
        XCTAssertEqual(s.passages[0].cheval, "JAVA LOUVO")
        XCTAssertEqual(s.passages[0].debut, 100.5)
        XCTAssertFalse(s.lecture(lu("124 FRA"), t: 101, concours: concours))   // même couple : rien de neuf
    }

    func testCoupleSuivantFermeLePrecedent() {
        var s = SuiviIncrustation()
        s.lecture(lu("124"), t: 100, concours: concours)
        s.lecture(lu("124"), t: 100.5, concours: concours)
        s.lecture(lu("125"), t: 200, concours: concours)
        s.lecture(lu("125"), t: 200.5, concours: concours)
        XCTAssertEqual(s.passages.count, 2)
        XCTAssertEqual(s.passages[0].fin, 200.5)
        XCTAssertEqual(s.passages[1].dossard, "125")
    }

    func testArriveeQuandLeTempsSArrete() {
        var s = SuiviIncrustation()
        s.lecture(lu("124", "0"), t: 100, concours: concours)
        s.lecture(lu("124", "1"), t: 101, concours: concours)
        s.lecture(lu("124", "74"), t: 174, concours: concours)
        s.lecture(lu("124", "74"), t: 176, concours: concours)
        XCTAssertNil(s.passages[0].fin)
        s.lecture(lu("124", "74"), t: 177.5, concours: concours)
        XCTAssertEqual(s.passages[0].fin, 174)
    }

    func testEpreuveParNumeroOuParNom() {
        XCTAssertEqual(SuiviIncrustation.trouverEpreuve("5 - Amateur 2 GP", dans: concours)?.numero, "05")
        XCTAssertEqual(SuiviIncrustation.trouverEpreuve("Amateur 2 Grand Prix", dans: concours)?.numero, "05")
        XCTAssertNil(SuiviIncrustation.trouverEpreuve("Pro Elite", dans: concours))
    }

    func testEpreuveForceeALaMain() {
        var s = SuiviIncrustation()
        s.lecture(lu("12", ep: "illisible"), t: 1, concours: concours, epreuveForcee: "5")
        s.lecture(lu("12", ep: "illisible"), t: 2, concours: concours, epreuveForcee: "5")
        XCTAssertEqual(s.passages.first?.code.texte, "#05_12")
    }

    func testDossardLu() {
        XCTAssertEqual(SuiviIncrustation.dossardLu("DOSSARD | 124 | FRA"), "124")
        XCTAssertEqual(SuiviIncrustation.dossardLu("FRA"), "")
    }
}
