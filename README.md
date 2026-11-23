# App concours : Tri-photo (app Mac native)

La vraie app Mac de Tri-photo, écrite en Swift. Elle remplacera petit à petit la version Python (`tri-photos` du dépôt sporttiming,
« v00 »), qui reste la référence et le secours tant que la nouvelle app n'a pas fait ses preuves en concours.

Plan de développement validé le 23/11/2026 : 6 étapes, chacune testée avant la suivante.

| Étape | Contenu | État |
| --- | --- | --- |
| 0 | Fondations : fenêtre, menus, panneaux, réglages, fichier FFE, raccourcis, mode entraînement | validée 23/11 |
| 1 | Moteur photos (réception, renommage, .cube, IPTC, Lightroom) + accueil | en cours |
| 2 | Codes (chrono, à valider), revue, suivi Lightroom, Capture Horse & Comp | |
| 3 | App iPhone Piste + messagerie | |
| 4 | Galerie FTP, régulateur réseau, clôture, accès à distance | |
| 5 | Mémoire partagée iCloud + détections | |

## Organisation

- `Sources/TriPhotoCommun` : ce qui servira aussi à l'iPhone (lecture du fichier FFE SIF / FFE Compet, codes
  `#épreuve_dossard`, noms des dossiers d'épreuve).
- `Sources/TriPhotoMoteur` : le moteur photos, sans interface (réception, contrôle, renommage `IMG_4410-32.JPG`,
  copie .cube vers le serveur local, IPTC dans l'original sans recompression, import Lightroom, dossier tampon,
  régulateur Lightroom, journal SQLite pour reprendre après un plantage).
- `Sources/TriPhotoMac` : l'app Mac (SwiftUI).
- `Sources/essai-moteur` : essai du moteur sur un dossier de photos, sans toucher au dossier donné :
  `swift run -c release essai-moteur ~/Photos/test --cube mon.cube --ffe conc123.xml`
- `Tests/TriPhotoCommunTests` : tests, avec des fichiers inventés (aucune personne ni cheval réel).
- `Ressources/Icone-1024.png` : l'icône.

## Construire et lancer (sur un Mac)

```bash
swift test                      # les tests
./scripts/construire-app.sh     # fabrique build/Tri-photo.app
open build/Tri-photo.app
```

macOS 13 (Ventura) ou plus récent. L'app est signée « ad hoc » : au premier lancement, clic droit > Ouvrir.

Les réglages sont gardés dans `~/Library/Application Support/Tri-photo/` (réglages, fichier FFE lu, raccourcis,
modèles de concours).
