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
- `Casts.lua` : aides partagées sur les sorts lancés par le joueur (`ns.CastReachesPlayer` : le sort atteint-il le joueur ?), pour suivre les buffs en combat quand les auras sont secrètes.
- `Widgets/TimerBar.lua` : barre de durée réutilisable. Elle lit son apparence dans une table de réglages (`ns.TimerBarDefaults`) et la réapplique avec `bar:ApplySettings()`.
- `Widgets/AlertIcon.lua` : icône d'alerte réutilisable (icône + texte centré, animation de secousse), pour signaler quelque chose qui manque. Réglages dans `ns.AlertIconDefaults`, réappliqués avec `icon:ApplySettings()`.
- `Widgets/BuffIcon.lua` : icône d'un buff présent, avec le temps restant au centre et un balayage circulaire qui efface l'icône au fil du temps (cadre Cooldown dont la texture de balayage est l'icône elle-même ; la partie écoulée reste visible en « fantôme » selon `ghostAlpha`). Réglages dans `ns.BuffIconDefaults`. Toujours membre d'un groupe.
- `Widgets/IconGroup.lua` : groupe d'icônes affichées côte à côte (rangée centrée sur une position unique, déplaçable). Sert de base aux zones. Chargé avant `AlertIcon.lua`.
- `Widgets/NineSlice.lua` : découpe d'une texture carrée en neuf tranches (coins fixes, bords étirés), utilisée par la surbrillance de déverrouillage et la bordure. Chargé en premier.
- `Widgets/Border.lua` : bordure dorée des widgets (`ns.CreateBorder`), dans le style des cadres natifs : biseau fin, coins échancrés, épaisseur proportionnelle à la taille du widget (`border:Apply(size, outside)`). Texture `Media/Border.tga`, activable par le réglage `border` de chaque widget.
- `Widgets/Movable.lua` : position sauvegardée, déplacement à la souris et surbrillance de déverrouillage, partagés par les widgets (`ns.Movable`, à copier dans la classe du widget). Chargé avant les autres widgets.
- `Zones/Zone.lua` : zones d'affichage (`ns.GetZone(définition)`). Une zone = un groupe d'icônes + les réglages partagés par toutes ses icônes (taille, opacité, bordure…) + sa position, dans `MarcelTrackerDB[clé].settings` / `.position`. Les trackers n'ont plus de réglages d'apparence : ils rejoignent une zone (`zone:AddMember(self)`) et y créent leurs icônes avec `zone.settings`. Toutes les icônes d'une zone ont la même taille.
- `Zones/*.lua` : une définition par zone (`key`, `name`, `defaults`, `options`, `defaultPosition`, `Migrate` optionnel). `Zones/Reminders.lua` : zone « Rappels » des buffs manquants (aura, bénédiction), `ns.GetReminderZone()`. `Zones/ShortBuffs.lua` : zone « Buffs courts » (liberté, protection divine, BoP, forme de pierre), `ns.GetShortBuffZone()`.
- `Config/Controls.lua` : fabriques de contrôles de la page de config, une par type d'option (`toggle`, `slider`, `select`, `color`, `position`, `button`, `header`).
- `Config/Window.lua` : fenêtre de config autonome (`/marcel config`), une page par zone (options des trackers de la zone sous « Contenu », puis apparence et position de la zone) et une page par tracker hors zone (barre du sceau) ou par valeur de `page` partagée (« Divers »), plus un simple bouton dans Options > AddOns. Aucune logique dans le panneau Blizzard (taint).
- `design/` : maquettes des textures de barre (`index.html` + PNG), produites par `tools/generate_designs.py`. Non chargé par le jeu.
- `Media/` : textures chargées par le jeu (`.tga`), converties depuis `design/` par `python3 tools/generate_textures.py`. Ne pas les éditer à la main.
- `Trackers/*.lua` : un fichier par tracker, enregistré via `ns.RegisterTracker`. Pour apparaître dans la config, un tracker déclare `name`, `defaults`, `options` et `ApplySettings(key)` ; ses réglages vivent dans `MarcelTrackerDB[key].settings`. Un tracker de zone ne déclare que ses propres options (activé…), affichées sur la page de sa zone. `Trackers/AuraCaster.lua` n'affiche rien à l'écran : il ajoute le nom complet du lanceur (aligné à droite) aux infobulles des auras, via des hooks sur les setters de `GameTooltip`. Il déclare `page = "Divers"` : les trackers hors zone qui partagent un même `page` sont regroupés sur une seule page de config.
- Namespace partagé entre fichiers via `local addonName, ns = ...` ; aucune globale hormis `MarcelTrackerDB` (SavedVariables), `SLASH_*` / `SlashCmdList` et `MarcelTrackerConfigFrame` (nom de frame requis par `UISpecialFrames` pour fermer avec Échap).

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
- Description de PR rédigée en **français** (le titre reste en anglais avec gitmoji, puisqu'il devient le message du commit squashé).
- Chaque description de PR contient une section **« Tests de validation »** : une checklist (`- [ ]`) des tests à effectuer en jeu pour valider le changement (étapes concrètes : commande à taper, situation à reproduire, résultat attendu).
  - Uniquement des tests qui vérifient réellement un comportement. Pas de tests de remplissage (relire un fichier, vérifier le rendu Markdown, « ça correspond à ce qu'on a dit »…).
  - S'il y a peu ou pas de tests pertinents (changement de doc, petite modif), le dire explicitement dans la PR plutôt que d'en inventer.
