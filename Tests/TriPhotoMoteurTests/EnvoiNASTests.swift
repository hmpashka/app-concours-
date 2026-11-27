import XCTest
@testable import TriPhotoMoteur

/// « Au bureau » › Envoyer un concours sur le NAS : copie vérifiée, reprise, doublons, « À décider ».
final class EnvoiNASTests: XCTestCase {
    private var dossiers: [URL] = []
    private let fm = FileManager.default

    override func tearDown() {
        for d in dossiers { try? fm.removeItem(at: d) }
        dossiers.removeAll()
    }

    private func dossier() throws -> URL {
        let d = fm.temporaryDirectory.appendingPathComponent("envoi-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        dossiers.append(d)
        return d
    }

    private func ecrire(_ texte: String, _ u: URL) throws {
        try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(texte.utf8).write(to: u)
    }

    /// L'envoi part tout seul dans son fil : on attend qu'il ait fini.
    private func attendre(_ m: EnvoyeurNAS) {
        let limite = Date().addingTimeInterval(20)
        while m.occupe && Date() < limite { Thread.sleep(forTimeInterval: 0.05) }
        XCTAssertFalse(m.occupe)
    }

    private func texte(_ u: URL) -> String? { (try? Data(contentsOf: u)).flatMap { String(data: $0, encoding: .utf8) } }

    /// Un concours « 26-11-22_ESSAI » avec deux épreuves ; la même photo dans les deux épreuves.
    private func preparer() throws -> (concours: URL, annee: URL, moteur: EnvoyeurNAS) {
        let mac = try dossier(), nas = try dossier(), etat = try dossier()
        let c = mac.appendingPathComponent("26-11-22_ESSAI", isDirectory: true)
        try ecrire("photo A", c.appendingPathComponent("01_PREPA 50/A.JPG"))
        try ecrire("photo B", c.appendingPathComponent("01_PREPA 50/B.JPG"))
        try ecrire("photo A", c.appendingPathComponent("02_CLUB 2/A.JPG"))
        let annee = nas.appendingPathComponent("CONCOURS 2026", isDirectory: true)
        try fm.createDirectory(at: annee, withIntermediateDirectories: true)
        let m = EnvoyeurNAS(dossier: etat)
        m.debitMax = 0
        return (c, annee, m)
    }

    func testEnvoiVerifieEtPhotoIdentiqueDansDeuxEpreuves() throws {
        let (c, annee, m) = try preparer()
        let t = TacheEnvoi(source: c, annee: annee)
        m.ajouter([t])
        attendre(m)
        let dest = annee.appendingPathComponent("26-11-22_ESSAI")
        XCTAssertEqual(texte(dest.appendingPathComponent("01_PREPA 50/A.JPG")), "photo A")
        XCTAssertEqual(texte(dest.appendingPathComponent("01_PREPA 50/B.JPG")), "photo B")
        // la même photo dans une autre épreuve : on garde les deux, chacune dans son dossier
        XCTAssertEqual(texte(dest.appendingPathComponent("02_CLUB 2/A.JPG")), "photo A")
        let b = BilanEnvoi(m.fichiers(t.id))
        XCTAssertEqual(b.total, 3)
        XCTAssertEqual(b.verifies, 3)
        XCTAssertTrue(b.toutVerifie)
        XCTAssertEqual(m.taches.first?.etat, .fini)
        // pas de fichier provisoire oublié
        let restes = fm.enumerator(atPath: dest.path)?.compactMap { $0 as? String }.filter { $0.hasSuffix(".part") } ?? []
        XCTAssertTrue(restes.isEmpty)
        // l'original n'a pas bougé
        XCTAssertEqual(texte(c.appendingPathComponent("01_PREPA 50/A.JPG")), "photo A")
    }

    func testRenvoiSansDoublon() throws {
        let (c, annee, m) = try preparer()
        let t = TacheEnvoi(source: c, annee: annee)
        m.ajouter([t])
        attendre(m)
        // un 2e envoi du même concours (nouvelle tâche) : tout est déjà là, rien n'est copié en double
        let t2 = TacheEnvoi(source: c, annee: annee)
        m.ajouter([t2])
        attendre(m)
        let b = BilanEnvoi(m.fichiers(t2.id))
        XCTAssertEqual(b.dejaLa, 3)
        let dest = annee.appendingPathComponent("26-11-22_ESSAI/01_PREPA 50")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dest.path).sorted(), ["A.JPG", "B.JPG"])
    }

    func testMemeNomPhotoDifferenteADeciderPuisGarderLesDeux() throws {
        let (c, annee, m) = try preparer()
        // sur le NAS, un autre « B.JPG » dans la même épreuve
        let surNAS = annee.appendingPathComponent("26-11-22_ESSAI/01_PREPA 50/B.JPG")
        try ecrire("autre photo", surNAS)
        let t = TacheEnvoi(source: c, annee: annee)
        m.ajouter([t])
        attendre(m)
        var f = m.fichiers(t.id).first { $0.chemin == "01_PREPA 50/B.JPG" }
        XCTAssertEqual(f?.etat, .aDecider)
        XCTAssertEqual(texte(surNAS), "autre photo")              // jamais écrasée sans décision
        XCTAssertEqual(m.taches.first?.etat, .fini)
        XCTAssertFalse(BilanEnvoi(m.fichiers(t.id)).toutVerifie)   // pas de « Libérer la place » possible

        m.decider(t.id, chemin: "01_PREPA 50/B.JPG", .garderLesDeux)
        attendre(m)
        f = m.fichiers(t.id).first { $0.chemin == "01_PREPA 50/B.JPG" }
        XCTAssertEqual(f?.etat, .verifie)
        XCTAssertEqual(f?.nomSurNAS, "B-2.JPG")
        XCTAssertEqual(texte(surNAS), "autre photo")
        XCTAssertEqual(texte(surNAS.deletingLastPathComponent().appendingPathComponent("B-2.JPG")), "photo B")
        XCTAssertTrue(BilanEnvoi(m.fichiers(t.id)).toutVerifie)
    }

    func testRemplacerEtNePasEnvoyer() throws {
        let (c, annee, m) = try preparer()
        let b = annee.appendingPathComponent("26-11-22_ESSAI/01_PREPA 50/B.JPG")
        let a = annee.appendingPathComponent("26-11-22_ESSAI/01_PREPA 50/A.JPG")
        try ecrire("ancienne B", b)
        try ecrire("ancienne A", a)
        let t = TacheEnvoi(source: c, annee: annee)
        m.ajouter([t])
        attendre(m)
        m.decider(t.id, chemin: "01_PREPA 50/B.JPG", .remplacer)
        attendre(m)
        m.decider(t.id, chemin: "01_PREPA 50/A.JPG", .nePasEnvoyer)
        XCTAssertEqual(texte(b), "photo B")
        XCTAssertEqual(texte(a), "ancienne A")
        XCTAssertEqual(m.fichiers(t.id).first { $0.chemin == "01_PREPA 50/A.JPG" }?.etat, .ignore)
    }

    func testResteDEnvoiCoupeEtPhotoAjouteeApres() throws {
        let (c, annee, m) = try preparer()
        // un envoi coupé a laissé un fichier provisoire
        let part = annee.appendingPathComponent("26-11-22_ESSAI/01_PREPA 50/.A.JPG.part")
        try ecrire("pho", part)
        let t = TacheEnvoi(source: c, annee: annee)
        m.ajouter([t])
        attendre(m)
        XCTAssertFalse(fm.fileExists(atPath: part.path))
        XCTAssertEqual(texte(part.deletingLastPathComponent().appendingPathComponent("A.JPG")), "photo A")
        // une photo ajoutée sur le Mac après coup : « Revérifier » n'envoie qu'elle
        try ecrire("photo C", c.appendingPathComponent("02_CLUB 2/C.JPG"))
        m.reprendre(t.id)
        attendre(m)
        let bilan = BilanEnvoi(m.fichiers(t.id))
        XCTAssertEqual(bilan.total, 4)
        XCTAssertTrue(bilan.toutVerifie)
        XCTAssertEqual(texte(annee.appendingPathComponent("26-11-22_ESSAI/02_CLUB 2/C.JPG")), "photo C")
    }

    func testCSVJointEtEtatGarde() throws {
        let (c, annee, m) = try preparer()
        let csvs = try dossier()
        let csv = csvs.appendingPathComponent("26-11-22_ESSAI SERV.csv")
        try ecrire("1;CLUB 2;;1;NOM Prenom", csv)
        let t = TacheEnvoi(source: c, annee: annee, csv: csv)
        m.ajouter([t])
        attendre(m)
        XCTAssertEqual(texte(annee.appendingPathComponent("26-11-22_ESSAI/26-11-22_ESSAI SERV.csv")), "1;CLUB 2;;1;NOM Prenom")
        XCTAssertTrue(fm.fileExists(atPath: csv.path))            // le CSV d'origine reste où il est
        // l'état est relu après un redémarrage de l'app
        let m2 = EnvoyeurNAS(dossier: m.dossier)
        XCTAssertEqual(m2.taches.first?.etat, .fini)
        XCTAssertEqual(BilanEnvoi(m2.fichiers(t.id)).verifies, 4)
    }

    func testLibererLaPlaceSeulementSiToutVerifie() throws {
        let (c, annee, m) = try preparer()
        let t = TacheEnvoi(source: c, annee: annee, verifier: false)
        m.ajouter([t])
        attendre(m)
        XCTAssertThrowsError(try m.libererLaPlace(t.id))
        XCTAssertTrue(fm.fileExists(atPath: c.path))
    }
}
