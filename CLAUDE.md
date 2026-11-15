# MarcelTracker

Addon World of Warcraft pour le client **Forever** (dossier `_forever_`), destiné à aider dans l'interface.

## Objectif

Tracker des informations en jeu et les afficher visuellement. Exemples :
- afficher une **icône quand un buff manque** ;
- afficher une **barre de progression** pour suivre la durée restante d'un buff ;
- … d'autres trackers du même genre viendront s'ajouter.

Conséquences pour le code :
- Penser chaque tracker comme une unité indépendante (détection + affichage), pour pouvoir en ajouter facilement.
- Privilégier les événements (`UNIT_AURA`, etc.) au polling ; n'utiliser `OnUpdate` que pour animer ce qui en a besoin (barres de durée), et le couper quand rien n'est affiché.
- Vérifier quelle API d'auras est disponible sur ce client (`C_UnitAuras.*` vs `UnitBuff`/`UnitAura`) avant de l'utiliser.

## Client cible

- `## Interface: 16001` dans le `.toc` (même valeur que les addons spécifiques Forever installés : ForeverAuras, DBM-Party-Forever, Vendor_Camelot).
- Lua 5.1 (runtime WoW) : pas de `goto`, pas d'opérateurs bitwise natifs, pas de `//`.
- API de type Classic : vérifier qu'une fonction existe avant de l'utiliser. Pour les API déplacées dans `C_*`, prévoir un fallback (ex. `(C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)`).

## Structure

- `MarcelTracker.toc` : métadonnées et liste des fichiers chargés, dans l'ordre. Tout nouveau fichier `.lua` doit y être ajouté.
- `MarcelTracker.lua` : point d'entrée (frame d'événements, `ADDON_LOADED`, slash commands).
- Namespace partagé entre fichiers via `local addonName, ns = ...` ; aucune globale hormis `MarcelTrackerDB` (SavedVariables) et `SLASH_*` / `SlashCmdList`.

## Commandes en jeu

- `/marcel` et `/marceltracker`.
- Ne **pas** utiliser `/mt` : déjà pris par Blizzard (main tank).
- Avant d'ajouter une slash command, vérifier qu'elle n'entre pas en conflit avec une commande Blizzard ou d'un addon installé (`../`).

## Tester

- Pas de build : les fichiers sont lus directement par le jeu depuis ce dossier.
- Modification de `.lua` → `/reload` en jeu. Modification du `.toc` ou ajout de fichier → redémarrage complet du client.
- Erreurs Lua : `/console scriptErrors 1`.

## Environnement

- Le repo est sous `/mnt/c/...` (WSL) : `core.fileMode` est à `false` pour ignorer les faux bits exécutables.
- Remote : `git@github.com:lchalamaud/MarcelTracker.git`, branche `main`.

## Conventions

- Code, commentaires et messages de commit en **anglais**.
- Textes affichés en jeu (chat, fenêtres) en **français uniquement**, chaînes en dur (pas de table de locale).
- **Aucune bibliothèque externe** (pas d'Ace3, LibStub…) : API WoW brute uniquement.

## Git

- Messages de commit préfixés par un gitmoji en unicode (🎉 init, ✨ feature, 🐛 fix, ♻️ refactor, 📝 doc, 🔧 config…).
- Branches : `main` (releases), `develop` (intégration), branches de feature nommées `type/description` (`feat/…`, `fix/…`, `docs/…`, `refactor/…`, `chore/…`), créées depuis `develop`.
- Workflow : dev en local → commits sur la branche de feature → push de la branche → PR vers `develop` via `gh`.
- **Interdiction de push sur `main` et `develop`.** Seules les branches de feature sont poussées.
- **Toujours demander avant de push**, et **toujours demander avant de merger une PR**.
- Les PR sont fusionnées en **squash and merge** : le titre de la PR devient le commit final, il doit donc porter le gitmoji.
- Chaque description de PR contient une section **« Validation tests »** : une checklist (`- [ ]`) des tests à effectuer en jeu pour valider le changement (étapes concrètes : commande à taper, situation à reproduire, résultat attendu).
