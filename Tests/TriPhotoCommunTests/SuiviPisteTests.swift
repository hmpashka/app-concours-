import XCTest
@testable import TriPhotoCommun

final class SuiviPisteTests: XCTestCase {
    let concours = Concours(numero: "1", nom: "Essai", format: .ffeCompet, epreuves: [
        Epreuve(numero: "11", nom: "Club 2", engages: []),
        Epreuve(numero: "12", nom: "Amateur 3 Préparatoire", engages: (1...10).map {
            Engage(dossard: String($0), cavalier: "Cavalier \($0)", cheval: "Cheval \($0)")
        }),
    ])

    func passage(_ ep: String, _ d: String, _ t: Double, source: String = "P3") -> Passage {
        Passage(source: source, carriere: "Carrière herbe", epreuve: ep, dossard: d, entree: t, depart: t + 10, fin: t + 80)
    }

    func testEpreuveEnCoursPartisEtSuivant() {
        let ps = [passage("11", "40", 0), passage("11", "41", 90),
                  passage("12", "1", 1000), passage("12", "2", 1090), passage("12", "3", 1180),
                  passage("12", "9", 500, source: "P1")]
        let s = SuiviPiste.calculer(source: "P3", passages: ps, concours: concours, maintenant: 1200)
        XCTAssertEqual(s.epreuve, "12")
        XCTAssertEqual(s.nomEpreuve, "Amateur 3 Préparatoire")
        XCTAssertEqual(s.partis, 3)
        XCTAssertEqual(s.engages, 10)
        XCTAssertEqual(s.enPiste?.dossard, "3")
        XCTAssertEqual(s.precedent?.dossard, "2")
        XCTAssertEqual(s.suivant?.dossard, "4")
        XCTAssertEqual(s.debutEpreuve, 1000)
        XCTAssertEqual(s.secondesParCouple, 90)
        // 7 restants : le dernier sort vers 1180 + 90 × 8
        XCTAssertEqual(s.finEstimee, 1180 + 90 * 8)
    }

    func testSuivantSauteCeuxDejaPartis() {
        let ps = [passage("12", "1", 0), passage("12", "3", 90), passage("12", "2", 180)]
        let s = SuiviPiste.calculer(source: "P3", passages: ps, concours: concours, maintenant: 200)
        XCTAssertEqual(s.suivant?.dossard, "4")
    }

    func testPisteVide() {
        let s = SuiviPiste.calculer(source: "P2", passages: [passage("12", "1", 0)], concours: concours, maintenant: 10)
        XCTAssertNil(s.enPiste)
        XCTAssertNil(s.finEstimee)
    }

    func testAlerteChangeTonCode() {
        let ps = [passage("11", "41", 0), passage("12", "1", 1000)]
        let s = SuiviPiste.calculer(source: "P3", passages: ps, concours: concours, maintenant: 1100)
        let photos = [(code: "#11_41", prise: 900.0), (code: "#11_41", prise: 1040), (code: "#11_41", prise: 1045),
                      (code: "#11_41", prise: 1050)]
        let a = SuiviPiste.alerteCode(boitier: "DERB", photos: photos, suivi: s)
        XCTAssertEqual(a?.ancien, "#11_41")
        XCTAssertEqual(a?.attendu, "#12_01")
        XCTAssertEqual(a?.photos, 3)
    }

    func testPasDAlerteQuandLeCodeEstBon() {
        let ps = [passage("11", "41", 0), passage("12", "1", 1000)]
        let s = SuiviPiste.calculer(source: "P3", passages: ps, concours: concours, maintenant: 1100)
        let photos = [(code: "#11_41", prise: 1040.0), (code: "#11_41", prise: 1045), (code: "#12_01", prise: 1050)]
        XCTAssertNil(SuiviPiste.alerteCode(boitier: "DERB", photos: photos, suivi: s))
        // pendant les 30 s de grâce : rien
        let tot = [(code: "#11_41", prise: 1010.0), (code: "#11_41", prise: 1020)]
        XCTAssertNil(SuiviPiste.alerteCode(boitier: "DERB", photos: tot, suivi: s))
        // une seule photo : rien
        XCTAssertNil(SuiviPiste.alerteCode(boitier: "DERB", photos: [(code: "#11_41", prise: 1050.0)], suivi: s))
    }

    func testTrames() {
        var t = Trames()
        let a = Trames.encoder(DepuisPiste.incident(heure: 12, note: "chute"))!
        let b = Trames.encoder(DepuisPiste.bonjour(nom: "Tom", piste: "Piste 3", appareil: "iPhone", version: 1))!
        var flux = a + b
        let moitie = flux.count - 5
        XCTAssertEqual(t.recevoir(flux.prefix(moitie), comme: DepuisPiste.self), [.incident(heure: 12, note: "chute")])
        flux = flux.suffix(5)
        XCTAssertEqual(t.recevoir(flux, comme: DepuisPiste.self).count, 1)
    }
}
