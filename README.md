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
- **Buffs courts** : tant que le personnage a Bénédiction de liberté, Protection divine (paladin), Bénédiction de protection ou Forme de pierre (nain), son icône s'affiche avec le temps restant ; un balayage circulaire l'efface au fil du temps. En combat, Forever rend les auras illisibles : seuls les buffs que le joueur se lance lui-même sont suivis (au sort lancé, avec la durée connue) ; ceux reçus d'un autre joueur n'apparaissent qu'en sortie de combat.

## Zones

Les icônes s'affichent dans des zones. Chaque zone a sa propre page de configuration : ce qu'elle affiche, puis la taille, l'opacité, la bordure et la position de ses icônes, communes à toute la zone.

- **Rappels** : les buffs manquants (aura, bénédiction).
- **Buffs courts** : les protections de quelques secondes, avec leur temps restant. Pensée pour être posée sur le personnage ou juste au-dessus (grande icône transparente ou petite icône).
