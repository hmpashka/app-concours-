import XCTest
@testable import TriPhotoCommun

final class AttributionTests: XCTestCase {
    // Piste 1 : n° 13 de 1000 à 1080 (arrivée), n° 14 entre à 1100, part à 1110, arrive à 1190.
    let passages = [
        Passage(source: "P1", epreuve: "11", dossard: "13", entree: 1000, depart: 1005, fin: 1080),
        Passage(source: "P1", epreuve: "11", dossard: "14", entree: 1100, depart: 1110, fin: 1190),
    ]

    func code(_ s: String) -> CodePassage { CodePassage.lire(s)! }

    func testCodeJuste() {
        guard case .conforme = Attribution.decider(code: code("#11_14"), t: 1150, passages: passages) else {
            return XCTFail("le code est juste")
        }
    }

    func testCodeFauxProposeLeChrono() {
        guard case .proposer(let c, _, let confiance, _) = Attribution.decider(code: code("#11_25"), t: 1150, passages: passages)
        else { return XCTFail("proposition attendue") }
        XCTAssertEqual(c.texte, "#11_14")
        XCTAssertEqual(confiance, 95)
    }

    func testCode00ProposeLeDossard() {
        guard case .proposer(let c, let raison, _, _) = Attribution.decider(code: code("#11_00"), t: 1150, passages: passages)
        else { return XCTFail("proposition attendue") }
        XCTAssertEqual(c.texte, "#11_14")
        XCTAssertTrue(raison.contains("_00"))
    }

    func testFinDeTourToleree() {
        // 1090 : après l'arrivée du 13 (1080) mais dans les 15 s de tolérance, avant l'entrée du 14
        guard case .conforme = Attribution.decider(code: code("#11_13"), t: 1090, passages: passages) else {
            return XCTFail("fin de tour : pas de correction")
        }
    }

    func testLatenceAuChangement() {
        // 1103 : le 14 vient d'entrer, la photo porte encore le 13 : normal
        guard case .conforme = Attribution.decider(code: code("#11_13"), t: 1103, passages: passages) else {
            return XCTFail("latence tolérée")
        }
        guard case .proposer = Attribution.decider(code: code("#11_13"), t: 1130, passages: passages) else {
            return XCTFail("au-delà de la latence : proposition")
        }
    }

    func testAttenteApresLeDernier() {
        guard case .attendre = Attribution.decider(code: code("#11_14"), t: 1300, passages: passages) else {
            return XCTFail("le chrono n'a pas encore le suivant")
        }
    }

    func testRemiseDesPrixJamaisCorrigee() {
        guard case .conforme = Attribution.decider(code: code("#11_99"), t: 1150, passages: passages) else {
            return XCTFail("_99 n'est jamais corrigé")
        }
    }

    func testDeuxPistesDepartageesParLEpreuve() {
        let deux = passages + [Passage(source: "P2", epreuve: "5", dossard: "40", entree: 1120, depart: 1125, fin: 1200)]
        guard case .proposer(let c, _, _, _) = Attribution.decider(code: code("#05_41"), t: 1150, passages: deux)
        else { return XCTFail("proposition sur la piste 2") }
        XCTAssertEqual(c.texte, "#05_40")
        guard case .garder = Attribution.decider(code: nil, t: 1150, passages: deux) else {
            return XCTFail("sans code ni piste connue : rien à proposer")
        }
        guard case .proposer(let c2, _, _, _) = Attribution.decider(code: nil, t: 1150, passages: deux, piste: "P2")
        else { return XCTFail("piste du boîtier connue") }
        XCTAssertEqual(c2.texte, "#05_40")
    }

    func testJuryARemplaceLeCavalier() {
        let p = [Passage(source: "P1", epreuve: "11", dossard: "21", entree: 1000, depart: 1010, fin: 1080,
                         remplaceDossard: "25", remplaceA: 1004)]
        guard case .proposer(let c, let raison, let confiance, _) = Attribution.decider(code: code("#11_25"), t: 1050, passages: p)
        else { return XCTFail("proposition attendue") }
        XCTAssertEqual(c.texte, "#11_21")
        XCTAssertTrue(raison.contains("remplacé"))
        XCTAssertGreaterThanOrEqual(confiance, 90)
    }

    func testLecturePassageHM() throws {
        let json = #"{"source":"piste1","depart":1005.5,"entree":1000,"fin":1080,"epreuve":"11","dossard":"13","cavalier":"A","cheval":"B","remplace":{"dossard":"25","a":1002}}"#
        let d = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let p = try XCTUnwrap(Passage.depuisHM(d))
        XCTAssertEqual(p.debut, 1000)
        XCTAssertEqual(p.remplaceDossard, "25")
        XCTAssertEqual(p.code.texte, "#11_13")
    }
}
