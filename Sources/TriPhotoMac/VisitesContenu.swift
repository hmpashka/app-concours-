import Foundation

/// Le texte des visites guidées. Tutoiement, phrases simples : c'est pour la vendeuse qui découvre l'app au stand.
/// Une zone absente (panneau fermé, page pas encore ouverte) n'empêche rien : la bulle s'affiche au centre.
enum Visites {

    // MARK: Morceaux réutilisés

    private static let revue: [EtapeVisite] = [
        EtapeVisite(ecran: .revue, repere: "revue.recherche",
                    titre: "Retrouver les photos d'un client",
                    texte: "Tape le nom du cavalier, son prénom, le nom du cheval ou son code (par exemple #08_14). L'écran ne garde que ses photos, toutes épreuves confondues.",
                    action: "tape le nom d'un cavalier ou d'un cheval ici.",
                    attente: .signal("revue.recherche")),
        EtapeVisite(ecran: .revue, repere: "revue.epreuve",
                    titre: "Choisir l'épreuve, le boîtier, la piste",
                    texte: "Ces listes réduisent les photos affichées : une seule épreuve, un seul photographe (boîtier) ou une seule piste. « Toutes » remet tout. Pour revoir tout le monde, efface aussi le nom tapé dans la recherche."),
        EtapeVisite(ecran: .revue, repere: "revue.filtre",
                    titre: "Le filtre",
                    texte: "« Bonnes : la plus belle de chaque couple » montre la meilleure photo de chaque cavalier avec son cheval : parfait pour montrer au client. « Toutes » montre tout.",
                    action: "ouvre la liste et choisis un autre filtre.",
                    attente: .signal("revue.filtre")),
        EtapeVisite(ecran: .revue, repere: "revue.vue",
                    titre: "Galerie ou photo en grand",
                    texte: "Le premier bouton montre toutes les photos en petit (touche G), le second une seule photo en grand (touche E). Dans la galerie, le curseur change la taille des vignettes.",
                    action: "clique sur l'autre bouton pour changer de vue.",
                    attente: .signal("revue.vue")),
        EtapeVisite(ecran: .revue, repere: "revue.centre",
                    titre: "Passer d'une photo à l'autre",
                    texte: "Les flèches ← → du clavier avancent d'une photo. Dans la galerie, un clic choisit une photo, un double-clic l'ouvre en grand. La touche P met la photo en plein écran pour le client (P ou Échap pour revenir).",
                    action: "appuie sur → ou clique sur une autre photo.",
                    attente: .signal("revue.photo")),
        EtapeVisite(ecran: .revue, repere: "revue.boutons",
                    titre: "Les boutons sous la photo",
                    texte: "M marque une « Meilleure » photo, R une photo pour les réseaux sociaux, X une chute. Les autres lettres reclassent (bonne, floue, sol, code). « Supprimer » enlève la photo partout : ne t'en sers pas sans demander à HUGO. Pendant la visite, la suppression est bloquée."),
        EtapeVisite(ecran: .revue, repere: "revue.droite",
                    titre: "Les infos de la photo",
                    texte: "À droite : le nom du fichier, le code (#épreuve_dossard), le cavalier et le cheval. Ce sont ces infos qui servent pour une commande."),
    ]

