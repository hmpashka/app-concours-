import XCTest
@testable import TriPhotoMoteur

/// L'UDM de la remorque est reconnu par l'adresse MAC du routeur, écrite comme le fait `arp` (zéros enlevés).
final class DetectionUDMTests: XCTestCase {
    func testAdresseMACNormalisee() {
        XCTAssertEqual(DetectionUDM.normaliser("74:AC:B9:2:4f:a"), "74:ac:b9:02:4f:0a")
        XCTAssertEqual(DetectionUDM.normaliser("d0:21:f9:88:03:7c"), "d0:21:f9:88:03:7c")
        XCTAssertNil(DetectionUDM.normaliser("(incomplete)"))
        XCTAssertNil(DetectionUDM.normaliser("ff:ff:ff:ff:ff:ff"))
        XCTAssertNil(DetectionUDM.normaliser("74:ac:b9:12:4f"))
    }

    func testUDMConnuGardeSesReglages() throws {
        let u = UDMConnu(mac: "74:ac:b9:12:4f:0a", nom: "Remorque A", montantMbit: 20, empreinte: "ab", derniereAdresse: "192.168.1.1")
        let d = try JSONEncoder().encode([u])
        XCTAssertEqual(try JSONDecoder().decode([UDMConnu].self, from: d), [u])
    }
}
