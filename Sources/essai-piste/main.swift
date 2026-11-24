import Foundation
import Network
import TriPhotoCommun

// Essai du lien Mac ↔ iPhone sans iPhone : fait comme l'app Piste (trouve Tri-photo sur le wifi, dit bonjour,
// affiche ce que le Mac envoie, envoie un message et un incident).
//
//   swift run essai-piste [nom] [piste] [secondes]       ex. swift run essai-piste Tom "Piste 1" 20

let args = CommandLine.arguments
let nom = args.count > 1 ? args[1] : "Essai"
let piste = args.count > 2 ? args[2] : "Piste 1"
let duree = args.count > 3 ? Double(args[3]) ?? 20 : 20

print("Recherche de Tri-photo (\(LienPiste.service)) sur le réseau…")
var canal: Canal<VersPiste, DepuisPiste>?
var recus = 0
let chercheur = NWBrowser(for: .bonjour(type: LienPiste.service, domain: nil), using: .tcp)
chercheur.browseResultsChangedHandler = { resultats, _ in
    guard canal == nil, let r = resultats.first else { return }
    if case .service(let n, _, _, _) = r.endpoint { print("Trouvé : \(n)") }
    let c = Canal<VersPiste, DepuisPiste>(NWConnection(to: r.endpoint, using: Canal<VersPiste, DepuisPiste>.parametres))
    canal = c
    c.etat = { pret in
        print(pret ? "Connecté." : "Connexion perdue.")
        guard pret else { return }
        c.envoyer(.bonjour(nom: nom, piste: piste, appareil: "essai-piste", version: LienPiste.version))
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            c.envoyer(.message(texte: "Message d'essai de \(nom)", pour: ""))
            c.envoyer(.incident(heure: Date().timeIntervalSince1970, note: "essai"))
            print("Message et incident envoyés.")
        }
    }
    c.recu = { m in
        recus += 1
        switch m {
        case .accueil(let a):
            print("ACCUEIL · \(a.concours) · photographes : \(a.photographes.joined(separator: ", ")) · pistes : \(a.pistes.map { "\($0.nom) (\($0.info))" }.joined(separator: ", "))")
        case .direct(let d):
            print("DIRECT \(d.piste) · épreuve \(d.epreuve) \(d.nomEpreuve) · \(d.partis)/\(d.engages) · en piste \(d.enPiste?.code ?? "—") \(d.enPiste?.cavalier ?? "") · précédent \(d.precedent?.code ?? "—") (\(d.precedent?.photos ?? 0) photos) · suivant \(d.suivant?.code ?? "—") · fin \(d.finEstimee.map { Date(timeIntervalSince1970: $0).formatted(date: .omitted, time: .shortened) } ?? "—") · à renvoyer \(d.aRenvoyer.count) · mes photos \(d.mesPhotos) · alerte \(d.alerte.map { "\($0.ancien) → \($0.attendu)" } ?? "aucune")")
        case .messages(let l):
            print("MESSAGES (\(l.count)) · dernier : \(l.last.map { "\($0.qui) : \($0.texte)" } ?? "—")")
        case .clients(let texte, let l):
            print("CLIENTS « \(texte) » : \(l.map { "\($0.nom) \($0.prenom)" }.joined(separator: ", "))")
        case .commandes(let l):
            print("COMMANDES (\(l.count))")
        }
    }
    c.demarrer()
}
chercheur.start(queue: .main)
DispatchQueue.main.asyncAfter(deadline: .now() + duree) {
    print(canal == nil ? "ÉCHEC : Tri-photo pas trouvé sur le réseau." : "Fin de l'essai : \(recus) messages reçus du Mac.")
    exit(canal == nil || recus == 0 ? 1 : 0)
}
dispatchMain()
