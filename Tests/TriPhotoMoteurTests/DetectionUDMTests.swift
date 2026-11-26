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

    /// VPN allumé : la route par défaut passe par le tunnel, on prend celle du câble / wifi.
    func testPasserelleAvecVPN() {
        let table = """
        Routing tables

        Internet:
        Destination        Gateway            Flags               Netif Expire
        default            link#40            UCSIg              utun12
        default            192.168.1.254      UGScIg                en0
        127                127.0.0.1          UCS                   lo0
        """
        XCTAssertEqual(DetectionUDM.passerelleDansTable(table), "192.168.1.254")
        XCTAssertNil(DetectionUDM.passerelleDansTable("default  link#40  UCSIg  utun12"))
    }

    func testUDMConnuGardeSesReglages() throws {
        let u = UDMConnu(mac: "74:ac:b9:12:4f:0a", nom: "Remorque A", montantMbit: 20, empreinte: "ab", derniereAdresse: "192.168.1.1")
        let d = try JSONEncoder().encode([u])
        XCTAssertEqual(try JSONDecoder().decode([UDMConnu].self, from: d), [u])
    }
}

/// Galerie du stand : l'adresse du partage (smb://) collée à la place de l'adresse web est corrigée.
final class AdresseGalerieStandTests: XCTestCase {
    func testAdresseWeb() {
        XCTAssertEqual(GalerieStand.adresseWeb("smb://190.160.40.5"), "https://190.160.40.5")
        XCTAssertEqual(GalerieStand.adresseWeb("190.160.40.5"), "https://190.160.40.5")
        XCTAssertEqual(GalerieStand.adresseWeb(" https://190.160.40.5 "), "https://190.160.40.5")
        XCTAssertEqual(GalerieStand.adresseWeb("smb://190.160.40.5/photos"), "https://190.160.40.5")
    }
}
