import XCTest
@testable import TriPhotoCommun

/// Collections dynamiques Lightroom : mêmes noms, même gabarit que l'ancien outil de HUGO.
final class CollectionsLightroomTests: XCTestCase {
    private let epreuves = [
        EpreuveEngages(numero: "1", nom: "Preparatoire 110 m VEN", date: "20/11/2026", engages: []),
        EpreuveEngages(numero: "17", nom: "Amateur 1 Grand Prix 120 m DIM", date: "22/11/2026", engages: []),
        EpreuveEngages(numero: "5", nom: "SO Cycle Libre 1,00 m SAM", date: "05/11/2026", engages: []),
    ]

    func testNomsEtGabarit() {
        let l = CollectionsLightroom.collections(epreuves, id: { "ID" })
        XCTAssertEqual(l.map(\.fichier), ["80_DIVERS.lrsmcol", "01_PREPA_110_M_VEN.lrsmcol",
                                         "17_AMATEUR_1_GP_120_M_DIM.lrsmcol", "05_CL_1M_M_SAM.lrsmcol"])
        XCTAssertEqual(l[1].titre, "01 PREPA 110 M VEN")
        let c = l[1].contenu
        XCTAssertTrue(c.contains("value = \"#01_\","))
        XCTAssertTrue(c.contains("internalName = \"01 PREPA 110 M VEN\","))
        XCTAssertTrue(c.contains("criteria = \"pick\","))
        // dates lues jour d'abord : le 05/11 est bien le 5 novembre, premier jour
        XCTAssertTrue(c.contains("value = \"2026-11-05\","))
        XCTAssertTrue(c.contains("value2 = \"2026-11-22\","))
        XCTAssertTrue(c.contains("combine = \"intersect\","))
    }
}
