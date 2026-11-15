---
name: tests-valides
description: Clôture d'une PR après les tests en jeu. Vérifie que toutes les cases de la section « Tests de validation » de la PR sont cochées, fusionne la PR vers develop (squash and merge), supprime la branche de feature et remet le dépôt local sur develop à jour.
argument-hint: "[numéro de PR] [consignes : PR à ne pas fusionner, branche à garder…]"
disable-model-invocation: true
---

# Tests validés : fusionner une PR

L'utilisateur déclare les tests en jeu validés. Arguments : `$ARGUMENTS`

Dépôt unique : `lchalamaud/MarcelTracker`, dans le dossier de l'addon. Branche par défaut : `develop`. Messages en français.

**Lancer ce skill vaut demande de fusion au sens de `CLAUDE.md`** (« toujours demander avant de merger une PR ») : la PR ciblée, en squash and merge. Ne pas reposer la question, sauf si une étape ci-dessous dit de s'arrêter ou de demander. Les consignes données dans les arguments ou le message l'emportent sur ce qui suit.

## 1. Identifier la PR

- Numéro pris dans les arguments (`2`, `#2`). Sinon, la PR ouverte de la branche courante :
  ```sh
  gh pr view --json number,title,state,isDraft,baseRefName,headRefName,headRefOid,body,comments,mergeable,mergeStateStatus
  ```
- Si la branche courante est `develop` ou `main`, ou n'a pas de PR ouverte, et qu'aucun numéro n'est donné : lister les PR ouvertes (`gh pr list --state open`) et demander laquelle.
- Plusieurs PR en argument : traiter chacune en entier, l'une après l'autre. Une PR qui ne passe pas l'étape 2 ou 3 est laissée de côté et signalée, les autres continuent.

## 2. Vérifier les tests de validation (arrêt si incomplet)

Dans le corps de la PR :

- la section `## Tests de validation` doit exister ;
- elle contient au moins une case, **ou** dit explicitement qu'il n'y a pas de test pertinent (cas prévu par `CLAUDE.md` pour la doc ou les petites modifs) ;
- **aucune case `- [ ]` ne doit rester**, dans tout le corps (cocher = `- [x]` ou `- [X]`).

S'il manque des coches : **s'arrêter là**, sans rien fusionner. Lister les tests manquants (texte de la case, raccourci) et le lien vers la PR. Ne jamais cocher une case à la place de l'utilisateur.

Lire aussi les commentaires de la PR : si l'un d'eux signale un test raté ou une erreur Lua, et qu'aucune réponse ni aucun commit ultérieur ne montre que c'est corrigé, s'arrêter et demander.

## 3. Tout contrôler avant de fusionner

Au moindre problème, s'arrêter sans rien fusionner et le signaler :

- base `develop` (jamais `main` : la release est une autre opération) ; pas en brouillon ;
- `mergeable` vaut `MERGEABLE` (si `UNKNOWN`, relancer après quelques secondes) ;
- titre en anglais, préfixé par un gitmoji unicode : il devient le message du commit squashé. Sinon, proposer un titre corrigé et demander ;
- branche locale de la PR : sa tête vaut `headRefOid` (`git rev-parse <branche>`). Rien de non poussé, rien de plus récent sur GitHub ;
- pas de modification non commitée sur un fichier suivi (`git status --short --untracked-files=no` ; les fichiers non suivis ne gênent pas). Sinon, montrer le diff et demander avec `AskUserQuestion` : **la garder** telle quelle, **la committer à part** après la fusion, ou **l'abandonner** (`git restore <fichier>`). Ne jamais l'ajouter à la PR. Le choix s'applique aux étapes 5 et 6.

## 4. Fusionner

```sh
gh pr merge <pr> --squash
```

- Le titre du commit fusionné est celui de la PR suivi de `(#<pr>)`, au format de l'historique. Ne pas le changer.
- Vérifier ensuite `gh pr view <pr> --json state,mergeCommit` (`MERGED`). Si la fusion échoue, s'arrêter et le dire.
- Le dépôt ne supprime pas les branches fusionnées tout seul : supprimer la branche distante de la PR avec `git push origin --delete <branche>`. Seulement une branche de feature (`feat/…`, `fix/…`…), **jamais `develop` ni `main`**.
- Les `Closes #n` du corps ferment les issues liées (la fusion se fait sur la branche par défaut). Vérifier qu'elles sont bien fermées, sinon les fermer avec `gh issue close <n> --reason completed --comment "Fusionné dans #<pr>."`.

## 5. Remettre le dépôt local à jour

```sh
git fetch --prune
git checkout develop
git pull --ff-only
```

- Une modification gardée ou à committer à part (étape 3) qui bloque le `checkout` (« would be overwritten ») : `git stash push -m "<description>" -- <fichiers>`, puis `checkout` et `pull`, puis `git stash pop`. Si le `pop` entre en conflit, s'arrêter et le signaler : la modification reste dans le stash, ne jamais la jeter.
- Supprimer la branche locale de la PR. La fusion squash empêche `git branch -d` de la reconnaître comme fusionnée : n'utiliser `git branch -D <branche>` que si sa tête vaut le `headRefOid` de la PR fusionnée. Sinon, la garder et le signaler.
- `develop` doit finir à jour avec `origin/develop` (`git status -sb`). En retard ou divergent : le signaler, ne jamais forcer.
- Rappel : le jeu lit les fichiers directement depuis ce dossier. Être sur `develop` veut dire que l'addon chargé en jeu est désormais celui de `develop`. Si la PR a changé le `.toc` ou ajouté des fichiers, le signaler (redémarrage complet du client) ; sinon un `/reload` suffit.

## 6. Modification à committer à part

Seulement si l'utilisateur l'a choisi à l'étape 3 : une branche `type/description` créée depuis `develop` à jour, un commit au format de `CLAUDE.md` (gitmoji, anglais), puis **demander avant de pousser** (`CLAUDE.md`). Si l'utilisateur accepte : push et PR vers `develop` (description en français avec sa section « Tests de validation »). **Ne pas la fusionner** : la demande de fusion du skill ne couvre que la PR ciblée.

## 7. Message final

Quelques lignes, sans détail inutile :

- PR fusionnée (lien) et titre du commit squashé ;
- issues fermées, s'il y en a ;
- branche locale et distante supprimées, ou gardées (et pourquoi) ;
- `/reload` ou redémarrage du client nécessaire ;
- ce qui reste à faire (modification gardée, PR à part en attente…).
