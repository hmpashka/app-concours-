import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import TriPhotoMoteur
import TriPhotoCommun

/// Onglet « Au bureau » : index des archives, recherche, copie des originaux.
final class IndexArchivesTests: XCTestCase {
    private var dossiers: [URL] = []

    override func tearDown() {
        for d in dossiers { try? FileManager.default.removeItem(at: d) }
        dossiers.removeAll()
    }

    private func nouveauDossier() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("archives-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        dossiers.append(d)
        return d
    }

    /// Une vraie petite photo JPEG avec date, mots-clés et copyright (comme celles de Groom Pix).
    private func photo(_ url: URL, mots: [String], copyright: String, prise: String = "2026:11:24 14:22:07") throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let ctx = CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        let im = ctx.makeImage()!
        let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        let props: [CFString: Any] = [
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCKeywords: mots, kCGImagePropertyIPTCCopyrightNotice: copyright],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCopyright: copyright],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: prise],
            kCGImageDestinationEmbedThumbnail: true,
        ]
        CGImageDestinationAddImage(d, im, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(d))
    }

    func testNormaliserEtDecouper() {
        XCTAssertEqual(IndexArchives.normaliser("Julie MARTIN, Quaprice d'Or — Été #12_45"), "julie martin quaprice d or ete #12_45")
        XCTAssertEqual(IndexArchives.normaliser("25-02-16_CLUB 01_PREPA 12_45"), "25 02 16 club 01 prepa 12_45")
        let (c, e, d) = IndexArchives.decouper("26-11-24_LAMOTTE INDOOR/12 Pro 2 GP/Manche 1/DERB1340-35.JPG")
        XCTAssertEqual(c, "26-11-24_LAMOTTE INDOOR")
        XCTAssertEqual(e, "12 Pro 2 GP › Manche 1")
        XCTAssertEqual(d, "26-11-24_LAMOTTE INDOOR/12 Pro 2 GP/Manche 1")
        XCTAssertEqual(IndexArchives.numeroEpreuve(code: "", epreuve: "05 Amateur 2"), "5")
        XCTAssertEqual(IndexArchives.numeroEpreuve(code: "#12_45", epreuve: "05 Amateur 2"), "12")
        XCTAssertEqual(LecturePhoto.codeDans("HM Photographie #12_045"), "#12_45")
        XCTAssertEqual(LecturePhoto.codeDans("© HM 2024-25"), "")
        XCTAssertEqual(ArchiveAnnee.anneeDevinee("Archives 2025"), "2025")
        let carte = LecteurAttributionCSV.lire(Data("TYPE;CHP1;CHP2\r\nHMV;05;Club 2;24/11/2026;012;MARTIN;julie;Cavalier;;;P;QUAPRICE;;;;;;;\r\n05;Club 2;24/11/2026;99;Remise des prix;;;;;;;;;;;;;\r\n".utf8))
        XCTAssertEqual(carte, ["#05_12": ["Julie MARTIN", "QUAPRICE"]])
        // formats 2025 (code en 1re colonne, en-tête HMV;CHP1) et 2026 (sans en-tête, cavalier entier)
        XCTAssertEqual(LecteurAttributionCSV.lire(Data("HMV;CHP1;CHP2\r\n#01_00;1;PREPA 50;;0;Inconnu PREPA 50;;;;;;\r\n#01_07;1;PREPA 50;;7;DURAND;paul;;;;ECLAIR;\r\n".utf8)),
                       ["#01_07": ["Paul DURAND", "ECLAIR"]])
        XCTAssertEqual(LecteurAttributionCSV.lire(Data("1;CLUB 3;;1;PETIT Zoe;;;;;;BALOU\n".utf8)), ["#01_01": ["Zoe PETIT", "BALOU"]])
        // rapprochement CSV ↔ dossier de concours
        XCTAssertNotNil(RapprochementCSV.note(concours: "25-02-16_CLUB BERGENNE", csv: "25-02-15_CLUB BERGENNE SERV copie.csv"))
        XCTAssertNil(RapprochementCSV.note(concours: "25-02-16_CLUB BERGENNE", csv: "25-02-23_SUBLIGNY.csv"))
        XCTAssertNil(RapprochementCSV.note(concours: "25-02-16_CLUB BERGENNE", csv: "24-02-16_CLUB BERGENNE.csv"))
        XCTAssertNotNil(RapprochementCSV.note(concours: "26-01-03-GALOPIN", csv: "26-01-03 GALOPIN.csv"))
    }

    func testRecherche() throws {
        let idx = try IndexArchives(dossier: try nouveauDossier())
        let jour = { (j: Int) in Calendar.current.date(from: DateComponents(year: 2025, month: 6, day: j, hour: 15))! }
        idx.ajouterPourEssai(archive: "A25", chemin: "25-06-01_LAMOTTE/12 Pro 2/DERB1.JPG", prise: jour(1),
                             motsCles: ["Julie MARTIN", "QUAPRICE"], copyright: "#12_45")
        idx.ajouterPourEssai(archive: "A25", chemin: "25-06-01_LAMOTTE/12 Pro 2/DERB2.JPG", prise: jour(1),
                             motsCles: ["Paul DURAND", "ÉCLAIR"], copyright: "#12_46")
        idx.ajouterPourEssai(archive: "A25", chemin: "25-06-08_FONTAINEBLEAU/03 Club/IMG_7.JPG", prise: jour(8),
                             motsCles: ["Julie MARTIN", "BALOU"], copyright: "#03_12")
        idx.ajouterPourEssai(archive: "A24", chemin: "24-05-02_SAUMUR/IMG_9.JPG", motsCles: ["Julie MARTIN", "QUAPRICE"])
        idx.ajouterPourEssai(archive: "A26", chemin: "25-02-16_CLUB BERGENNE/05_PREPA 70/28-R3CR3127.JPG", copyright: "#05_01")
        idx.ajouterPourEssai(archive: "A26", chemin: "25-02-16_CLUB BERGENNE/02_PREPA 60/32-R3CR2870.JPG", copyright: "#02_10")

        // chaque mot doit y être, dans n'importe quel ordre, sans accents ni majuscules
        XCTAssertEqual(idx.chercher(RechercheArchives(texte: "martin quaprice")).total, 2)
        XCTAssertEqual(idx.chercher(RechercheArchives(texte: "QUAPRICE Julie")).total, 2)
        XCTAssertEqual(idx.chercher(RechercheArchives(texte: "eclair")).total, 1)
        XCTAssertEqual(idx.chercher(RechercheArchives(texte: "julie")).total, 3)
        // par champ
        XCTAssertEqual(idx.chercher(RechercheArchives(texte: "derb", champ: .nomFichier)).total, 2)
        XCTAssertEqual(idx.chercher(RechercheArchives(texte: "derb", champ: .motsCles)).total, 0)
        XCTAssertEqual(idx.chercher(RechercheArchives(texte: "#12_45", champ: .copyright)).total, 1)
        XCTAssertEqual(idx.chercher(RechercheArchives(texte: "fontainebleau", champ: .concours)).total, 1)
        // « _ » n'est pas un joker : « 12_4 » ne trouve pas « 1234 »
        XCTAssertEqual(idx.chercher(RechercheArchives(texte: "12_4")).total, 2)
        // année, concours, épreuve, dates
        var r = RechercheArchives(texte: "julie")
        r.archive = "A24"
        XCTAssertEqual(idx.chercher(r).total, 1)
        r = RechercheArchives()
        r.concours = "25-06-01_LAMOTTE"
        XCTAssertEqual(idx.chercher(r).total, 2)
        r = RechercheArchives()
        r.epreuve = "03"
        XCTAssertEqual(idx.chercher(r).photos.map(\.nom), ["IMG_7.JPG"])
        r = RechercheArchives()
        r.epreuve = "club"
        XCTAssertEqual(idx.chercher(r).total, 1)
        r = RechercheArchives()
        r.du = jour(5)
        r.au = jour(8)
        XCTAssertEqual(idx.chercher(r).total, 1)
        XCTAssertEqual(idx.concours(archive: "A25"), ["25-06-01_LAMOTTE", "25-06-08_FONTAINEBLEAU"])
        XCTAssertEqual(idx.compte(archive: "A25").photos, 3)
        XCTAssertEqual(idx.compte(archive: "A25").concours, 2)
        // essai NAS du 26/11 : « 70 » ne doit pas trouver « R3CR2870 », « club » trouve « 25-02-16_CLUB »
        XCTAssertEqual(idx.chercher(RechercheArchives(texte: "prepa 70")).photos.map(\.nom), ["28-R3CR3127.JPG"])
        XCTAssertEqual(idx.chercher(RechercheArchives(texte: "bergenne club")).total, 2)
        XCTAssertEqual(idx.chercher(RechercheArchives(texte: "2870", champ: .nomFichier)).total, 1)
        XCTAssertEqual(idx.chercher(RechercheArchives(texte: "mart")).total, 3)
        idx.oublier(archive: "A25")
        XCTAssertEqual(idx.chercher(RechercheArchives(texte: "julie")).total, 1)
    }

    func testIndexationLectureEtMiseAJour() throws {
        let racine = try nouveauDossier()
        let base = try nouveauDossier()
        let p1 = racine.appendingPathComponent("26-11-24_LAMOTTE INDOOR/12 Pro 2 GP/DERB1340-35.JPG")
        let p2 = racine.appendingPathComponent("26-11-24_LAMOTTE INDOOR/12 Pro 2 GP/DERB1341-35.JPG")
        try photo(p1, mots: ["Julie MARTIN", "QUAPRICE"], copyright: "#12_45")
        try photo(p2, mots: ["Paul DURAND", "ÉCLAIR"], copyright: "#12_46")
        try Data("pas une photo".utf8).write(to: racine.appendingPathComponent("26-11-24_LAMOTTE INDOOR/notes.txt"))
        let avant = try Data(contentsOf: p1)

        let idx = try IndexArchives(dossier: base)
        let indexeur = IndexeurArchives(index: idx)
        indexeur.pauseEntrePhotos = 0
        let a = ArchiveAnnee(id: "A26", annee: "2026", chemin: racine.path)
        var p = indexeur.indexerIci(a)
        XCTAssertEqual(p.etape, .fini)
        XCTAssertEqual(p.trouvees, 2)
        XCTAssertEqual(p.lues, 2)

        let r = idx.chercher(RechercheArchives(texte: "martin quaprice"))
        XCTAssertEqual(r.total, 1)
        let f = try XCTUnwrap(r.photos.first)
        XCTAssertEqual(f.concours, "26-11-24_LAMOTTE INDOOR")
        XCTAssertEqual(f.epreuve, "12 Pro 2 GP")
        XCTAssertEqual(f.code, "#12_45")
        XCTAssertEqual(f.motsCles, ["Julie MARTIN", "QUAPRICE"])
        XCTAssertNotNil(f.prise)
        XCTAssertNotNil(idx.vignette(f, archive: a), "vignette du boîtier, ou faite d'après l'original")

        // deuxième passage : rien n'a changé, rien n'est relu
        p = indexeur.indexerIci(a)
        XCTAssertEqual(p.lues, 0)
        // une photo effacée sur le disque sort de l'index ; une nouvelle y entre
        try FileManager.default.removeItem(at: p2)
        try photo(racine.appendingPathComponent("26-11-24_LAMOTTE INDOOR/05 Club/IMG_1.JPG"), mots: ["Zoé PETIT", "BALOU"], copyright: "#05_03")
        p = indexeur.indexerIci(a)
        XCTAssertEqual(p.lues, 1)
        XCTAssertEqual(idx.chercher(RechercheArchives(texte: "durand")).total, 0)
        XCTAssertEqual(idx.chercher(RechercheArchives(texte: "zoe balou")).total, 1)

        // photo sans mots-clés (archives) : cavalier et cheval tirés du CSV d'attribution du concours
        try photo(racine.appendingPathComponent("26-11-24_LAMOTTE INDOOR/12 Pro 2 GP/DERB1350-36.JPG"), mots: [], copyright: "#12_47")
        let csv = racine.appendingPathComponent("26-11-24_LAMOTTE INDOOR/26-11-24_LAMOTTE INDOOR.csv")
        try Data("80;Divers;24/11/2026;80;DIVERS;;;;;;;;;;;;;\r\n12;Pro 2 GP;24/11/2026;00;INCONNU;;;;;;;;;;;;;\r\n12;Pro 2 GP;24/11/2026;47;LEROY;marc;Cavalier;;;Proprio;ULYSSE;Cheval;;10;M;Bai;SF;\r\n".utf8).write(to: csv)
        p = indexeur.indexerIci(a)
        XCTAssertEqual(p.lues, 1)
        let l = idx.chercher(RechercheArchives(texte: "marc leroy ulysse"))
        XCTAssertEqual(l.total, 1)
        XCTAssertEqual(l.photos.first?.motsCles, ["Marc LEROY", "ULYSSE"])
        XCTAssertEqual(idx.chercher(RechercheArchives(texte: "ulysse", champ: .motsCles)).total, 1)
        // CSV corrigé : appliqué sans relire les photos
        try Data("HMV;12;Pro 2 GP;24/11/2026;47;LEROY;marc;Cavalier;;;Proprio;VOLTAIRE;Cheval;;10;M;Bai;SF;\r\n".utf8).write(to: csv)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: csv.path)
        p = indexeur.indexerIci(a)
        XCTAssertEqual(p.lues, 0)
        XCTAssertEqual(idx.chercher(RechercheArchives(texte: "leroy voltaire")).total, 1)
        XCTAssertEqual(idx.chercher(RechercheArchives(texte: "ulysse")).total, 0)

        // disque débranché : la recherche marche toujours, rien n'est retiré
        let absent = ArchiveAnnee(id: "A26", annee: "2026", chemin: racine.appendingPathComponent("nulle-part").path)
        XCTAssertFalse(absent.present)
        XCTAssertEqual(indexeur.indexerIci(absent).etape, .absent)
        XCTAssertEqual(idx.compte(archive: "A26").photos, 3)

        // l'original n'a jamais été touché
        XCTAssertEqual(try Data(contentsOf: p1), avant)
    }

    func testCopieSansEcraserEtAttente() throws {
        let racine = try nouveauDossier()
        let bureau = try nouveauDossier().appendingPathComponent("MARTIN Julie", isDirectory: true)
        let p1 = racine.appendingPathComponent("C/DERB1.JPG")
        try photo(p1, mots: ["Julie MARTIN"], copyright: "#01_02")
        let c1 = try CopieArchive.copier(p1, vers: bureau)
        let c2 = try CopieArchive.copier(p1, vers: bureau)
        XCTAssertEqual(c1.lastPathComponent, "DERB1.JPG")
        XCTAssertEqual(c2.lastPathComponent, "DERB1-2.JPG")
        XCTAssertEqual(try Data(contentsOf: c1), try Data(contentsOf: p1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: p1.path), "l'original reste à sa place")

        let idx = try IndexArchives(dossier: try nouveauDossier())
        let id = try XCTUnwrap(idx.ajouterPourEssai(archive: "A", chemin: "C/DERB1.JPG"))
        idx.mettreEnAttente(try XCTUnwrap(idx.photo(id: id)), destination: bureau)
        XCTAssertEqual(idx.enAttente().count, 1)
        idx.retirerAttente(idx.enAttente()[0].cle)
        XCTAssertEqual(idx.enAttente().count, 0)
    }
}
