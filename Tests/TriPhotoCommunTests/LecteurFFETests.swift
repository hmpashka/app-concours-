import XCTest
@testable import TriPhotoCommun

/// Fichiers inventés : aucune personne ni aucun cheval réel.
final class LecteurFFETests: XCTestCase {
    private func essaiSIF() throws -> Concours {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "conc_essai", withExtension: "xml", subdirectory: "Donnees"))
        return try LecteurFFE.lire(fichier: url)
    }

    /// Export FFE Compet (version 1, UTF-8, heure de début, piste, nombre d'engagés).
    private let compet = """
    <?xml version="1.0" encoding="UTF-8"?>
    <ffe:message xmlns:ffe="http://www.ffe.com/message" version="1">
      <concours num="9999002" nom="ESSAI COMPET">
        <epreuve num="8" date="2026-06-20" nom_categorie="Amateur 2 - Grand Prix (1.15 m)" heure_debut="09h15"
                 nom_piste="Carrière d'honneur" nbr_engages="2">
          <engagement id="1" dossard="05"><cavalier nom="ÉTÉ" prenom="Zoé"/><equide nom="CHEVAL CINQ"/></engagement>
          <engagement id="2" dossard="12"><cavalier nom="UN" prenom="X"/><equide nom="CHEVAL DOUZE"/></engagement>
        </epreuve>
      </concours>
    </ffe:message>
    """

    func testSIFReconnu() throws {
        let c = try essaiSIF()
        XCTAssertEqual(c.format, .sif)
        XCTAssertEqual(c.numero, "9999001")
        XCTAssertEqual(c.nom, "CONCOURS D'ESSAI")
        XCTAssertEqual(c.epreuves.map(\.numero), ["01", "02"])
        XCTAssertEqual(c.epreuves[0].nom, "Club 2 Vitesse")
        XCTAssertEqual(c.epreuves[0].heure, "")
    }

    func testEngagesSIFSansLesBalisesDuProfil() throws {
        let e = try essaiSIF().epreuves[0]
        XCTAssertEqual(e.engages.map(\.dossard), ["1", "2"])
        XCTAssertEqual(e.engages[0].cavalier, "Alice TEST")
        XCTAssertEqual(e.engages[0].cheval, "CHEVAL UN")
        XCTAssertTrue(e.engages[1].horsClassement)
    }

    func testFFECompetReconnu() throws {
        let c = try LecteurFFE.lire(Data(compet.utf8), nomFichier: "export.xml")
        XCTAssertEqual(c.format, .ffeCompet)
        let e = try XCTUnwrap(c.epreuves.first)
        XCTAssertEqual(e.heure, "09:15")
        XCTAssertEqual(e.piste, "Carrière d'honneur")
        XCTAssertEqual(e.nombreAnnonce, 2)
        XCTAssertEqual(e.engages[0].cavalier, "Zoé ÉTÉ")
        XCTAssertEqual(e.nomDossier, "08 Amateur 2 Grand Prix 1,15 m")
    }

    func testNeufChiffresDonneFFECompet() throws {
        let sansHoraire = compet.replacingOccurrences(of: "version=\"1\"", with: "version=\"1.6\"")
            .replacingOccurrences(of: "heure_debut=\"09h15\"", with: "")
            .replacingOccurrences(of: "nbr_engages=\"2\"", with: "")
        XCTAssertEqual(try LecteurFFE.lire(Data(sansHoraire.utf8), nomFichier: "conc1.xml").format, .sif)
        XCTAssertEqual(try LecteurFFE.lire(Data(sansHoraire.utf8), nomFichier: "123456789.xml").format, .ffeCompet)
    }

    func testCoupleDUnCode() throws {
        let c = try LecteurFFE.lire(Data(compet.utf8))
        XCTAssertEqual(c.couple(pour: CodePassage(epreuve: "08", dossard: "5"))?.cheval, "CHEVAL CINQ")
        XCTAssertNil(c.couple(pour: CodePassage(epreuve: "8", dossard: "00")))
        XCTAssertNil(c.couple(pour: CodePassage(epreuve: "8", dossard: "99")))
    }

    func testPasUnFichierFFE() {
        XCTAssertThrowsError(try LecteurFFE.lire(Data("<racine/>".utf8))) { erreur in
            XCTAssertEqual(erreur as? LecteurFFE.Erreur, .pasUnConcoursFFE)
        }
    }

    func testHeures() {
        XCTAssertEqual(LecteurFFE.heure("9h"), "09:00")
        XCTAssertEqual(LecteurFFE.heure("14:30"), "14:30")
        XCTAssertEqual(LecteurFFE.heure("25h00"), "")
        XCTAssertEqual(LecteurFFE.heure(nil), "")
    }
}

final class CodePassageTests: XCTestCase {
    func testLecture() {
        XCTAssertEqual(CodePassage.lire("#08_05"), CodePassage(epreuve: "8", dossard: "5"))
        XCTAssertEqual(CodePassage.lire("#1_025"), CodePassage(epreuve: "01", dossard: "25"))
        XCTAssertEqual(CodePassage.lire("Copyright #5A_12 HUGO"), CodePassage(epreuve: "5a", dossard: "12"))
        XCTAssertNil(CodePassage.lire("HUGO photographe"))
        XCTAssertNil(CodePassage.lire(nil))
    }

    func testTexteEtSpeciaux() {
        XCTAssertEqual(CodePassage(epreuve: "8", dossard: "5").texte, "#08_05")
        XCTAssertEqual(CodePassage.lire("#08_00")?.special, .inconnu)
        XCTAssertEqual(CodePassage.lire("#08_00")?.texte, "#08_00")
        XCTAssertEqual(CodePassage.lire("#08_99")?.special, .remiseDesPrix)
        XCTAssertNil(CodePassage.lire("#08_12")?.special)
        XCTAssertTrue(CodePassage.meme("#01_025", "#1_25"))
    }

    func testNomDossier() {
        XCTAssertEqual(NomDossier.pourEpreuve(numero: "3", nom: "Club 1 (Vitesse) — Poney/Cheval"),
                       "03 Club 1 Vitesse Poney Cheval")
        XCTAssertEqual(NomDossier.pourEpreuve(numero: "12", nom: ""), "12")
    }
}
