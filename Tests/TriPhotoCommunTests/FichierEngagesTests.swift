import XCTest
@testable import TriPhotoCommun

/// Fichier d'attribution : même format que l'ancien CSV de HUGO (fichiers inventés, aucune personne réelle).
final class FichierEngagesTests: XCTestCase {
    private let compet = """
    <?xml version="1.0" encoding="UTF-8"?>
    <ffe:message xmlns:ffe="http://www.ffe.com/message" version="1">
      <concours num="9999002" nom="ESSAI INDOOR" date_debut="2026-11-20">
        <epreuve num="1" date="2026-11-20" nom_epreuve="" nom_categorie="Préparatoire (1,10 m)" heure_debut="08h15">
          <engagement id="2" dossard="2" role="Cavalier"><cavalier nom="Durand" prenom="LOIC" nom_club="EARL ESSAI"/>
            <equide nom="LOREL" equide_age="5" code_race="SF" robe="BAI" sexe="Hongre"/></engagement>
          <engagement id="1" dossard="1" role="Cavalier"><cavalier nom="ÉTÉ" prenom="MELINDA" nom_club="S H F"/>
            <equide nom="HELLO BOY D'ESSAI" equide_age="9" code_race="SF." robe="BAI" sexe="Hongre"/></engagement>
        </epreuve>
        <epreuve num="17" date="2026-11-22" nom_categorie="Amateur 1 - Grand Prix (1,20 m)">
          <engagement id="3" dossard="10"><cavalier nom="UN" prenom="jean-paul"/><equide nom="X" dnaiss="2016-04-01" sexe="F"/></engagement>
        </epreuve>
        <epreuve num="18" date="2026-11-22" nom_categorie="Vide"/>
      </concours>
    </ffe:message>
    """

    private func epreuves() throws -> [EpreuveEngages] { try LecteurEngagesFFE.lire(Data(compet.utf8)) }

    func testLignesCommeLAncienCSV() throws {
        let texte = FichierEngages.debut(try epreuves())
        let lignes = texte.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lignes[0], "80;divers;;00;divers;;;;;;;;;;;;;")
        XCTAssertEqual(lignes[1], "1;Preparatoire 110 m VEN;20/11/2026;00;inconnu Preparatoire 110 m VEN;;;;;;;;;;;;;")
        XCTAssertEqual(lignes[2], "1;Preparatoire 110 m VEN;20/11/2026;1;ETE;Melinda;Cavalier;;;S H F;HELLO BOY D'ESSAI;Cheval / Poney Titulaire;;9 ans;Hongre;BAI;SF.;")
        XCTAssertEqual(lignes[3], "1;Preparatoire 110 m VEN;20/11/2026;2;DURAND;Loic;Cavalier;;;EARL ESSAI;LOREL;Cheval / Poney Titulaire;;5 ans;Hongre;BAI;SF;")
        XCTAssertEqual(lignes[4], "1;Preparatoire 110 m VEN;20/11/2026;99;Remise des prix Preparatoire 110 m VEN;;;;;;;;;;;;;")
        // SIF : âge calculé, sexe en toutes lettres, prénom composé
        XCTAssertEqual(lignes[6], "17;Amateur 1 Grand Prix 120 m DIM;22/11/2026;10;UN;Jean-Paul;Cavalier;;;;X;Cheval / Poney Titulaire;;10 ans;Jument;;;")
        // épreuve sans engagé : absente, comme dans l'Excel
        XCTAssertEqual(lignes.count, 8)
        XCTAssertTrue(lignes.allSatisfy { $0.split(separator: ";", omittingEmptySubsequences: false).count == 18 })
        XCTAssertTrue(texte.allSatisfy(\.isASCII))
    }

    func testClotureAvecEngagesTerrain() throws {
        let terrain = [EngageTerrain(epreuve: "1", dossard: "31", nom: "Martin", prenom: "zoé", cheval: "Tornade", source: .main),
                       EngageTerrain(epreuve: "01", dossard: "2", nom: "DOUBLE", prenom: "x", cheval: "y", source: .chrono),
                       EngageTerrain(epreuve: "18", dossard: "4", nom: "SEUL", prenom: "Ana", cheval: "Z", source: .main)]
        let texte = FichierEngages.cloture(try epreuves(), terrain: terrain)
        let lignes = texte.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lignes[0], "TYPE;CHP1;CHP2;CHP3;CHP4;CHP5;CHP6;CHP7;CHP8;CHP9;CHP10;CHP11;CHP12;CHP13;CHP14;CHP15;CHP16;CHP17;")
        XCTAssertEqual(lignes[1], "HMV;80;divers;;00;divers;;;;;;;;;;;;;")
        // le terrain est rangé par dossard, avant la ligne 99 ; un dossard déjà engagé n'est pas doublé
        XCTAssertEqual(lignes[5], "HMV;1;Preparatoire 110 m VEN;20/11/2026;31;MARTIN;Zoe;Cavalier;;;;TORNADE;Cheval / Poney Titulaire;;;;;;")
        XCTAssertTrue(lignes[6].hasPrefix("HMV;1;Preparatoire 110 m VEN;20/11/2026;99;"))
        // une épreuve vide dans le FFE apparaît dès qu'elle a un engagé terrain
        XCTAssertTrue(lignes.contains { $0.hasPrefix("HMV;18;Vide DIM;22/11/2026;4;SEUL;Ana;") })
        XCTAssertEqual(lignes.filter { $0.contains(";2;DOUBLE;") }.count, 0)
    }

    func testNomDuChronoCoupe() {
        XCTAssertEqual(EngageTerrain.couper("Melinda DE LA TOUR").nom, "DE LA TOUR")
        XCTAssertEqual(EngageTerrain.couper("Melinda DE LA TOUR").prenom, "Melinda")
        XCTAssertEqual(EngageTerrain.couper("Jean Dupont").nom, "Dupont")
    }

    func testNomDuFichier() {
        let d = FichierEngages.dateISO("2026-11-20")
        XCTAssertEqual(FichierEngages.nomFichier(concours: "Lamotte Indoor", premierJour: d), "26-11-20_LAMOTTE INDOOR.csv")
    }
}