    private static let commandes: [EtapeVisite] = [
        EtapeVisite(ecran: .commandes, repere: "commandes.nouvelle",
                    titre: "Nouvelle commande",
                    texte: "Ce bouton démarre une commande vide. Une commande se fait en 3 pages : le cavalier, ses chevaux, puis le récapitulatif avec le prix."),
        EtapeVisite(ecran: .commandes, repere: "commandes.recherche",
                    titre: "1 · Qui commande ?",
                    texte: "Tape le nom, le prénom ou le cheval du client. L'app cherche dans le fichier des engagés du concours (et dans les anciens concours gardés).",
                    action: "tape le nom d'un cavalier.",
                    attente: .signal("commandes.recherche")),
        EtapeVisite(ecran: .commandes, repere: "commandes.resultats",
                    titre: "Cocher le cavalier",
                    texte: "Clique sur la bonne personne pour la cocher. Tu peux en cocher plusieurs : une famille, deux sœurs… Chacun aura sa commande.",
                    action: "coche un cavalier dans la liste.",
                    attente: .signal("commandes.cavalier")),
        EtapeVisite(ecran: .commandes, repere: "commandes.suivant1",
                    titre: "Page suivante",
                    texte: "Une fois le ou les cavaliers cochés, on passe aux chevaux.",
                    action: "clique sur « Suivant : les chevaux ».",
                    attente: .signal("commandes.etape2")),
        EtapeVisite(ecran: .commandes, repere: "commandes.page",
                    titre: "2 · Quels chevaux ?",
                    texte: "Coche les chevaux que le client achète. Un couple cavalier + cheval = toutes ses photos du concours, toutes épreuves. Le nombre de passages et de photos est écrit à côté.",
                    action: "coche un cheval puis clique sur « Suivant : récapitulatif ».",
                    attente: .signal("commandes.etape3")),
        EtapeVisite(ecran: .commandes, repere: "commandes.page",
                    titre: "3 · Récapitulatif et prix",
                    texte: "Le prix se calcule tout seul : le pack pour le premier cheval, puis un supplément par cheval en plus du même cavalier. Tu peux changer un prix à la main. Remplis ensuite le téléphone, le mail, le règlement (CB, espèces, chèque, virement) et le statut."),
        EtapeVisite(ecran: .commandes, repere: "commandes.page",
                    titre: "Enregistrer",
                    texte: "En vrai, le bouton « Enregistrer la commande » en bas la garde : elle est visible sur les autres Mac et les iPhone du stand. Pendant la visite, l'enregistrement est bloqué : rien n'est créé."),
        EtapeVisite(ecran: .commandes, repere: "commandes.liste",
                    titre: "Les commandes déjà prises",
                    texte: "Ici, toutes les commandes du concours avec une pastille de couleur : à faire, en cours, envoyé. Les boutons du haut filtrent par statut. Un clic sur une commande l'ouvre pour la modifier (téléphone oublié, règlement reçu…)."),
    ]

    // MARK: Visite « vendeuse »

    static let vendeuse = ParcoursVisite(id: "vendeuse", nom: "Visite vendeuse",
                                         menu: "Visite « vendeuse » : Revue, Commandes, Messages (6 min)",
                                         etapes: [
        EtapeVisite(titre: "Bienvenue dans Groom Pix",
                    texte: "Les photos des pistes arrivent toutes seules : l'app les range par épreuve et par cavalier, et les envoie à Lightroom et au serveur du stand. Toi, tu vas surtout retrouver les photos d'un client et prendre ses commandes. Cette visite te montre où cliquer, pas à pas. Rien n'est effacé ni enregistré pendant la visite."),
        EtapeVisite(repere: "bandeau.onglets",
                    titre: "Les onglets",
                    texte: "Chaque onglet est un écran de l'app. Pour toi, les plus utiles sont « Revue » (voir les photos), « Commandes » (prendre une commande) et « Messages » (les photographes sur la piste)."),
        EtapeVisite(repere: "onglet.Revue",
                    titre: "L'écran Revue",
                    texte: "C'est ici qu'on regarde les photos déjà triées.",
                    action: "clique sur l'onglet « Revue ».",
                    attente: .ecran(.revue)),
    ] + revue + [
        EtapeVisite(repere: "onglet.Commandes",
                    titre: "L'écran Commandes",
                    texte: "Quand un client veut ses photos, tout se passe ici.",
                    action: "clique sur l'onglet « Commandes ».",
                    attente: .ecran(.commandes)),
    ] + commandes + [
        EtapeVisite(repere: "onglet.Messages",
                    titre: "Les messages des photographes",
                    texte: "Les photographes sur la piste écrivent depuis leur iPhone. Un chiffre sur l'onglet dit combien de messages ne sont pas lus.",
                    action: "clique sur l'onglet « Messages ».",
                    attente: .ecran(.messages)),
        EtapeVisite(ecran: .messages, repere: "messages.fil",
                    titre: "Lire et répondre",
                    texte: "À gauche, choisis une piste (ou « Toutes les pistes »). Au centre, la conversation : écris en bas et appuie sur Entrée pour répondre."),
        EtapeVisite(repere: "bandeau.aide",
                    titre: "C'est fini !",
                    texte: "Tu connais l'essentiel. Ce bouton « ? » reste toujours là : il relance cette visite, ou la visite d'un seul écran, quand tu veux."),
    ])

    // MARK: Un écran à la fois

