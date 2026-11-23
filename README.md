# MarcelTracker

Addon World of Warcraft (client Forever, Interface `16001`) pour aider dans l'interface.

## Installation

Cloner ce repo dans `World of Warcraft/_forever_/Interface/AddOns/MarcelTracker`.

## Commandes

- `/marcel` ou `/marceltracker` : aide
- `/marcel config` : ouvrir la fenêtre de configuration (taille, textes, couleur, position… appliqués en direct)
- `/marcel unlock` / `/marcel lock` : déverrouiller / verrouiller les barres pour les déplacer
- `/marcel reset` : remettre les barres à leur position par défaut

## Trackers

- **Sceaux (paladin)** : barre qui se vide pendant la durée du sceau actif, avec l'icône à gauche, le nom au centre et le temps restant à droite.
- **Aura (paladin)** : icône « Aura » qui apparaît et se secoue dès qu'aucune aura du paladin n'est active ; rien n'est affiché tant qu'une aura est en place.
- **Bénédiction (paladin)** : icône « Béné » qui apparaît dès que le personnage n'a plus de bénédiction.

## Zones

Les icônes s'affichent dans des zones. Chaque zone a sa propre page de configuration : ce qu'elle affiche, puis la taille, l'opacité, la bordure et la position de ses icônes, communes à toute la zone.

- **Rappels** : les buffs manquants (aura, bénédiction).
