# Module Groom Pix pour le Loupedeck CT

Maquette validée par HUGO le 25/11/2026 : `App concours/04 Maquettes/loupedeck-ct.png`.

## Comment ça marche
- Groom Pix ouvre un « pont » sur ce Mac seulement (http://127.0.0.1:8095, rien sur le réseau).
  Réglages › 5. Envois › « Loupedeck CT » pour le couper. Le tri n'en dépend pas.
- Le module lit l'état une fois par seconde (`GET /etat`, ≈ 1 Ko) et envoie les boutons (`POST /action/<nom>?pas=n`).
  En-tête `X-Groom-Pix: 1` obligatoire (une page web ne peut pas piloter l'app).
- Les touches marchent même si Groom Pix n'est pas devant (Lightroom au premier plan, par exemple).

## Construire et installer (Mac de concours)
    ./scripts/construire-loupedeck.sh

## Placer les actions dans le logiciel Loupedeck (une seule fois)
| Emplacement du CT | Action « Groom Pix » |
|---|---|
| Écran tactile, 12 touches (de gauche à droite, de haut en bas) | Écran tactile › Case 01 … Case 12 |
| Molettes gauche 1, 2, 3 | Molettes › Photo, Série, Écran |
| Molettes droite 4, 5, 6 | Molettes › Épreuve, Filtre, Zoom |
| Grande roue | Molettes › Grande roue |
| Ronds 1 à 8 | Boutons › Écran Accueil, À valider, Revue, Mémoire, Commandes, Messages, Clôturer, Panneaux |
| Carré ○ / ↵ | Ignorer la série / Valider la série |
| Carré Undo / Save | Annuler / Pause |
| Carré ⌨ | Changer le code |
| Carrés ▲ A / ▼ B | Série précédente / suivante |
| Carrés ◀ C / ▶ D | Photo précédente / suivante |
| Carré E | Rush : tout envoyer |
| Carrés Fn | inchangés (2e couche du Loupedeck) |

Les cases de l'écran changent toutes seules : page « Direct » (état du stand) ou page « Revue » (B F S C / M R X ⌫).