    static func ecran(_ e: Ecran) -> ParcoursVisite? {
        func p(_ etapes: [EtapeVisite]) -> ParcoursVisite {
            ParcoursVisite(id: e.rawValue, nom: e.rawValue, menu: e.rawValue, etapes: etapes)
        }
        switch e {
        case .revue: return p(revue)
        case .commandes: return p(commandes)
        case .accueil: return p([
            EtapeVisite(ecran: .accueil, repere: "accueil.principal",
                        titre: "L'accueil : la journée en un coup d'œil",
                        texte: "En haut, les chiffres du jour (photos reçues, file d'attente, photos à renvoyer, à valider). En dessous : les alertes, l'épreuve en piste, les doublons à trancher, les boîtiers des photographes et les dernières photos arrivées."),
            EtapeVisite(ecran: .accueil, repere: "bandeau.pause",
                        titre: "Pause",
                        texte: "Pause arrête tous les envois (serveur, Lightroom, galerie en ligne). Les photos attendent, rien n'est perdu. « Reprendre » relance tout."),
            EtapeVisite(ecran: .accueil, repere: "bandeau.cloturer",
                        titre: "Clôturer",
                        texte: "Le soir, « Clôturer » ferme la journée et prépare le fichier des cavaliers. La flèche propose la clôture du concours et les engagés terrain. C'est HUGO qui s'en occupe."),
        ])
        case .aValider: return p([
            EtapeVisite(ecran: .aValider, repere: "avalider.series",
                        titre: "Les séries à valider",
                        texte: "Quand le chrono ou une photo de code propose de changer le code de plusieurs photos, la série attend ici. Le chiffre orange sur l'onglet dit combien il y en a."),
            EtapeVisite(ecran: .aValider, repere: "avalider.detail",
                        titre: "Valider ou corriger",
                        texte: "Au centre, les photos de la série et le code proposé. On valide si c'est juste, on corrige sinon. En dessous : les photos sans code (_00) à attribuer et les séries déjà validées, qu'on peut revoir."),
            EtapeVisite(ecran: .aValider, repere: "avalider.droite",
                        titre: "Le détail",
                        texte: "À droite, les derniers passages du chrono (heure, code, cavalier), pour décider sans se tromper."),
        ])
        case .messages: return p([
            EtapeVisite(ecran: .messages, repere: "messages.conversations",
                        titre: "Les conversations",
                        texte: "Une conversation par piste, plus « Toutes les pistes » pour écrire à tout le monde. Un chiffre dit les messages pas lus."),
            EtapeVisite(ecran: .messages, repere: "messages.fil",
                        titre: "Lire et répondre",
                        texte: "Les messages s'affichent au centre. Écris en bas et appuie sur Entrée pour envoyer."),
            EtapeVisite(ecran: .messages, repere: "messages.iphones",
                        titre: "Les iPhone connectés",
                        texte: "À droite, les iPhone de la piste reliés au Mac en ce moment. Si un photographe n'y est pas, son iPhone n'est pas sur le Wi-Fi du stand."),
        ])
        case .memoire: return p([
            EtapeVisite(ecran: .memoire, repere: "memoire.categories",
                        titre: "Ce que l'app a appris",
                        texte: "La mémoire garde des exemples de photos par catégorie (bonne, floue, sol, code, meilleure…). Elle sert à tous les Mac du stand et ne s'efface jamais entre deux concours."),
            EtapeVisite(ecran: .memoire, repere: "memoire.centre",
                        titre: "Les exemples",
                        texte: "Au centre, les exemples de la catégorie choisie. Une photo mal rangée peut être retirée : l'app apprend mieux.",
                        action: "choisis une autre catégorie à gauche.",
                        attente: .signal("memoire.categorie")),
            EtapeVisite(ecran: .memoire, repere: "memoire.droite",
                        titre: "Le détail",
                        texte: "À droite, l'état des détections : la mémoire est prête quand chaque catégorie a assez d'exemples (20 suffisent)."),
        ])
        case .auBureau: return p([
            EtapeVisite(ecran: .auBureau, repere: "bureau.mode",
                        titre: "Au bureau",
                        texte: "Cet écran sert après les concours : retrouver des photos dans les archives de toutes les années, ou envoyer un concours terminé sur le NAS."),
            EtapeVisite(ecran: .auBureau, repere: "bureau.contenu",
                        titre: "Rechercher dans les archives",
                        texte: "Tape un cavalier ou un cheval : l'app cherche dans tous les concours archivés. Depuis une commande, « Retrouver aux archives » arrive directement ici."),
        ])
        case .reglages: return p([
            EtapeVisite(ecran: .reglages, repere: "reglages.sections",
                        titre: "Les réglages",
                        texte: "Tous les réglages du concours, rangés par rubrique. C'est HUGO qui les prépare avant la journée : n'y touche pas sans lui."),
            EtapeVisite(ecran: .reglages, repere: "reglages.pret",
                        titre: "Prêt à démarrer ?",
                        texte: "À droite, la liste de ce qui est prêt (vert) ou manque encore (orange) avant de démarrer la journée."),
        ])
        }
    }
}
