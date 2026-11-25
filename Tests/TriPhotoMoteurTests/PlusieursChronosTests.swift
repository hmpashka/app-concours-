import XCTest
@testable import TriPhotoMoteur
import TriPhotoCommun

/// Plusieurs chronos sur un concours : deux HM Timing (dont un qui chronomètre deux pistes) et une capture Horse & Comp.
final class PlusieursChronosTests: XCTestCase {
    private func fichier(_ passages: [[String: Any]]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("passages-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: ["passages": passages]).write(to: url)
        return url
    }

    func testPistesSepareesEtNommees() throws {
        let a = try fichier([
            ["source": "Piste 1", "epreuve": "3", "dossard": "12", "depart": 1000],
            ["source": "Piste 2", "epreuve": "5", "dossard": "40", "depart": 1010],
        ])
        let b = try fichier([["source": "Piste 1", "epreuve": "7", "dossard": "101", "depart": 1020]])
        let ch = Chrono(config: ConfigChrono(liens: [
            ConfigLienChrono(id: "A", nom: "HM remorque", fichierPassages: a, prefixer: true),
            ConfigLienChrono(id: "B", nom: "HM carrière", fichierPassages: b, prefixer: true),
            ConfigLienChrono(id: "C", nom: "Indoor", externe: true, sourceFixe: "Indoor"),
        ]))
        XCTAssertNil(ch.ok)
        ch.actualiserSiBesoin(depuis: Date())
        // la capture Horse & Comp n'a encore rien envoyé : les HM Timing répondent quand même
        XCTAssertEqual(ch.ok, true)
        XCTAssertEqual(ch.okPour(piste: "HM remorque · Piste 2"), true)
        XCTAssertNil(ch.okPour(piste: "Indoor"))
        ch.recevoir(lien: "C", [Passage(source: "Horses & Competitions", epreuve: "9", dossard: "3", depart: 1030)], erreur: "")
        XCTAssertEqual(ch.okPour(piste: "Indoor"), true)

        let cles = Set(ch.passages.map(\.source))
        XCTAssertEqual(cles, ["HM remorque · Piste 1", "HM remorque · Piste 2", "HM carrière · Piste 1", "Indoor"])
        XCTAssertEqual(ch.passages.map(\.depart), [1000, 1010, 1020, 1030])
        XCTAssertEqual(ch.etats.first { $0.id == "A" }?.sources, ["Piste 1", "Piste 2"])
        XCTAssertEqual(ConfigLienChrono.brut("HM remorque · Piste 2"), "Piste 2")
    }

    func testUnSeulChronoGardeLesNomsDeHMTiming() throws {
        let a = try fichier([["source": "Piste 1", "epreuve": "3", "dossard": "12", "depart": 1000]])
        let ch = Chrono(config: ConfigChrono(adresse: "", codeRegie: "", codeTechnicien: "", fichierPassages: a))
        ch.actualiserSiBesoin(depuis: Date())
        XCTAssertEqual(ch.passages.first?.source, "Piste 1")
        XCTAssertEqual(ch.okPour(piste: nil), true)
    }

    func testChronoEnPanneNeBloquePasLesAutres() throws {
        let a = try fichier([["source": "Piste 1", "epreuve": "3", "dossard": "12", "depart": 1000]])
        let ch = Chrono(config: ConfigChrono(liens: [
            ConfigLienChrono(id: "A", nom: "HM A", fichierPassages: a),
            ConfigLienChrono(id: "B", nom: "HM B", fichierPassages: URL(fileURLWithPath: "/nexiste/pas.json"), prefixer: true),
        ]))
        ch.actualiserSiBesoin(depuis: Date())
        XCTAssertEqual(ch.okPour(piste: "Piste 1"), true)
        XCTAssertEqual(ch.ok, true)
        XCTAssertTrue(ch.erreur.contains("HM B"))
    }
}
