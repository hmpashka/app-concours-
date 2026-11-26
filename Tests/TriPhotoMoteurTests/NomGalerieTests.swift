import XCTest
@testable import TriPhotoMoteur

/// Nom des fichiers de la galerie en ligne : « CODE_<texte>_<nom de la photo> ».
final class NomGalerieTests: XCTestCase {
    func testNom() {
        XCTAssertEqual(PhotoEnLigne.nomGalerie(code: "#07_34", perso: "LAMOTTE", photo: "DR__7563-49.JPG"),
                       "07_34_LAMOTTE_DR__7563-49.JPG")
        XCTAssertEqual(PhotoEnLigne.nomGalerie(code: "#07_34", perso: "", photo: "DR__7563-49.JPG"),
                       "07_34_DR__7563-49.JPG")
        XCTAssertEqual(PhotoEnLigne.nomGalerie(code: "#7_5", perso: "", photo: "A.JPG"), "07_05_A.JPG")
        XCTAssertEqual(PhotoEnLigne.nomGalerie(code: "", perso: "", photo: "A.JPG"), "00_00_A.JPG")
        XCTAssertEqual(PhotoEnLigne.nomGalerie(code: "#12_103", perso: "Lamotte Indoor", photo: "A.JPG"),
                       "12_103_Lamotte-Indoor_A.JPG")
    }

    func testTexteNettoye() {
        XCTAssertEqual(PhotoEnLigne.nettoyerPerso("Été / Noël  2026"), "Ete-Noel-2026")
        XCTAssertEqual(PhotoEnLigne.nettoyerPerso("  #HC (test) "), "HC-test")
        XCTAssertEqual(PhotoEnLigne.nettoyerPerso(""), "")
    }

    func testNumeroIncrusteGardeLeNomDeLaPhoto() {
        let p = PhotoEnLigne(nom: "07_34_DR__7563-49.JPG", signature: "", original: "", copie: "", copyright: "#07_34",
                             auteur: "", numero: "DR__7563-49")
        XCTAssertEqual(p.numero, "DR__7563-49")
        XCTAssertEqual(PhotoEnLigne(nom: "A.JPG", signature: "", original: "", copie: "", copyright: "", auteur: "").numero, "A")
    }
}
