import XCTest
@testable import TriPhotoCommun

/// Commandes de pack photo (noms inventés).
final class CommandesTests: XCTestCase {
    private func listing(_ id: String, _ nom: String, fin: String, _ couples: [CoupleListing]) -> ListingConcours {
        ListingConcours(id: id, nom: nom, debut: fin, fin: fin, couples: couples)
    }

    private var listings: [ListingConcours] {
        [listing("A", "Essai Indoor", fin: "18/10/2026", [
            CoupleListing(epreuve: "8", nomEpreuve: "Amateur 2 Vitesse", dossard: "4", nom: "DURAND", prenom: "Loïc", cheval: "LOREL"),
         ]),
         listing("B", "Lamotte", fin: "22/11/2026", [
            CoupleListing(epreuve: "17", nomEpreuve: "Amateur 1 GP", dossard: "12", nom: "DURAND", prenom: "Loïc", cheval: "LOREL", classement: "3"),
            CoupleListing(epreuve: "17", nomEpreuve: "Amateur 1 GP", dossard: "13", nom: "MARTIN", prenom: "Zoé", cheval: "TORNADE"),
            CoupleListing(epreuve: "5", nomEpreuve: "Amateur 2 GP", dossard: "7", nom: "DURAND", prenom: "Loïc", cheval: "HELLO BOY"),
         ])]
    }

    func testTarif() {
        XCTAssertEqual(TarifConcours.parDefaut.prix(chevaux: 1), 120)
        XCTAssertEqual(TarifConcours.parDefaut.prix(chevaux: 3), 140)
        XCTAssertEqual(TarifConcours.parDefaut.prix(chevaux: 0), 0)
        XCTAssertEqual(Commande.euros(130), "130 €")
    }

    func testRechercheEtRemise() throws {
        // par le cheval, sans accent ni majuscule : tout le cavalier revient, concours récent d'abord
        let r = Commandes.chercher("lorel", dans: listings, concoursEnCours: "B", photos: ["#17_12": 14])
        XCTAssertEqual(r.count, 1)
        let c = try XCTUnwrap(r.first)
        XCTAssertEqual(c.chevaux, ["HELLO BOY", "LOREL"])
        XCTAssertEqual(c.concours, ["B", "A"])
        let gp = try XCTUnwrap(c.participations.first { $0.epreuve == "17" })
        XCTAssertEqual(gp.remise, true)
        XCTAssertEqual(gp.photos, 14)
        XCTAssertEqual(c.participations.first { $0.epreuve == "5" }?.remise, nil)    // pas de résultats : à la main
        XCTAssertEqual(Commandes.chercher("zoe mar", dans: listings).first?.nom, "MARTIN")
        XCTAssertTrue(Commandes.chercher("x", dans: listings).isEmpty)
        // MARTIN pas classée alors que l'épreuve a des résultats : pas à la remise
        let b = listings[1]
        XCTAssertEqual(b.remise(b.couples[1]), false)
    }

    func testCommandeUnSeulConcours() throws {
        let c = try XCTUnwrap(Commandes.chercher("durand", dans: listings).first)
        // deux chevaux du même cavalier sur Lamotte, plus un passage d'un autre concours (ignoré : concours séparés)
        let k = try XCTUnwrap(Commande.nouvelle(c, choix: c.participations, par: "Mac"))
        XCTAssertEqual(k.concours, "B")
        XCTAssertEqual(k.lignes.count, 2)
        XCTAssertEqual(k.prix, 130)
        XCTAssertEqual(k.statut, .aFaire)
        XCTAssertEqual(k.remise, true)
    }

    func testListingDepuisFFEAvecTerrain() {
        let e = [EpreuveEngages(numero: "1", nom: "Prepa VEN", date: "20/11/2026",
                                engages: [LigneEngage(epreuve: "1", nomEpreuve: "Prepa VEN", date: "20/11/2026", dossard: "2",
                                                      nom: "DURAND", prenom: "Loic", cheval: "LOREL")]),
                 EpreuveEngages(numero: "2", nom: "GP SAM", date: "21/11/2026", engages: [])]
        let t = [EngageTerrain(epreuve: "02", dossard: "40", nom: "Seul", prenom: "ana", cheval: "Zou", source: .main)]
        let l = ListingConcours.depuis(e, terrain: t, id: "9999", nom: "Essai")
        XCTAssertEqual(l.couples.count, 2)
        XCTAssertEqual(l.couples[1].nom, "SEUL")
        XCTAssertTrue(l.couples[1].terrain)
        XCTAssertEqual(l.titre, "Essai · 20-21/11/2026")
    }
}
