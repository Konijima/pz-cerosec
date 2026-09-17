# Parcours de test CeroSec

> **In English:** this is the in-game test checklist, every step that has to be
> walked on the glass, in order, because no headless suite can reach it. It is
> written in French because that is the maintainer's working language; an English
> translation is very welcome as its own pull request.

Voir aussi [TESTING.md](TESTING.md) pour les suites headless (`sh tests/run.sh`)
et les rungs [TEST-rung1.md](TEST-rung1.md), [TEST-rung2.md](TEST-rung2.md) et
[TEST-rung4.md](TEST-rung4.md).

Ce parcours couvre CeroSec au-delà de ce qui a déjà été vu marcher : allumer et
éteindre un ordinateur, ouvrir le terminal, se connecter, le fait que l'écran
appartient à la machine, renommer avec `hostname` et ouvrir le manuel par le menu
de développement. Tout le reste ci-dessous n'a jamais été validé en jeu.

Partir d'une nouvelle partie avec CeroSec activé dans la liste des mods. Sur une
sauvegarde existante, une machine plus vieille que la version courante reçoit sa
mise à niveau (`sysv`) au premier chargement : les commandes et fichiers manquants
apparaissent une fois, rien d'autre n'est touché. Régler
`CeroSec.DEBUG = true` dans `42/media/lua/shared/CeroSec/CeroSecDefs.lua` pour voir
les lignes de console pendant les tests.

Le sous-menu **CeroSec (dev)** est déjà présent sur tous les ordinateurs : il
tient les trois volumes du manuel (`CeroSec.DEV_MANUAL_MENU = true`) et la
**fenêtre de débogage** (`CeroSec.DEV_DEBUG_MENU = true`, voir la section X et
[DEBUG.md](DEBUG.md)). Un ordinateur de bureau
(`Desktop`) se trouve dans les bureaux et dans les maisons ; le menu debug peut
aussi en faire apparaître un, ou fournir un Computer en objet à placer. Pour une
chaise, tirer n'importe quelle chaise de bureau devant l'écran, dos au moniteur.
Pour une caisse, `-debug` (mode debug) permet d'en faire apparaître ou d'en
empiler deux pour tester la hauteur. Un générateur d'appoint et de l'essence
s'obtiennent pareil en mode debug ou via les réglages de bac à sable
(`ElecShutModifier` à 0 jour coupe le réseau dès le départ). Pour une clé ou un
cadenas sur une porte, le mode Hôte donne les pouvoirs d'admin nécessaires pour
placer ou retirer ce qu'il faut sans passer par le jeu normal.

Rapporter chaque étape par son numéro, OK ou KO, et une ligne sur ce qui s'est
passé réellement, même quand ça correspond au texte attendu.

## A. Allumer, portée et posture

1. Ordinateur sur bureau, aucune chaise, clic droit à distance, "Turn on
   computer" → le personnage marche jusqu'au carré que l'écran regarde, s'y
   arrête, se tourne vers le moniteur, puis seulement joue l'animation de
   fouille debout et allume le sprite. [ ]
2. Refaire l'étape 1 sur les quatre orientations (S, E, N, O) → le carré est
   toujours celui que l'écran regarde : S vers y+1, N vers y-1, E vers x+1, O
   vers x-1. [ ]
3. Ordinateur posé au sol, pas sur un meuble → même marche, mais l'animation est
   accroupie (`Bob_IdleLooting_Low`), pas debout. [ ]
4. Ordinateur sur deux caisses empilées → l'option est grisée, l'infobulle dit
   "This computer is too high to reach." / "Cet ordinateur est trop haut pour
   l'atteindre." [ ]
5. Bureau poussé contre un mur, écran qui regarde le mur → grisé, "You cannot
   stand in front of this computer." / "Impossible de se placer devant cet
   ordinateur." Passer par l'arrière ne débloque rien. [ ]
6. Carré devant traversé par une fenêtre fermée → grisé. Ouvrir la fenêtre →
   reste grisé, une fenêtre n'est pas un endroit où se tenir. [ ]
7. Personnage déjà debout sur le carré devant l'écran, clic droit, bascule → il
   fait un pas dans le carré pour se coller au meuble, puis l'animation. [ ]
7a. **Debout au clavier.** Ordinateur sur un bureau, AUCUNE chaise devant, "Use
   computer" depuis l'autre bout de la pièce → au bout de la marche le
   personnage est collé au bureau, pas au milieu du carré : les mains tombent
   sur le clavier et non dans le vide. Refaire sur les quatre orientations (S,
   E, N, O) → toujours contre le meuble, et toujours centré sur l'autre axe,
   jamais de travers dans un coin du carré. [ ]
7b. **La dérive.** Terminal ouvert debout, se faire pousser par un zombi (ou
   faire un pas dans le carré avec les touches de déplacement) sans quitter le
   carré → cliquer sur la fenêtre : le personnage revient au clavier, se
   retourne vers l'écran, et l'animation de frappe reprend. Cliquer trois fois
   de suite alors qu'il est déjà au clavier → aucun pas, aucun saccade, la
   frappe n'est pas coupée. [ ]
8. Lancer la bascule depuis l'autre bout de la pièce, puis appuyer sur une
   touche de déplacement pendant la marche → le personnage s'arrête,
   l'ordinateur NE bascule PAS, aucune erreur dans `console.txt`. [ ]
9. Courant coupé sur un ordinateur par ailleurs atteignable → l'infobulle reste
    "This computer has no power." (la vérification de portée passe avant celle
    du courant). [ ]
10. Ordinateur sur une caisse, clic droit sur le bas du moniteur → "Turn on
    computer" est là. [ ]
11. Même ordinateur, clic droit sur les tout premiers pixels du haut du
    moniteur → "Turn on computer" est là aussi. [ ]
12. Clic droit un ou deux pixels au-dessus du sprite, hors de l'écran → l'option
    a disparu, aucun vol de clic vers le carré derrière. [ ]
12a. **Le bureau avec une chaise devant.** C'EST le cas de la capture du
    2026-09-12. Ordinateur vanilla posé sur un bureau, une chaise de bureau
    tirée devant, dos au moniteur (donc le carré devant l'écran est occupé par
    la chaise). Clic droit en plein milieu du moniteur, pas sur le cadre, pas
    sur le bureau → "Turn on computer" est là. Refaire une dizaine de fois, en
    bougeant la souris de quelques pixels entre chaque clic : l'entrée est là
    chaque fois, jamais une fois sur trois. [ ]
12b. **Ce que le jeu, lui, a attrapé.** Même position, avec `-debug` : ouvrir le
    menu et lire les lignes du jeu. `Tile Report` peut très bien nommer la
    chaise (`furniture_seating_indoor_*`) et `Room Report` donner le carré de la
    chaise, un carré au sud du bureau → c'est normal et ce n'est plus un
    problème : le jeu a le droit de choisir la chaise, nos entrées doivent
    apparaître quand même. Si elles manquent, c'est le moment d'ouvrir l'onglet
    **Log** de la fenêtre de débogage (étape 12d). [ ]
12c. **La chaise garde ses propres pixels.** Même position, clic droit sur le
    DOSSIER de la chaise, là où il n'y a pas de moniteur derrière → aucune
    entrée CeroSec, le menu est celui de la chaise ("Mahogany Chair", "Sit on
    ground", "Walk to"). On ne vole pas un clic qui n'est pas le nôtre : si
    l'entrée apparaît ici, la garde est passée du masque de pixels à une simple
    boîte. [ ]
12d. **Lire un raté.** Mettre `CeroSec.DEBUG = true` dans
    `42/media/lua/shared/CeroSec/CeroSecDefs.lua`, relancer, refaire 12a, puis
    ouvrir la fenêtre de débogage → onglet **Log**. Il doit y avoir, pour chaque
    clic droit : une ligne `menu: game handed ...` avec le sprite et le carré de
    ce que le jeu a donné, une ligne `pick: mouse X,Y zoom Z ... (N candidates)`,
    et une ligne par candidat avec son carré, son `raise`, sa boîte et `HIT` ou
    `no mask`. Un raté en jeu se lit ici : le carré du bureau est-il dans les
    candidats, et le masque a-t-il dit non. [ ]
12e. **Deux bureaux côte à côte.** Deux ordinateurs sur deux bureaux collés,
    chacun avec sa chaise. Clic droit sur le moniteur de gauche → c'est
    l'ordinateur de GAUCHE qui s'allume (vérifier le sprite qui change), pas
    celui de droite. Puis l'inverse. [ ]

## B. Terminal, écran de la machine

13. "Use computer" lancé de loin sur un ordinateur allumé → marche jusqu'au
    carré devant l'écran, tourne, joue l'animation, puis seulement la fenêtre
    s'ouvre. [ ]
14. Les cinq lignes du BIOS s'écrivent en environ deux secondes, puis la
    bannière `CeroSec OS 1.0 -- unauthorized access is prohibited.`, puis
    `login:`. [ ]
15. Le curseur est un bloc plein, allumé une demi-seconde, éteint une
    demi-seconde ; aucune invite devant lui pendant le BIOS. [ ]
16. `root`, Entrée, mot de passe vide, Entrée → le nom s'affiche à l'écran,
    l'invite devient `password:`, ce qui est tapé montre des `*`, puis la
    bannière revient et l'invite finale est `root@ksp-<x>-<y>:/root# `. [ ]
17. `exit`, puis `root` / `xyz` → `login incorrect`, retour à `login:`. [ ]
18. `admin`, mot de passe vide → `admin@ksp-<x>-<y>:/home/admin$ ` (un `$`, pas
    un `#`). [ ]
19. Fenêtre ouverte, taper `wwww`, `1`, `e`, `i` → le personnage ne marche pas,
    ne change pas d'arme, n'ouvre pas l'inventaire. [ ]
20. `root`, `cd /etc`, s'éloigner du carré devant l'écran (la fenêtre se ferme),
    revenir, "Use computer" → exactement le même écran : mêmes lignes, encore
    connecté, même invite, aucun BIOS. [ ]
21. Après le retour de l'étape 20, `pwd` → `/etc`, le dossier courant appartient
    à la machine, pas à la session. [ ]
22. `exit`, s'éloigner, revenir → toujours `login:`, aucun BIOS. [ ]
23. Éteindre l'ordinateur par le menu, le rallumer, "Use computer" → le BIOS
    rejoue une fois, l'écran derrière est vide. [ ]
24. Écrire un fichier (`mkdir /root/notes`, `echo "kept" > /root/notes/a.txt`,
    `cat`), fermer la fenêtre, sauvegarder, quitter au menu, recharger, ouvrir →
    le fichier est là, la session est encore connectée, la dernière sortie est
    encore sur l'écran, aucun BIOS. [ ]
25. `root`, `shutdown` → la ligne tapée reste affichée, l'ordinateur s'éteint
    (sprite éteint, son de bascule), la fenêtre se ferme d'elle-même. [ ]
26. Rallumer, ouvrir, `root`, `ls /home/admin` et `cat /etc/passwd` → exactement
    comme avant l'arrêt (un arrêt est une coupure, pas une réparation). [ ]
27. `root`, `reboot` → l'ordinateur s'éteint pour de vrai : sprite éteint, lueur
    de l'écran disparue, la fenêtre se ferme. Environ trois secondes plus tard la
    machine se rallume toute seule et la fenêtre se rouvre à la même place, sans
    remarcher jusqu'à la machine : elle rejoue `CeroSec BIOS 1.0`, compte la
    mémoire, détecte le disque, affiche le motd, s'arrête à `login:`. [ ]
27b. Refaire `reboot` et **s'éloigner du bureau** pendant le noir → la machine
    revient allumée toute seule, mais aucune fenêtre ne s'ouvre : revenir et
    l'utiliser à la main comme n'importe quel écran allumé. [ ]
27c. Refaire `reboot` et **couper le courant de la pièce** pendant les trois
    secondes de noir → la machine reste éteinte, comme une vraie après une panne.
    Remettre le courant : elle ne revient pas d'elle-même, c'est la main sur
    l'interrupteur qui la rallume. [ ]

## C. Shell de base

28. `ls -l` dans `/` → le squelette `bin dev etc home root`, une ligne chacun,
    jamais plus large que l'écran. [ ]
29. `mkdir notes`, `cd notes`, `echo "hello" > a.txt`, `cat a.txt` → `hello`. [ ]
30. `echo "second" >> a.txt`, `cat a.txt` → deux lignes, `hello` puis
    `second`. [ ]
31. `mkdir tree`, `mkdir tree/inner`, un fichier dans chacun, `cp -r tree copy`,
    `ls -l copy/inner` → tout est copié, daté à maintenant, propriété du compte
    courant. [ ]
32. `grep alpha notes.txt` sur un fichier de quelques lignes → trouve la chaîne
    exacte ; `grep a.b notes.txt` matche les trois caractères `a.b`, pas `axb`
    (pas de regex sur cette machine). [ ]
33. `grep -n alpha notes.txt` numérote les lignes ; `grep -i ALPHA notes.txt`
    ignore la casse ; `grep zebra notes.txt` n'affiche rien. [ ]
34. `head -n 2 notes.txt`, `tail -n 3 notes.txt` sur un fichier d'une douzaine
    de lignes → les deux premières, puis les trois dernières. [ ]
35. `date` → forme `Thu Jul  8 14:32:00 1993` ; comparer l'heure et la minute
    avec le HUD du jeu au même instant. [ ]
36. `df` → deux lignes, `hda` (taille 65536) et `nodes` (512) ; écrire un gros
    fichier fait bouger les octets utilisés vers le haut, l'effacer les fait
    redescendre. [ ]
37. `man ls` → le même texte que `cat /bin/ls`, suivi de la ligne d'usage ;
    `ls a b` (mauvais appel) répond avec cette même ligne d'usage. [ ]
38. Historique : flèche haut remonte dans les dernières lignes tapées, bas
    redescend, bas au-delà de la plus récente laisse une ligne vide, seules les
    20 dernières sont gardées. [ ]
39. Remplir l'écran (`ls -l /` plusieurs fois), molette de la souris sur la
    fenêtre → `-- more --` en haut pendant qu'on est remonté, toute nouvelle
    sortie ramène en bas. [ ]
40. Taper 200 caractères sans presser Entrée (tenir une touche) → la ligne
    s'enroule sur les rangées du dessous (quatre rangées de soixante), le
    curseur bloc suit sur ces rangées. [ ]
41. Escape à une invite shell inactive → ferme la fenêtre. Escape en pleine
    question (`passwd`, `sudo`, un nom à moitié tapé à `login:`) → imprime `^C`
    sur la ligne et redonne l'invite ou `login:`, sans fermer la fenêtre. [ ]

## D. Éditeur

42. `admin`, `edit notes.txt` (fichier neuf) → barre inversée
    ` EDIT /home/admin/notes.txt`, dix-sept rangées vides, barre
    ` Esc exit   Tab save `, curseur bloc en haut à gauche. Escape ensuite sans
    rien taper : `ls` ne montre rien, aucun fichier créé. [ ]
43. Taper deux lignes avec Entrée entre elles → le curseur avance en tapant,
    Backspace efface à travers le saut de ligne, les flèches et Home/End
    bougent le curseur sur la ligne sans rien changer. [ ]
44. Dès que le tampon diffère du fichier sur disque → `[modified]` apparaît
    collé au bord droit de la barre. [ ]
45. Tab → `Saved N bytes` en bas, `[modified]` disparaît, `cat notes.txt`
    montre ce qui a été tapé. [ ]
46. Retaper un caractère, Escape → `Save modified buffer? (y/n)`. Escape encore
    → la question disparaît, tampon intact, curseur inclus. Escape puis `n` →
    retour au shell, `cat` montre l'ancien texte. Escape puis `y` → sauvegardé,
    `cat` montre le nouveau. [ ]
47. `root`, `chmod 444 /etc/motd`, puis `admin`, `edit /etc/motd` → `[read-only]`
    au lieu de `[modified]`, Tab répond `Cannot save: permission denied` sur la
    ligne de message, sans rien écrire. [ ]
48. `root`, `chmod 000 /etc/motd`, puis `admin`, `edit /etc/motd` →
    `edit: /etc/motd: permission denied` à l'invite, aucun éditeur ne s'ouvre.
    Remettre `chmod 644 /etc/motd`. [ ]
49. Tenir une touche jusqu'à soixante caractères sur une ligne → rien de plus
    n'apparaît, `Line too long: 60 characters` en bas ; Backspace fait encore
    reculer le compte et fait disparaître le message une fois sous soixante. [ ]
50. Coller (Ctrl+V) plus de 2000 caractères dans le tampon → l'arrêt se fait à
    2000, `Buffer full: 2000 typed characters` en bas. [ ]
51. Avec `[modified]` affiché, s'éloigner du carré devant l'écran (la fenêtre se
    ferme), revenir, "Use computer" → l'éditeur est encore ouvert, même
    fichier, même texte, `[modified]` toujours là, curseur revenu au tout début
    du tampon. [ ]
52. Sauvegarder la partie avec un tampon non sauvegardé ouvert, quitter au menu,
    recharger, ouvrir l'ordinateur → l'éditeur revient ouvert avec le même
    tampon. [ ]

## E. Comptes, sudo, su

53. `admin`, `passwd`, Entrée sur l'ancien mot de passe (vide) → `New password:`,
    taper `hunter2`, Entrée → `Retype new password:`, retaper, Entrée →
    `passwd: password updated`. [ ]
54. `exit`, se reconnecter en `admin` avec le mot de passe vide → `login
    incorrect` ; avec `hunter2` → connecté. [ ]
55. `passwd`, mauvais ancien mot de passe → `passwd: authentication failure`,
    rien de changé. [ ]
56. `passwd`, bon ancien mot de passe, `abc` puis `abd` aux deux nouveaux →
    `passwd: passwords do not match`. [ ]
57. `admin`, `cat /etc/passwd` → `cat: /etc/passwd: permission denied`.
    `sudo cat /etc/passwd`, mauvaise réponse au mot de passe →
    `sudo: authentication failure`, retour direct au shell, pas de deuxième
    essai. [ ]
58. `sudo cat /etc/passwd` de nouveau, Entrée sur le mot de passe vide → le
    fichier s'affiche, hachages inclus. [ ]
59. `root`, `edit /etc/sudoers`, retirer la ligne `admin`, sauvegarder. `admin`,
    `sudo ls` → `admin is not in the sudoers file.` (pas de préfixe `sudo:`).
    Remettre la ligne. [ ]
60. `root`, faire de la ligne `admin NOPASSWD`. `admin`, `sudo whoami` → `root`
    sans aucune question. Remettre `admin` seul. [ ]
61. `admin`, `sudo useradd bob`, mot de passe vide → `bob: created` puis
    `useradd: set a password with passwd bob`. `ls -l /home` → `bob`,
    `drwxr-x---`. `id bob` → `uid=bob flag=user groups=bob`. [ ]
62. `useradd Bob` → `useradd: Bob: invalid name`. `useradd admin` →
    `useradd: admin: already exists`. [ ]
62a. **`-G wheel` fait un administrateur, et ça veut dire quelque chose.**
    `sudo useradd -G wheel kate` puis `id kate` → `flag=admin` **et**
    `groups=kate,wheel,sudo`. `passwd kate`, se reconnecter en `kate`,
    `sudo whoami` → son propre mot de passe est demandé, puis `root` : c'est la
    ligne `%wheel` de `/etc/sudoers` qui l'accorde, pas le drapeau.
    `cat /etc/sudoers` pour la voir. [ ]
62b. **La liste REMPLACE, elle n'ajoute pas.** `admin` : `sudo groupadd crew`,
    `sudo usermod -G crew,wheel kate`, `groups kate` → `kate wheel crew sudo`.
    Puis `sudo usermod -G crew kate` → `groups kate` → `kate crew` : `wheel` est
    parti et `sudo whoami` en `kate` répond
    `kate is not in the sudoers file.` C'est la sémantique SVR4 de `-G`. [ ]
62c. **La liste vide est refusée.** `sudo usermod -G "" kate` →
    `usermod: empty group list`, et `groups kate` n'a pas bougé. Puis
    `sudo usermod -G nosuch kate` → `usermod: nosuch: no such group`, toujours
    rien de changé. `sudo usermod -G crew nosuchuser` →
    `usermod: nosuchuser: no such user`. [ ]
63. `userdel root` → `userdel: root: cannot remove`. `admin`,
    `sudo userdel admin` → `userdel: admin: user is logged in`. `userdel bob`
    sans `-r` → `id bob` devient `no such user` mais `ls -l /home` montre
    encore le dossier `bob`. `userdel -r carl` → le dossier disparaît. [ ]
63a. **`userdel` balaie le nom partout.** `sudo useradd -G wheel dan`,
    `cat /etc/group` → `wheel:dan`. `sudo userdel dan`, `cat /etc/group` →
    `wheel:` de nouveau, et `cat /etc/sudoers` n'a jamais eu son nom. Un nom
    laissé dans `wheel` serait `root` qui attend le prochain `dan`. [ ]
64. `admin`, `su` (mot de passe défini sur `root`) → `Password:` avec des `*` ;
    mauvais mot de passe → `su: authentication failure`. Bon mot de passe →
    `root@<host>:/root#`. `exit` → retour à `admin@<host>:~$`, écran non
    effacé ; `exit` encore → déconnexion complète, écran effacé, `login:`. [ ]
65. `root`, `su root` quatre fois de suite (chacune libre), une cinquième →
    `su: too many levels`. Quatre `exit` ramènent à la toute première
    session. [ ]

## F. Groupes

66. `id` en `admin` sur une machine neuve → `uid=admin flag=user
    groups=admin,sudo,users`. [ ]
67. `admin`, sans `su`, `echo on > /dev/light0` → la lumière s'allume, aucun mot
    de passe demandé (le groupe `sudo` fait le travail). [ ]
68. `sudo useradd bob`, `passwd bob`, se reconnecter en `bob`,
    `echo off > /dev/light0` → `light0: permission denied`, la lumière reste
    allumée. [ ]
69. `root`, ajouter une ligne `bob` à `/etc/sudoers`, puis `bob`, `id` →
    `groups=bob,sudo`, et `echo off > /dev/light0` fonctionne. Retirer la
    ligne : ça s'arrête, sans redémarrer la machine. [ ]
70. `admin` : `sudo groupadd crew`, `sudo usermod -G crew bob`,
    `mkdir /home/admin/shared`, `chgrp crew /home/admin/shared`,
    `chmod 770 /home/admin/shared`, `chmod 755 /home/admin`. `bob` :
    `cd /home/admin/shared`, `echo hi > note.txt`, `ls -l` → le fichier est là,
    propriété de `bob`, groupe `bob`. `admin` : `cat shared/note.txt` → `hi`. [ ]
71. `sudo useradd kate`, se reconnecter en `kate`, `ls /home/admin/shared` →
    `permission denied` (troisième compte, pas membre). [ ]
72. `admin`, `chmod 700 /home/admin/shared` → `bob` refusé à `ls`. Remettre
    `770` → `bob` rentre de nouveau. [ ]
73. `root`, `groupdel crew` → `ls -l /home/admin` montre encore `crew` dans la
    colonne groupe, personne dedans ; `chgrp crew /home/admin/shared` répond
    ensuite `chgrp: crew: no such group`. `groupdel root`, `groupdel wheel`,
    `groupdel sudo` et `groupdel users` répondent tous `cannot remove`, les
    quatre groupes livrés, `wheel` inclus parce que `/etc/sudoers` le nomme. [ ]

## G. Fichiers système et BIOS

74. `admin`, `ls -l /bin` → une ligne `-rwxr-xr-x root` par commande ;
    `cat /bin/ls` → `list a directory`. [ ]
75. `admin`, `cat /etc/passwd` → `cat: /etc/passwd: permission denied`. `root`,
    `cat /etc/passwd` → deux lignes, `root:$cs1$…:/root:admin` et
    `admin:$cs1$…:/home/admin:user`, chacune coupée sur deux rangées de
    soixante colonnes. [ ]
76. `root`, `hostname` → `ksp-<x>-<y>` ; `hostname ksp-front` → change le nom.
    Fermer et rouvrir la fenêtre → titre `CeroSec OS · ksp-front`, et l'invite
    aussi. [ ]
77. `root`, `hostname Upper` → `hostname: Upper: invalid name` (majuscule
    refusée) ; même refus pour un nom commençant par un tiret ou dépassant
    seize caractères. [ ]
78. `root`, `rm /bin/ls` → `ls: command not found`, `help` ne liste plus `ls`.
    `echo "list a directory" > /bin/ls`, `chmod 755 /bin/ls` → `ls` refonctionne. [ ]
79. `root`, garder un fichier sous `/home/admin` puis `rm -r /bin` → `help`
    répond `help: no commands in /bin: the system is damaged.` puis
    `help: switch the computer off and on to repair it.` ; `exit` fonctionne
    encore. [ ]
80. Fermer puis rouvrir la fenêtre → `No operating system found.` et
    `Restore system? (y/n)`, aucun `login:` nulle part. [ ]
81. Répondre `n` → la question reste affichée, rien d'autre ne se passe.
    Rouvrir, répondre `y` → `Restoring system ...`, puis le motd, puis
    `login:` ; le fichier laissé sous `/home` est intact. [ ]
82. Ouvrir un ordinateur venant d'une sauvegarde faite avant cette version →
    `help` liste déjà toutes les commandes (`sudo`, `shutdown`, `reboot`,
    `chgrp`, `usermod`, `groupadd`, `more`, `find`, `cut`, `tr`, `tee`,
    `uptime`, `w`, etc.), les vieux noms n'y sont **plus** (étape 274), et
    `cat /etc/sudoers` (en `root`) montre la liste livrée plus la ligne
    `%wheel`, sans que rien d'existant sur le disque ait bougé. [ ]

## H. Périphériques

83. Maison avec une pièce nommée et éclairée, ordinateur alimenté dedans,
    `root` (ou `admin`, membre du groupe `sudo`), `ls -l /dev` → une ligne par
    porte, interrupteur et fenêtre de **tout le bâtiment**, pas
    seulement la pièce de l'ordinateur ; colonnes `c` + mode, `root`, l'id, la
    description, le côté, l'état, rien de plus large que l'écran. Chaque porte
    extérieure paraît **deux fois** : `doorN` (ce qui ouvre) et `lockN` (la
    clé). Les portes intérieures n'ont que leur `doorN`. [ ]
84. Les descriptions sont les ids bruts de la carte (`kitchen`, `livingroom`),
    jamais un nom habillé. Une porte donnant sur l'extérieur lit `exterior` ;
    entre deux pièces, `<pièce>-<pièce>`, avec la première moitié qui est la
    pièce du côté où se trouve la porte. Se tenir dehors près de la maison
    voisine : ses lumières n'apparaissent pas dans la liste. [ ]
85. `cat /dev/light0` → `on` ou `off`. `echo off > /dev/light0` → la pièce
     s'assombrit dans le monde, `cat` confirme `off`. `echo on` la rallume. [ ]
86. Interrupteur sans ampoule, ou courant coupé sur la maison :
     `echo on > /dev/light0` → `light0: no power`, l'interrupteur ne bouge
     pas, `cat` dit toujours `off`. [ ]
87. Porte **extérieure** verrouillée (la seule sorte où la serrure mord) :
     `cat /dev/lockN` → `locked`. Sortir de la maison, essayer d'entrer sans
     clé → refusé par le jeu. `echo unlock > /dev/lockN`, réessayer de
     l'extérieur → elle ouvre, sans message de porte verrouillée.
     `echo lock > /dev/lockN`, essayer encore de l'extérieur → refusé de
     nouveau. Puis, de l'**intérieur**, la même porte verrouillée s'ouvre
     quand même à la main : c'est la règle du jeu, et c'est pour ça qu'une
     porte intérieure n'a pas de `lockN` du tout. [ ]
88. Fenêtre : `cat /dev/win0` → `locked` ou `unlocked`. `echo unlock`, ouvrir
     à la main ; `echo lock` bloque de nouveau. [ ]
89. Casser une fenêtre à la main → `ls -l /dev` dit `smashed` pour elle,
     `echo lock > /dev/winN` répond `winN: smashed`. En barricader une autre →
     `barricaded`, même refus pour `echo lock`. [ ]
90. Base construite sans bâtiment de carte (quatre murs et une porte posés
     soi-même), ordinateur dedans, `ls -l /dev` → liste tout ce qui est dans
     dix cases sur le même plancher ; à onze cases, absent, à dix, présent. [ ]
91. Un deuxième étage avec un interrupteur : absent de la liste, un seul
     plancher est couvert. La porte du joueur lit `built` dans la colonne
     description, avec le côté qu'elle regarde. [ ]
91a. **L'ordinateur du trottoir ne voit pas la maison.** C'est le rapport du
     propriétaire. Prendre un ordinateur, le poser DEHORS sur le trottoir, à
     cinq cases d'une maison dont les appareils sont équipés (modules posés, ou
     option « Modules matériels obligatoires » décochée), ne rien câbler.
     Attendu : `dev` ne montre AUCUN appareil de cette maison, ni la lumière
     de l'intérieur, ni la porte d'entrée (dont l'objet est pourtant posé sur
     une case de trottoir), ni la lampe de porche. Ce qui est dehors et à
     personne reste listé : un générateur traîné sur le trottoir, une lampe de
     rue sur son poteau. [ ]
91b. **Le câble, lui, est payé.** Même ordinateur du trottoir : tirer un câble
     jusqu'à la lampe du porche (clic droit sur la lampe, sous-menu CeroSec,
     avec une bobine de fil). Attendu : `ls -l /dev` la montre enfin, avec les
     tuiles de fil qu'elle a coûté dans `dev find`. La porte d'entrée, posée
     sur la même case, reste absente : le câble est sur la lampe, pas sur la
     case. [ ]
91c. **Une safehouse revendiquée (multijoueur).** Maison revendiquée par un
     autre joueur, option « Modules dans les safehouses » cochée. Un
     non-membre, depuis le trottoir : le clic droit refuse le câble sur la
     porte d'entrée et sur les fenêtres (« C'est le refuge de quelqu'un
     d'autre. »),
     même si l'objet est posé sur une case de trottoir hors de la zone
     revendiquée. Le propriétaire, lui, câble sa porte normalement. Reste
     ouvert et connu : la LAMPE DE PORCHE d'une maison revendiquée est encore
     câblable par n'importe qui. [ ]
92. Cadenasser la porte du joueur → `cat /dev/lockN` dit `padlock`.
     `echo unlock > /dev/lockN` → le cadenas tombe dans l'inventaire comme si
     on l'avait retiré à la main ; `echo lock > /dev/lockN` le remet. Une
     porte du joueur sans cadenas ni clé répond `lockN: no padlock` aux deux
     mots. Attention : un cadenas ne retient pas la **porte** dans ce jeu, il
     retient ce qu'il y a derrière (le contenant, et la porte contre le
     ramassage). Donc `dev doorN open` sur une porte cadenassée l'ouvre, et
     un survivant qui clique dessus l'ouvre aussi. [ ]
93. Ordinateur dans une maison éloignée, se connecter, s'éloigner jusqu'à ce
     que ses chunks se déchargent → `ls -l /dev` ne liste plus rien,
     `echo on > /dev/light0` répond `light0: no such device`. Revenir → les
     mêmes ids réapparaissent sur les mêmes appareils. [ ]
94. Marteau-piqueur sur une porte → son id disparaît de la liste,
     `cat /dev/lockN` sur elle dit `lockN: no such device`, pas
     `no such file`. Construire une nouvelle porte au même endroit → elle
     prend le numéro suivant jamais utilisé, pas celui laissé vide. [ ]
95. `admin` (sans `su`), `chmod 666 /dev/light0` en tant que `root` d'abord,
     puis `exit` la session root : `admin` peut maintenant lire et écrire ce
     device sans sudo. Sauvegarder et recharger → le `666` est toujours là. [ ]
96. `rm /dev/light0`, `mv /dev/light0 /root/x`, `cp /dev/light0 /root/x`,
     `edit /dev/light0` → les quatre répondent `is a device`.
     `mkdir /dev/mine` et `touch /dev/mine` répondent `/dev: read-only`. [ ]
97. `dev` seul dans un grand bâtiment → un tableau, une ligne par appareil,
     `id  description  position  côté  état`, trié par sorte puis par numéro
     (`light2` avant `light10`), rien de plus large que l'écran, l'écran
     défile. La colonne position se lit depuis l'ordinateur : `0 0` pour un
     appareil sur sa propre case, `3E 2N` trois cases à l'est et deux au
     nord, `+1` / `-1` collé derrière pour un autre étage. Vérifier une
     lumière à main droite de l'écran (est) et une porte au nord : les
     lettres correspondent au monde, pas l'inverse.
     `dev door`, `dev light`, `dev lock`, `dev win` → seulement cette sorte.
     `dev toaster` → `dev: toaster: unknown kind`, `dev light99` →
     `dev: light99: no such device`. [ ]
98. `dev light0` → `light0: on`. `dev light0 off` → la pièce s'assombrit dans
     le monde et la ligne répond `light0: off`. `dev light0 toggle` la
     rallume. `dev lockN toggle` sur une porte verrouillée l'ouvre, sur une
     porte cadenassée retire le cadenas (`lockN: unlocked`), et de nouveau
     remet le cadenas (`lockN: padlock`). Sur une fenêtre cassée ou
     barricadée : `winN: cannot toggle`, et `dev winN lock` répond toujours
     `winN: smashed` / `winN: barricaded`. En tant qu'un compte hors du
     groupe `sudo` : `dev` affiche le tableau, mais `dev light0 off` répond
     `light0: permission denied`. [ ]

98b. **Le lampadaire de rue.** Poser un relais sur un lampadaire dehors,
     le câbler à la machine, la nuit, réseau debout. `dev lightN` →
     `lightN: on`. `dev lightN off` → **le lampadaire s'éteint dans le
     monde** et la ligne répond `lightN: off` ; `dev lightN on` le
     rallume. Puis couper le réseau (l'électricité du comté tombée, aucune
     génératrice en portée) : `dev lightN on` répond `lightN: no power` et
     rien ne bouge. [ ]

99. `dev find lightN` sur une lumière allumée → la ligne répond
     `lightN: blinking`, la lumière clignote environ six secondes (deux
     changements par seconde) et **revient allumée** à la fin. Recommencer sur
     une éteinte : elle revient éteinte. Pendant le clignotement, taper
     `dev lightN off` → le clignotement s'arrête tout de suite et la lumière
     reste éteinte. Sur une lumière sans courant : `lightN: no power`, rien ne
     bouge. [ ]
100. `dev find lockN` / `dev find winN` → la ligne répond `lockN: highlighted`
     et l'objet est entouré à l'écran environ six secondes, puis redevient
     normal. Fermer la fenêtre du terminal pendant le contour → il disparaît
     immédiatement. En mode Hôte avec un deuxième joueur (écran partagé) :
     seul celui qui a tapé la commande voit le contour, alors que le
     clignotement d'une lumière se voit des deux. [ ]

Les cinq étapes suivantes portent des lettres et non des numéros neufs : les
numéros 101 et suivants sont déjà cités ailleurs dans ce document (section M) et
dans des rapports déjà rendus, et les décaler rendrait ces renvois faux.

100a. Porte **intérieure** d'une maison, ordinateur dans la même maison :
     `dev` la montre en `doorN` avec l'état `closed` et **aucun** `lockN` pour
     elle. Se placer de façon à voir la porte depuis l'écran, taper
     `dev doorN open` → la ligne répond `doorN: open` et la porte s'ouvre dans
     le monde **sans que personne ne bouge** : aucun survivant ne marche
     jusqu'à elle, aucune animation, aucun son de porte. `dev doorN close` la
     referme. `dev doorN toggle` fait l'aller-retour. Retaper
     `dev doorN open` sur une porte déjà ouverte → `doorN: open`, et rien ne
     bouge une deuxième fois. [ ]
100b. Porte **extérieure** verrouillée (étape 87) : `dev` la montre deux fois,
     `doorN` à l'état `locked` et `lockN` à `locked`. `dev doorN open` →
     `doorN: locked`, la porte ne bouge pas : l'ordinateur n'est pas une clé.
     `dev doorN toggle` répond exactement la même chose. Puis
     `dev lockN unlock` → `lockN: unlocked`, et `dev doorN open` → la porte
     s'ouvre. La refermer et reverrouiller avec `dev lockN lock` :
     `cat /dev/doorN` dit de nouveau `locked`. [ ]
100c. Bloquer l'embrasure avec quelque chose que **le jeu lui-même** refuse :
     garer un véhicule en travers d'une porte extérieure, ou faire pousser /
     apparaître un arbre sur la case de la porte (mode debug). Vérifier
     d'abord à la main qu'un survivant ne peut pas ouvrir cette porte, puis
     `dev doorN open` → `doorN: blocked`, la porte ne bouge pas ;
     `dev doorN toggle` dit la même chose. Déplacer le véhicule ou l'arbre →
     `dev doorN open` fonctionne de nouveau. **Contre-épreuve à ne pas
     oublier :** se tenir soi-même dans l'embrasure (sur la case de la porte
     ou sur celle d'en face) et taper `dev doorN close` → la porte doit
     **fermer normalement**, sans `blocked`. Une porte traverse un survivant
     dans ce jeu ; la machine ne doit pas inventer un refus que le jeu ne fait
     pas. Même contre-épreuve avec un zombi immobile dans l'embrasure. [ ]
100d. Barricader la porte intérieure (planches, marteau, clous) →
     `dev doorN open` répond `doorN: barricaded`, et la porte ne bouge pas
     d'un poil. `dev doorN toggle` dit la même chose. Retirer les planches →
     `dev doorN open` fonctionne de nouveau. Important : confirmer qu'une
     porte barricadée ne s'ouvre **jamais à moitié** ou en silence. [ ]
100e. Base construite par le joueur, porte posée soi-même avec un cadenas
     dessus : `dev` la montre en `doorN` (`built`, `closed`) **et** en `lockN`
     (`built`, `padlock`). `dev doorN open` → `doorN: open`, la porte s'ouvre
     malgré le cadenas, même résultat qu'un clic à la main : le cadenas ne
     tenant pas la porte. Poser plutôt une **clé** sur la porte (`lockN` à
     `locked`) : `dev doorN open` → `doorN: locked`. Enfin, une porte de
     garage ou une porte double : elle a un `lockN` et **aucun** `doorN`, et
     `dev door<son numéro> open` répond `dev: ...: no such device`. [ ]
100f. **Détecteur de mouvement, le posé.** Trouver un **Motion Sensor**
     (`Base.MotionSensor`), le module électronique : il se ramasse dans le
     butin d'électronique, se démonte d'une `HomeAlarm`
     (`recipes_electrical.txt:78`), ou se donne en debug, et le **laisser
     tomber par terre** dans la pièce nommée où se trouve l'ordinateur.
     `dev sensor` → une ligne `sensorN`, description = le nom brut de la pièce,
     colonne côté **vide**, position juste, état `clear`. `ls -l /dev` sur cette
     ligne → `cr--r-----` et non `crw-rw----` : mode `440`. Lâcher un marteau à
     côté → il n'apparaît **pas**. [ ]
100f'. **Et la bombe n'en est pas un.** Fabriquer (ou se donner) un
     `PipeBombSensorV1`, une bombe artisanale avec un détecteur dessus, et le
     laisser tomber dans la même pièce. `dev sensor` ne gagne **aucune** ligne,
     et `cat /dev/sensor<numéro suivant>` répond `no such file`. Refaire avec un
     `AerosolbombSensorV2`, un `FlameTrapSensorV3`, un `NoiseTrapSensorV1` et un
     `SmokeBombSensorV2` : aucun des quinze ne devient un device. C'est voulu :
     une mine qui explose quand elle détecte du mouvement n'est pas un
     détecteur, et une machine qui la câblerait offrirait au survivant un
     système de sécurité qui le tue. Vérifier aussi qu'un de ces pièges
     **placé** (posé, donc armé) n'apparaît pas davantage. [ ]
100g. **Marcher devant.** Rester immobile 10 secondes, `cat /dev/sensorN` →
     `clear`. Puis traverser la pièce devant le capteur et taper tout de suite
     `cat /dev/sensorN` → `motion`. La portée est de **trois cases** : bouger à
     deux cases du capteur → `motion` ; bouger à cinq cases (même pièce, grande
     salle) → il reste `clear`. Et la portée est un **cercle** et non un carré :
     bouger deux cases à l'est ET trois au sud du capteur (3,6 cases à vol
     d'oiseau) → `clear`, alors qu'un compteur de cases aurait dit trois.
     Passer dans la pièce **d'à côté**, mur entre les deux, à une seule case du
     capteur → il reste `clear` : un PIR ne voit pas à travers un mur. Faire
     entrer une **voiture** dans le champ → `motion` (le capteur du jeu lui-même
     déclenche sur un véhicule). [ ]
100h. **Le maintien de cinq secondes, et le zombi immobile.** Bouger devant le
     capteur puis s'arrêter net et compter : `cat` à 2 s → `motion`, `cat` à 4 s
     → `motion`, `cat` à 6 s → `clear`. Attirer un zombi dans le champ et le
     laisser **debout sans bouger** (derrière une clôture, ou endormi) : six
     secondes après son dernier pas, `cat` dit `clear` alors qu'il est toujours
     là. C'est voulu : le capteur détecte le MOUVEMENT et pas les corps.
     Vérifier aussi qu'écrire est refusé : `echo motion > /dev/sensorN` et
     `dev sensorN motion` → `sensorN: invalid value`, et `dev sensorN toggle` →
     `sensorN: cannot toggle`. [ ]
100i. **Le ramasser, et le montrer.** `dev find sensorN` → la ligne répond
     `sensorN: highlighted` et l'objet au sol est entouré environ six secondes,
     pour celui qui a tapé et pour personne d'autre. Puis ramasser le capteur :
     `dev sensor` ne le liste plus, `cat /dev/sensorN` répond
     `sensorN: no such device` (pas `no such file`). Le relâcher **sur la même
     case** → il reprend `sensorN`, le numéro appartenant à l'endroit ; le
     lâcher sur une autre case → il prend le numéro suivant jamais utilisé.
     Enfin, éteindre l'ordinateur, marcher, revenir, rallumer, attendre une
     minute, `cat` → `clear` d'abord (le capteur se réchauffe une seconde), puis
     `motion` en bougeant devant. [ ]

## I. Manuel

101. Clic droit sur un ordinateur, dernière entrée du menu → "Read the CeroSec
     manual (dev)" est un SOUS-MENU de trois entrées : "User's Guide", "System
     Administrator's Guide", "Programmer's Guide", dans cet ordre. Chacune
     ouvre son propre volume, sans copie du livre dans l'inventaire, sur un
     ordinateur allumé ou éteint, à portée ou pas. L'entrée parente elle-même
     n'ouvre rien quand on passe dessus. [ ]
102. Menu debug → Items list, filtre `CeroSec` → TROIS livres :
     `CeroSec.ManualUser`, `CeroSec.ManualAdmin` et `CeroSec.ManualProgrammer`.
     `CeroSec.Manual` n'existe plus du tout : l'ancien livre unique était une
     deuxième copie du volume 1 sous un autre nom et il a été retiré du script.
     Catégorie affichée Literature pour les trois, noms
     "CeroSec OS User's Guide", "... System Administrator's Guide",
     "... Programmer's Guide". Faire apparaître les
     trois volumes dans l'inventaire → trois icônes DIFFÉRENTES : le même livre
     à petit écran vert, relié bleu marqué 1, vert marqué 2, rouge marqué 3.
     Jamais un point d'interrogation blanc, et le chiffre reste lisible à la
     taille où l'inventaire les dessine. [ ]
103. Clic droit sur chaque volume dans l'inventaire → "Read the User's Guide" /
     "Read the System Administrator's Guide" / "Read the Programmer's Guide",
     une seule option et la bonne ; pas de "Read" ni "Write" ni "Look at
     pictures" de la vanille. Sélectionner les trois ensemble → trois options,
     dans l'ordre 1, 2, 3. Aucune option "Read the manual" nulle part : l'objet
     qui la portait n'existe plus. Vérifier que la couverture du volume 1 dit
     bien `CeroSec OS 1.0 User's Guide` et que sa table des matières est celle
     du volume 1 (`1. Your first day`), et non celle de l'ancien livre
     (`1. Your machine`). [ ]
103a. Double-clic sur un volume dans l'inventaire → le livre s'ouvre, exactement
     comme par l'option "Read the ..." : le bon volume, sa propre couverture, et
     le signet de CET exemplaire. Aucune animation de lecture, rien en file
     d'action. Double-clic sur un livre de la vanille (`Base.Book`) → le
     comportement vanilla habituel, PAS notre lecteur. Double-clic sur une arme
     → elle s'équipe comme avant ; sur un sac → il s'équipe comme avant. C'est
     ce qui prouve que l'enveloppe rend la main à la fonction d'origine. [ ]
104. Ouvrir un volume → deux feuilles crème côte à côte, numéros de page aux
     coins extérieurs, boutons `< Back`, `Contents`, `Next >` sous le livre. [ ]
105. Marcher, ouvrir une porte, se faire mordre avec le livre ouvert → il reste
     ouvert, aucune animation de lecture, rien en file d'action. [ ]
106. Page 1 de chaque volume : titre centré `CeroSec OS 1.0 User's Guide`
     (puis `... System Administrator's Guide`, `... Programmer's Guide`), une
     règle dessous, `First Edition, 1993` en dessous encore, en encre plus
     pâle. Page 2 : Contents. [ ]
107. Page 2 de chaque volume ne liste QUE ses propres chapitres : aucun
     chapitre d'un des deux autres volumes n'y apparaît. [ ]
108. Table des matières : chaque ligne reprend exactement le titre du chapitre
     tel qu'il apparaît sur sa propre feuille (`1. Your first day`, jamais
     `1.  1. Your first day`), numéro de page aligné à droite. Cliquer sur
     chaque ligne → ouvre au premier feuillet du bon chapitre, et le numéro
     affiché sur la table correspond au numéro écrit au pied de la feuille. [ ]
109. Flèche droite fait ce que fait `Next >`, flèche gauche ce que fait
     `< Back`. Au tout début du livre, `< Back` et la flèche gauche ne font
     rien ; à la toute fin, `Next >` et la flèche droite ne font rien. [ ]
110. Tourner à un endroit au milieu du livre, fermer avec Escape, rouvrir →
     même feuillet exactement. Sauvegarder, quitter, recharger, rouvrir →
     encore le même feuillet (le signet vit sur l'objet, dans sa modData). [ ]
111. Faire apparaître un second exemplaire du MÊME volume, le laisser sur une
     autre page que le premier → chacun garde son propre signet, indépendant de
     l'autre. [ ]
112. Deux volumes, deux signets : tourner le User's Guide au milieu, le fermer,
     ouvrir le Programmer's Guide → il s'ouvre à SON début, pas sur la page de
     l'autre. Le tourner ailleurs, le fermer, rouvrir le User's Guide → il est
     resté où il était. Refaire la même chose par la porte dev, sans aucun
     exemplaire dans l'inventaire : la porte garde aussi un signet par volume,
     le temps de la session. [ ]
113. Butin. Avec `CeroSec.DEBUG = true`, la console dit une seule fois au
     chargement `the manual set added in 36 places` (douze listes fois trois
     volumes). Menu debug → Spawn rate checker, liste `LibraryComputer` :
     `CeroSec.ManualUser` à 4, `CeroSec.ManualAdmin` à 2,
     `CeroSec.ManualProgrammer` à 1, dans cet ordre, et aucune ligne
     `CeroSec.Manual`. Liste `UniversityDesk_Computer` :
     `CeroSec.ManualProgrammer` remonte à 2. [ ]
114. Vérifier que la version affichée est la même partout : la bannière de
     démarrage et `/etc/motd` disent `CeroSec OS 1.0`, la couverture de chacun
     des trois volumes dit `CeroSec OS 1.0` suivi de son propre nom, et le BIOS
     affiche `CeroSec BIOS 1.0` comme un numéro séparé. Aucun de ces textes ne
     doit afficher un quatrième numéro de version. [ ]

## J. Sons et animation

115. Taper un mot lentement dans le terminal → un clic court par touche, pas
     toujours le même échantillon (quatre au hasard) ; tenir une touche →
     clics réguliers et rapides, jamais deux collés en moins de 40 ms. [ ]
116. Entrée au shell, puis Entrée dans l'éditeur pour une nouvelle ligne → un
     clic plus lourd et plus long que celui d'une lettre, dans les deux cas. [ ]
117. Flèches haut et bas (historique au shell, curseur dans l'éditeur)
     cliquent ; gauche, droite, Home et End ne cliquent pas. [ ]
118. Ouvrir le terminal debout, taper → animation de fouille, mains sur le
     clavier, arrêt environ une seconde et demie après la dernière touche.
     Lire sans taper → le personnage reste immobile face au moniteur. [ ]
119. Avec une chaise, assis, taper au clavier → noter si l'animation joue
     depuis la chaise ou si le personnage reste simplement assis face à
     l'écran sans animation superposée. [ ]

## K. Mode Héberger

120. Hôte allume un ordinateur → le client voit le sprite passer à l'écran
     allumé sans recharger, et voit la lueur apparaître la nuit sans
     s'éloigner et revenir. [ ]
121. Deux joueurs au même ordinateur, terminal ouvert des deux côtés : le
     premier tape `ls -l /`, la ligne tapée et sa sortie apparaissent en
     direct sur l'écran de l'autre. [ ]
122. L'un des deux tape `edit notes.txt` ; l'écran de l'autre montre le même
     éditeur avec `Another user is editing`, ses touches ne font rien, son
     Escape ferme seulement sa fenêtre. [ ]
123. Un joueur `echo on > /dev/light0` ; l'autre, debout dans la pièce
     concernée, voit la lumière s'allumer sans se reconnecter ni s'éloigner
     et revenir. [ ]
124. Un joueur déverrouille une porte à clé depuis l'ordinateur ; l'autre
     l'ouvre à la main. Puis le premier la reverrouille depuis l'ordinateur ;
     le second est refusé en essayant de l'ouvrir. [ ]
125. L'un des deux tape `reboot` en `root` : les deux fenêtres se ferment et le
     sprite s'éteint pour les deux joueurs. Trois secondes plus tard la machine
     se rallume et **les deux** fenêtres se rouvrent, chacune chez son joueur, et
     rejouent le BIOS ensemble jusqu'à `login:`. Aucune ne reste sur l'ancien
     écran. Si l'un des deux s'éloigne pendant le noir, seul celui qui est resté
     retrouve sa fenêtre. [ ]
126. Un joueur ferme sa fenêtre en pleine partie (ou quitte) ; l'autre continue
     de taper, et dans la minute qui suit, la machine ne compte plus la
     fenêtre partie dans ses balayages. [ ]

## L. Scripts, et l'invite qui parle la même langue

Écrire les scripts avec `edit`, jamais en collant du texte : c'est l'éditeur de
la machine qui est testé en même temps. Un script tapé sur une machine reste
dessus.

Les étapes 140 à 148 ne passent par aucun fichier : elles se tapent à l'invite,
parce que l'invite **est** le langage de script depuis le palier 5a.1. C'est la
capture d'écran prise en jeu qui les a fait écrire (`while: command not found`).

127. `edit compte.sh`, taper les quatre lignes ci-dessous, `Tab` pour
     enregistrer, `Échap` pour sortir. Puis `cat compte.sh` → les quatre lignes
     sont bien là, dans l'ordre. [ ]

         i=0
         while [ $i -lt 3 ]; do
           echo tour $i
           i=$((i + 1))
         done

128. `sh compte.sh` → `tour 0`, `tour 1`, `tour 2` apparaissent l'un après
     l'autre, l'invite ne revient qu'à la fin, et pendant ce temps rien de ce
     qu'on tape n'apparaît à l'écran. [ ]
129. `chmod 755 compte.sh` puis `./compte.sh` → même résultat. `chmod 644
     compte.sh` puis `./compte.sh` → `./compte.sh: permission denied`, alors
     que `sh compte.sh` marche toujours. [ ]
129a. En `root` (`su -`, ou une session root), `cd /home/admin`, `chmod 644
     compte.sh` puis `./compte.sh` → `./compte.sh: permission denied` **pour
     root aussi** : un fichier sans aucun bit `x` est un fichier que personne
     n'a le droit d'exécuter, root compris. `chmod 100 compte.sh` (ou `010`, ou
     `001` : un seul bit `x` n'importe où suffit) → `./compte.sh` repart. Puis
     `chmod 755 compte.sh`. [ ]
130. `compte.sh` tout court (sans `./`) → `compte.sh: command not found` : un
     nom nu reste une commande de `/bin` et rien d'autre. [ ]
131. `edit bonjour.sh` avec `read -p "nom? " n` puis `echo "salut $n"` →
     `sh bonjour.sh` affiche `nom? ` à l'invite, ce qui est tapé s'y ajoute
     normalement, et après Entrée la machine répond `salut <ce qui a été
     tapé>`. La ligne `nom? <réponse>` reste à l'écran. [ ]
132. Relancer `sh bonjour.sh` et appuyer sur **Échap** à la question → `^C`
     s'affiche, puis `killed`, l'invite revient, et la fenêtre du terminal ne
     se ferme pas. [ ]
133. `edit boucle.sh` avec une seule ligne : `while true; do echo x; done`.
     `sh boucle.sh` → les `x` arrivent en filet régulier (une vingtaine par
     seconde au plus), jamais d'un coup, et l'écran ne garde que ses cent
     dernières lignes. Pendant ce temps, marcher autour de l'ordinateur et
     ouvrir une porte : le jeu ne saccade pas. [ ]
134. Pendant que `boucle.sh` tourne, **Échap** → `^C` puis `killed`, l'invite
     revient immédiatement. [ ]
135. `sh boucle.sh &` → la machine répond `[1] 42` (ou un autre numéro) et
     l'invite revient tout de suite. Les `x` continuent d'arriver par-dessus
     ce qu'on tape. `ps` → une ligne avec l'id, l'état `R` ou `O` et un nombre
     de pas qui **monte** à chaque appel. `jobs` → `[1] running`. [ ]
136. `kill %1` → `[1] killed` s'affiche, `ps` ne montre plus rien. Relancer
     `kill %1` → `kill: %1: no such job`. [ ]
137. Lancer quatre fois `sh boucle.sh &`, puis une cinquième →
     `sh: too many jobs`, et `jobs` en montre toujours exactement quatre. Les
     tuer une par une avec `kill %1` … `kill %4`. [ ]
138. `edit dur.sh` avec `while true; do x=1; done` (aucune sortie), puis
     `sh dur.sh &`. Laisser tourner **cinq minutes de temps réel** en jouant
     normalement à côté. Au bout des cinq minutes, la machine affiche
     `[1] killed: cpu limit` toute seule. Vérifier avec `ps` avant et après.
     Noter si le jeu a saccadé une seule fois pendant ces cinq minutes. [ ]
139. `sh boucle.sh &` puis `reboot` en `root` (ou couper le courant de la
     pièce) → après le noir, le BIOS et la reconnexion, `ps` est vide : un
     redémarrage ne laisse aucun travail en cours. Même chose après avoir
     sauvegardé et rechargé la partie. [ ]

140. `while true; do echo tick; sleep 1; done &` tapé **directement à
     l'invite** (aucun fichier) → la machine répond `[1] <numéro>` et rend
     l'invite tout de suite, puis `tick` arrive une fois par seconde.
     **Jamais** `while: command not found`. `jobs` → `[1] sleeping` suivi de la
     ligne telle qu'elle a été tapée. `kill %1` → `[1] killed`. [ ]
141. Toujours à l'invite : `echo a && echo b`, `false || echo c`,
     `for i in 1 2 3; do echo $i; done`, `echo $((7 * 6))`,
     `echo $(whoami)`, `echo 'un   deux'` → chacun répond comme dans un
     script. `while true; do echo x` (sans `done`) →
     `sh: syntax error: missing 'done'` et **rien** ne tourne. [ ]
141a. **Les dollars dans une somme.** `edit part.sh` avec deux lignes :
     `echo $(($1 / $2)) chacun, $(($1 % $2)) de reste` et
     `echo $# nombres`. Puis `chmod 755 part.sh` et `./part.sh 17 5` →
     `3 chacun, 2 de reste` puis `2 nombres`. `./part.sh` tout court →
     `part.sh: line 1: divide by zero` (un mot vide vaut zéro, et rien
     divisé par rien est refusé). À l'invite : `x=9`, `echo $((${x} * 2))`
     → `18` ; `false`, `echo $(($? + 1))` → `2`. [ ]
142. `x=5` puis `echo $x` → `5`. Fermer la fenêtre, s'éloigner, revenir,
     rouvrir → `echo $x` répond encore `5`. `exit` puis se reconnecter →
     `echo [$x]` répond `[]` : une déconnexion emporte les variables. Vérifier
     aussi que `cd /etc` à l'invite déplace bien l'invite (`pwd`), alors que
     `cd /etc` **dans** un script ne la déplace pas. [ ]
142a. **L'environnement, et ce qu'un script voit.** `edit voir.sh` avec une
     seule ligne : `echo "x=[$x] w=[$w] HOME=[$HOME]"`, puis
     `chmod 755 voir.sh`. Taper `x=hi`, `w=secret`, `./voir.sh` →
     `x=[] w=[] HOME=[/home/admin]` : un script reçoit l'ENVIRONNEMENT (ce
     qu'un login exporte), jamais les variables de l'invite. `export x` puis
     `./voir.sh` → `x=[hi] w=[]`. `env` → trois lignes triées, `HOME=...`,
     `PATH=/bin`, `x=hi`, et **pas** `w`. `export` tout court → les mêmes,
     précédées de `export `. [ ]
142b. **Ce qu'un script pose ne revient pas, sauf par le point.** `edit pose.sh`
     avec `y=dedans`, puis `y=dehors`, `./pose.sh`, `echo [$y]` → `[dehors]`.
     Ensuite `. ./pose.sh` puis `echo [$y]` → `[dedans]` : le point lit le
     fichier DANS ce shell-ci. Vérifier aussi `. pose.sh` (sans `./`) →
     `.: pose.sh: no such file` tant que le dossier n'est pas dans `PATH`, et
     `chmod 600 pose.sh` → `. ./pose.sh` marche encore (le point veut `r`, pas
     `x`) alors que `./pose.sh` répond `./pose.sh: permission denied`. [ ]
143. Taper `while true; do echo y; done` sans `&` → les `y` arrivent en filet,
     il n'y a aucune invite en dessous, et **Échap** rend l'invite avec `^C`.
     Pendant ce temps, marcher et ouvrir une porte : le jeu ne saccade pas. [ ]
144. `history` → la liste numérotée de tout ce qui a été tapé depuis le début,
     la plus récente en bas. **Flèche haut** et **flèche bas** à l'invite
     remontent et redescendent la même liste. Fermer la fenêtre, revenir,
     rouvrir, **flèche haut** → la dernière ligne tapée **avant** de partir est
     là. `!!` rejoue la dernière, `!3` rejoue la troisième, et c'est la ligne
     **développée** qui s'affiche. `!999` → `sh: !999: event not found`.
     `history -c` puis `history` → vide. [ ]
145. `passwd`, répondre aux trois questions, puis `history` → la commande
     `passwd` y est, les **mots de passe tapés n'y sont pas**. `ls -A` dans le
     home → `.sh_history` apparaît, `ls` tout court ne le montre pas,
     `ls -l .sh_history` → mode `-rw-------`. Se connecter comme un autre
     compte et `cat /home/admin/.sh_history` → `permission denied`. [ ]
146. `edit .profile`, écrire `echo bonjour`, `saluer=ok` et `cd /etc`.
     Se déconnecter (`exit`) et se reconnecter → `bonjour` s'affiche après le
     motd, l'invite est sur `/etc`, et `echo $saluer` répond `ok`. Vérifier que
     `.profile` n'est **pas** dans `history`. Puis remplacer son contenu par
     `while true; do echo z; done`, se reconnecter → l'invite est occupée,
     **Échap** la rend, et `edit .profile` permet de réparer le fichier : la
     machine n'est jamais bloquée. [ ]
147. En `root` : `shutdown -r +2` → une ligne `[1] 44` (le numéro du **processus**)
     puis `The system is going down for reboot in 2 minutes!` sur **tous** les
     écrans ouverts sur la machine. Attendre une minute → `... in 1 minute!`.
     `shutdown -c` → la ligne d'usage `shutdown: usage: shutdown [-h|-r] now|+N` :
     ce drapeau n'existe pas ici, et l'ordre est **toujours** en attente. Refaire
     `shutdown -r +1`, laisser filer →
     `The system is going down for reboot NOW!`, la machine s'éteint et la
     fenêtre se ferme, puis trois secondes de noir, puis le BIOS et `login:`
     dans une fenêtre rouverte toute seule, un `reboot` programmé est le même
     `reboot`. `halt` se comporte comme avant : la machine s'éteint et rien ne
     revient.
     Enfin : `shutdown -r +10`, **sauvegarder et recharger la partie** → le
     compte à rebours est oublié et la machine reste allumée (c'est voulu et
     c'est écrit dans le manuel). `halt` en `root` → la machine s'éteint. [ ]
147a. **Un ordre en attente est un processus**, et on l'annule en le tuant : c'est
     ce que fait un vrai `shutdown` de 1993, et il n'y a pas de `-c`. En `root` :
     `shutdown -h +3`, puis `jobs` → une ligne `[1] waiting` suivie de
     `shutdown -h +3`, et `ps` → la même chose avec son numéro et un `W`.
     `kill %1` (ou `kill <numéro>`) → **rien ne s'affiche**, c'est ainsi que
     `kill` répond, et passé les trois minutes la machine est **toujours
     allumée**. Deux ordres à la fois sont permis (deux processus le sont) :
     `shutdown -h +5` puis `shutdown -r +9` → les deux sont acceptés, `jobs` en
     montre deux, et c'est la première échéance qui emporte la machine ; tuer les
     deux pour la suite. Puis la permission : `shutdown -h +3` en `root`,
     `exit`, se reconnecter en `admin`, `kill <numéro>` →
     `kill: <numéro>: Operation not permitted`, et la machine s'éteint quand même
     à l'heure dite. Enfin `shutdown -r +1` tué avant la minute → **aucun**
     redémarrage, pas même le noir de trois secondes. [ ]
148. Fichiers cachés et `/bin` : `ls -a` dans le home → `.` et `..` en tête,
     puis les noms pointés, puis le reste ; `ls -A` → les mêmes sans `.` ni
     `..` ; `ls -la` et `ls -aF` lisent pareil (`./` et `../` avec `-F`). Puis
     `sudo rm /bin/sleep` → `sleep 1` répond `sleep: command not found` ;
     `sudo chmod 600 /bin/echo` → `echo hi` répond `echo: permission denied`
     et `sudo echo hi` est refusé de la même façon (aucun bit `x` : même root
     ne l'exécute pas), puis `sudo chmod 755 /bin/echo` le remet ; `if true; then history; fi`
     marche toujours (la grammaire n'est pas un fichier) ; `ls /bin` ne montre
     ni `cd` ni `exit` ni `jobs` ni `wait` -- ce sont des mots du shell, pas des
     fichiers -- et `cd /etc` marche quand meme, `man cd` repond, et `help` les
     nomme sous la table. Enfin
     `sudo rm /bin/sh` → **toute** ligne tapée répond `sh: command not found`,
     `exit` fonctionne encore, et éteindre puis rallumer la machine la répare
     par le BIOS. [ ]

## M. Les doutes ouverts

Ce sont les points que les programmeurs ont signalés comme réglables seulement
en observant le jeu réel, pas par un banc de test.

149. Comparer `date` à l'horloge du HUD au même instant, plusieurs fois à des
     heures différentes : l'heure et la minute doivent toujours correspondre à
     ce que le jeu affiche, jamais à l'heure réelle de l'ordinateur qui fait
     tourner le jeu. [ ]
150. Reprendre l'étape 1 en se tenant déjà sur le carré devant l'écran, dos au
     mur derrière, à l'étape du bord de la case plutôt qu'au centre : vérifier
     que le point de position d'assise (avec une chaise) et le point de départ
     de l'animation (sans chaise) sont bien à l'intérieur du carré devant
     l'écran, jamais décalés vers une case voisine. [ ]
151. À l'étape 4, noter les hauteurs exactes des deux caisses empilées et si le
     seuil de blocage se déclenche vraiment à deux caisses ou déjà à une seule
     selon leurs sprites : ça dépend de la valeur `Surface` de chaque caisse,
     pas d'un nombre fixe dans le mod. [ ]
152. À l'étape 84, vérifier sur une vraie porte extérieure quel côté du mot
     `exterior` correspond au côté réel de la porte, et si un couloir entre
     deux pièces donne bien `<pièce-du-carré-de-la-porte>-<autre-pièce>` dans
     ce sens précis. [ ]
153. À l'étape 90, tester un interrupteur de lumière posé sur une case qui n'a
     elle-même aucune pièce définie (pas de plancher de maison dessous) mais
     qui est dans le rayon de dix cases d'une base : confirmer qu'il apparaît
     tout de même dans `ls -l /dev`. [ ]
154. Après une sauvegarde et un rechargement en pleine chaîne `su` (deux
     comptes de profondeur ou plus), vérifier que `console.stack` a gardé
     exactement la même profondeur et la bonne invite, sans qu'un `exit` de
     trop ou de moins soit nécessaire pour ressortir. [ ]
155. `sudo su bob` en tant que `admin` : l'invite devient celle de `bob` sans
     qu'aucun mot de passe de `bob` soit demandé, `whoami` répond `bob`, et
     `exit` ramène à `admin`. `sudo su` tout court donne `root` et son `#`.
     `sudo exit` répond `sudo: exit: command not found` et ne déconnecte
     personne ; `sudo cd /` répond `sudo: cd: command not found` (et non plus
     rien du tout), `pwd` n'a pas bougé, et `sudo jobs`, `sudo read x` et
     `sudo type ls` répondent pareil chacun sous son nom. [ ]
156. En mode Hôte, allumer ou éteindre un ordinateur en étant l'hôte lui-même :
     noter si l'hôte entend son propre son de bascule ou seulement si le
     client distant l'entend. [ ]
157. S'éloigner d'un ordinateur allumé jusqu'à décharger son chunk, puis
     revenir : compter exactement une lueur autour de l'écran, jamais deux
     superposées et jamais aucune. [ ]
158. Comparer la taille de l'icône du manuel dans l'inventaire à celle d'un
     livre vanille de même catégorie (Literature) : noter si elle paraît trop
     grande, trop petite, ou pareille. [ ]
159. Au premier démarrage d'une partie avec le mod actif, confirmer dans
     `~/Zomboid/console.txt` qu'aucune erreur de script ne nomme
     `items_cerosec.txt` (le script d'objets chargé depuis `common/`) et que
     la ligne `manual added to 12 distribution lists` apparaît une fois. [ ]

160. À l'étape 133, chronométrer une vingtaine de lignes `x` : confirmer qu'il
     en arrive bien une vingtaine par seconde et pas deux fois plus ni deux
     fois moins. Le débit est réglé côté serveur
     (`CeroSec.JOB_OUT_PER_SEC`) et dépend de la cadence réelle de
     `Events.OnTick`, qui n'a jamais été mesurée en jeu. [ ]
161. À l'étape 133, faire tourner la boucle sur **quatre ordinateurs à la
     fois** (quatre machines allumées, un script sur chacune) et jouer à côté
     pendant une minute : noter la moindre saccade. Le Lua du jeu (Kahlua) est
     une machine virtuelle Java et n'a jamais été comparée à `lua5.1`, sur
     lequel tous les chiffres du banc ont été pris ; si ça saccade, les deux
     budgets (`CeroSec.STEP_BUDGET_PER_TICK`, `STEP_BUDGET_PER_MACHINE`) sont
     à baisser. [ ]
162. À l'étape 131, vérifier avec `read -n 1 -p "y/n? " a` que la machine prend
     bien le premier caractère tapé **après Entrée** : la fenêtre n'envoie
     rien avant Entrée, donc `-n 1` prend le premier caractère de la ligne et
     non la première touche pressée. Noter si ça surprend en jeu. [ ]

163. Au shell, avec `note2.txt` et `notes.txt` dans le dossier, taper `cat no`
     puis appuyer sur Tab : la ligne doit devenir `cat note` et le curseur bloc
     se poser juste après le `e`. Confirmer surtout que la touche Tab arrive
     bien à la fenêtre en jeu -- le jeu ne donne qu'Échap et Tab à une boîte de
     texte focalisée, et ça n'a jamais été vérifié avec un vrai clavier. [ ]
163a. **Tab connaît le PATH, pas seulement `/bin`.** `mkdir bin`,
     `echo "echo hi" > bin/hello`, `chmod 755 bin/hello`. Taper `hell` puis Tab
     → **rien ne bouge** (le PATH ne nomme pas encore ce dossier). Puis
     `PATH=$PATH:$HOME/bin`, retaper `hell` et Tab → la ligne devient
     `hello ` avec l'espace, et `hello` tout court répond `hi`. [ ]
164. À l'étape 163, appuyer sur Tab une deuxième fois : les deux noms doivent
     s'afficher en colonnes sur l'écran, et l'invite avec `cat note` se
     redessiner juste en dessous. Noter ce qui arrive à cette liste quand on
     appuie ensuite sur Entrée : elle est dessinée par la fenêtre et non par la
     machine, donc elle disparaît au prochain écran envoyé par le serveur -- un
     vrai ksh l'aurait gardée dans le défilement. Dire si ça surprend en jeu. [ ]
165. Deux joueurs devant le même ordinateur : le premier tape `cat no` et fait
     Tab deux fois, le second regarde son propre écran. Confirmer qu'aucune
     ligne de complétion n'apparaît chez le second et que son invite reste
     intacte -- la complétion est adressée à une seule fenêtre. Puis, sur un
     dossier où le compte a `x` sans `r` (`chmod 300 secret`), vérifier que Tab
     n'offre rien du tout et n'affiche aucune erreur. [ ]

## L2. Tubes, cron et `fg` (palier 5b)

166. Au shell : `ls /bin | wc` puis `ls /bin | grep sort`. La première ligne doit
     donner trois nombres (lignes, mots, octets) sans nom de fichier derrière,
     la seconde le seul mot `sort`. Confirmer surtout que rien de l'étage de
     gauche n'apparaît à l'écran : ce qui traverse le tube n'est pas affiché. [ ]
166b. **Une ligne plus large que l'écran ne se coupe que sur la vitre.**
     `grep root /etc/passwd | cut -d: -f1` → une seule ligne, `root`, et rien
     d'autre (avant, la ligne du fichier des comptes arrivait à `cut` déjà
     pliée à soixante colonnes et une deuxième ligne `n` suivait).
     `grep root /etc/passwd | wc -l` → `     1`. Puis `cat /etc/passwd > copie`
     et `wc -l copie` → le nombre de comptes, pas le double. Enfin
     `cat /etc/passwd` tout seul : là, la ligne DOIT se plier à soixante
     colonnes, c'est l'écran qui le veut. [ ]
167. Écrire un fichier avec `edit fruits` contenant `poire`, `pomme`, `poire`,
     `figue` (une par ligne), puis taper `cat fruits | sort | uniq -c`. Attendu,
     dans cet ordre : `      1 figue`, `      1 pomme`, `      2 poire`. Le
     compte est cadré sur sept colonnes. [ ]
168. `while true; do echo y; done | head -n 1` : une seule ligne `y` doit
     apparaître, l'invite doit revenir tout de suite, et `ps` juste après ne
     doit montrer que le shell. C'est le SIGPIPE : le lecteur ferme, l'écrivain
     meurt. Noter le temps que ça prend vraiment en jeu (ça doit être
     instantané). [ ]
169. `echo bonjour | read x` puis `echo $x` : la deuxième ligne doit être vide.
     Chaque étage d'un tube est un sous-shell, donc la variable meurt avec lui.
     Puis `x=$(echo bonjour)` et `echo $x` → `bonjour`. Dire si le premier
     résultat surprend. [ ]
169a. **Une capture trop grosse ne salit pas l'écran.** Fabriquer un gros
     fichier : `edit gros.txt`, coller une quarantaine de lignes de trente
     caractères (ou `cat /var/log/messages > gros.txt` si le fichier dépasse
     mille octets), puis `x=$(cat gros.txt)` → **une seule** ligne
     `sh: word too large`, et rien du contenu du fichier ne défile derrière
     elle. `echo [$x]` → `[]`. [ ]
170. `crontab -l` → `no crontab for admin`. Puis `crontab -e`, écrire
     `60 * * * * echo test` et sauver avec Tab : l'écran doit répondre
     `Cannot save: "/var/spool/cron/admin":1: bad minute` et **rien** ne doit
     être installé (Échap, puis `crontab -l` doit encore dire `no crontab`). [ ]
171. `crontab -e`, écrire `* * * * * echo tic`, sauver, Échap. Attendre deux
     minutes de jeu (l'horloge du jeu, pas la vraie), puis `mail` : on doit voir
     la ligne `From cron`, une ligne `Subject: Cron <admin@...> echo tic` et
     `tic`. Refaire `mail` → `No mail for admin`. Confirmer surtout qu'aucun
     `tic` n'est jamais apparu tout seul à l'écran entre-temps. [ ]
172. À l'étape 171, `sudo cat /var/log/cron` doit montrer une ligne par minute
     écoulée, de la forme `Jul  8 04:01 (admin) CMD (echo tic)`, et jamais plus
     d'une par minute. Puis `cat /var/log/cron` sans sudo → `permission denied`.
     Enfin `df` : le disque ne doit pas avoir bougé à cause du journal ni du
     courrier. [ ]
173. Toujours avec `* * * * * echo tic` installé : éteindre l'ordinateur
     (menu contextuel), attendre cinq minutes de jeu, rallumer. Le courrier ne
     doit PAS contenir cinq nouveaux `tic` : une minute que cron a dormie est
     une minute perdue, et rien n'est rattrapé. Noter aussi qu'une ligne
     `@reboot echo debout` installée avant l'extinction, elle, doit produire un
     courrier au rallumage. [ ]
174. Une ligne qui travaille le bâtiment : `crontab -e` avec
     `* * * * * echo on > /dev/light0` (prendre l'id d'une vraie lumière vu par
     `dev`), sauver, sortir de la fenêtre du terminal et s'éloigner de deux
     carrés en regardant l'ampoule. À la minute suivante la lumière doit
     s'allumer sans que personne n'ait tapé quoi que ce soit. [ ]
174a. **`at` : une fois, à l'heure dite.** Regarder l'heure (`date`), puis
     `echo 'echo la nuit tombe' | at HH:MM` avec la minute suivante →
     `job 1 at <la date complète>`. `atq` → `1  <la même date>`.
     `cat /var/spool/at/1` → `permission denied` (la file est à `root`),
     `sudo cat /var/spool/at/1` → la ligne d'en-tête `at admin <secondes>` puis
     la commande. Attendre la minute : **rien** n'apparaît à l'écran, `atq` ne
     montre plus rien, et `mail` livre `la nuit tombe`. [ ]
174b. **`at` n'oublie pas, contrairement à `cron`.** `echo halt | at HH:MM` avec
     une minute qui tombe dans deux minutes, puis **éteindre** l'ordinateur
     (Turn off) et attendre que l'heure passe. Rallumer, se connecter :
     à la minute suivante la machine s'éteint, le travail attendait dans la
     file. Refaire avec `crontab -e` et `* * * * *` pour comparer : une minute
     manquée par `cron` est perdue. [ ]
174c. **`atrm`, et les droits.** `echo halt | at 23:59`, `atq` (noter le
     numéro), `atrm <numéro>` → rien à l'écran, `atq` est vide, et l'heure
     passe sans rien faire. Puis `sudo useradd bob`, `su bob`,
     `echo x | at 23:58`, `exit` : en `admin`, `atq` ne montre pas le travail de
     `bob`, `atrm <son numéro>` → `atrm: N: Operation not permitted`, et en
     `root` `atq` montre les deux. [ ]
174d. **`mail` envoie, et pas seulement lit.** `sudo useradd bob`, puis
     `echo salut | mail -s Bonjour bob`. Rien à l'écran. `su bob`, `mail` → la
     ligne d'enveloppe `From admin  <date>`, puis `From: admin@<machine>`,
     `To: bob`, `Date: <la même>`, `Subject: Bonjour`, une ligne vide et
     `salut`. `exit`. En `admin`, `cat /var/mail/bob` → `permission denied` :
     la boîte reste à `bob` en `600` même si c'est `admin` qui a écrit
     dedans. [ ]
174e. **Le corps tapé à la main, et l'interruption.** `mail -s Note bob` sans
     rien avant le tuyau : l'invite devient vide (le curseur seul). Taper
     `ligne un`, Entrée, `ligne deux`, Entrée, puis `.` seul et Entrée → rien à
     l'écran, et `sudo cat /var/mail/bob` montre les deux lignes. Refaire,
     taper deux lignes, puis **Échap** : `^C`, l'invite revient, et
     `sudo cat /var/mail/bob` n'a rien de nouveau, un message interrompu est
     un message jamais parti. [ ]
174f. **Les refus, mot pour mot.** `echo x | mail fantome` →
     `fantome... User unknown`. `echo x | mail fantome bob` → le même refus, et
     `sudo cat /var/mail/bob` n'a rien de neuf : une seule mauvaise adresse
     refuse toute la ligne. `echo x | mail bob@gate` →
     `bob@gate... Cannot send mail: no mailer`, et `echo x | mail gate!bob`
     pareil. `mail bob` depuis un `crontab -e` avec `* * * * * mail bob` :
     attendre une minute, puis `sudo cat /var/mail/bob` montre un message au
     corps vide (personne devant l'écran, donc `Null message body`). [ ]
174g. **Le courrier sur le câble.** Deux machines nommées l'une l'autre dans
     `/etc/hosts` et un `/etc/hosts.equiv` sur la seconde (voir les étapes du
     chapitre réseau), un compte `bob` sur la seconde. Sur la première :
     `echo 'les lumières sont éteintes' > note`, puis
     `cat note | rsh gate mail -s Lumieres bob`. Rien à l'écran. Sur la
     seconde, en `bob` : `mail` montre le message, et `From:` porte le nom de
     la **seconde** machine, c'est là qu'il a été posté. Puis
     `rsh gate mail bob` tout seul → `Null message body; hope that's ok` à
     l'écran de la première, et un message au corps vide dans la boîte. [ ]
175. `sh watch.sh &`
 (n'importe quel script qui dort et écrit), puis `jobs`,
     puis `fg %1` : la ligne de commande doit se réafficher, l'invite doit
     devenir occupée, et Échap doit tuer le travail (`^C` puis `killed`).
     Vérifier ensuite que `fg` seul, sans travail en arrière-plan, répond
     `fg: no current job`. Et pendant que le travail de cron de l'étape 171
     tourne, `jobs` ne doit pas le lister alors que `ps` le montre. [ ]
176. Les drapeaux des outils de texte, sur le fichier `fruits` de l'étape 167
     (`poire`, `pomme`, `poire`, `figue`). Attendu, à la colonne près :
     `wc fruits` → `     4      4     23 fruits` ; `wc -l fruits` →
     `     4 fruits` ; `wc -cl fruits` → `     4     23 fruits` (toujours
     lignes puis octets, peu importe l'ordre demandé) ; `head -1 fruits` →
     `poire` ; `tail -2 fruits` → `poire` puis `figue`. Confirmer que le nom du
     fichier reste bien à droite des nombres et que la ligne ne dépasse pas
     l'écran. [ ]
177. Toujours sur `fruits` : `grep -c poire fruits` → `2` ; `grep -v poire
     fruits` → `pomme` puis `figue` ; `grep -c melon fruits` → `0` et rien
     d'autre (le zéro est une réponse, pas un silence) ; `sort -u fruits` →
     `figue`, `poire`, `pomme` sur trois lignes ; `cat fruits | sort -u | wc -l`
     → `     3`. Puis `wc -q fruits` → `wc: -q: unknown option` et `wc` tout
     seul → `wc: usage: wc [-clw] [file]...`. [ ]

## N. Le réseau (palier 6a)

Il faut **deux ordinateurs dans le même bâtiment de la carte** -- pas dans une
base construite : une base n'a pas de bâtiment, donc pas de fil, et c'est le
sujet de l'étape 189. Un bureau de Knox County en a souvent deux ; sinon, le mode
debug permet d'en placer un deuxième dans la même pièce. Les deux doivent avoir du
courant. Dans ce qui suit, `ici` est la machine devant laquelle on est assis et
`gate` l'autre -- remplacer par les vrais noms que `hostname` donne.

178. Allumer les deux ordinateurs, ouvrir le terminal du premier et regarder le
     BIOS : entre `Detecting drives ... hda 64K` et `Booting from hda ...` il doit
     y avoir une ligne `Ethernet: eth0 10.x.y.1`. Puis se connecter et taper
     `ifconfig` : `eth0` avec cette même adresse et un masque `0xffffff00`, et
     `lo0` avec `127.0.0.1` sous elle. Enfin `cat /etc/hosts` : deux lignes, la
     boucle locale et la machine elle-même, avec l'adresse que le BIOS a
     annoncée. [ ]
179. Ouvrir le terminal du **deuxième** ordinateur et faire la même chose. Les
     trois premiers nombres de l'adresse doivent être identiques à ceux du
     premier (même bâtiment) et le dernier doit être différent (`.2` au lieu de
     `.1`). Noter les deux adresses. [ ]
180. Revenir au premier. `ruptime` → une ligne par machine allumée du bâtiment,
     la sienne comprise, de la forme
     `gate      up  00:04,  1 user,  load 0.00`. Puis `rwho` → une ligne par
     personne connectée, `admin    gate:console  Jul  8 14:32`. Éteindre le
     deuxième ordinateur, refaire `ruptime` : il ne doit plus être listé du
     tout (pas de ligne `down`). Le rallumer. [ ]
181. Nommer l'autre machine : `sudo edit /etc/hosts`, ajouter une ligne
     `<adresse du deuxième> gate`, sauver. Puis `ping gate` : la ligne
     `PING gate (10.x.y.2): 56 data bytes`, trois réponses `64 bytes from ...
     icmp_seq=0/1/2 ttl=255 time=0.4 ms` espacées d'une seconde chacune (les
     compter : elles arrivent l'une après l'autre, pas d'un coup), une ligne
     vide, `--- gate ping statistics ---`,
     `3 packets transmitted, 3 packets received, 0% packet loss` et le
     `round-trip`. [ ]
182. `ping pump` (un nom qui n'est dans aucune ligne) → `ping: unknown host
     pump`, tout de suite et sans attendre. Éteindre le deuxième ordinateur,
     `ping gate` → aucune réponse pendant trois secondes puis
     `3 packets transmitted, 0 packets received, 100% packet loss`, sans ligne
     `round-trip`. Le rallumer. [ ]
183. `rlogin gate` → `login:` apparaît **sur cet écran**, l'invite devient celle
     de l'autre machine. Se connecter (`admin`, mot de passe vide) : le motd de
     l'autre machine, puis une invite `admin@gate:~$`. Taper `hostname` → le nom
     de l'autre machine. Taper `pwd`, `ls /`, `dev` : tout doit parler de
     l'autre machine, et `dev` doit lister SES périphériques. [ ]
184. Toujours dans la session : `who` → deux lignes s'il y a quelqu'un au clavier
     de `gate`, et la ligne de la session doit être `ttyp0` avec `(ici)` entre
     parenthèses au bout. Puis `last` → la même session, `still logged in`.
     Enfin `exit` → `Connection closed.` et l'invite locale revient, avec tout ce
     qui s'est passé encore visible au-dessus. [ ]
185. Vérifier les deux historiques : sur la machine locale, `history` contient
     `rlogin gate` et **pas** `hostname` ni `pwd`. Refaire `rlogin gate`, se
     connecter, et `history` là-bas contient `hostname` et `pwd`. [ ]
186. La confiance. Dans la session sur `gate` : `edit .rhosts`, écrire
     `<nom de la machine locale> admin`, sauver, puis `chmod 600 .rhosts` et
     `exit`. Refaire `rlogin gate` → **aucun mot de passe demandé**, l'invite
     `admin@gate:~$` arrive directement. Puis `chmod 666 .rhosts` et ressortir :
     le `rlogin` suivant redemande `login:` sans dire pourquoi. Remettre 600. [ ]
183b. Le deuxième champ nomme le compte **qui arrive**, pas celui qu'on devient.
     Dans la session sur `gate` : `sudo useradd bob`, puis
     `sudo edit /home/bob/.rhosts` avec `<nom de la machine locale> admin`,
     `sudo chown bob /home/bob/.rhosts`, `sudo chmod 600 /home/bob/.rhosts`,
     `exit`. Puis `rlogin gate -l bob` → aucun mot de passe, et `whoami` là-bas
     répond `bob`. [ ]
187. `rsh gate hostname` depuis l'invite locale → le nom de l'autre machine
     s'affiche et l'invite locale revient, sans `Connection closed.`. Puis
     retirer la confiance (`rlogin gate`, `rm .rhosts`, `exit`) et refaire
     `rsh gate hostname` → `rsh: gate: Permission denied`, sans aucune question.
     Remettre le `.rhosts`. [ ]
187b. **`rsh` attend et revient.** `rsh gate hostname | wc -l` → `1` (la ligne
     est entrée dans le tuyau, pas sur la glace). `x=$(rsh gate hostname); echo
     [$x]` → `[<nom de gate>]`. `rsh gate hostname > venu.txt` puis
     `cat venu.txt` → le nom. Un script `echo avant`, `rsh gate dev light0`,
     `echo "apres $?"` → les trois lignes, dans cet ordre, `apres 0`. Et
     `rsh gate false; echo $?` → `1` : le `$?` est celui de la commande de
     l'autre machine. [ ]
187c. Une commande distante qui ne finit jamais :
     `rsh gate "while true; do x=1; done" &` puis `jobs` → `[1] remote`, et `ps`
     sur **gate** (depuis un `rlogin` dans une autre fenêtre) montre la boucle
     là-bas. `kill %1` ici → le travail part et la session sur `gate` se ferme
     avec lui (`who` sur `gate` n'a plus de `ttyp`). Même chose en coupant le
     courant de la pièce pendant l'attente. [ ]
188. `echo bonjour > notes.txt` puis
     `rcp notes.txt gate:/home/admin/venu.txt` → la commande prend une seconde
     ou deux et ne dit rien du tout. Vérifier avec `rsh gate cat
     /home/admin/venu.txt` → `bonjour`. Puis dans l'autre sens :
     `rcp gate:/home/admin/venu.txt retour.txt` et `cat retour.txt`. Enfin
     `rcp notes.txt gate:/etc/passwd` → `permission denied` (les droits sont ceux
     de l'autre machine, pas d'un privilège). [ ]
189. Les limites. `rlogin ici` (soi-même par son propre nom, ou `localhost`)
     fonctionne et ouvre une deuxième session sur la même machine : `who` doit
     alors montrer la console et un `ttyp`. Depuis cette session, `rlogin gate`
     fonctionne encore (deux sauts), et depuis celle-là un troisième `rlogin`
     répond `rlogin: connect: Connection refused`. Ressortir avec `exit` jusqu'à
     l'invite locale. [ ]
190. Échap. Dans une session `rlogin gate` à l'invite : appuyer sur Échap →
     `Connection closed.` et l'invite locale, **la fenêtre ne se ferme pas**.
     Refaire `rlogin gate`, lancer `while true; do echo x; done` et appuyer sur
     Échap → `^C` et `killed`, la session reste ouverte. Un deuxième Échap ferme
     alors la session, et un troisième ferme la fenêtre. [ ]
191. Ce qui coupe une session. `rlogin gate`, puis : (a) `sudo halt` dans la
     session → l'autre machine s'éteint et l'écran revient à l'invite locale avec
     `Connection closed.` ; rallumer, refaire, puis (b) faire éteindre l'autre
     ordinateur par le menu contextuel pendant la session ; puis (c) ramasser
     l'autre ordinateur ; puis (d) couper le courant de la pièce. Chacune des
     quatre doit rendre l'invite locale et jamais laisser la fenêtre coincée sur
     un écran mort. [ ]
192. Une machine dans une **base construite** (aucun bâtiment de la carte) :
     `ifconfig` doit montrer `eth0: flags=2<BROADCAST>` sans ligne `inet`, le
     BIOS ne doit annoncer aucune ligne `Ethernet:`, `ruptime` ne doit rien
     lister, et `rlogin` sur n'importe quel nom doit répondre
     `No route to host`. Même chose depuis un ordinateur d'un AUTRE bâtiment de
     la carte vers celui de ce parcours : `No route to host`. [ ]

## O. PATH, liens, `/dev/null` et `/var/tmp` (palier 6b)

193. `PATH`. À l'invite : `echo $PATH` → `/bin:/usr/local/bin`, et
     `ls /usr/local/bin` → vide. Puis `echo $HOME` →
     `/home/admin`. `type ls` → `ls is /bin/ls`, `type cd` →
     `cd is a shell builtin`, `type if` → `if is a shell keyword`,
     `which ls` → `/bin/ls`, et `which frobnicate` → **aucune ligne** (et rien
     d'autre non plus). [ ]
194. Une commande à soi. `mkdir bin`, `edit bin/hello` avec une seule ligne
     `echo salut`, sauver, `chmod 755 bin/hello`. Puis `hello` →
     `hello: command not found`. Ensuite `PATH=$PATH:$HOME/bin` → `echo $PATH`
     dit `/bin:/usr/local/bin:/home/admin/bin`, et `hello` →
     `salut`. `which hello` → `/home/admin/bin/hello`. Enfin mettre la même
     ligne `PATH=$PATH:$HOME/bin` dans `edit .profile`, `exit`, se reconnecter,
     et `hello` doit marcher dès la première invite. [ ]
195. Le piège de cron. Toujours avec `~/bin` dans le `PATH` de l'invite :
     `crontab -e` et écrire `* * * * * hello`, sauver. Attendre une minute (une
     minute de jeu ; accélérer le temps aide), puis `mail` → le courrier dit
     `hello: command not found`. Remplacer la ligne par
     `* * * * * /home/admin/bin/hello` → le courrier suivant dit `salut`.
     Terminer par `crontab -r`. [ ]
196. Les liens. `echo bonjour > notes.txt`, `ln -s notes.txt lien`, puis
     `cat lien` → `bonjour` ; `ls -l` → une ligne
     `lrwxrwxrwx  admin  admin   lien -> notes.txt` ; `ls -F` → `lien@` ;
     La flèche de `ls -l` est **la** façon de voir la cible : il n'y a pas de
     `readlink` sur cette machine (`readlink lien` →
     `readlink: command not found`). Puis `rm lien` → `notes.txt` est toujours
     là (`cat notes.txt`). Refaire le lien, `mv lien deplace`,
     `ls -l deplace` → la flèche pointe toujours sur `notes.txt`. `ln -s rien casse` puis
     `cat casse` → `casse: no such file`, mais `ls -l casse` montre encore la
     flèche. `ln -s a b` et `ln -s b a` puis `cat a` →
     `too many levels of symbolic links`. Enfin `ln notes.txt dur` (sans `-s`)
     → la ligne d'usage `ln: usage: ln -s <target> <name>`, et `ls dur` →
     `ls: dur: no such file` : rien n'a été créé. [ ]
196a. **Et la page des écarts le dit.** Volume 1, chapitre 1, la page
     **One command is narrower here than you remember it: ln** → elle explique
     qu'un vrai `ln` sans drapeau faisait un lien DUR, pourquoi cette machine
     n'en a pas (l'ordinateur se transporte, le disque est recopié nom par nom),
     et elle imprime mot pour mot la réponse de l'étape 196. [ ]
196b. **`find -exec`, les deux formes.** Dans le home : `mkdir tas`,
     `echo un > tas/a.log`, `echo deux > tas/b.log`, `echo trois > tas/c.txt`.
     Puis `find tas -name '*.log' -exec cat {} \;` → `un` puis `deux`, et
     **aucun** chemin affiché (nommer une action retire l'affichage). Ajouter
     `-print` : `find tas -name '*.log' -print -exec cat {} \;` → le chemin
     puis le contenu, deux fois. La forme groupée :
     `find tas -name '*.log' -exec cat {} +` → même résultat en une seule
     commande. Oublier le backslash (`-exec cat {} ;`) → la ligne d'usage
     `find: usage: find <path>... [expression]`. Un mot du shell n'est pas un
     programme : `find tas -exec cd {} \;` → `cd: command not found`. Enfin
     `find tas -name '*.log' -exec rm {} \;` puis `find tas` → il ne reste que
     `tas` et `tas/c.txt`. [ ]
196c. **Un balayage qui prend du temps le prend proprement.** `mkdir gros`, puis
     une trentaine de fichiers (`edit` ou une boucle
     `i=0; while [ $i -lt 30 ]; do echo x > gros/f$i.log; i=$((i+1)); done`).
     `find gros -name '*.log' -exec chmod 644 {} \;` → les lignes arrivent au
     fil des passes, l'invite ne revient qu'à la fin, et **pendant** ce temps
     marcher et ouvrir une porte : le jeu ne saccade pas. Refaire avec `+` → la
     même chose en un instant. [ ]
197. `/dev/null`. `cat /dev/null` → **rien du tout** (pas même une ligne vide).
     `echo bruit > /dev/null` → rien, et `cat /dev/null` toujours rien.
     `df` avant et après doit donner exactement les mêmes nombres.
     `ls -l /dev` → une ligne `crw-rw-rw-  root  root  null` parmi les
     appareils, et `dev` (la commande) ne la montre pas. `rm /dev/null` →
     `rm: /dev/null: is a device`. [ ]
198. `/var/tmp` et `ls` dans un tube. `ls -l /var` → `tmp` est en
     `drwxrwxrwx`. `echo a moi > /var/tmp/mien.txt`, puis
     `sudo useradd bob`, `su bob` (mot de passe vide : Entrée), et depuis bob :
     `rm /var/tmp/mien.txt` → `permission denied`, alors que
     `echo a bob > /var/tmp/bob.txt` marche et que `rm /var/tmp/bob.txt` marche
     aussi. `exit` pour revenir. Ensuite, avec des lumières dans le bâtiment :
     `ls /dev` à l'écran affiche des colonnes, tandis que
     `for l in $(ls /dev | grep light); do dev $l off; done` doit éteindre
     chaque lumière et ne rien dire d'autre (aucun `invalid value`). [ ]

## R. La disquette (palier 4e)

Il faut une disquette : elle se trouve dans les bureaux, les cybercafés, les
magasins d'électronique et les caisses d'informatique, ou, en mode debug, par le
menu d'apparition d'objets, sous `CeroSec.FloppyBlue`, `FloppyYellow`,
`FloppyRed` ou `FloppyGreen`. Les quatre sont la même disquette dans quatre
coques.

199. **L'objet et la fente.** Prendre une disquette dans l'inventaire, clic droit
     sur l'ordinateur → l'entrée **Insert floppy** est là. Sans disquette sur
     soi et avec une fente vide, ni Insert ni Eject n'apparaissent. Cliquer
     Insert → le personnage marche devant la machine, se tourne, joue
     l'animation de fouille, et on entend le lecteur prendre la disquette. La
     disquette a quitté l'inventaire ; le menu offre maintenant **Eject
     floppy**. Avec une deuxième disquette sur soi, **Insert floppy** est grisé
     et l'infobulle dit *Eject the floppy first.* [ ]
199b. **Le menu après l'éjection.** Disquette dans la fente, cliquer **Eject
     floppy** → la disquette revient dans l'inventaire. **Refermer le menu et
     rouvrir le clic droit** : **Insert floppy** est là et n'est PAS grisé, pas
     d'infobulle *Eject the floppy first*, et **Eject floppy** a disparu. C'est
     la copie du client qui est en cause et non la machine : le menu montrait la
     fente encore pleine alors que la disquette était dans les mains du
     survivant. [ ]
199c. **Plusieurs disquettes : le sous-menu.** Se faire apparaître UNE disquette de
     chaque couleur (`FloppyBlue`, `FloppyYellow`, `FloppyRed`, `FloppyGreen`),
     fente vide, clic droit sur l'ordinateur → **Insert floppy** est maintenant un
     SOUS-MENU de quatre lignes, dans l'ordre bleu, jaune, rouge, vert, chacune
     lisant `3.5" Floppy Disk (bleue)` etc. L'entrée parente elle-même n'insère
     rien quand on passe dessus. Cliquer la ligne **verte** → c'est la disquette
     VERTE qui quitte l'inventaire, pas la bleue : c'est tout le point de ce
     sous-menu. L'éjecter. Garder ensuite DEUX disquettes bleues sur soi → deux
     lignes quand même, et non une. Avec une seule disquette sur soi → pas de
     sous-menu du tout, l'entrée directe d'avant. [ ]
199d. **Le sous-menu quand c'est refusé.** Trois disquettes sur soi et une dans la
     fente → **Insert floppy** est UNE seule ligne grisée avec l'infobulle *Eject
     the floppy first*, et AUCUN sous-menu : il n'y a rien à choisir. Pareil hors
     de portée (derrière un comptoir) : une ligne grisée avec
     *Tooltip_CeroSec_NoAccess*. [ ]
199e. **Écrire sur l'étiquette.** Sans rien pour écrire sur soi, clic droit sur une
     disquette dans l'inventaire → **aucune** entrée d'étiquette. Prendre un stylo
     (`Base.Pen`) ou un crayon, reclic droit → **Étiqueter la disquette**. Cliquer
     → une boîte de texte vide s'ouvre. Taper `PAYROLL 93`, OK → le nom de la
     disquette dans l'inventaire devient **PAYROLL 93**. Reclic droit → deux
     entrées maintenant : **Changer l'étiquette** (la boîte s'ouvre déjà remplie)
     et **Effacer l'étiquette**. Essayer une étiquette de plus de 24 caractères,
     puis une avec un `/` ou un `_` → refusée, un message rouge le dit, et le nom
     ne change pas. Annuler la boîte → rien ne change. **Effacer l'étiquette** →
     le nom revient à `3.5" Floppy Disk`. Poser le stylo par terre → les entrées
     disparaissent du menu. [ ]
199e-bis. **Imprimée ou écrite à la main.** Se faire apparaître des disquettes de
     butin jusqu'à en trouver deux écrites (la plupart sont vierges : c'est
     voulu). Attendu, dans le sac, SANS rien lire : une disquette de logiciel
     porte un nom de produit avec sa version -- `CeroSec UTILITIES 1.0`,
     `SHAREWARE GAMES 2.1`, `NIGHTLINE DIALER 1.2`, `CeroSec OS 1.0 DIST` --,
     son étiquette dessinée est blanche avec deux lignes d'impression dessus, et
     l'infobulle dit **Printed label**. Une disquette de quelqu'un porte SES mots
     en minuscules -- `books 93`, `do not read`, `home dir 8 july`,
     `club net log` --, garde l'étiquette nue, et l'infobulle dit
     **Handwritten label**. Une disquette vierge ne dit ni l'un ni l'autre et
     s'appelle `3.5" Floppy Disk`. Deux disquettes du même genre trouvées dans
     deux villes ne portent pas forcément les mêmes mots : chaque récit a son
     écriture. Insérer une disquette imprimée : le sous-menu la nomme par son
     produit, et `mount` écrit exactement la même ligne entre parenthèses. [ ]
199e-ter. **Le stylo ne peut pas imprimer.** Prendre la disquette imprimée de
     l'étape précédente, stylo en main, **Changer l'étiquette** → taper
     `mes affaires`. Attendu : le nom change, l'étiquette imprimée disparaît de
     l'icône (elle redevient nue) et l'infobulle passe à **Handwritten label**.
     Recommencer en retapant exactement `CeroSec UTILITIES 1.0` : c'est toujours
     écrit à la main -- l'icône reste nue et l'infobulle ne change pas. Puis
     **Effacer l'étiquette** → le nom revient à `3.5" Floppy Disk` et
     l'infobulle ne dit plus rien du tout. [ ]
199f. **L'étiquette, la machine et l'aller-retour.** Étiqueter une disquette
     `PAYROLL 93`, l'insérer : le sous-menu la nommait bien `PAYROLL 93 (verte)`.
     `newfs /dev/fd0`, `mount /dev/fd0 /mnt`, puis `mount` sans rien → la ligne de
     la disquette est `/dev/fd0 on /mnt type ufs (rw) (PAYROLL 93)`, et celle de
     `hda` n'a RIEN entre parenthèses au bout. `df` → la ligne `fd0` porte
     `(PAYROLL 93)` au bout, la ligne `fd0 nodes` ne le répète pas, et les colonnes
     de chiffres n'ont pas bougé. `umount /mnt`, éjecter → la disquette revient
     dans l'inventaire **en portant toujours le nom PAYROLL 93** (c'est un nouvel
     objet : sans report explicite l'écriture serait perdue). La réinsérer →
     `mount` la renomme pareil. Avec une disquette NON étiquetée : la ligne `mount`
     est nue, sans parenthèses vides, et ne dit jamais `3.5" Floppy Disk`. [ ]
200. **Le lecteur, éteint.** Éteindre l'ordinateur (Turn off), puis clic droit :
     Insert et Eject sont toujours proposés, une fente est mécanique.
     Éjecter la disquette machine éteinte, la reprendre, la remettre, rallumer.
     [ ]
201. **`/dev/fd0`.** Machine allumée, disquette dedans, se connecter et taper
     `ls /dev` → `fd0` apparaît à côté de `null`. `ls -l /dev` → une ligne
     `crw-rw----  root  sudo  fd0` avec, tout à droite, `blank` pour une
     disquette neuve. `cat /dev/fd0` → `blank`. `echo on > /dev/fd0` →
     `fd0: invalid value`. `rm /dev/fd0` → `rm: /dev/fd0: is a device`. Éjecter
     la disquette puis `ls /dev` → `fd0` a disparu, et `newfs /dev/fd0` →
     `newfs: /dev/fd0: no such file`. [ ]
202. **`newfs` et `mount`.** Disquette remise. `mount /dev/fd0 /mnt` →
     `mount: /dev/fd0 on /mnt: Incorrect super block` (elle est vierge).
     `newfs /dev/fd0` → `/dev/fd0: 4096 bytes, 32 inodes`, et `cat /dev/fd0` →
     `ready`. `mount /dev/fd0 /mnt` → rien du tout (c'est la réussite).
     `mount` sans rien → deux lignes : `/dev/hda on / type ufs (rw)` et
     `/dev/fd0 on /mnt type ufs (rw)`. `cat /dev/fd0` → `mounted`. [ ]
203. **La greffe.** `echo les pompes sont au dépôt > /mnt/notes.txt`,
     `cat /mnt/notes.txt`, `ls /mnt`, `mkdir /mnt/sous`,
     `cp /mnt/notes.txt /mnt/sous/copie.txt`, `cd /mnt` puis `pwd` → `/mnt`, et
     `edit /mnt/notes.txt` s'ouvre et enregistre. Tout marche sans qu'aucune
     commande n'ait à savoir qu'il y a une disquette. `df` → quatre lignes :
     `hda`, `nodes`, `fd0` (taille 4096) et `fd0 nodes` (32). Écrire sur la
     disquette ne fait pas bouger la ligne `hda`. [ ]
204. **Les plafonds sont ceux de la disquette.** Dans l'éditeur, remplir un
     fichier de `/mnt` jusqu'à ce qu'il soit gros (ou répéter
     `echo ... >> /mnt/gros.txt`) jusqu'à `disk full`, puis vérifier que
     `echo ok > /home/admin/ok.txt` passe toujours : la machine, elle, n'est pas
     pleine. `mv /home/admin/ok.txt /mnt` → `mv: /mnt/ok.txt: cross-device
     link` ; `cp` puis `rm` marchent. [ ]
205. **Le point de montage n'est pas un nom à effacer.** Disquette montée sur
     `/mnt` : `sudo rm -r /mnt` → `rm: /mnt: Device busy`, et
     `sudo mv /mnt /ailleurs` → `mv: /ailleurs: Device busy`. Après `umount`,
     les deux passent (remettre `/mnt` avec `sudo mkdir /mnt` ensuite, ou
     rallumer la machine : le micrologiciel le repose). [ ]
206. **`umount`, et qui est dedans.** `cd /mnt` puis `umount /mnt` →
     `umount: /mnt: Device busy`. `cd` (retour maison) puis `umount /mnt` → rien,
     et `ls /mnt` est vide. `umount /mnt` une seconde fois →
     `umount: /mnt: not mounted`. Remonter, puis `newfs /dev/fd0` →
     `newfs: /dev/fd0: Device busy`. [ ]
207. **La disquette traverse la ville.** Disquette montée avec le fichier
     dessus : l'éjecter par le menu **sans démonter** → le lecteur rend la
     disquette, de la même couleur que celle qui est entrée, et `mount` ne liste
     plus que `hda`. Porter la disquette jusqu'à un **autre** ordinateur,
     l'insérer, `cat /dev/fd0` → `ready` (pas `blank`), `mount /dev/fd0 /mnt`,
     `cat /mnt/notes.txt` → la note est là, entière. Vérifier aussi les droits :
     un fichier écrit par `bob` là-bas est encore à `bob` (`ls -l /mnt`), et
     `root` le lit partout. [ ]
207a. **Le home entier sur la disquette : `tar`.** Disquette montée sur `/mnt`.
     Dans le home : `mkdir travail`, `echo un > travail/a.txt`,
     `echo deux > notes.txt`, `chmod 600 notes.txt`. Puis
     `tar cvf /mnt/home.tar /home/admin` → chaque nom s'affiche au fil des
     passes (une ligne à la fois, pas d'un bloc), et `ls -l /mnt` montre
     `home.tar` avec sa taille. `tar tvf /mnt/home.tar` → une ligne par membre
     avec le mode, le propriétaire, la taille et le chemin. Ensuite
     `rm -r travail`, `rm notes.txt`, `tar xvf /mnt/home.tar` → tout revient,
     `cat notes.txt` → `deux`, et `ls -l notes.txt` → le mode `600` est revenu
     aussi. Enfin `df` avant et après un `tar cf` : l'archive **compte** sur le
     disque, et un home trop gros répond `tar: /mnt/home.tar: file too large`.
     Pendant un `tar` d'un gros home, marcher et ouvrir une porte : le jeu ne
     saccade pas. [ ]
208. **Reprendre la machine avec la disquette dedans.**
 Disquette insérée et
     montée, ramasser l'ordinateur (clic droit → Pick up / prendre le meuble),
     le reposer ailleurs, le rallumer et se connecter : `ls /dev` → `fd0` est
     toujours là, rien n'est monté (`mount` ne liste que `hda`), et un seul
     `mount /dev/fd0 /mnt` retrouve les fichiers. [ ]
209. **Les droits sur le lecteur.** `sudo useradd bob`, `su bob`, puis
     `newfs /dev/fd0` → `newfs: /dev/fd0: permission denied`, pareil pour
     `mount` et `cat /dev/fd0`. `exit`, puis `sudo chmod 666 /dev/fd0` et
     redevenir `bob` : `mount /dev/fd0 /mnt` passe. Le mode reste au **lecteur** :
     éjecter, remettre une autre disquette, `ls -l /dev` montre toujours
     `crw-rw-rw-`. [ ]

## S. Le téléphone (palier 6b)

Il faut **deux ordinateurs dans deux bâtiments différents de la carte**, aussi
loin l'un de l'autre qu'on veut : c'est le contraire de la section N, où tout se
passait dans un seul bâtiment. Les deux doivent avoir du courant. Dans ce qui
suit, `ici` est la machine devant laquelle on est assis et `là-bas` celle de
l'autre bâtiment ; noter les deux numéros de téléphone au premier BIOS.

Depuis ce changement, la ligne appartient au **local** (« premises ») et non au
bâtiment : une maison est un local, un centre commercial en est une douzaine. Les
pas 215b et 215c sont là pour ça, et ils demandent un mall (le mall de Louisville ou
celui de West Point) avec deux boutiques différentes.

Et depuis **premises v2**, une boutique est un local même quand la carte n'a dessiné
**aucune zone** autour d'elle : c'est le cas de tous les malls livrés, et c'est ce
que les pas 215j à 215n vérifient. Le mall à retenir pour ça est celui de
**12809,1294** : un dentiste, une pharmacie, un café, une librairie, deux magasins de
vêtements et trois étages de bureaux au-dessus. Le magasin de musique
(`musicstore`) est dans les malls de **13515,1261**, **13868,5745** et
**12165,1563**.

210. **Le numéro.** Allumer les deux et regarder le BIOS de chacun : sous la
     ligne `Ethernet: eth0 10.x.y.z` il doit y avoir une ligne
     `Phone line: NNN-NNNN`, **sept** chiffres, et le premier des trois premiers
     n'est jamais 0 ni 1. Les deux machines d'un **même** local (celles de la
     section N, dans une maison) doivent afficher le **même** numéro ; celle de
     l'autre bâtiment un numéro différent. Si les deux bâtiments sont dans la même
     région de la carte (moins de 1024 tuiles d'écart), les **trois premiers**
     chiffres doivent être les mêmes des deux côtés : c'est le central de la
     ville. Vérifier ensuite qu'il n'est écrit nulle part sur le disque :
     `cat /etc/phone` → `no such file`, et `ifconfig` ne le montre pas (ce n'est
     pas une interface tant qu'on n'a pas appelé). Éteindre et rallumer : le même
     numéro revient. [ ]
211. **L'appel, et la sonnerie.** Depuis `ici` : `cu 555-NNNN` (le numéro de
     `là-bas`). **Rien ne s'affiche pendant environ quatre secondes**, c'est le
     modem qui compose et le poste d'en face qui sonne ; compter, ça doit se
     sentir, puis `CONNECT 2400`, puis `Connected.`, puis le `login:` de l'autre
     machine.
     S'y connecter (`admin`, Entrée) : l'invite devient `admin@<là-bas>`,
     `hostname` répond le nom de l'autre machine et `pwd` son `/home/admin`.
     Vérifier que le mot de passe est demandé **même** si `/etc/hosts.equiv` de
     `là-bas` contient le nom de `ici` (l'écrire, refaire l'appel : il demande
     quand même). Puis là-bas : `who` → une ligne `ttyp0` avec `(555-MMMM)`, le
     numéro de `ici`, et `last` → la même chose. Ressortir avec `exit` →
     `Disconnected.` (et **pas** `Connection closed.`). [ ]
212. **`~.` et la lenteur.** Rappeler, se connecter, puis taper `~.` seul sur la
     ligne → `Disconnected.` et l'écran revient à l'invite locale. Vérifier que
     ce n'était une commande nulle part : là-bas (par un nouvel appel)
     `grep '~' /home/admin/.sh_history` ne doit rien trouver, et ici non plus.
     Rappeler et lancer `cat /etc/hosts` puis `ls /bin` là-bas : les lignes
     doivent arriver **par petits paquets** (quatre par seconde), visiblement
     plus lentement que la même commande tapée sur sa propre machine. Rien ne
     doit manquer à la fin. [ ]
213. **Une ligne par local.** Pendant un appel ouvert entre `ici` et `là-bas`,
     aller à la **deuxième** machine du local de `ici` (celle de la section N) et
     taper `cu 555-NNNN` → `BUSY` après environ **deux** secondes (la tonalité
     d'occupation est plus courte que la sonnerie). Depuis cette même machine,
     appeler le numéro de son **propre** local → `BUSY` aussi. Raccrocher (`~.`),
     puis depuis `ici` appeler le numéro de sa propre machine → `BUSY` (une ligne
     qu'on utilise soi-même). Enfin, éteindre toutes les machines de `là-bas` et
     appeler son numéro : **rien pendant quinze secondes**, puis `NO CARRIER`,
     c'est le registre S7 du modem, chronométrer. Même chose pour un numéro que
     personne n'a. [ ]
213b. **Les deux bouts sont occupés pendant que ça sonne.** Éteindre `là-bas`,
     puis depuis `ici` appeler son numéro : pendant les quinze secondes de
     sonnerie, aller à la deuxième machine du local de `ici` et appeler le numéro
     de `ici` → `BUSY`. Revenir et attendre le `NO CARRIER`. [ ]
213c. **Échap raccroche.** Relancer le même appel vers une machine éteinte et
     appuyer sur Échap au bout de deux ou trois secondes : la ligne doit dire
     `NO CARRIER` tout de suite et l'invite locale revenir. Refaire `cu` vers un
     numéro qui répond juste après : l'appel doit passer (la ligne a bien été
     rendue). [ ]
214. **Le central est sur le réseau électrique.** Régler le bac à sable pour que
     le courant soit déjà coupé (`ElecShutModifier` à 0 jour), donner du courant
     aux deux ordinateurs par générateur, puis `cu 555-NNNN` → `NO DIALTONE` :
     les deux machines tournent, le central non. Sur une partie où le courant
     tient encore, ouvrir un appel et faire couper le réseau (ou avancer jusqu'au
     jour de la coupure) : à la première touche tapée, l'appel doit tomber avec
     `NO CARRIER` et rendre l'invite locale. Vérifier aussi qu'un appel ouvert
     meurt de la même façon quand on éteint la machine d'en face, quand on la
     ramasse, ou quand on coupe le courant de sa pièce. [ ]
215. **Ce qui ne téléphone pas.** Depuis `ici`, avec le nom de `là-bas` écrit
     dans `/etc/hosts` : `rsh <nom> hostname` et `rcp notes.txt <nom>:/tmp/n` →
     `No route to host` dans les deux cas (ce sont des commandes de réseau, pas
     le téléphone), et `ping <nom>` → 100 % de perte. Puis `crontab -e` avec
     `* * * * * cu 555-NNNN`, attendre une minute : `mail` doit dire
     `cu: not a terminal` et **aucune** session ne doit s'être ouverte là-bas
     (`who` là-bas ne montre que la console). Finir par `crontab -r`. Enfin, sur
     une machine d'une base construite (aucun bâtiment) : `cu 555-NNNN` →
     `cu: no phone line`, et son BIOS n'affiche aucune ligne `Phone line:`. [ ]
215b. **Une boutique de mall est un local.** Dans un centre commercial, poser un
     ordinateur dans **une** boutique et un autre dans une **autre** boutique du
     même bâtiment, les allumer, et comparer les BIOS : deux numéros de téléphone
     **différents**, deux adresses `10.x.y.z` dont les deux octets du milieu
     diffèrent, et sur chacun une ligne `Phone line: NNN-NNNN (NomDeLaZone)`, le
     nom de la boutique entre parenthèses. Depuis l'une, écrire l'adresse de
     l'autre dans `/etc/hosts` puis `ping <nom>` → 100 % de perte et
     `rlogin <nom>` → `No route to host` : ce n'est pas le même câble. Puis
     `cu` vers son numéro → l'appel passe. Poser un troisième ordinateur dans le
     **couloir** du mall (hors de toute boutique) : troisième numéro, troisième
     segment, et **aucun** nom entre parenthèses. Enfin, sur cette machine du
     couloir, `dev | wc -l` : le mall entier est **un** bâtiment pour `/dev`, donc
     la liste peut passer 96 entrées (le plafond est 256) et elle doit tenir
     jusqu'au bout, `dev light`, `dev door`, `dev win` kind par kind pour la
     lire. [ ]
215c. **Une maison reste un seul local.** Dans une maison ordinaire (pas un mall),
     poser deux ordinateurs dans deux pièces différentes, les allumer : **même**
     numéro de téléphone, **même** segment, et aucun nom entre parenthèses, les
     zones nommées qui couvrent une maison sont plus grandes qu'elle, donc elles
     ne comptent pas. Vérifier au passage qu'un appel vers ce numéro sonne sur la
     machine à l'adresse la plus basse (`who` là-bas), et que pendant ce temps
     l'autre machine de la maison ne peut pas appeler (`BUSY`). [ ]
215d. **Une sauvegarde d'avant ce changement.** Sur un monde créé avec une version
     précédente du mod, où un ordinateur avait déjà été allumé : le rallumer. Le
     BIOS doit afficher l'adresse `Ethernet:` comme avant **et** une ligne
     `Phone line:` (le central est calculé au moment où la machine revoit son
     carré). Une machine dont on regarde l'écran sans l'allumer doit aussi
     l'obtenir dès qu'on ouvre la fenêtre dessus. [ ]
215e. **L'annuaire : le trouver et le lire.** Ramasser un `Phonebook` (table
     d'entrée, comptoir de magasin, tiroir de bureau, l'objet vanilla) et faire
     un clic droit dessus dans le sac : **Chercher un numéro** est la première
     entrée du menu, au-dessus de l'option vanilla **Lire** (qui doit toujours
     être là). Cliquer : une fenêtre de
     livre s'ouvre, comme le manuel, titrée `Knox County Telephone Directory`.
     Le premier feuillet est la page de titre, le deuxième la table des matières
     avec une seule ligne `Exchange NNN`, et ensuite la préface (deux lignes) puis
     les inscriptions, une par ligne, `Nom ..... NNN-NNNN`, en police fixe et
     alignées. Vérifier **au passage** que le nom de l'objet dans le sac a changé
     et porte le central : `Phonebook (central NNN)`. Les flèches gauche/droite
     tournent les feuillets, Échap ferme. Rouvrir : il s'ouvre à la page où on
     l'a laissé. [ ]
215f. **Un annuaire = un central, et il ne bouge pas.** Noter les trois chiffres
     du central du livre et les comparer avec les trois premiers du
     `Phone line:` d'un ordinateur du même coin de la carte : **les mêmes**.
     Puis partir à plus de 1024 tuiles (une autre ville) avec ce même livre et
     rouvrir : **même** central, **mêmes** inscriptions, et le nom de l'objet n'a
     pas changé une deuxième fois, c'est l'annuaire de là où on l'a trouvé.
     Ramasser un **deuxième** `Phonebook` sur place et l'ouvrir : central
     **différent**, inscriptions différentes. [ ]
215g. **Un numéro de l'annuaire sonne vraiment.** Dans une boutique nommée par la
     carte (une boutique de mall, un restaurant), poser un ordinateur, l'allumer
     et lire son `Phone line: NNN-NNNN (NomDeLaZone)`. Rouvrir l'annuaire de
     cette région : la boutique doit y être, sous son nom **séparé en mots**
     (`CoffeeShop` → `Coffee Shop`), avec **exactement** ce numéro. Depuis un
     autre ordinateur d'un autre local : `cu <ce numéro>` → environ quatre
     secondes, puis `CONNECT 2400` et le `login:` d'en face. Puis éteindre
     l'ordinateur de la boutique et rappeler le **même** numéro de l'annuaire :
     **rien pendant quinze secondes**, puis `NO CARRIER` (chronométrer). Faire de
     même sur une inscription derrière laquelle personne n'a jamais rien posé :
     `NO CARRIER` après quinze secondes aussi, l'inscription est bonne, le local
     est vide. [ ]
215h. **Ce qui n'est pas dedans.** Dans une **maison** ordinaire, poser un
     ordinateur, l'allumer, noter son numéro : il n'est **nulle part** dans
     l'annuaire de la région (aucune ligne ne porte ces sept chiffres), les
     pages blanches demanderaient un nom de famille que la carte ne donne pas.
     Parcourir ensuite tout l'annuaire feuillet par feuillet : **aucune**
     coordonnée de carte n'y apparaît, et aucun nom de zone de région (`Farm`,
     `StreetPoor`, `University`), seulement des commerces. Si la dernière ligne
     du dernier feuillet dit que l'annuaire est plein, c'est le plafond de 400 :
     le noter dans le rapport. [ ]
215i. **Multijoueur.** Deux joueurs, chacun son `Phonebook`, ouverts en même
     temps dans deux régions différentes : chacun voit **son** central et ses
     propres inscriptions, et la fenêtre de l'un ne change pas quand l'autre
     ouvre la sienne. [ ]
215j. **Le dentiste et le magasin de musique (premises v2).** C'est le pas qui
     répond au rapport de jeu, « ils partagent tous la même chose peu importe le
     commerce ». Aller dans le mall de **12809,1294** (ou n'importe quel mall).
     Poser un ordinateur dans le **cabinet du dentiste** et un autre dans un
     **magasin** du même mall (vêtements, librairie, pharmacie), les allumer, et
     comparer les deux BIOS :
     - deux `Phone line:` **différents**, chacun avec un nom entre parenthèses en
       **mots** : `(Dentist)`, `(Clothes Store)`, `(Music Store)` ;
     - deux adresses `10.x.y.z` dont **les deux octets du milieu** diffèrent ;
     - les **trois premiers** chiffres du numéro sont les **mêmes** des deux côtés :
       un mall, un central.
     Puis se connecter sur chacune (`admin`, Entrée) et regarder ce qu'il y a
     dessus : `hostname` commence par `ward` chez le dentiste et par `till` dans le
     magasin ; `ls /home` ne donne **pas** les mêmes gens ; `cat /etc/motd` ne dit
     pas la même chose. C'est ça, « avoir ses spécificités ». [ ]
215k. **Le papier du tiroir n'ouvre que sa boutique.** Dans le mall, fouiller les
     tiroirs du bureau **du dentiste** jusqu'à trouver le papier `root` (un
     `Notebook` nommé). Le mot de passe dessus doit ouvrir `root` sur la machine du
     dentiste, et **échouer** sur celle du magasin d'à côté. Refaire dans l'autre
     sens. Avant ce changement un seul papier ouvrait tout le mall. [ ]
215l. **L'arrière-boutique appartient à sa boutique, le couloir à personne.** Poser
     un ordinateur dans une **réserve** collée à une boutique (`...storage`) : même
     numéro, même segment et même nom entre parenthèses que la boutique devant
     elle, et le papier de cette boutique l'ouvre. Poser un autre ordinateur dans
     le **couloir** du mall : numéro différent des deux, **aucun** nom entre
     parenthèses, le couloir est au bâtiment. Sur la machine de la boutique,
     `ruptime` doit lister **sa** machine et celle de sa réserve, et **pas** celles
     des autres boutiques ; `ping <adresse d'une autre boutique>` → 100 % de perte,
     `rlogin` → `No route to host`, et `cu <son numéro>` → l'appel passe. [ ]
215m. **L'annuaire liste les boutiques du mall.** Rouvrir un `Phonebook` de la
     région du mall : les boutiques doivent y être **sous leur métier en mots** :
     `Dentist`, `Music Store`, `Pharmacy`, `Book Store`, avec **exactement** les
     numéros lus au BIOS. `cu` sur une inscription dont on n'a pas posé
     d'ordinateur : `NO CARRIER` après quinze secondes (l'inscription est bonne, le
     local est vide). Vérifier aussi ce qui n'y est **pas** : ni `Hall`, ni une
     réserve, ni un bureau des étages. [ ]
215n. **Ce qui ne doit PAS avoir changé.** Trois cas, et c'est le vrai risque de ce
     changement :
     - une **quincaillerie ou une armurerie isolée** (un commerce, un bureau au
       fond, une réserve) : ses deux ordinateurs gardent **un** numéro et **un**
       segment, et aucun nom entre parenthèses ;
     - une **maison avec un bureau** dedans : un seul local (pas 215c) ;
     - une **station-service** : les quatre îlots de pompes portent le même nom de
       pièce, et la station reste **un** local, un numéro. Idem une **école** (les
       salles de classe ne sont pas des commerces) et un **poste de police**. [ ]
215o. **Une machine qui était déjà dans un mall.** Sur un monde d'avant premises v2
     où un ordinateur avait déjà été allumé **dans un mall** : le rallumer. Le
     numéro et l'adresse **changent une fois** (le mall était un seul local, la
     boutique en est un), et le BIOS montre maintenant le nom de la boutique. Mais
     ce qui est sur le disque ne bouge pas : `ls /home` donne les mêmes gens,
     l'ancien papier `root` trouvé dans ce mall **ouvre toujours** cette machine, et
     les fichiers écrits à la main sont là. Rallumer une deuxième fois : plus rien
     ne change. [ ]
215p. **La fenêtre de débogage le dit.** Sur une machine du mall, ouvrir la fenêtre
     de débogage (section X) et lire le bloc du local : une ligne
     `tenancies: <n>  <noms>` avec le compte des boutiques du bâtiment, et une ligne
     `premises: room  <Nom>` (ou `zone`, ou `building`). Dans une maison :
     `tenancies: 0` et `premises: building`. C'est l'outil à utiliser si un des pas
     ci-dessus ne répond pas ce qu'il devrait. [ ]

## T. La radio (palier 6c)

Il faut **deux ordinateurs dans deux bâtiments**, comme à la section S, et en plus
**deux radios bidirectionnelles** : une radio amateur (`Premium Technologies Ham`,
la tuile `appliances_com_01`, ou l'objet `HamRadio1` posé à la main) ou un
talkie-walkie, une par machine, **dans la même pièce** que l'ordinateur. Un poste
radio ordinaire ou un téléviseur ne compte pas : il ne fait que recevoir. Prévoir
aussi un talkie dans l'inventaire pour la dernière étape. `ici` et `là-bas` comme
avant.

216. **Le TNC et l'indicatif.** Poser une radio dans la pièce de `ici`, l'allumer
     (piles ou courant) et régler sa fréquence dans sa propre fenêtre, par
     exemple 144.390. Puis sur la machine : `dev radio` → une ligne `radio0`,
     `ham` (ou `walkie`), la position de la radio par rapport à l'ordinateur, et
     `144.390 on`. `cat /dev/radio0` → `144.390 on`. Éteindre la radio →
     `144.390 off` ; enlever la pile (ou couper le courant de la pièce) →
     `144.390 no power`. Vérifier qu'on ne peut rien y écrire :
     `echo 145.010 > /dev/radio0` → `radio0: permission denied`, et
     `ls -l /dev/radio0` → `cr--r-----`. Enfin le BIOS : éteindre et rallumer
     l'ordinateur, une ligne `Callsign: K?4???` doit apparaître **sous**
     `Phone line:`, et `cat /etc/callsign` doit donner le même indicatif. Les
     **deux** machines d'un même bâtiment doivent avoir des indicatifs
     **différents** (contrairement au numéro de téléphone, qui est celui du
     bâtiment). [ ]
217. **Le dialogue du TNC.** Il n'y a **pas** de commande `call` : le TNC est un
     boîtier au bout d'un câble série, et on l'atteint comme n'importe quel
     périphérique série de 1993. Depuis `ici` : `cu -l /dev/radio0` → une seule
     ligne `CeroSec Systems TNC-200 (TNC-2 compatible)`, puis l'invite du boîtier,
     `cmd:`. Y taper : `MYCALL` → `MYCALL <indicatif>` ; `MH` → **rien** (le
     boîtier n'a encore rien entendu) ; `BONJOUR` → `?EH`, qui est la seule chose
     qu'un TNC-2 répond à une ligne qu'il ne comprend pas ; `mycall` en
     minuscules → la même réponse que `MYCALL` (un TNC ne distingue pas la
     casse) ; une ligne vide → l'invite `cmd:` revient et rien d'autre. Ressortir
     avec `~.` seul sur la ligne → `Disconnected.` et l'invite du shell.
     Vérifier aussi qu'`enlever la radio de la pièce` puis `cu -l /dev/radio0`
     donne `cu: /dev/radio0: no such device` (il n'y a pas de ligne à ouvrir), et
     que `cu -l /dev/null` donne la même chose. Remettre la radio. [ ]
217a. **MYCALL écrit le fichier.** En `admin`, à `cmd:` : `MYCALL W4ZZZ` →
     `cu: /etc/callsign: permission denied` et `cat /etc/callsign` est inchangé
     (c'est un fichier de `root` : la mémoire du boîtier, c'est ce fichier). En
     `root` : `MYCALL W4ZZZ` → `MYCALL W4ZZZ`, et `cat /etc/callsign` répond
     `W4ZZZ`. `MYCALL kd4axr` → `MYCALL KD4AXR` (mis en majuscules, comme un TNC
     le fait), et `MYCALL nimportequoi` → `?EH` sans rien changer. [ ]
217b. **La liaison.** Régler les deux radios sur la **même** fréquence et les
     allumer. Depuis `ici`, à `cmd:` : `C <indicatif de là-bas>` →
     `*** CONNECTED to <indicatif>`, puis le `login:` de l'autre machine
     (`CONNECT <indicatif>` en entier fait la même chose). S'y connecter :
     l'invite devient `admin@<là-bas>`, `hostname` répond son nom. Vérifier que le
     mot de passe est demandé **même** avec le nom de `ici` dans
     `/etc/hosts.equiv` de `là-bas`. Puis là-bas : `who` → `ttyp0` avec
     `(<indicatif de ici>)` entre parenthèses, et `last` pareil. [ ]
217c. **Les trois sorties, et elles ne font pas la même chose.** Liaison ouverte,
     à l'invite de la machine d'en face : **Échap** → retour à `cmd:`, **sans**
     `*** DISCONNECTED` : c'est la touche d'interruption du TNC-2 et la liaison est
     toujours là. `K` (ou `CONV`) → on est de nouveau sur la machine d'en face,
     avec son écran tel qu'on l'a laissé. Échap de nouveau, puis `D` (ou
     `DISCONNE`) → `*** DISCONNECTED` et on reste à `cmd:` ; un deuxième `D`
     répond la même ligne. Enfin `~.` → `Disconnected.` et l'invite du shell.
     Reprendre une liaison et essayer l'autre ordre : `~.` directement depuis la
     machine d'en face → `*** DISCONNECTED` **puis** `Disconnected.`, et l'invite
     du shell (le boîtier dit que la liaison tombe, `cu` dit qu'il raccroche).
     `exit` là-bas fait la même chose depuis l'autre bout. [ ]
218. **Tout le comté écoute.** Prendre un talkie dans l'inventaire, le régler sur
     la **même** fréquence que les deux postes, l'allumer, et rester à portée.
     Refaire une liaison : dans la fenêtre du talkie doit apparaître une ligne
     `<indicatif appelé> de <indicatif appelant> *** CONNECTED`. Raccrocher : une
     deuxième ligne, la même avec `*** DISCONNECTED`. Changer la fréquence du
     talkie et refaire un appel : plus rien. C'est la leçon de sécurité du
     palier, la radio ne peut pas se taire, et la seule défense est de changer de
     fréquence. [ ]
218a. **MHEARD : ce que les boîtiers ont noté.** Les deux postes accordés et
     allumés. Ouvrir une liaison depuis `ici` puis revenir à `cmd:` (Échap) et
     taper `MH` → une ligne `<indicatif de là-bas>  hh:mm` : l'indicatif et
     l'heure, parce qu'un TNC-2 imprime l'heure quand `DAYTIME` est réglé, et ici
     il l'est au démarrage sur l'horloge de la machine. **Jamais** son propre
     indicatif : un boîtier ne s'entend pas. Aller sur `là-bas`,
     `cu -l /dev/radio0`, `MH` → l'indicatif de `ici` avec une heure : les deux
     bouts se sont entendus, une liaison étant deux émissions. Revenir sur `ici`,
     `MHCLEAR` puis `MH` → plus rien. Refaire une liaison pour remplir la liste,
     puis **éteindre l'ordinateur** et le rallumer : `cu -l /dev/radio0` puis `MH`
     → vide (c'est de la RAM dans un boîtier ; le courant l'emporte). Enfin la
     portée : régler le talkie de l'étape 218 sur la même fréquence, s'en éloigner
     franchement, refaire une liaison → rien de neuf dans `MH` là-bas. [ ]
219. **Les six silences.** Chacun de ces six cas doit répondre exactement
     `*** retry count exceeded`, et rien d'autre, chacun tapé comme `C
     <indicatif>` à l'invite `cmd:` du boîtier : (a) la radio de `là-bas`
     éteinte ; (b) sa pile retirée ; (c) sa fréquence changée (les deux postes
     allumés, mais pas sur la même) ; (d) la machine `là-bas` éteinte ;
     (e) un indicatif que personne n'a (`C W4ZZZ`) ; (f) son propre indicatif.
     Après chacun, le boîtier revient à `cmd:` et reste utilisable. Vérifier aussi
     les refus que la machine dit en son **propre** nom sans émettre : enlever la
     radio de la pièce de `ici` → `cu -l /dev/radio0` répond
     `cu: /dev/radio0: no such device` (et `dev radio` ne liste plus rien) ; la
     remettre, puis `rm /etc/callsign` en root, ouvrir la ligne et `C
     <indicatif>` → `cu: no callsign` (et `MYCALL` → `MYCALL NOCALL`, la valeur
     d'usine d'un boîtier que personne n'a programmé). [ ]
220. **La distance et le chargement du monde.** Laisser les deux postes allumés et
     accordés, puis s'éloigner : une liaison ne tient que jusqu'à la **plus
     petite** des deux portées (7500 tuiles pour un poste amateur). Plus
     intéressant et plus facile à provoquer : ouvrir une liaison, puis faire
     éteindre la radio d'en face (ou la déplacer hors de la pièce) pendant que la
     session est ouverte, et taper n'importe quoi → `*** retry count exceeded` et
     retour à l'invite locale (et **pas** `*** DISCONNECTED` : la liaison est
     tombée, personne n'a raccroché), et l'écran revient à `cmd:` et **pas** au
     shell : c'est `cu` qui tient la ligne et il est toujours là. Enfin le cas
     propre à la radio : s'éloigner assez pour que le morceau de carte de
     `là-bas` ne soit plus chargé, puis `C <son indicatif>` →
     `*** retry count exceeded`, alors que
     `cu 555-NNNN` vers la **même** machine marche toujours. Une radio est une
     tuile ; un disque, non. [ ]
221. **Un poste, une liaison, et ce qui ne s'émet pas.** Mettre **une seule**
     radio dans une pièce où il y a **deux** ordinateurs (la paire de la section
     N). Ouvrir une liaison depuis le premier, puis aller au second,
     `cu -l /dev/radio0` et `C <même indicatif>` → `*** BUSY`. Raccrocher, puis
     vérifier qu'une liaison ne se laisse pas automatiser : `crontab -e` avec
     `* * * * * cu -l /dev/radio0`, attendre une minute → `mail` dit
     `cu: not a terminal`, la bannière du boîtier n'apparaît **pas** (la ligne n'a
     jamais été ouverte), **aucune** session ne s'est ouverte là-bas, et, le
     point important, **rien n'est passé sur les ondes** (le talkie de l'étape
     218, accordé et allumé, ne doit rien afficher). Finir par `crontab -r`.
     Vérifier aussi la lenteur : lancer `ls /bin` sur la machine d'en face, les
     lignes doivent arriver **deux par seconde**, visiblement plus lentement
     qu'un appel téléphonique (quatre) et rien ne doit manquer à la fin. [ ]
221a. **`call` a disparu, et la machine d'une vieille partie le perd.** Sur une
     machine neuve : `call KD4AXR` → `call: command not found`, `ls /bin` ne montre
     pas `call`, `help` ne le nomme pas, et **Tab** après `cal` ne complète rien.
     Puis la mise à niveau : charger une partie **d'avant** cette version (ou
     recréer le cas à la main en root, `echo "call another machine on the radio" >
     /bin/call` puis `chmod 755 /bin/call`, et dans le débogueur remettre le
     `sysv` de la machine à 16), éteindre et rallumer l'ordinateur → `/bin/call`
     a été **supprimé** par la mise à niveau et `ls /bin` ne le montre plus. Un
     fichier que le joueur a écrit lui-même à ce nom (un contenu différent, un
     autre mode ou un autre propriétaire) doit au contraire **rester**. [ ]

## U. Nommer les voisines (palier 6d)

Les deux ordinateurs d'un **même bâtiment** de la section N, tous les deux
allumés. Repartir d'un `/etc/hosts` que personne n'a encore complété : celui que
la machine s'écrit toute seule (la boucle locale et sa propre ligne). `ici` est la
machine devant laquelle on est assis, `gate` l'autre.

222. **Le trou que `arp` bouche.** `ruptime` → l'autre machine est là, listée par
     le nom qu'elle **annonce** (`ksp-<x>-<y>`). Taper `ping <ce nom>` →
     `ping: unknown host <ce nom>` : rien sur ce disque ne résout ce nom. Puis
     `arp -a` → une ligne par **autre** machine allumée du bâtiment, de la forme
     `? (10.x.y.2) at 8:0:20:<3 octets>` : le `?` parce qu'aucune ligne de
     `/etc/hosts` ne nomme cette adresse. Vérifier trois choses : la machine
     devant laquelle on est assis **n'est pas** dans sa propre liste ; refaire
     `arp -a` donne exactement la même carte (elle est dérivée, pas tirée au
     sort) ; et `arp -a` après avoir éteint et rallumé l'autre machine donne
     encore la même. Enfin `arp <nom annoncé>` → `arp: <nom>: unknown host`, et
     `arp 10.x.y.9` (une adresse que personne ne porte) →
     `10.x.y.9 (10.x.y.9) -- no entry`, sans `arp:` devant. [ ]
223. **La ligne écrite à la main.** `sudo edit /etc/hosts` (ou, en root,
     `echo "10.x.y.2 gate" >> /etc/hosts`), ajouter l'adresse relevée à l'étape
     222 sous le nom `gate`, sauver. `arp -a` → la même ligne dit maintenant
     `gate (10.x.y.2) at 8:0:20:...`, **avec la même carte qu'avant** : le nom a
     changé, l'adresse et la carte non. `ping gate` → trois réponses. Puis
     l'autre sens : `rlogin 10.x.y.2` **sans aucune ligne** pour elle → la
     session s'ouvre sur `login:`, et pareil pour `rsh 10.x.y.2 hostname` et
     `rcp <fichier> 10.x.y.2:/tmp/a` une fois la confiance en place. Se
     connecter là-bas et taper `who` : la session est nommée par ce que le
     `/etc/hosts` **de cette machine-là** dit de l'adresse d'ici -- le nom s'il y
     a une ligne, l'adresse `10.x.y.1` toute nue sinon (c'est le cas par défaut,
     personne n'a rien écrit là-bas). `last` et `cat /var/log/wtmp` doivent
     porter exactement la même chose dans la colonne d'origine. [ ]
224. **Une machine ne se nomme pas elle-même dans la confiance.** Sur `gate`, en
     root : `echo "pump" > /etc/hosts.equiv` -- un nom que le `/etc/hosts` de
     `gate` ne porte pas. Revenir ici et se renommer : `sudo hostname pump`, puis
     vérifier avec `hostname` et avec `ruptime` **depuis gate** (la machine
     s'annonce bien `pump` maintenant). Refaire `rlogin gate` → il demande
     **quand même** `login:` et `password:`. Puis, toujours sur `gate` en root,
     ajouter la ligne qui manquait : `echo "10.x.y.1 pump" >> /etc/hosts`.
     Refaire `rlogin gate` → cette fois la session s'ouvre **sans mot de passe**.
     Remettre `echo "<adresse d'ici>" > /etc/hosts.equiv` (l'adresse au lieu du
     nom) et retirer la ligne de `/etc/hosts` : la confiance tient toujours, une
     adresse n'a besoin de personne pour être résolue. Finir par
     `sudo hostname <le nom d'origine>` et `echo "" > /etc/hosts.equiv`. [ ]

## V. Le morceau de carte qui s'en va (palier 6d)

Le monde se décharge autour du joueur (le jeu garde 13x13 morceaux de 8 tuiles).
Une machine hors du monde garde l'état qu'elle avait : elle reste allumée, ses jobs
et son crontab continuent, elle répond encore au fil, et seuls `/dev` et la mesure
du courant s'en vont avec le morceau de carte. Le courant est remesuré au
rechargement du morceau, jamais avant. La règle est dans
[ARCHITECTURE.md](ARCHITECTURE.md#the-chunk-that-goes-away).

225. **S'éloigner, revenir, tout est encore allumé.** Allumer deux ou trois
     ordinateurs dans un bâtiment sur le réseau (ou sur un générateur), poser un
     `crontab -e` avec `* * * * * date >> /home/admin/heures` sur l'un d'eux, puis
     partir assez loin pour décharger le quartier (traverser la ville, ou dormir
     ailleurs) et revenir quinze minutes de jeu plus tard. Attendu : les machines
     sont **toutes encore allumées**, la lueur d'écran est de retour (une seule par
     écran), le terminal retrouve le même écran qu'avant, et `cat
     /home/admin/heures` montre une ligne par minute passée, y compris les minutes
     où personne ne regardait. Pendant l'absence, `ls /dev` depuis une autre
     machine du même bâtiment par `rlogin` ne liste rien et `echo on >
     /dev/light0` répond `light0: no such device` : c'est le monde qui manque, pas
     la machine. [ ]
225b. **La lueur revient d'un aller-retour très loin.** Un ordinateur allumé, se
     placer devant pour voir la lueur bleutée sur le mur, puis se téléporter très
     loin (ou traverser la carte) assez pour que le quartier se décharge, et
     revenir tout de suite. Attendu : la lueur est là **dès que le morceau de
     carte arrive**, sans rien toucher, sans attendre une minute et sans passer
     par l'interrupteur, une seule lueur, jamais deux. Refaire l'aller-retour
     trois ou quatre fois de suite : c'est toujours une. C'était le bogue
     rapporté (« je me téléporte très loin et je reviens, la lumière n'est plus
     là alors que l'ordinateur est allumé ») : le moteur retire la lueur avec le
     morceau de carte et ne le dit à personne. Le contrôle du même geste :
     éteindre la machine pendant l'absence (par `rlogin` depuis une autre du même
     bâtiment, ou un `halt` au crontab) → au retour, sprite éteint et **aucune**
     lueur. [ ]
226. **Le générateur mort pendant l'absence.** Un ordinateur allumé dans un
     bâtiment alimenté par un générateur, réseau coupé (`ElecShutModifier` passé,
     ou bâtiment hors réseau). Vider le générateur d'essence ou l'éteindre, puis
     s'éloigner assez pour décharger le morceau de carte **avant** que la minute
     suivante passe, attendre, et revenir. Attendu : la machine est éteinte, et
     elle s'éteint **au retour** (sprite éteint, plus de lueur, un terminal ouvert
     dessus se ferme en disant que le courant est parti), pas pendant l'absence.
     Le contrôle du même geste : rester devant la machine et couper le générateur
     sur place → elle s'éteint toute seule dans la minute qui suit. [ ]

## W. Les modules matériels (palier 4f)

Depuis ce palier, une porte, une fenêtre ou un interrupteur n'est un
périphérique que si **quelqu'un y a vissé un module**. L'option de bac à sable
`CeroSec.HardwareRequired` (page « CeroSec » de l'écran des options, **activée
par défaut**) commande tout : désactivée, c'est exactement le monde d'avant. Les
quatre modules sont le contact magnétique (voit une porte ou une fenêtre), le
relais (actionne un interrupteur), la gâche électrique (la serrure) et
l'opérateur de porte (ouvre et ferme). Règles et preuves :
[DEVICES.md](DEVICES.md#the-hardware-modules).

227. **Un bâtiment tout neuf ne répond à rien.** Nouvelle partie avec l'option
     **activée** (la valeur par défaut : ne rien toucher dans le bac à sable).
     Ordinateur alimenté dans une maison avec des portes, des fenêtres et des
     interrupteurs. En `root` : `ls -l /dev` → **rien du monde**, seulement
     `null` et `fd0` s'il y a une disquette. `dev` → tableau vide. `dev light0`
     → `dev: light0: no such device`. C'est le changement de ce palier ; si des
     portes apparaissent encore, l'option n'est pas lue. [ ]
228. **Le menu, et ce qu'il refuse.** Clic droit sur un **interrupteur**, sans
     rien dans le sac → aucune entrée « Matériel CeroSec » (on ne parle pas de
     matériel qu'on n'a pas). Se donner un `CeroSec.Relay` : l'entrée apparaît,
     « Installer Module relais ». Sans tournevis → grisée, infobulle « Il vous
     faut un tournevis. ». Avec le tournevis mais Électricité 0 → grisée,
     « Électricité 1 requise. ». Même essai en visant une **porte** avec le
     relais en poche → « Ce module ne va pas ici. ». [ ]
229. **Poser le relais.** Électricité 1, tournevis et relais en main, clic droit
     sur l'interrupteur → Installer. Attendu : le personnage **marche jusqu'à
     l'interrupteur**, joue l'animation de fouille quelques secondes, le relais
     **quitte le sac**, le tournevis reste, et un petit gain d'XP Électricité
     apparaît. Puis sur l'ordinateur : `dev` → l'interrupteur est là,
     `echo off > /dev/light0` éteint bien la pièce. [ ]
230. **Le contact seul : on regarde, on ne touche pas.** Poser un
     `CeroSec.MagneticContact` sur une porte **extérieure**. `ls -l /dev` → la
     ligne de cette porte porte `cr--r-----` (pas de `w`). En `admin` :
     `echo open > /dev/doorN` → `doorN: permission denied`. Faire `su root`
     puis le même ordre → `doorN: operation not supported`. Dans les deux cas
     la porte **ne bouge pas** dans le monde. `cat /dev/doorN` répond
     `closed`, `open` ou `locked` selon ce qu'on lui fait à la main : ouvrir la
     porte au clic et relire → la lecture suit. [ ]
231. **L'opérateur sur la même porte.** Poser un `CeroSec.DoorOperator`
     (Électricité 3) sur cette porte. Attendu : **même numéro** qu'à l'étape
     230, `doorN` n'a pas changé, mais `ls -l /dev` montre maintenant
     `crw-rw----`, et `echo open > /dev/doorN` ouvre la porte pour de bon. Si la
     porte est verrouillée, elle répond `doorN: locked` : c'est la serrure, pas
     le module. [ ]
232. **La gâche, et les deux portes qui la refusent.** Sur une porte
     **intérieure** (une pièce de chaque côté), clic droit avec la gâche →
     entrée grisée, « Cette porte n'a pas de serrure à câbler. ». Sur une porte
     de **garage** ou une porte double, avec l'opérateur → grisée, « Un
     ordinateur ne peut pas actionner une porte double ou de garage. ». Sur la
     porte extérieure de l'étape 230 → la gâche se pose, et `lockN` apparaît à
     côté de `doorN` : `echo unlock > /dev/lockN` déverrouille, essayer d'entrer
     depuis dehors le confirme. [ ]
233. **La fenêtre ne prend qu'un contact, et le contact sent le châssis.** Clic
     droit sur une fenêtre avec la gâche ou l'opérateur en poche → « Ce module
     ne va pas ici. ». Avec le contact → il se pose, `winN` apparaît. Ouvrir la
     fenêtre **à la main**, puis `dev winN` → `winN: open` ; la refermer →
     `winN: locked` ou `unlocked` selon le loquet. Casser la vitre → `smashed`,
     même châssis ouvert : le verre passe avant le reste. `dev winN toggle` sur
     une fenêtre ouverte → `winN: cannot toggle` (ses deux mots sont `lock` et
     `unlock`, rien ne défait un châssis). `echo unlock > /dev/winN` en `root` →
     `winN: operation not supported`, et le loquet ne bouge pas : rien dans le
     moteur n'ouvre un châssis sans un survivant devant, donc une fenêtre se lit
     et ne se travaille pas. [ ]
233b. **La lecture du châssis vaut dans les deux modes.** Option **désactivée**
     (étape 237), sans aucun module posé : ouvrir une fenêtre à la main et
     `dev winN` → `winN: open` tout pareil, et `echo lock > /dev/winN`
     fonctionne toujours comme avant ce palier. Ce que le contact achète, c'est
     le droit d'exister dans `/dev`, jamais un mot de plus. [ ]
234. **Retirer rend le module entier.** Clic droit sur l'interrupteur de l'étape
     229 → « Retirer Module relais ». Attendu : le relais **revient dans le
     sac** (un seul, pas deux), l'interrupteur disparaît de `dev`, et
     `dev light0` répond `light0: no such device`. Le reposer : c'est **le même
     `light0`** qu'avant. Sur une porte qui porte contact **et** gâche, retirer
     le contact ne touche pas à la gâche : `lockN` répond toujours. [ ]
235. **Le guide, et ce qu'il débloque.** Nouvelle partie, Électricité 1,
     **sans avoir rien lu** : ouvrir l'établi, onglet **Électrique** → aucun
     des quatre modules n'est proposé. C'est le changement apporté ici ;
     s'ils sont déjà là, la recette s'auto-apprend encore au niveau qui la
     fabrique. Se donner un `CeroSec.WiringGuide` : il s'appelle **Guide de
     câblage CeroSec**, il pèse 0,5, il est rangé sous **Ressource de recette**
     et son infobulle nomme les quatre modules. Clic droit → **Lire**, c'est
     l'entrée *vanilla*, aucune des nôtres, et le personnage s'assoit et lit.
     Attendu : à la fin, les quatre recettes sont apprises d'un coup, et un
     deuxième clic droit propose **Relire**. [ ]
235b. **Fabriquer les quatre.** Le guide lu, avec Électricité 1 : le contact
     magnétique et le module relais sont dans l'onglet **Électrique** de
     l'établi. À 2 la gâche apparaît, à 3 l'opérateur, la compétence barre
     toujours la fabrication, le livre n'enlève que l'ignorance. Vérifier qu'un
     tournevis est demandé et **rendu** (il est toujours là après la
     fabrication), et que l'opérateur mange bien une boîte de pièces de
     moteur. [ ]
235c. **L'électricien chevronné s'en passe.** Personnage monté à **Électricité
     7** sans avoir jamais vu le guide : le contact et le relais sont là quand
     même (la gâche à 8, l'opérateur à 9). C'est la forme vanilla, le
     magazine avance l'accès, il n'en est pas la seule porte. [ ]
236. **Le butin.** Dans une camionnette d'électricien, une boutique
     d'électronique, une caisse d'entrepôt, une quincaillerie ou un garage : on
     trouve des contacts assez souvent, des relais moins, des gâches encore
     moins et un opérateur rarement. Aucun module sur un bureau de bureau ni
     dans une bibliothèque, ce ne sont pas les mêmes étagères que les
     disquettes. Le **guide**, lui, se trouve là où le jeu met ses propres
     magazines d'électronique et aux mêmes taux : surtout sur le présentoir
     d'une boutique d'électronique, puis une librairie, une quincaillerie et la
     camionnette d'un électricien, puis un présentoir mixte, le courrier d'un
     bureau de poste, une caisse de magazines et une bibliothèque. Nulle part
     ailleurs : pas sur l'étagère d'un salon ni dans la garde-robe d'un enfant,
     là où le jeu met ses magazines « traînés ». [ ]
237. **L'option désactivée, c'est le monde d'avant.** Nouvelle partie, bac à
     sable, page CeroSec, décocher « Modules matériels obligatoires ». Attendu :
     dans un bâtiment où **rien n'est posé**, `ls -l /dev` liste toutes les
     portes, fenêtres, serrures et lumières comme aux étapes 83 à 90, `echo
     unlock > /dev/win0` fonctionne de nouveau, et le clic droit sur une porte
     **n'offre aucune entrée** « Matériel CeroSec » (poser un module n'y
     servirait à rien). [ ]
238. **Ça survit à la sauvegarde et au déchargement.** Option activée, deux ou
     trois modules posés. Quitter la partie, revenir : `dev` montre exactement
     les mêmes périphériques avec les mêmes numéros. Puis s'éloigner assez pour
     décharger le quartier et revenir (section V) : au retour, les modules sont
     toujours là. [ ]
239. **En multijoueur (si testé).** Hôte + client : le client pose un module,
     l'hôte voit le périphérique apparaître dans `dev` sur sa propre machine
     sans recharger, et inversement. Le client qui n'est **pas** à côté de la
     porte ne peut rien poser dessus. [ ]
## X. La fenêtre de débogage (palier debug)

La fenêtre est un outil de développement, jamais quelque chose qu'un joueur voit.
Elle ne change que six choses sur cette rangée de boutons : allumer, éteindre, où le
personnage se trouve, **réinitialiser la machine**, derrière deux clics, et seulement
sur une machine éteinte, c'est-à-dire en refaire une que personne n'a jamais
utilisée, lancer l'autotest, et donner la disquette de diagnostic. Tout le reste est
en lecture. Les huit outils de la **deuxième rangée**, les papiers, les comptes, le
mot de passe enlevé, n'importe quelle disquette, root à l'écran, cron tout de suite,
le câblage forcé, sont la section [AI](#ai-les-outils-de-ladmin-et-du-testeur-fenêtre-de-débogage-2e-rangée).
Détails et protocole dans [DEBUG.md](DEBUG.md).

Les étapes 258b à 258i sont la porte de sortie du mod : ce sont les deux seules
vérifications qui font tourner le moteur sur la machine virtuelle que le joueur a
vraiment (Kahlua, et pas `lua5.1`), et [RELEASE.md](RELEASE.md) en fait ses étapes
6a et 6b. Aucune version ne part sans leurs deux sentences collées dans les notes.

Pour cette section : deux ordinateurs allumés dans le même bâtiment, un troisième
dans un bâtiment loin (le même décor que la section N), et au moins une porte et
un interrupteur dans la pièce.

240. **La porte.** Clic droit sur un ordinateur → dernière entrée du menu,
     **CeroSec (dev)**, et dedans les trois volumes du manuel puis **Fenêtre de
     débogage** en dernier. Attendu : le sous-menu ne s'appelle plus « Read the
     CeroSec manual (dev) », il porte le nom du mod, et l'entrée debug est bien
     la dernière des quatre. [ ]
241. **Ouvrir.** Cliquer **Fenêtre de débogage** → une fenêtre s'ouvre au centre
     de l'écran, avec une barre de titre « CeroSec débogage », six onglets
     (Machines, Files, Devices, Network, Scheduler, Log) et une rangée de boutons
     en bas. Attendu : elle ressemble aux fenêtres de debug du jeu (mêmes
     couleurs, même police, mêmes en-têtes de colonnes), et pas au terminal vert.
     [ ]
241b. **Rien de dessiné deux fois sur la même ligne.** C'est le défaut du
     2026-09-12 : la rangée d'onglets et les en-têtes de colonnes étaient sur la
     MÊME ligne (on lisait « ess », « tel », « call », « jobs », « eyes » entre les
     noms d'onglets). Attendu, de haut en bas et sans chevauchement : la barre de
     titre, la rangée d'onglets, la rangée grise des en-têtes de colonnes, les
     lignes, la rangée de boutons, puis le bloc de détail. Passer sur chacun des
     six onglets : la même chose partout. [ ]
241c. **Les colonnes.** Attendu : chaque colonne est assez large pour son
     en-tête ET pour la plus longue cellule affichée, aucune cellule n'empiète sur
     la colonne d'à côté, les traits verticaux tombent entre les colonnes et pas au
     milieu d'un mot, et la dernière colonne va jusqu'au bord droit. Sélectionner
     une machine avec un nom d'hôte long et regarder l'onglet Files (les chemins
     sont les cellules les plus longues) : une cellule trop longue est **coupée**
     avec un `~`, jamais dessinée par-dessus la suivante. [ ]
242. **L'onglet Machines.** Attendu : une ligne par ordinateur **utilisé** que le
     serveur tient, y compris celui du bâtiment loin, avec ses colonnes nommées en
     mots clairs, `x,y,z`, `facing`, `power`, `chunk`, `wire`, `host`, `address`,
     `tel`, `call`, `jobs`, `windows`. La machine devant laquelle on est est déjà
     sélectionnée. [ ]
242b. **Le filtre, et le compte.** Sous la liste, une ligne `showing N of M` avec
     le mode (`used only`). Le bouton **Voir toutes les machines** montre tout :
     attendu, beaucoup plus de lignes, une par sprite d'ordinateur que le streamer
     a chargé depuis le début de la partie, éteinte, avec des colonnes vides (c'est
     ce qu'on a vu en jeu : 44 lignes pour 6 machines qui comptent), et `N` monte
     jusqu'à `M`. Le bouton devient **Voir les utilisées** et revient en arrière. Le
     filtre ne change rien à la sélection ni aux autres onglets, et il ne demande
     rien au serveur (aucun délai). [ ]
242c. **La sélection tient.** Machine sélectionnée, attendre trois
     rafraîchissements (six secondes) sans toucher à rien. Attendu : la ligne
     surlignée est toujours la MÊME machine, même si une autre est apparue ou a
     disparu au-dessus d'elle dans la liste. [ ]
243. **Sous la liste.** Attendu : le détail de la machine sélectionnée sur
     plusieurs lignes, son sprite, la version de son état, `sysv`, si le système
     passe, et sa console (qui est connecté, dans quel répertoire, combien de
     lignes à l'écran). Ouvrir le terminal dessus, taper `ls`, revenir à la
     fenêtre : le nombre de lignes a bougé dans les deux secondes. [ ]
243b. **Où la machine se trouve.** Toujours sous la liste, après la console :
     l'empreinte du bâtiment (coin, coin opposé, taille, superficie, nombre de
     pièces) ou `outdoors` pour une machine dans une base construite, le nom de la
     pièce, et une ligne par zone dans laquelle le carré se trouve, son type, son
     nom, sa position, `w x h`, sa boîte (`w*h`) et sa superficie réelle. Faire
     l'essai **dans un centre commercial** : attendu, la zone nommée du magasin est
     plus petite que le bâtiment autour d'elle, et pour une zone de forme
     irrégulière la superficie réelle est plus petite que sa boîte. Sur une machine
     dont le morceau de carte n'est pas chargé : `premises: no square (the chunk is
     away)` et rien d'autre, personne n'est là pour répondre. [ ]
244. **Sélectionner une autre machine.** Cliquer la ligne de l'ordinateur du
     bâtiment loin. Attendu : la liste garde ses lignes et la ligne cliquée reste
     surlignée, le détail dessous devient celui de cette machine, et les onglets
     Files et Devices se vident puis se remplissent avec ceux de la nouvelle
     machine, jamais le disque de l'ancienne sous le nom de la nouvelle. [ ]
245. **La machine dont le quartier n'est pas chargé.** Sa colonne **chunk** dit
     `away` et sa colonne **wire** dit `-` et pas `no` : personne n'est là pour
     répondre sur le courant. Attendu : elle est quand même **allumée** (`on`), et
     son nom et son adresse sont là, parce que le serveur tient son disque quoi
     que fasse le streamer. [ ]
246. **Éteindre à distance.** Machine loin sélectionnée, cliquer **Éteindre**.
     Attendu : sa colonne `power` passe à `off` dans les deux secondes, éteindre ne
     demande rien au monde, le serveur tient l'état. [ ]
246b. **Rallumer une machine dont le quartier n'est pas chargé, et savoir
     pourquoi.** C'est l'autre moitié du défaut du 2026-09-12 : le bouton
     **Allumer** était cliquable, on cliquait, et il ne se passait **rien du tout**.
     Machine loin (colonne `chunk` = `away`) sélectionnée. Attendu : le bouton
     **Allumer** est **grisé**, et la PREMIÈRE ligne du bloc sous la liste dit
     pourquoi, « cannot turn on: its chunk is away, so there is nobody to ask about
     the wire -- teleport to it first ». Cliquer dessus quand même : rien ne part sur
     le fil et la ligne reste. [ ]
246c. **Rallumer une machine qu'on peut rallumer.** Se téléporter à la machine
     loin (étape 247), attendre que la colonne `chunk` passe à `here` et que `wire`
     dise `yes`. Attendu : **Allumer** n'est plus grisé, la ligne de raison est
     vide, et le clic allume la machine (colonne `power` → `on` dans les deux
     secondes, l'écran s'allume dans le monde). Puis **Allumer** se grise et
     **Éteindre** s'active. [ ]
246d. **Un refus que le serveur envoie quand même.** Couper le courant de la pièce
     (générateur à l'arrêt / interrupteur du réseau) SANS rafraîchir, puis cliquer
     **Allumer** dans les deux secondes qui suivent, le bouton était encore
     activé. Attendu : le refus revient du serveur et s'affiche sur la première
     ligne (« cannot turn on: there is no wire at its square »), jamais un clic
     muet. [ ]
247. **S'y téléporter.** Machine loin sélectionnée, cliquer **S'y téléporter** →
     le personnage se retrouve au milieu du carré de cette machine (pas sur le
     coin), le quartier se charge, et la colonne **chunk** de cette ligne passe à
     `here` au rafraîchissement suivant. [ ]
248. **Ouvrir le terminal.** Sur une machine allumée dont le quartier est chargé
     et à côté de laquelle on se trouve, cliquer **Ouvrir le terminal** → le
     terminal s'ouvre comme si on avait utilisé l'ordinateur par devant, sans la
     marche et sans la chaise. [ ]
248b. **Les trois raisons de ne pas l'ouvrir.** Attendu : le bouton est grisé et la
     première ligne sous la liste dit laquelle des trois manque, « cannot open the
     terminal: its chunk is away, there is no screen in the world » (machine loin),
     « ... it is off » (machine éteinte devant laquelle on est), « ... the player is
     not standing at it » (machine allumée et chargée, mais on s'est éloigné de trois
     carrés). Faire les trois. Cliquer quand même : rien ne s'ouvre. [ ]
249. **L'onglet Files.** Attendu : l'arbre du disque de la machine sélectionnée,
     `/` en première ligne, puis `/bin`, `/etc`, `/home`… en profondeur, avec le
     mode écrit comme `ls -l` l'écrit, le propriétaire, la taille et la date.
     Sous la liste : le compte de nœuds et d'octets contre les plafonds. Comparer
     avec `ls -l /etc` tapé dans le terminal de la même machine : mêmes modes,
     mêmes propriétaires, mêmes tailles. [ ]
250. **Vider l'état.** `CeroSec.DEBUG` n'a rien à voir ici. Cliquer **Vider
     l'état** → la console du jeu (`console.txt`) reçoit le contenu de l'état de
     la machine, une ligne par clé, et une dernière ligne qui dit où ça a été
     coupé. Attendu : c'est borné (pas plus de 401 lignes), et rien n'apparaît
     dans la fenêtre. [ ]
250b. **Réinitialiser la machine, les deux clics.** C'est le bouton
     **Réinitialiser la machine**, après **Vider l'état**, et il existe pour une
     seule raison : le préremplissage n'arrive qu'au PREMIER allumage, donc une
     machine dont le premier allumage a planté à moitié est une machine sur laquelle
     on ne peut plus réessayer. Sur une machine **éteinte** : cliquer une fois.
     Attendu : rien ne part sur le fil et la première ligne sous la liste dit
     « Click again to reset <nom d'hôte> at x,y,z ». Attendre plus de **cinq
     secondes** sans rien faire : la ligne disparaît et le clic suivant ne fait
     qu'armer de nouveau. Cliquer deux fois de suite : le disque part. Aucune
     boîte de dialogue, jamais, les deux clics SONT la garde. [ ]
250c. **Ce que la réinitialisation laisse.** Avant de réinitialiser : noter le nom
     d'hôte et les comptes de la machine (`cat /etc/passwd`), écrire un fichier à
     soi, mettre une **disquette** dans le lecteur, et repérer le papier déjà trouvé
     dans un tiroir de ces lieux. Réinitialiser (machine éteinte), puis rallumer.
     Attendu : les **mêmes comptes** et le **même nom d'hôte** qu'avant, ils
     viennent du secret de la sauvegarde et des lieux, que rien de tout ça ne touche,
     donc **le papier du tiroir ouvre encore la machine** ; le fichier écrit à la
     main a disparu ; et la **disquette est toujours dans le lecteur**, avec ce qui
     est écrit dessus (`mount /dev/fd0 /mnt` puis `ls /mnt`). Rien n'est éjecté par
     terre : une disquette dans un lecteur est dans le lecteur. Et aucun second
     papier n'apparaît dans les tiroirs de ces lieux. [ ]
250d. **Les refus.** Sur une machine **allumée** : attendu, le bouton est **grisé**,
     et cliquer quand même n'envoie rien et écrit « cannot reset: it is on -- switch
     it off first » sur la première ligne. Puis : armer sur une machine éteinte,
     l'allumer par le menu de l'ordinateur AVANT le second clic, et cliquer.
     Attendu : rien n'est réinitialisé, la même phrase s'affiche. Enfin armer sur une
     machine, cliquer une autre ligne, et cliquer **Réinitialiser la machine** :
     attendu, ce clic ne fait qu'armer sur la nouvelle machine, un armement ne
     traverse jamais une sélection. [ ]
250e. **La ligne qui ne disparaît pas sous le curseur.** Une machine
     réinitialisée n'a plus d'état, donc le serveur ne la compte plus comme
     « utilisée ». Filtre sur **Voir les utilisées** (le réglage par défaut),
     réinitialiser la machine sélectionnée. Attendu : sa ligne **reste** dans la
     liste et reste surlignée, aux rafraîchissements suivants aussi, pendant que les
     autres machines jamais utilisées restent cachées, sans quoi l'ordinateur qu'on
     vient de réinitialiser aurait l'air d'avoir été supprimé. Cliquer **Allumer**
     dessus : elle revient dans la liste par la porte normale. [ ]
251. **L'onglet Devices.** Attendu : une ligne par entrée de `/dev` de la machine
     sélectionnée, avec le même nom et le même état que `ls -l /dev` dans son
     terminal, plus ce que le terminal ne montre pas : le carré absolu de l'objet,
     la « poignée » qu'un `dev find` enverrait (le nom de sprite d'une porte, le
     type d'objet d'un détecteur posé par terre, **rien** pour un interrupteur,
     un interrupteur clignote au lieu d'être entouré), et si l'objet est encore
     là. Sous la liste : le carnet de numéros et un enregistrement par détecteur.
     [ ]
252. **Un périphérique qui s'en va.** Ramasser le détecteur posé par terre.
     Attendu : au rafraîchissement suivant sa ligne dit que l'objet est parti
     (`gone`) et son numéro reste dépensé, c'est la différence entre un
     périphérique hors de portée et un chemin mal tapé. [ ]
253. **L'onglet Network.** Attendu : une ligne `eth` par bâtiment avec ses
     machines et leurs adresses, une ligne `tel` par bâtiment avec libre/occupé,
     une ligne `tel exchange` avec l'état du central et du réseau, une ligne
     `radio` par machine qui a un indicatif, et rien de plus s'il n'y a aucune
     session ouverte. [ ]
254. **Une session qui monte.** `rlogin` depuis une machine du bâtiment vers
     l'autre du même bâtiment, se connecter. Attendu : une ligne `pty ttyp0`
     apparaît avec d'où elle vient, par quel lien, combien de sauts et son âge, et
     des lignes `evt` disent ce que le fil a été demandé et ce qu'il a répondu.
     Taper `exit` : la ligne `pty` disparaît et une ligne `evt close` apparaît.
     [ ]
255. **Un refus qui laisse une trace.** `rlogin` vers l'adresse de la machine du
     bâtiment **loin** (pas de câble entre deux bâtiments) → le terminal dit son
     refus, et dans l'onglet Network une ligne `evt eth <adresse> unreach`
     apparaît. Attendu : c'est la seule trace qui existe de ce refus, puisque
     aucune session n'a été créée et que l'écran finira par défiler. En revanche
     `rlogin nimportequoi` (un nom que rien ne résout) **ne** fait **pas** de
     ligne `evt` : ce refus est celui du résolveur et n'atteint jamais le fil. [ ]
256. **L'onglet Scheduler.** Lancer `sleep 60 &` sur la machine sélectionnée.
     Attendu : une ligne apparaît avec la machine, l'id que le shell a annoncé,
     le slot `[1]`, le nom, l'état, les pas, le temps processeur et la dette,
     l'état étant le mot que `jobs` imprime pour le même job. Sous la liste : les
     constantes de budget de `CeroSecDefs` et l'horloge du planificateur. [ ]
257. **Le crontab.** `crontab -e` avec `* * * * * date` sur la machine
     sélectionnée. Attendu : sous la liste, une ligne par ligne de crontab avec
     `DUE NOW` ou `waiting` et la commande. Écrire une ligne impossible à la main
     en root (`60 * * * * echo non` dans `/var/spool/cron/admin`) : une ligne
     `BAD (bad minute)` apparaît, avec le numéro de ligne. [ ]
258. **L'onglet Log.** Attendu : les lignes que le mod a écrites sur lui-même,
     la plus récente en bas, avec leur niveau. Les boutons **All**, **Warnings**
     et **Errors** filtrent, et les trois boutons ne sont là que sur cet onglet.
     Attendu aussi : il y a des lignes **même avec `CeroSec.DEBUG = false`** :
     l'impression dans la console est conditionnée par ce réglage, l'anneau non.
     [ ]
258b. **L'autotest du moteur.** C'est l'étape qui aurait attrapé les deux bogues
     du 2026-09-12 : le jeu ne tourne pas sur `lua5.1`, il tourne sur Kahlua, et
     `tonumber(s, 16)` comme l'opérateur `%` y répondent autrement. Aller sur
     l'onglet **Machines**, cliquer une ligne dont la colonne `chunk` dit `here`
     (sinon **S'y téléporter** d'abord), puis presser **Autotest**. Attendu : sous
     la liste, une ligne `selftest: PASS n FAIL 0` avec `n` au-dessus de cent. La
     même ligne apparaît sur l'onglet **Log** au niveau `info`, et dans
     `console.txt`. [ ]
258c. **Une machine dont le morceau de carte est parti.** Sélectionner
     l'ordinateur du bâtiment loin (colonne `chunk` à `away`) et presser
     **Autotest**. Attendu : `FAIL 1` au moins, et sur l'onglet **Log** filtré par
     **Warnings** une ligne `save.chunk` qui dit que le morceau de carte est parti
     et qu'il faut s'y téléporter. Ce n'est pas un bogue, c'est le refus attendu :
     la moitié de l'autotest porte sur le chemin de sauvegarde de la machine
     choisie, et une machine sans sprite dans le monde n'a rien où l'écrire. Un
     autotest qui aurait sauté cette moitié en silence aurait annoncé un succès
     plus pauvre que le précédent. S'y téléporter, presser encore : `FAIL 0`. [ ]
258d. **Les lignes qui échouent se lisent.** Rien à casser ici : vérifier
     seulement qu'à l'étape 258c la ligne `warn` nomme la vérification, ce que
     `lua5.1` répond et ce que le jeu a répondu, et que le bouton **Warnings** de
     l'onglet Log la trouve. Une ligne de refus qu'un lecteur ne trouve pas est un
     refus qui ressemble à un bogue du mod. [ ]
258e. **La disquette de diagnostic.** Presser **Donner la disquette de
     diagnostic**, sans rien sélectionner si on veut (c'est un geste sur le sac et
     pas sur une machine). Attendu : une ligne sous la liste qui dit que
     `CeroSec DIAGNOSTICS 1.0` est dans l'inventaire, et dans le sac une disquette
     dont l'étiquette porte ce nom, imprimée (icône à deux lignes, infobulle
     **Printed label**) comme le reste des supports de la maison. L'éjecter après
     l'avoir insérée : elle ressort en portant toujours son nom ET son étiquette
     imprimée. Elle ne se trouve **jamais** en butin : le seul
     chemin vers elle est ce bouton. [ ]
258f. **La suite du shell, dans le jeu.** Insérer la disquette dans un ordinateur
     allumé. Attendu d'abord : elle entre. C'est le geste qui ne marchait pas, et
     il portait sur **toutes** les disquettes étiquetées, pas seulement celle-ci :
     écrire une étiquette appelle `setCustomName`, qui écrit une clé `customName`
     dans le modData de l'objet, et la fente refusait la disquette pour une clé que
     le jeu avait posée. Vérifier aussi qu'une disquette étiquetée à la main
     (menu de l'inventaire, `Écrire sur l'étiquette`) entre elle aussi. Puis
     s'asseoir devant, ouvrir une session et taper :

         mount /dev/fd0 /mnt
         sh /mnt/selftest.sh

     Attendu : une ligne par vérification échouée, puis `PASS 26 FAIL 0`, et rien
     d'autre. `echo $?` répond `0`. Vingt-six vérifications : `echo`, un tube,
     `cut`, `sort`, `wc`, `grep -c`, `more`, `tee`, `$(( ))` avec un quotient
     au-dessus de 2^31, `for`, `while`, `read` sur un tube, `mkdir` et `rm`, `test`
     sur des fichiers, `chmod`, `find`, l'horloge, `df`, l'étiquette dans `mount`,
     `ls -l /dev`, `dev`, `hostname`, `id`, `uptime`, `mkpasswd`, `sleep`. [ ]
258g. **Ce qu'elle laisse.** `cat /mnt/RESULTS.TXT` → la même sentence
     `CEROSEC SELFTEST PASS 26 FAIL 0`, avec les lignes d'échec en dessous s'il y
     en avait et s'il restait de la place sur la disquette. Puis `ls -l ~` :
     attendu, **aucun** fichier commençant par `st.`, la suite range ses fichiers
     de travail derrière elle. Et `df` : le disque n'a pas bougé. [ ]
258g-bis. **Un refus d'insertion se lit.** Avec la disquette encore dans le
     lecteur, en insérer une deuxième : attendu, `Éjectez d'abord la disquette.`
     au-dessus de la tête du survivant, et rien dans le lecteur qui ait changé.
     Puis éjecter, s'éloigner de l'ordinateur pendant que l'action joue : attendu,
     `Cet ordinateur n'est plus là.` Aucun geste sur le lecteur ne doit finir en
     silence : un refus qu'on ne lit pas est le bogue derrière le bogue. [ ]
258h. **Le crontab, à la main.** La suite ne fait pas ce tour-là et ne peut pas :
     un crontab ne s'écrit que par `crontab -e`, qui veut un terminal, et un script
     n'en a pas. Donc ici : `crontab -e`, écrire `0 4 * * * echo minuit`, sauver,
     puis `crontab -l`. Attendu : la ligne ressort telle quelle. `crontab -r` puis
     `crontab -l` → `no crontab for admin`. [ ]
258i. **Un refus de permission, à la main.** Même raison : la suite ne tourne que
     sous un seul compte, et `su` comme `sudo` posent une question qu'un script ne
     peut pas répondre. Donc : `touch secret.txt`, `chmod 600 secret.txt`, puis
     `su` vers un autre compte et `cat ~admin/secret.txt`. Attendu :
     `permission denied`. [ ]
259. **Deux fenêtres, une seule.** Ouvrir la fenêtre, puis la rouvrir par le menu
     d'un autre ordinateur → la première se ferme, il n'y en a jamais deux. [ ]
260. **Redimensionner.** Tirer le coin de la fenêtre, en grand PUIS en petit → la
     liste et les colonnes suivent le bord, la dernière colonne va toujours jusqu'au
     bord droit, les boutons restent sous la liste, le bloc de détail reste lisible
     en bas, et surtout : les en-têtes de colonnes ne remontent JAMAIS sur la rangée
     d'onglets, à aucune taille. Vérifier sur deux onglets différents. [ ]
261. **Fermer, et le rafraîchissement qui s'arrête.** Mettre
     `CeroSec.DEBUG = true`, ouvrir la fenêtre, la fermer par sa croix, et
     regarder la console pendant une minute. Attendu : plus rien de la fenêtre,
     elle ne demande plus rien au serveur. (C'est la fuite que
     `tests/debug_ui_test.lua` garde, mais elle se voit aussi comme ça.) [ ]
262. **Le drapeau.** Mettre `CeroSec.DEV_DEBUG_MENU = false` et
     `CeroSec.DEV_MANUAL_MENU = false`, recharger la partie. Attendu : plus de
     sous-menu **CeroSec (dev)** du tout sur le menu d'un ordinateur. Relancer le
     jeu avec `-debug` : le sous-menu revient avec **Fenêtre de débogage** dedans
     et **rien** d'autre, le manuel se trouve ou ne se lit pas. [ ]

## Y. Les outils qui manquaient, et les noms qui s'en vont (fidélité A)

263. **`more`, le pagineur.** `admin` : `edit long.txt` et y mettre une
     quarantaine de lignes numérotées (ou `ls -l /bin > long.txt`), sauver.
     `more long.txt` → dix-neuf lignes puis `--More--(NN%)` sur la vingtième.
     Taper une **espace** puis Entrée → l'écran suivant, et le pourcentage a
     monté. Entrée **seule** → une seule ligne de plus. `q` puis Entrée →
     l'invite revient, rien de plus n'est affiché. [ ]
264. **Échap à l'invite du pagineur.** `more long.txt`, puis Échap → `^C` après
     le `--More--`, la fenêtre reste ouverte et le shell revient. [ ]
265. **`more` dans un tube, en dernier.** `ls -l /bin | more` → même chose, une
     page à la fois. Puis `ls /bin | more | wc -l` → **un seul nombre** et
     aucune question : quand sa sortie n'est pas un écran, `more` recopie sans
     pagineur, ce que fait le vrai. Et `more long.txt > copie.txt` → rien à
     l'écran, `wc -l copie.txt` compte tout le fichier. [ ]
266. **`more` sans personne devant.** `more long.txt &` → `more: not a
     terminal`. Même chose depuis une ligne de `crontab` : le courrier dit
     `more: not a terminal`. [ ]
267. **`find`.** `mkdir -p` n'existe pas : faire `mkdir arbre`,
     `mkdir arbre/dedans`, `touch arbre/haut.txt`, `touch arbre/dedans/bas.txt`,
     `touch arbre/dedans/bas.log`. Puis `find arbre` → cinq lignes, le dossier
     **avant** ce qu'il contient. `find arbre -type d` → deux. `find arbre -name
     "*.txt"` → deux. `find arbre -name "bas.*"` → deux. `find arbre -name
     "*.txt" -type d` → **rien** (les deux tests doivent être vrais).
     `find arbre -print` → comme `find arbre`. `find` tout seul → la ligne
     d'usage. [ ]
268. **`find` et ce qu'il ne peut pas lire.** `admin`, `find /` → il nomme
     `/root` et dit ensuite `find: /root: permission denied`, et la marche
     continue. La commande est **en échec** : `find / | wc -l` affiche donc les
     chemins au lieu de les compter, exactement comme `cat bon mauvais | wc -l`.
     En `root`, `find / -name "*.txt"` marche partout. [ ]
269. **`cut`.** `cut -d : -f 1 /etc/passwd` → `root` puis `admin`.
     `cut -c 1-8 /etc/passwd` → les huit premiers caractères de chaque ligne.
     `echo un,deux,trois > c.txt` puis `cut -d , -f 1,3 c.txt` → `un,trois`
     (le séparateur revient **entre** les champs gardés), `cut -d , -f 2- c.txt`
     → `deux,trois`. `echo sansvirgule > s.txt` puis `cut -d , -f 2 s.txt` →
     `sansvirgule`, la ligne **entière** : elle n'a pas de champ à découper.
     `cut -c x c.txt` → `cut: x: invalid list`. [ ]
270. **`tr`.** `cat c.txt | tr a-z A-Z` → `UN,DEUX,TROIS`.
     `cat c.txt | tr -d ,` → `undeuxtrois`. `cat c.txt | tr a-z x` → que des
     `x` sauf les virgules (le dernier caractère du deuxième jeu sert pour tout
     le reste). `tr a-z A-Z` **sans tube** → la ligne d'usage : `tr` ne lit que
     son entrée standard, comme tous les `tr`. `cat c.txt | tr z-a b` →
     `tr: z-a: invalid set`. [ ]
271. **`tee`.** `ls /bin | tee liste | wc -l` → un nombre à l'écran **et**
     `wc -l liste` donne le même. `ls /etc | tee liste` → `liste` est
     **remplacé**. `ls /etc | tee -a liste` → il est doublé, sans ligne vide au
     milieu. `cat c.txt | tee /etc/motd` en `admin` →
     `tee: /etc/motd: permission denied`. [ ]
272. **`uptime` et `w`.** `uptime` → une ligne de la forme
     ` 3:14PM  up 2 days,  4:03,  1 user,  load 0.00 0.00 0.00`, tenant dans les
     soixante colonnes. Lancer `sleep 300 &` quatre fois, attendre une dizaine
     de secondes, `uptime` → la première moyenne monte (elle compte les travaux
     prêts à tourner) ; `kill` les quatre, attendre une minute, elle redescend.
     `w` → la même ligne, puis
     `USER     TTY      FROM        LOGIN@ IDLE  WHAT` et une ligne par session.
     `FROM` est `-` au clavier ; `WHAT` est `w` lui-même. `uptime -a` → la ligne
     d'usage. [ ]
273. **`w` avec une session venue du réseau.** Depuis une deuxième machine,
     `rlogin <hôte>` et se connecter. Sur la première, `w` → **deux** lignes :
     la console et un `ttyp0` dont `FROM` est le nom de la machine d'en face, et
     la première ligne dit `2 users`. Laisser la session distante tranquille une
     minute : sa colonne `IDLE` monte. [ ]
274. **Les vieux noms ont disparu, et la mise à niveau les a effacés.** Sur une
     machine **d'une sauvegarde antérieure à cette version** (ou après
     `sudo rm /bin/hash` sur une neuve, ce qui est la même absence) : `adduser`,
     `deluser`, `gpasswd`, `hash`, `readlink`, `restart` et `write` répondent
     tous `command not found`, et `ls /bin` n'en montre aucun. `help` non plus.
     Et ce qu'il faut taper à la place : `useradd`, `userdel`, `usermod -G`,
     `mkpasswd`, `ls -l` pour lire la flèche d'un lien, `reboot`, et
     `echo texte > fichier`. [ ]
275. **La page des écarts.** Ouvrir le **Guide de l'utilisateur** (volume 1),
     chapitre 1, et tourner jusqu'à **What is not Unix here** : elle nomme
     `help`, `dev`, `mkpasswd`, `edit`, `sudo`, `jobs`, `more` et dit où `hash`,
     `readlink`, `restart` et `write` sont partis. Rien d'autre sur la machine
     ne doit surprendre quelqu'un qui a déjà utilisé un Unix. [ ]
276. **`jobs` appartient à la machine.** `admin` : `sleep 300 &`. Puis `exit`,
     se reconnecter (ou se connecter en `bob` depuis une autre fenêtre sur la
     **même** machine) et taper `jobs` → le travail de `admin` est là, avec son
     crochet. `kill %1` marche. `man jobs` dit
     `list the background jobs on this machine`. [ ]

## Z. La sauvegarde d'avant la mise à jour (migrations)

C'est la seule étape du parcours qui demande **deux** versions du mod : la suite
headless prouve la chaîne sur des photos de sauvegardes
(`tests/fixtures/state-v<N>.lua`, voir [ARCHITECTURE.md](ARCHITECTURE.md#migration)),
mais ce qu'elle ne peut pas prouver, c'est que le jeu redonne bien à la machine la
table qu'il avait écrite.

277. **Une machine d'avant la mise à jour garde tout.** Avec la version
     **précédente** du mod : allumer un ordinateur, se connecter en `admin`,
     `mkdir travail`, `echo "garde-moi" > travail/notes.txt`, ajouter un compte
     (`sudo useradd sam` puis `sudo passwd sam`, mot de passe `letmein`), mettre
     une disquette dans le lecteur et écrire une étiquette dessus. Quitter la
     partie proprement (**Enregistrer et quitter**, pas Alt-F4 : la table de
     l'objet part sur un enregistrement). Installer cette version-ci, recharger
     la **même** sauvegarde, revenir devant la même machine, l'allumer :
     - le BIOS compte sa mémoire et l'écran finit sur `login:`, **pas** sur
       `No operating system found.` ;
     - `admin` se connecte avec son mot de passe, `cat travail/notes.txt` dit
       `garde-moi` ;
     - `sam` se connecte avec `letmein` ;
     - dans la fenêtre de débogage (section X), la ligne de détail de cette
       machine montre `os v` au **nouveau** numéro de forme et `sysv` au numéro
       de contenu de cette version : rien dans le jeu normal ne les dit, et
       c'est là qu'on les constate au lieu de les supposer ;
     - `mount /dev/fd0 /mnt` monte la disquette et `df` montre l'étiquette
       écrite avant la mise à jour ;
     - les modules vissés sur une porte avant la mise à jour répondent encore :
       `dev` les liste, et en `root` (`su root`)
       `echo open > /dev/door0` ouvre la porte pour de bon (comme à l'étape 231) ;
     - et ce que la mise à jour AJOUTE est là : `ls /usr/local/bin` répond (vide),
       sans `no such file`, et `echo $PATH` dit `/bin:/usr/local/bin`, une
       machine d'une vieille sauvegarde gagne la chaîne au chargement. Si on
       avait fabriqué soi-même un `/usr` sous l'ancienne version, il est intact,
       avec ce qu'il y avait dedans. [ ]

## AA. Ce qui est déjà sur les machines (contenu du monde, 1re partie)

Tout ce qui suit demande l'option bac à sable **Machines et disquettes garnies**
sur **Activé** (c'est le défaut). Les étapes 285 et 286 la mettent à l'arrêt pour
prouver le contrôle : une machine nue, comme avant ce changement.

Les mots de passe de cette section sont **propres à la sauvegarde**. Rien de ce
qui est écrit ici n'est un mot de passe à recopier : ce qui compte est que celui
qu'on lit sur le papier soit celui que la machine demande.

278. **Un ordinateur jamais allumé dans un bureau.** Trouver un bâtiment que la
     carte a marqué comme bureau (une zone nommée, ou une pièce que le jeu
     appelle `office`) avec un ordinateur vanilla dedans, **jamais touché de la
     partie**. L'allumer :
     - le BIOS compte sa mémoire, puis l'écran finit sur `login:` ;
     - l'invite ne dit **pas** `ksp-` : le nom de la machine commence par le mot
       du commerce (`acct-`), et la queue reste les coordonnées ;
     - se connecter sur un compte **ouvert** (un des noms trouvés plus bas) : le
       message d'accueil n'est pas celui d'usine, il nomme l'entreprise ;
     - `cat /etc/passwd` montre **plus de deux** comptes : `root` et des gens avec
       des noms de personnes. Et **pas** `admin` : une machine que quelqu'un avait
       installée a rendu le compte d'usine (voir l'étape 330) ;
     - `cat /var/log/messages` montre une semaine de lignes datées **avant** le
       premier jour de la partie (juillet 1993 sur une partie par défaut), chaque
       ligne tient dans les 60 colonnes ;
     - `ls -l /home` montre un répertoire par personne, à son nom ;
     - `cat /var/mail/root` (en root, après l'étape 280) montre un courrier non lu ;
     - `su root` avec un mot de passe vide est **refusé** : `root` est fermé. [ ]

279. **Le papier dans le tiroir.** Dans le **même** commerce, fouiller les
     bureaux, comptoirs, classeurs et casiers jusqu'à trouver un objet dont le nom
     dans l'inventaire est `Sticky note (root)`.
     - l'objet est une note jaune, il pèse ce que pèse une feuille de papier ;
     - le nom ne donne **que** le compte : le mot de passe n'est pas lisible dans
       la liste, il faut ouvrir la note ;
     - **un seul** papier `root` par commerce : les autres tiroirs du même
       commerce n'en ont pas d'autre ;
     - rien n'est jamais **par terre** : le papier est toujours dans un contenant ;
     - un bureau d'un **autre** bâtiment donne un autre mot. [ ]

279b. **La note est du vrai papier : la lire.** La prendre dans son sac, clic
     droit dessus. Sans stylo sur soi, l'entrée du menu est *Lire* ; avec un stylo
     ou un crayon dans le sac, c'est *Écrire*. Ouvrir : la fenêtre du jeu montre
     une page qui dit `Sticky note: root / <mot>`, dans la police du jeu. C'est ce
     mot-là qu'on tape à l'étape 280.
     - la note garde son icône de note jaune dans la fenêtre comme dans le sac ;
     - la fenêtre ne coûte **pas** des heures de jeu : ce n'est pas la lecture
       longue d'un livre, c'est une page qu'on ouvre et qu'on referme ;
     - dans le noir, le menu refuse et dit pourquoi (règle vanilla). [ ]

279c. **Écrire dessus et l'effacer.** Avec un stylo dans le sac, ouvrir la note :
     le texte est modifiable. Taper autre chose par-dessus, **OK**, rouvrir : c'est
     le nouveau texte qui est là. Rouvrir, cliquer la **poubelle** (le bouton sous
     la zone de texte) : la page se vide ; écrire de nouveau, **OK**. Une note
     trouvée n'est jamais verrouillée : elle appartient à celui qui la ramasse.
     (Le mot de passe de la machine, lui, ne change pas : c'est du papier qu'on
     réécrit, pas la machine.) [ ]

279d. **La brûler.** Poser la note au sol près d'un feu de camp ou la garder sur
     soi devant une cheminée / un barbecue : clic droit sur le foyer, la note est
     dans la liste du combustible comme n'importe quelle feuille de papier, et
     elle sert aussi d'allume-feu. La brûler : elle disparaît, le feu tient un peu
     plus longtemps. [ ]

279e. **Les vieilles notes d'une sauvegarde d'avant.** Sur une sauvegarde
     commencée **avant** cette mise à jour, où un papier `Sticky note: root / <mot>`
     avait déjà été trouvé : il est **toujours là**, avec le même nom qu'avant et le
     même mot de passe dessus, et ce mot ouvre toujours sa machine. Il ne se lit
     pas et ne brûle pas, c'est l'ancien objet, et il n'a pas été touché. Les
     notes **neuves** de la même partie, elles, sont du papier. [ ]

280. **Le mot du papier ouvre la machine.** Revenir à l'ordinateur de l'étape 278,
     `su root`, taper le mot lu sur le papier : ça passe, l'invite devient
     `root@...#`. C'est l'assertion centrale du changement : le papier et la machine
     ne se parlent jamais, ils calculent tous les deux la même réponse. [ ]

281. **Le papier trouvé AVANT d'allumer la machine.** Dans un autre commerce
     jamais visité : fouiller d'abord (trouver la note), **puis** allumer
     l'ordinateur pour la première fois. Le mot de passe de la note est celui que
     la machine demande. L'ordre n'a aucune importance, et c'est ce qu'il faut
     constater. [ ]

282. **Le papier dans la poche d'un mort.** Tuer les zombies **à l'intérieur**
     d'un commerce garni et fouiller les corps. Environ un sur vingt porte un
     objet nommé `Sticky note (<compte>)` dont la page dit `Note: <compte> / <mot>`.
     - le compte nommé n'est **jamais** `root`, ni sur la page ni sur le nom ;
     - `su <compte>` sur la machine du même commerce, avec ce mot : ça passe ;
     - un zombie tué **dehors** (rue, stationnement, champ) n'en porte jamais. [ ]

282b. **Pas d'ordinateur, pas de papier.** Le rapport de jeu : « un papier avec un
     mot de passe dans une maison qui n'a aucun ordinateur ». Trouver une **maison**
     avec une pièce que la carte appelle `office` (un bureau à l'étage, un coin
     travail) et **aucun ordinateur vanilla** dans tout le bâtiment. Fouiller les
     bureaux, commodes, tables de chevet et classeurs de cette maison :
     - **aucun** papier `Sticky note (root)` nulle part ;
     - tuer les zombies à l'intérieur : **aucune** note `Sticky note (<compte>)`
       dans leurs poches non plus.
     Puis **poser un ordinateur** ramassé ailleurs dans n'importe quelle pièce de
     cette maison et fouiller de **nouveaux** contenants du même bâtiment : cette
     fois le papier `root` finit par sortir. (Le mot dessus n'ouvre pas la machine
     qu'on vient de poser : une machine portée à la main garde le disque qu'elle
     avait et n'est jamais garnie, étape 250c. Il ouvre celle qu'on trouverait
     déjà debout dans ce bâtiment.)

     L'autre moitié de la règle, à constater dans une **maison avec un coin travail
     ET un ordinateur vanilla jamais touché** : le papier est bien dans un tiroir, et
     son mot de passe ouvre cette machine (étape 280). Un mot de passe sur un papier
     appartient toujours à une machine qui est là. [ ]

283. **Une disquette avec quelque chose dessus.** Fouiller les endroits à
     disquettes (bureau de cybercafé, classeur, étagère d'électronique) jusqu'à
     en trouver une dont le nom dans l'inventaire n'est pas le nom ordinaire d'une
     disquette mais une **étiquette** en majuscules (`UTILITIES`). (Le nom
     ordinaire est encore en anglais en français : `ItemName.json` FR ne traduit
     pas les quatre disquettes, ce qui est d'avant ce changement.)
     - la mettre dans le lecteur, `mount /dev/fd0 /mnt`, `ls /mnt` : il y a un
       `README.TXT` et au moins un fichier `.sh` ;
     - `cat /mnt/README.TXT` : le texte nomme les fichiers qui sont à côté, et
       rien d'autre ;
     - `df` montre l'étiquette de la disquette ;
     - suivre le README : `cp /mnt/lights.sh ~/bin`, puis `lights.sh` sans
       argument dit comment on l'utilise, et avec le nom d'une lumière câblée
       (section W) l'éteint pour de bon ;
     - la **plupart** des disquettes ramassées sont encore vierges : en ramasser
       une dizaine et constater qu'au plus une ou deux portent une étiquette. [ ]

284. **Une machine déjà utilisée n'est jamais regarnie.** Sur l'ordinateur de
     l'étape 278 : `mkdir ~/travail`, `echo garde-moi > ~/travail/n.txt`, éteindre
     avec l'interrupteur, rallumer. Les comptes, le nom de la machine, le journal
     et le fichier écrit sont exactement les mêmes : rien n'a été réécrit. [ ]

285. **L'option à l'arrêt : la machine nue.** Nouvelle partie, **Machines et
     disquettes garnies** sur **Désactivé**. Allumer un ordinateur dans un bureau :
     - l'invite dit `ksp-` et les coordonnées ;
     - `cat /etc/passwd` montre **exactement deux** lignes, `root` et `admin` ;
     - `su root` avec un mot de passe **vide** passe ;
     - `cat /var/log/messages` dit `cat: no such file` ;
     - fouiller les tiroirs du même bureau : aucun papier ;
     - les disquettes ramassées sont toutes vierges. [ ]

286. **Une machine hors de tout bâtiment.** Poser un ordinateur dans une base
     construite par le joueur (aucun bâtiment de la carte dessous), l'allumer avec
     l'option **activée** : deux comptes, `root` ouvert, aucun journal, comme une
     machine nue. C'est le même refus que pour l'adresse et la ligne
     téléphonique : pas de bâtiment, pas de commerce. [ ]

287. **Une autre sauvegarde, d'autres mots de passe.** Créer une **deuxième**
     partie sur la même carte, aller au **même** commerce que l'étape 278, y
     trouver la note et allumer la machine :
     - le mot de passe sur la note n'est **pas** celui de la première partie ;
     - il ouvre quand même la machine de cette partie-là ;
     - le mot de passe de la première partie n'ouvre **pas** cette machine. [ ]

## AB. Les programmes, les disquettes et les huit commerces (2e partie)

Même condition qu'à la section AA : option bac à sable **Machines et disquettes
garnies** sur **Activé**, qui est le défaut. Les mots de passe sont propres à la
sauvegarde ; rien de ce qui est écrit ici n'est un mot de passe à recopier.

288. **Un ordinateur de poste de police.** Trouver un poste de police (zone nommée
     `Police...`, ou un bâtiment dont le jeu nomme une pièce `police`) avec un
     ordinateur vanilla jamais touché. L'allumer :
     - l'invite commence par `disp-` et la queue reste les coordonnées ;
     - le message d'accueil dit `KNOX COUNTY SHERIFF -- DISPATCH` ;
     - `cat /etc/passwd` montre un compte nommé **`dispatch`** en plus de `root` et
       de deux personnes, et aucun `admin` ;
     - fouiller les tiroirs, comptoirs et casiers du **même** poste jusqu'à
       trouver `Sticky note (root)`, l'ouvrir pour lire le mot, puis `su root`
       avec ce mot : ça passe ;
     - `cat /var/log/dispatch` montre huit ou neuf lignes de juillet et la
       dernière s'arrête **au milieu d'une ligne**, au petit matin du 9 (le texte
       exact dépend de la premises : il y en a trois versions, voir l'étape 310) ;
     - si le bureau garni est celui de `dispatch`, `cat /home/dispatch/bolo.txt` se
       lit en entier, aucune ligne ne dépasse le bord droit ; sinon c'est un autre
       compte qui a des fichiers (étape 302) et `bolo.txt` est sur l'autre machine
       du poste ;
     - `crontab -l -u dispatch` n'existe pas ; faire `sudo cat
       /var/spool/cron/dispatch` → **sur la machine de `dispatch`**, une ligne à
       `0 22 * * *` qui appelle `locks.sh` ; sur la machine d'un autre compte, pas
       de crontab pour `dispatch`, le travail appartient au bureau où il se fait
       (étape 302). [ ]

289. **Le script du poste marche vraiment.** Toujours sur la machine de l'étape
     288, connecté sur le compte `dispatch` (mot de passe dérivé, voir
     l'étape 288 ; ou en root) :
     - `ls ~/bin` montre `locks.sh` ;
     - `cat ~/bin/locks.sh` se lit : chaque ligne tient dans les 60 colonnes ;
     - `sh ~/bin/locks.sh` **sans argument** dit comment on l'utilise et ne
       prétend pas avoir réussi ;
     - poser une gâche électrique (section W) sur une porte de la pièce, puis
       `dev lock` pour lire son numéro, puis `sh ~/bin/locks.sh lock lock0` → la
       porte se verrouille pour de bon et le script réaffiche `lock0 locked` ;
     - `sh ~/bin/locks.sh unlock lock0` la déverrouille. [ ]

290. **Le journal du magasin s'éteint tout seul.** Dans un magasin (zone
     `...Store`, `...Shop` ou `...Market`), machine jamais touchée dont le bureau
     garni est celui du patron (sinon essayer l'autre machine du magasin, ou un
     autre magasin) : l'invite dit
     `till-`, `cat ~/inventory.txt` se lit, et `sh ~/bin/total.sh prices.txt 2`
     additionne la colonne et répond un nombre. Câbler un relais sur un
     interrupteur (section W), noter son numéro avec `dev light`, mettre l'heure
     de la partie juste avant 21:00 et attendre : à 21:00 la lumière s'éteint
     sans que personne ne tape rien, et `mail` sur le compte du patron montre ce
     que la ligne de cron a imprimé. [ ]

291. **Le poste militaire n'a pas de compte ordinaire.** Trouver un bâtiment que
     la carte nomme `Military` ou `Army` (le camp, un poste de contrôle) avec un
     ordinateur dedans :
     - l'invite dit `post-` ;
     - le message d'accueil finit par `KEEP OUT.` ;
     - `cat /etc/passwd` montre **exactement** `root` et personne d'autre : aucun
       nom de personne, et pas `admin` non plus ;
     - `su root` avec un mot de passe vide est refusé ;
     - fouiller les tiroirs du même bâtiment jusqu'au papier `root`, puis
       `su root` avec ce mot ;
     - `ls /root` montre `memo-01.txt`, `memo-02.txt`, `memo-03.txt`, et le
       troisième dit que la route du sud était ouverte le 8 juillet ;
     - tuer des zombies **à l'intérieur** de ce bâtiment : aucun ne porte de
       note, jamais, il n'y a pas de compte ordinaire à nommer. [ ]

292. **La machine du vendeur porte toute la bibliothèque.** Cette étape demande
     une carte de mod avec une zone nommée `CeroSec...` : la carte livrée avec le
     jeu n'en a aucune. À défaut, la faire en mode debug en nommant une zone.
     Machine allumée : `ls /usr/local/src` montre quatorze `.sh` et un `CHANGES`,
     et `sh /usr/local/src/sweep.sh /etc` liste les fichiers de `/etc` et les
     compte. [ ]

293. **Une disquette BBS LIST donne les numéros de VOTRE région.** Fouiller les
     endroits à disquettes jusqu'à en trouver une étiquetée `BBS LIST` (3 sur
     100 ; le débug peut en faire apparaître).
     - **avant de l'insérer**, ramasser un annuaire (`Phonebook`) dans la même
       ville et l'ouvrir : noter deux ou trois numéros de l'exchange ;
     - insérer la disquette dans un ordinateur de cette ville, `mount /dev/fd0
       /mnt`, `cat /mnt/NUMBERS.TXT` → une liste de noms de BBS avec des numéros,
       et l'en-tête nomme le même exchange que l'annuaire ;
     - **au moins un** des numéros de la liste est un numéro que l'annuaire
       imprime aussi ;
     - `cu <ce numéro>` : si un ordinateur de ce commerce est allumé, le modem
       répond `CONNECT 2400` ; sinon `NO CARRIER` au bout d'une quinzaine de
       secondes ;
     - `cat /mnt/CALLS.TXT` montre des indicatifs, et le fichier dit lui-même
       qu'un indicatif ne se compose pas. [ ]

294. **La liste est imprimée UNE fois.** Suite de l'étape 293 : éjecter la
     disquette, traverser la carte jusqu'à une autre ville (un autre exchange,
     que l'annuaire local confirme), insérer la **même** disquette dans une
     machine là-bas et relire `/mnt/NUMBERS.TXT` → **exactement** la même liste et
     le même exchange que la première fois. La disquette est l'annuaire de là où
     on l'a utilisée d'abord, pas de là où on est. [ ]

295. **Ce qu'on a écrit dessus reste.** Suite : `edit /mnt/NUMBERS.TXT`, effacer
     tout et taper une ligne à soi, sauver, éjecter, insérer dans une troisième
     machine → la ligne est toujours là. Rien ne la réécrit, jamais. [ ]

296. **GUESS.SH se joue.** Trouver ou faire apparaître une disquette `GAMES`,
     l'insérer, `mount /dev/fd0 /mnt`, `cat /mnt/README.TXT`, puis
     `sh /mnt/guess.sh 100` :
     - il annonce un nombre entre 1 et 100 et huit essais ;
     - taper `50`, il répond `Higher.` ou `Lower.` ;
     - continuer en coupant l'intervalle en deux : il finit par dire
       `That is it.` avec le nombre et le nombre d'essais ;
     - taper une lettre au lieu d'un nombre → `Digits only.` et l'essai ne compte
       pas ; taper Entrée à vide → `A number, please.` ;
     - relancer le jeu **la même minute de jeu** : le nombre est le même (il
       vient des secondes de l'horloge). Attendre une minute et relancer : il
       change. [ ]

297. **HANGMAN.SH se joue.** Même disquette :
     `sh /mnt/hangman.sh /mnt/WORDS.TXT` → une rangée de points et
     `6 wrong left`. Taper `e` : soit les lettres apparaissent **en capitales**
     dans le mot, soit le compteur descend. Continuer jusqu'à gagner (le mot
     s'affiche en entier suivi de `You have it.`) ou perdre (`Out of guesses.`
     et le mot). [ ]

298. **ADVENTURE.SH va jusqu'au bout.** Même disquette, `sh /mnt/adventure.sh` :
     - il annonce `THE OLD WATERWORKS` et la liste des mots ;
     - `n`, `e` → le couloir ; `s` tout de suite → `The stair door is locked.` ;
     - `n`, `take` → la clé ; `s`, `s` → la salle des pompes et `THE END.`, et le
       script se termine (l'invite revient) ;
     - relancer et taper `quit` n'importe où → il sort proprement ;
     - taper n'importe quel autre mot → `I do not know how to <mot>.` [ ]

299. **La disquette du vendeur enseigne et n'exécute rien.** Trouver ou faire
     apparaître `CEROSEC OS 1.0 DIST`, l'insérer, la monter :
     - `ls /mnt` montre `README.TXT`, `INSTALL.TXT`, `MAN`, et trois `.sh` ;
     - `ls /mnt/MAN` montre six pages ; `cat /mnt/MAN/CU.TXT` se lit ;
     - `cat /mnt/INSTALL.TXT` explique la réparation par le BIOS et dit qu'il n'y
       a rien sur la disquette qui puisse écrire sur un disque système ;
     - vérifier que c'est vrai : il n'y a **aucun** programme sur cette disquette
       qui touche `/bin` ou `/etc`. [ ]

300. **Une disquette BACKUP raconte quelqu'un.** Trouver ou faire apparaître
     `BACKUP`, la monter, lire les quatre fichiers : la dernière entrée du
     journal est datée du **8 juillet**, dans les trois versions, et
     `FAMILY.TXT` dit lui-même que ses numéros ne sont pas ceux de votre
     exchange. Aucune accolade nulle part : les prénoms du journal et des
     lettres sont de vrais prénoms. [ ]

301. **La disquette WARDIALER dit pourquoi il n'y en a pas.** Monter la
     disquette `WARDIALER`, lire `README.TXT` : il dit qu'un script ne peut pas
     conduire `cu`. Le vérifier soi-même : `edit essai.sh`, écrire deux lignes,
     `cu 418-0100` puis `echo apres`, `sh essai.sh` → la deuxième ligne ne
     s'exécute **jamais**. Puis mettre la même ligne dans un crontab
     (`crontab -e`, `* * * * * cu 418-0100`) et attendre une minute :
     `mail` montre `cu: not a terminal`. [ ]

301b. **Une disquette LEDGER et le total de la semaine.** Trouver ou faire
     apparaître `LEDGER` (2 sur 100), l'insérer, `mount /dev/fd0 /mnt`.
     - `cat /mnt/README.TXT` nomme `SALES.TXT`, `SUPPLIERS.TXT` et `total.sh`,
       et dit que tout est en **cents** ;
     - `cat /mnt/SALES.TXT` → sept lignes, une par jour, trois colonnes
       séparées par des deux-points ;
     - `cd /mnt` puis `sh /mnt/total.sh SALES.TXT 3` → la ligne
       `column 3 of SALES.TXT adds up to 158244`. C'est la semaine en cents,
       soit 1582,44 $ : le faire à la main sur les sept lignes pour vérifier ;
     - `sh /mnt/total.sh SALES.TXT 2` → `346`, les tickets ;
     - le script n'est PAS copié sur la machine : il tourne depuis `/mnt`. [ ]

301c. **Une disquette PERSONAL, et sa dernière lettre est datée.** Trouver ou
     faire apparaître `PERSONAL` (2 sur 100), la monter.
     - `cat /mnt/README.TXT` nomme les cinq fichiers et rien d'autre ;
     - `cat /mnt/LETTERS.TXT` → trois lettres jamais envoyées, chacune avec sa
       date, et la **dernière** est datée du **8 ou du 9 juillet** ;
     - `cat /mnt/RECIPE.TXT`, `cat /mnt/POEM.TXT`, `cat /mnt/TODO.TXT`,
       `cat /mnt/NUMBERS.TXT` se lisent et aucun ne montre d'accolade
       (`{owner}`, `{staff1}`) : les prénoms sont dedans pour de vrai. [ ]

301d. **Une disquette RADIO LOG à côté de `MHEARD`.** Trouver ou faire
     apparaître `RADIO LOG` (1 sur 100), la monter sur une machine **qui a un
     poste radio câblé** (`ls /dev` montre `radio0`).
     - `cat /mnt/HEARD.LOG` → une douzaine de lignes : jour, heure, indicatif ;
     - `cat /mnt/MYCALL.TXT` → un indicatif, et `cat /mnt/NETS.TXT` → l'horaire
       des nets ;
     - `cu -l /dev/radio0` puis `MHEARD` dans la boîte → la liste des stations
       entendues **depuis l'allumage**, donc plus courte que le fichier, et sur
       une machine qui vient de démarrer elle est vide. C'est ce que le
       `README.TXT` de la disquette annonce. Échap pour récupérer l'écran ;
     - chaque indicatif du fichier est de la forme qu'une station d'ici porte :
       `K`, `N` ou `W`, une lettre en option, le chiffre **4**, puis deux ou
       trois lettres. [ ]

301e. **La même étiquette, trois histoires.** Faire apparaître en mode débug
     **six** disquettes d'un coup et regarder les étiquettes : sur six tirages,
     deux disquettes de la même étiquette narrative (`BACKUP`, `LEDGER`,
     `PERSONAL`, `RADIO LOG`) sortent souvent. En monter deux de la **même**
     étiquette l'une après l'autre et comparer les fichiers : environ deux fois
     sur trois ce ne sont pas les mêmes textes et pas les mêmes prénoms. Une
     `UTILITIES` et une `GAMES`, elles, sont identiques mot pour mot. [ ]

301f. **Le choix ne se refait jamais.** Suite de l'étape 301e : noter deux
     phrases d'une disquette narrative, `umount /mnt`, éjecter, **sauvegarder et
     recharger la partie**, remettre la même disquette dans une **autre**
     machine → mot pour mot le même texte et les mêmes prénoms. La disquette ne
     se réécrit jamais sous le joueur. [ ]

## AC. Un bureau, deux personnes, et la semaine d'avant (3e partie)

Même condition qu'aux sections AA et AB : option bac à sable **Machines et
disquettes garnies** sur **Activé**. Les mots de passe et les noms sont propres à la
sauvegarde ; rien de ce qui est écrit ici n'est un nom ou un mot de passe à recopier.

302. **Deux ordinateurs du même bureau sont deux bureaux différents.** Trouver un
     bâtiment avec **deux** ordinateurs vanilla jamais touchés dans la même
     premises (même zone nommée, ou même bâtiment sans zone). Allumer les deux :
     - `cat /etc/passwd` sur les deux → **exactement** les mêmes comptes, dans le
       même ordre ;
     - sur la machine A, `ls /home/*` → **un seul** des dossiers personnels
       contient des fichiers ; les autres ne contiennent que des fichiers en point
       (`ls -a` les montre) ;
     - sur la machine B, c'est **un autre** compte qui a les fichiers ;
     - se connecter au même compte sur les deux avec le même mot de passe (le
       papier du tiroir, ou la note dans une poche) : ça passe des deux côtés ;
     - `su root` avec le mot de passe du papier : ça passe des deux côtés aussi, le
       papier est celui de la premises. [ ]

303. **Ce qu'il a tapé.** Sur la machine du propriétaire (celle dont le dossier
     personnel est garni), connecté sur ce compte :
     - `ls -a` montre `.sh_history` ;
     - `wc -l .sh_history` → entre 12 et 30 ;
     - `cat .sh_history` se lit en entier, aucune ligne ne dépasse le bord droit ;
     - les dernières lignes sont le matin du 9 : `mail`, `cat /var/log/messages`,
       `who`, `date`, parfois un `cu 555-XXXX`, puis ce qu'il a fermé, puis
       `shutdown -h now` ;
     - appuyer sur **Haut** à l'invite : les mêmes lignes remontent, dans l'ordre,
       de la plus récente à la plus ancienne ;
     - `history` les affiche numérotées ;
     - prendre **n'importe quelle** ligne de ce fichier et la retaper : aucune ne
       répond `command not found` (les fautes qu'il a faites sont des fautes de
       nom de fichier, pas de commande). [ ]

304. **Qui s'est assis là.** Toujours sur la même machine : `last`
     - affiche les connexions de la quinzaine, la plus récente en haut ;
     - le compte du propriétaire revient plus souvent que les autres ;
     - chaque ligne porte une durée entre parenthèses, sauf au plus une ;
     - la dernière ligne du bloc est `wtmp begins <date>` ;
     - **toutes** les dates sont antérieures au jour où la partie commence ;
     - `last <compte>` d'un des autres employés → ses propres connexions, et lui
       aussi a un `.sh_history` court dans son dossier (deux ou trois lignes). [ ]

305. **Le courrier de la semaine.** Connecté sur le compte du propriétaire :
     `mail`
     - de trois à six messages, le plus ancien en premier ;
     - chacun porte `From:`, `To:` (son propre nom), `Date:` et `Subject:` ;
     - toutes les dates tombent dans la semaine qui précède le début de la partie ;
     - il y a du travail, de la famille, quelqu'un qui ne rentre pas, le comté ou
       la radio à propos des routes, et le dernier message n'a jamais reçu de
       réponse ;
     - relancer `mail` tout de suite après → `No mail for <compte>` : le lire le
       vide, comme sur une vraie machine ;
     - se connecter sur **un autre** compte de la même premises et faire `mail` →
       lui aussi a reçu un message, même si son dossier personnel est vide. [ ]

306. **Une machine trouvée déjà ouverte.** Allumer des ordinateurs jamais touchés
     jusqu'à en trouver un qui, après les lignes du BIOS et le message d'accueil,
     affiche directement une **invite de shell** au lieu de `login:` (environ un
     sur quatre) :
     - aucun mot de passe n'est demandé ;
     - `whoami` donne un compte de la premises, pas `admin` ;
     - `pwd` donne son dossier personnel ;
     - `echo $HOME` et `echo $PATH` répondent, la session est complète ;
     - `last` montre `still logged in` en face de son nom, une seule fois ;
     - `cat .sh_history` **ne finit pas** par `shutdown -h now` ;
     - `exit` → l'écran retombe sur `login:` et il faudra son mot de passe pour
       revenir. [ ]

306a. **Et le manuel le dit.** Toujours sur cette machine (ou n'importe laquelle) :
     ouvrir le Volume 1, chapitre 1, la page **What is not Unix here, and the end
     of the list** → le dernier paragraphe dit qu'une machine qui n'a jamais été
     déconnectée revient à cette invite quand le courant revient, et qu'un vrai
     Unix redemanderait. C'est la seule chose déclarée sur cette page qui n'est pas
     une commande. [ ]

307. **Le poste militaire n'est jamais laissé ouvert.** Allumer tous les
     ordinateurs de poste militaire qu'on trouve : aucun n'affiche jamais une
     invite de shell au démarrage, toujours `login:`. [ ]

308. **Le journal a les nuits de juillet dedans.** Sur n'importe quelle machine
     garnie, `sudo cat /var/log/messages` (ou en root) : sous les lignes de
     travail, datées entre 7h et 16h, il y a deux ou trois lignes datées **entre
     minuit et 5h**, un redémarrage que personne n'a demandé, une connexion
     refusée, un `cu: no carrier`. [ ]

309. **La page qu'il n'a pas finie.** Sur environ une machine sur deux, le dossier
     du propriétaire contient `draft.txt` : `cat draft.txt` → le texte s'arrête au
     milieu d'une phrase, sans point final. [ ]

310. **Le bureau d'à côté raconte autrement.** Trouver deux premises du **même
     type** dans deux endroits différents (deux bureaux, deux magasins) avec des
     machines jamais touchées :
     - le fichier du même nom (`handover.txt`, `inventory.txt`, `memo.txt`) n'a
       pas le même texte des deux côtés ;
     - les noms cités dedans sont ceux des employés de **cette** premises, et
       `cat /etc/passwd` le confirme ;
     - aucun texte ne contient d'accolade `{` ou `}` ;
     - `mail` des deux côtés montre des sujets différents. [ ]

311. **Le numéro qu'il a composé est un vrai.** Sur une machine dont le
     `.sh_history` contient une ligne `cu 555-XXXX` : ouvrir l'annuaire
     téléphonique (le livre vanilla) dans la même région et y retrouver ce numéro,
     puis taper la ligne telle quelle → le modem sonne et répond
     `CONNECT 2400` s'il y a un ordinateur allumé au bout, `NO CARRIER` sinon.
     Ce n'est jamais le numéro de la premises où l'on est. [ ]

## AD. Le magasin d'électronique et le bureau en trop (4e partie)

Même condition qu'aux sections AA à AC : option bac à sable **Machines et
disquettes garnies** sur **Activé**. Les mots de passe et les noms sont propres à la
sauvegarde ; rien de ce qui est écrit ici n'est un nom ou un mot de passe à recopier.

Le magasin d'électronique se reconnaît de l'extérieur : une devanture avec des
ordinateurs allumés dedans, plusieurs en rang. Dans la carte livrée, ces pièces
s'appellent `electronicsstore` et `electronicstore`, avec un `electronicsstorage`
derrière.

312. **Une machine en vitrine est de la marchandise.** Allumer un ordinateur posé
     sur le plancher de vente d'un magasin d'électronique jamais visité :
     - le nom de la machine commence par `demo-` et non par `sales-` ;
     - le message d'accueil est celui du vendeur (« demonstration machine »), pas
       celui d'un arrière-boutique ;
     - `whoami` → `demo`, et on est déjà au shell : rien n'a été demandé ;
     - `ls` → `WELCOME.TXT`, `DEMO.TXT`, `PRICES.TXT` ;
     - `cat PRICES.TXT` → la gamme complète avec les prix, trois modèles ;
     - `cat /etc/passwd` → **deux** comptes seulement : `root` et `demo`. Aucun
       employé du magasin, et pas de compte d'usine : un modèle d'exposition est
       une machine que le magasin a installée comme les autres. [ ]

313. **Et personne n'y a travaillé.** Sur la même machine :
     - `wc -l .sh_history` → **2 ou 3** lignes, pas douze ;
     - ces lignes sont celles d'un client : il a lu un fichier et il est parti ;
     - `mail` → `No mail.` ;
     - `last` ne montre aucune session encore ouverte ;
     - `cat draft.txt` → `no such file`. [ ]

314. **Les autres machines du plancher ne sont pas des copies.** Allumer deux ou
     trois autres modèles d'exposition du même magasin :
     - chacun a bien les trois fichiers en capitales, avec le **même** texte de
       vente (c'est le même magasin, donc la même version de l'argumentaire) ;
     - mais le `.sh_history` n'est pas le même partout : au moins deux modèles du
       magasin portent des lignes différentes. [ ]

315. **La machine du magasin est dans l'arrière-boutique.** Dans le même bâtiment,
     trouver l'ordinateur de la réserve ou du bureau du fond et l'allumer :
     - le nom commence par `sales-` ;
     - `cat /etc/passwd` → les employés du magasin en plus de `root`, et pas
       d'`admin` ;
     - un seul dossier personnel est garni ;
     - `cat floor.txt` (dans ce dossier) dit comment une machine part en
       exposition, et dit que `root` y est celui du magasin. [ ]

316. **Le papier du tiroir ouvre aussi la vitrine.** Trouver la note collante dans
     un tiroir du magasin (`Sticky note (root)`, ouverte pour lire le mot), puis,
     sur un modèle
     d'exposition du plancher :
     - `su root` avec ce mot de passe → ça passe ;
     - et ça passe aussi sur la machine de l'arrière-boutique. Un seul papier, une
       seule premises, toutes ses machines. [ ]

317. **Le bureau en trop.** Trouver une premises garnie avec **plus** d'ordinateurs
     jamais touchés que la premises n'a d'employés (un bureau a trois personnes :
     il faut donc quatre machines ou plus). Les allumer un par un :
     - les trois premiers allumés sont trois bureaux de trois personnes
       différentes : sur chacun, `ls /home/*` montre **un seul** dossier garni, et
       ce n'est pas le même compte d'une machine à l'autre ;
     - à partir du quatrième, la machine garde le nom et l'accueil de la premises,
       mais `whoami` → `demo`, `ls /home/*` ne montre **aucun** dossier garni, et
       `cat /etc/passwd` contient quand même tous les employés ;
     - le mot de passe d'un employé (papier de poche) ouvre son compte sur cette
       machine-là aussi. [ ]

318. **Et l'ordre est celui où on les allume.** Sur une sauvegarde neuve du même
     monde (ou une autre premises du même type), allumer les machines dans un ordre
     différent : ce n'est pas la même machine qui porte le même employé. Ce qui ne
     change pas : jamais deux machines de la même premises avec le **même**
     propriétaire, et jamais un employé de la premises qui n'existe pas dans
     `/etc/passwd`. Une fois allumée, une machine ne change plus jamais de
     propriétaire, même après sauvegarde et rechargement. [ ]

## AE. Un lieu qui tourne déjà tout seul (5e partie)

Même condition qu'aux sections AA à AD : option bac à sable **Machines et disquettes
garnies** sur **Activé**. Les mots de passe et les noms sont propres à la sauvegarde ;
rien de ce qui est écrit ici n'est un nom ou un mot de passe à recopier.

Environ une premises sur trois qui avait un travail de nuit à faire était équipée
avant l'épidémie : les relais et les contacts sont déjà posés, sa machine a été
laissée allumée, et sa crontab est toujours lue. Comme c'est un tirage, il faut
plusieurs commerces avant d'en trouver un : les deux premières étapes sont une
recherche, pas un échec.

**La décision se prend une seule fois**, au moment où le premier ordinateur de la
premises apparaît dans la sauvegarde. Donc toute cette section se fait sur des
commerces **jamais visités** : un magasin où on est déjà entré a déjà tiré, et il a
tiré avant que le joueur ne regarde.

319. **Trouver un commerce qui tourne encore.** Sortir vers un quartier commerçant
     jamais visité et marcher jusqu'à voir, de la rue, un écran allumé dans une
     boutique fermée : un ordinateur dont la tuile est la tuile allumée, sans que
     personne n'y ait touché. Compter les commerces visités avant d'en trouver un :
     ce doit être de l'ordre de trois, pas vingt. [ ]

320. **Les lumières s'éteignent à neuf heures, devant soi.** Se placer dans ce
     magasin vers **20 h 55** (montre en main, l'heure du jeu). Ne rien toucher.
     - à **21 h 00** pile, les lumières de la boutique s'éteignent ;
     - personne n'a actionné d'interrupteur et aucune fenêtre de terminal n'est
       ouverte ;
     - l'écran de la machine est toujours allumé. [ ]

     Si le magasin est une école, l'heure est **22 h 00** ; une banque verrouille sa
     chambre forte à **18 h 00** du lundi au vendredi ; une station de radio dit sa
     ligne d'horaire à **5 minutes** de chaque heure.

321. **Et elles se rallument le matin.** Rester sur place (ou revenir avant sept
     heures) : à **7 h 00**, les mêmes lumières se rallument, toujours sans personne
     à l'interrupteur. [ ]

322. **La ligne est dans la crontab.** Trouver la machine du magasin, l'ouvrir. Elle
     est souvent restée à l'invite de quelqu'un : dans ce cas on est déjà au shell.
     - `crontab -l` → la ligne de nuit, avec l'heure vue à l'étape 320 ;
     - si le compte au clavier n'est pas celui du travail, `su root` avec le mot de
       passe du papier du tiroir, puis `crontab -l -u <le compte>` ;
     - `dev` → les luminaires, les portes et les fenêtres du magasin, avec leurs
       numéros ;
     - les numéros nommés dans la ligne de crontab (`light0 light1`) sont bien dans
       cette liste. [ ]

323. **La ligne se change.** Toujours sur cette machine :
     - `crontab -r` puis `crontab -l` → `no crontab for <compte>` ;
     - le soir suivant à l'heure vue à l'étape 320, **rien** ne s'éteint ;
     - réécrire une ligne à soi (`echo "0 22 * * * sh $HOME/bin/lights.sh light0" |
       crontab`) et vérifier le lendemain à 22 h 00 que c'est bien celle-là qui
       s'exécute. [ ]

324. **Le relais s'enlève, et la lumière ne répond plus.** Clic droit sur
     l'interrupteur que la machine commande (pas sur l'ordinateur) → **Matériel
     CeroSec** → **Retirer le relais**. Il faut un tournevis et Électricité 1.
     - le relais est dans le sac après le geste ;
     - `dev light0` → `light0: no such device` ;
     - et surtout : attendre **deux ou trois minutes de jeu** et revérifier. Le
       relais **ne revient pas** tout seul sur la plaque. [ ]

325. **Rien ne se rejoue au rechargement.** Sauvegarder, quitter, recharger, revenir
     dans le même magasin :
     - la machine est toujours allumée ;
     - les modules retirés à l'étape 324 sont toujours retirés ;
     - les modules laissés en place sont toujours en place ;
     - la crontab est celle laissée à l'étape 323. [ ]

326. **Pas de courant, pas d'automatisme.** Sur une sauvegarde où le réseau
     électrique est tombé (ou après la coupure, dans une partie longue), entrer dans
     un commerce jamais visité :
     - aucun écran allumé en vitrine ;
     - mais en clic droit sur un interrupteur du magasin, le menu **Matériel
       CeroSec** propose bien **Retirer le relais** sur certains d'entre eux : le
       matériel est posé, c'est le courant qui manque ;
     - brancher un générateur et allumer la machine à la main : `dev` montre les
       luminaires, et une ligne de crontab écrite à la main fonctionne. [ ]

327. **Une maison ne s'automatise jamais.** Entrer dans une maison jamais visitée :
     aucun ordinateur allumé de lui-même, et les interrupteurs de la maison
     n'offrent pas **Retirer** (rien n'y a été posé). [ ]

328. **Ni un modèle d'exposition.** Dans un magasin d'électronique (section AD) qui
     tourne tout seul : la machine allumée d'elle-même est celle de
     l'**arrière-boutique**, pas une de la vitrine. Les machines de la vitrine sont
     allumées parce que ce sont des machines de démonstration (étape 312), ce qui se
     vérifie, c'est laquelle porte la crontab : `crontab -l` ne donne une ligne de
     nuit que sur celle du fond. [ ]

329. **L'option coupée coupe tout.** Nouveau monde, **Machines et disquettes
     garnies** sur **Désactivé** : parcourir cinq commerces jamais visités. Aucun
     écran allumé de lui-même, aucun module posé sur aucun interrupteur, et rien ne
     s'éteint à neuf heures. [ ]

330. **Le compte d'usine n'est pas sur la machine de quelqu'un.** C'est la seule
     chose qui rendait le papier du tiroir facultatif : tant qu'`admin` restait
     ouvert, il suffisait de taper `admin` puis `sudo su` pour être `root` sur
     n'importe quelle machine du comté. Sur un ordinateur garni (n'importe quel
     commerce, modèle d'exposition compris) :
     - à `login:`, taper `admin` et Entrée au mot de passe → `login incorrect` ;
     - se connecter avec un compte de la premises (papier du tiroir, papier d'une
       poche) puis `cat /etc/passwd` → aucune ligne `admin` ;
     - `ls /home` → un dossier par employé, aucun `admin` ;
     - `cat /etc/sudoers` → la ligne `%wheel` est là, aucune ligne `admin` ;
     - sur le compte **administrateur** de la premises (celui dont l'invite finit
       par `$` mais qui commande le bâtiment) : `echo off > /dev/light0` **passe**,
       et `sudo whoami` est refusé (`not in the sudoers file`) ;
     - `su root` avec le mot du papier **passe**. [ ]

331. **Et sur une machine que personne n'a installée, il est toujours là.** Un
     ordinateur posé par le joueur dans sa base, ou n'importe lequel avec l'option
     **Désactivé** : `admin` avec un mot de passe vide passe, `sudo whoami` donne
     `root`, et `ls /home` montre `admin`. C'est le témoin : ce compte décrit une
     machine que personne n'a jamais installée, et rien d'autre. [ ]

## AF. La bannière, et ce que `login` dit (fidélité)

Rien à régler dans le bac à sable : ces étapes marchent sur n'importe quelle
machine, garnie ou non. Ce qui est vérifié ici est l'ORDRE des lignes sur un seul
écran -- le message du jour était imprimé deux fois, au-dessus de `login:` et
en dessous, et aucune vraie machine ne faisait ça.

331a. **La bannière est au-dessus de `login:`, le message du jour n'y est pas.**
     Allumer un ordinateur froid et lire l'écran du haut vers le bas, sans rien
     taper :
     - les lignes du micrologiciel (`CeroSec BIOS`, la mémoire, `hda`) ;
     - **une** ligne qui nomme le système, la machine et `(console)` ;
     - puis `login:`.
     La phrase `unauthorized access is prohibited` (ou le message du jour de la
     premises) ne doit **pas** être sur cet écran. [ ]

331b. **Ce que `login` dit, une fois le mot de passe bon.** Se connecter avec un
     compte ouvert. Dans l'ordre, sous `password:` :
     - rien du tout au sujet d'une dernière connexion, **la première fois** ;
     - le message du jour, **une seule fois** sur tout l'écran ;
     - puis l'invite. [ ]

331c. **La deuxième connexion nomme la première.** `exit`, puis se reconnecter avec
     le même compte : `Last login: <date> on console`, avec la date et l'heure de
     la connexion précédente. Vérifier avec `last` que c'est bien la même ligne
     que le fichier a gardée. [ ]

331d. **Le courrier.** Poser une crontab qui écrit quelque chose
     (`crontab -e`, une ligne `* * * * * echo bonjour`), attendre une minute, puis
     `exit` et se reconnecter : `You have mail.` après le message du jour. `mail`
     montre le message, et jamais `You have new mail.` [ ]

331e. **`touch ~/.hushlogin` et la machine se tait.** Toujours sur ce compte :
     `touch ~/.hushlogin`, `exit`, se reconnecter → **aucune** des trois lignes.
     Se connecter avec un autre compte → les lignes sont là. Puis
     `rm ~/.hushlogin`, se reconnecter → elles reviennent. [ ]

331f. **Par le fil, c'est la machine d'où on vient qui est nommée.** Avec deux
     ordinateurs sur le même segment (section N) : `rlogin <voisine>`, se
     connecter, `exit`, puis `rlogin` une deuxième fois → `Last login: <date> from
     <nom de la machine d'ici>`, et pas `on ttyp0`. [ ]

331g. **La banque et le poste militaire préviennent avant la connexion.** Sur un
     ordinateur garni d'une banque ou d'un poste militaire (option **Machines et
     disquettes garnies** sur **Activé**), lire l'écran avant de taper quoi que ce
     soit : la ligne au-dessus de `login:` parle d'usage autorisé. [ ]

331h. **Une sauvegarde d'avant la mise à jour gagne le fichier, sans rien perdre.**
     Charger une sauvegarde faite avec la version précédente et ouvrir un
     ordinateur qui y tournait : `cat /etc/issue` nomme la machine **avec son nom
     actuel**, la bannière est au-dessus de `login:`, et tout ce qui était sur le
     disque est toujours là (`ls -l /home`, la crontab, l'historique). Sur une
     machine où l'on avait écrit soi-même dans `/etc/issue` avant, c'est ce qu'on
     avait écrit qui reste. [ ]

## AG. Le babillard sur la disquette BBS (6e partie)

Deux comptes sur une **même** machine suffisent : un joueur peut les prendre l'un
après l'autre. La disquette `BBS` se donne par la fenêtre de débogage (section X)
ou se trouve dans un tiroir. Le banc 6b de `content_test.lua` a déjà tout fait
tourner sans jeu ; ce qui se vérifie ici, c'est l'écran.

332. **Le sysop installe le babillard.** Sur un ordinateur allumé, mettre la
     disquette `BBS` dans le lecteur, puis, en `root` :
     - `mount /dev/fd0 /mnt` puis `cat /mnt/README.TXT` → la page se lit en
       entier, aucune ligne ne dépasse le bord droit ;
     - `sh /mnt/setup.sh /usr/local/lib/bbs` → il dit que le babillard est
       `/usr/local/lib/bbs/board`, que les quatre programmes sont dans
       `/usr/local/bin`, et quoi faire ensuite ;
     - `ls -l /usr/local/lib/bbs` → le répertoire est en `777` et `board` en
       `666` ; `ls -l /usr/local/bin` → les quatre en `755` ;
     - relancer la **même** commande → rien ne casse et rien n'est écrasé : le
       babillard existant est laissé tel quel. [ ]

333. **Deux comptes, et la ligne dans `.profile`.** Toujours en `root` :
     `useradd alice`, `passwd alice`, `useradd bob`, `passwd bob`. Puis, pour
     chacun : `edit /home/alice/.profile`, une seule ligne
     `sh /usr/local/bin/bbs.sh`, Tab pour enregistrer, et
     `chown alice /home/alice/.profile`. `exit`, se connecter comme `alice` → le
     menu s'affiche **tout seul**, sans avoir rien tapé. [ ]

334. **Écrire à tout le monde, et le babillard.** Dans le menu, comme `alice` :
     `P`, puis `all` comme destinataire, un sujet, deux lignes de texte, puis une
     ligne qui ne contient qu'un point `.` → il dit `Posted to all.` et
     `On the board too.` Puis `B` → le message est là, avec `From: alice`, une
     date et le sujet. `Q` pour sortir, `exit`. [ ]

335. **Le compte de messages non lus.** Se connecter comme `bob` → le menu.
     `N` → le message d'alice s'affiche. `Q`, `exit`, se reconnecter, `N` →
     `No new mail. 1 read.` Puis `cat ~/.bbs_seen` → **1**. Se faire envoyer un
     deuxième message (en `root` sur une autre console, ou par `at`) et refaire
     `N` → **seul** le nouveau s'affiche, et `.bbs_seen` passe à **2**. [ ]

336. **Une page à la fois.** Toujours comme `bob`, avec une boîte de plus de
     dix-huit lignes (trois ou quatre messages suffisent) : `R` → l'écran
     s'arrête sur `-- more -- `. Entrée continue, `q` arrête. Rien ne défile
     au-delà du bord de l'écran. [ ]

337. **Les quatre autres touches, et la sortie.** `W` → la ligne d'`alice` si elle
     est encore connectée ailleurs, sinon la sienne ; `L` → les dernières
     connexions, dix au plus ; `U` → `alice`, `bob` et `admin`, et **pas** `root` ;
     une touche qui n'est pas du menu → `N R P B W L U Q?` ; `Q` → `Goodbye.` et on
     retombe au prompt. Un `Ctrl`-`Échap` n'est pas nécessaire pour sortir. [ ]

338. **La sauvegarde du courrier.** En `root`, mettre une disquette vierge dans le
     lecteur, `mount /dev/fd0 /mnt`, puis
     `echo "tar cf /mnt/backup /var/mail" | at <l'heure dans deux minutes>` →
     attendre, puis `tar tf /mnt/backup` nomme les boîtes. La même ligne dans
     `crontab -e` à `0 3 * * *` se relit avec `crontab -l`. [ ]

## AH. Les dettes du shell (2e partie)

Tout se tape au prompt d'une seule machine allumée, en `admin`. Les bancs
`os_test.lua`, `hostile_test.lua` et `window_test.lua` ont déjà tout fait tourner
sans jeu ; ce qui se vérifie ici, c'est ce que l'écran répond.

339a. **`sudo` signe ce qu'il ne trouve pas.** `sudo lights on` → une seule ligne,
     `sudo: lights: command not found`, et non `lights: command not found` : c'est
     `sudo` qui a cherché. `sudo cd /root` répond pareil
     (`sudo: cd: command not found`). [ ]

339b. **`cut` prend sa valeur collée.** `cut -d: -f1 /etc/passwd` → la liste des
     comptes, une ligne chacun, exactement comme `cut -d : -f 1 /etc/passwd`.
     `cut -c1-8 /etc/passwd` marche pareil, et `cut -d: -f-2 /etc/passwd` donne
     les deux premiers champs (le `-2` est la liste, pas une option). [ ]

339c. **Un `$( )` est un sous-shell.** `x=1`, puis `y=$(x=2; echo $x)`, puis
     `echo "$y $x"` → `2 1` : le sous-shell a bien vu le 2, le shell ne l'a
     jamais eu. Pareil pour le répertoire : `echo $(cd /etc; pwd)` affiche
     `/etc` et `pwd` juste après affiche encore `/home/admin`. Et
     `export P=a`, `z=$(export P=b; echo $P)`, `env | grep P` → `P=a`. [ ]

339d. **Les deux imbrications que POSIX permet.** `echo $( echo $(( 2 + 3 )) )` →
     `5`. `echo $(( $(echo 3) + 1 ))` → `4`. Et la ligne que le manuel disait
     impossible : `stop=$(( $(date +%s) + 300 ))`, puis `now=$(date +%s)`, puis
     `echo $(( stop - now ))` → `300` (ou 299/300 selon la seconde qui passe).
     Deux prises restent refusées : `echo $(echo $(date))` →
     `sh: syntax error: bad substitution`. [ ]

339e. **La sortie d'un script suit la redirection de la ligne.** Avec
     `edit deux.sh` contenant `echo un` et `echo deux`, Tab pour enregistrer :
     `sh deux.sh > out` → **rien** à l'écran, puis `cat out` → `un` et `deux`.
     `sh deux.sh >> out` → `cat out` en montre quatre lignes. `chmod 755 deux.sh`
     puis `./deux.sh > out2` → pareil, et `./deux.sh | wc -l` → `2`. Un script
     qui contient `ls /nope` sous un `> fic` : le refus est à l'écran, le fichier
     ne contient que ce qui a été imprimé. Et `sh deux.sh > /etc/nope` →
     `sh: /etc/nope: permission denied`, le script ne tourne pas. [ ]

339f. **`case`.** Au prompt : `case abc in a*) echo star;; esac` → `star` ;
     `case abc in x|abc|y) echo alt;; esac` → `alt` ;
     `case abc in z*) echo no;; *) echo default;; esac` → `default` ;
     `case b in [a-c]) echo set;; esac` → `set`. Rien qui correspond ne rate
     pas : `case abc in q) echo no;; esac` puis `echo $?` → `0`. `type case` →
     `case is a shell keyword`, et `help` liste `case` et `esac` parmi les mots
     du shell. Dans un fichier avec `edit`, la forme sur plusieurs lignes
     marche aussi (`case $1 in`, une clause par bloc, `esac` seul sur sa
     ligne). Et `echo a;;` → `sh: syntax error: unexpected ';;'`. [ ]

339g. **Les fonctions du shell.** Au prompt : `greet() { echo hello $1; }` puis
     `greet world` → `hello world` ; `type greet` → `greet is a function` ;
     `help` liste `case` et `esac`. `r() { return 3; }`, `r`, `echo $?` → `3`.
     `x=outside`, `f() { x=inside; }`, `f`, `echo $x` → `inside` (pas de
     `local` en 1993). Fermer la fenêtre du terminal et la rouvrir : `greet bob`
     marche encore (c'est la machine qui garde la fonction). `exit` puis se
     reconnecter : `greet` → `greet: command not found`. Et dans un fichier
     `lib.sh` avec une définition dedans : `sh lib.sh` ne laisse rien,
     `. lib.sh` la laisse (`type` le dit). [ ]

339h. **`grep` lit une expression régulière.** Dans une boîte aux lettres
     (`mail` en a laissé une, ou `cat /var/mail/admin`) :
     `grep -c '^From ' /var/mail/admin` compte les messages (les lignes
     d'enveloppe) et pas les en-têtes `From:`. Puis, sur un fichier à soi :
     `grep 'l.ghts' fic`, `grep '[Ff]rom' fic`, `grep 'out$' fic`,
     `grep 'a\.b' fic` (le point littéral). `grep -e '-x' fic` cherche un motif
     qui commence par un tiret, et deux `-e` cherchent l'un ou l'autre. Les
     refus : `grep '[abc' fic` → `grep: [abc: unmatched [`. Et `man grep` donne
     la nouvelle ligne d'usage. [ ]

339i. **Lire son courrier ne le détruit plus.** `echo "essai" | mail -s Test admin`
     puis `mail` → le message s'affiche. `ls -l ~/mbox` → le fichier existe, en
     `-rw-------`. `mail` → `No mail for admin` (la boîte d'arrivée est vide),
     mais `mail -f` → le message est encore là, et deux `mail -f` de suite le
     montrent deux fois (rien n'est déplacé). Se déconnecter et se reconnecter :
     pas de `You have mail.` (c'est la boîte d'arrivée qui le dit, pas
     `~/mbox`). Puis un deuxième message, `mail`, `mail -f` → les deux messages
     dans l'ordre. [ ]

339j. **`wall`, sur tous les écrans.** Ouvrir **deux** fenêtres de terminal sur la
     même machine (clic droit → CeroSec sur l'ordinateur, deux fois). Dans la
     première, connecté : `echo "lights out in 5" | wall` → les deux écrans
     montrent `Broadcast Message from admin@<nom>`, puis
     `        (console) at hh:mm ...`, une ligne vide et le texte. Rien n'est
     imprimé en plus dans la fenêtre où on a tapé. Puis, depuis une autre
     machine, `rlogin <cette machine>` : refaire le `wall` → la session le reçoit
     aussi. `wall` tout seul → `wall: usage: wall [file]`, et `wall /etc/motd`
     diffuse le fichier. Un compte ordinaire (pas root) peut le faire. [ ]

339k. **`/bin/wall` arrive sur une sauvegarde existante.** Charger une
     sauvegarde faite avec la version précédente, ouvrir un ordinateur qui y
     tournait : `ls -l /bin/wall` → le fichier est là, `root`, `755`, et `help`
     le liste. Tout ce qui était sur le disque est toujours là. Sur une machine
     où l'on avait mis un fichier à soi au nom `wall`, c'est le sien qui
     reste. [ ]

339l. **Un ordre n'arrête pas la ligne.** Au prompt :
     `wall /etc/motd; echo envoye` → la diffusion s'affiche, **puis** `envoye`
     en dessous (avant, la ligne mourait sur son propre `wall` et `envoye` ne
     sortait jamais). Pareil pour l'écran : `echo a; clear; echo b` → l'écran
     se vide et il reste `b` dessous, pas un écran vide. Dans un script
     (`echo a`, `wall /etc/motd`, `echo b` dans un fichier lancé au prompt) →
     les deux lignes sortent et la diffusion est entre elles. Enfin par
     crontab, `* * * * * wall /etc/motd; echo fini` → à la minute suivante la
     diffusion arrive sur l'écran et `fini` est dans le courrier
     (`mail`). [ ]

339m. **Une seule fenêtre par survivant sur une machine.** Ouvrir le terminal sur
     un ordinateur, se connecter, taper `echo un`. Ouvrir la fenêtre de débogage
     (**CeroSec (dev)** → la fenêtre de débogage), sélectionner cette machine :
     l'onglet machine affiche `windows 1`. Revenir au jeu et rouvrir le terminal
     sur le **même** ordinateur : l'écran montre la même session et la ligne
     `echo un` (l'écran appartient à la machine), et la fenêtre de débogage
     affiche toujours `windows 1`, jamais 2. Ouvrir et refermer dix fois de
     suite, puis regarder : toujours `windows 1`. En écran partagé, chaque
     survivant compte pour un : `windows 2` avec les deux terminaux ouverts,
     `windows 1` après avoir fermé celui du joueur 2, et `windows 0` quand les
     deux sont fermés.

     Ce qu'on ne peut **pas** provoquer à la main, et c'est voulu : le client
     ferme toujours sa fenêtre précédente avant d'en ouvrir une autre (une
     fenêtre par joueur), donc le serveur n'a normalement rien à remplacer. La
     règle qui remplace la fenêtre d'un joueur et celle qui plafonne une machine
     à huit fenêtres sont là pour un client qui ne ferme rien, et ce sont les
     bancs qui les prouvent (`tests/hostile_test.lua`, le bloc du comté). Ce que
     cette étape vérifie sur le verre, c'est que ces règles ne cassent pas
     l'ouverture normale. [ ]

339n. **Un centre commercial finit par se câbler, et le dit.** Dans un des grands
     centres commerciaux du comté (Louisville en a de plus de cent pièces),
     trouver une boutique automatisée : un ordinateur allumé tout seul dans
     l'arrière-boutique. Sélectionner cette machine dans la fenêtre de débogage :
     l'onglet machine montre `tenancies: N` (plusieurs dizaines dans un centre
     commercial), `premises: room <nom de la boutique>` et la ligne
     `automated: yes  machine x,y,z  wired no  rooms walked K`. Faire le tour de
     la boutique et du couloir, de façon à charger ses pièces les unes après les
     autres, et regarder `rooms walked` monter de quelques pièces par minute de
     jeu jusqu'à ce que la ligne devienne `wired yes` **sans compteur** : le
     câblage est fini et le serveur ne repasse plus jamais dessus. Avant ce
     changement la ligne `wired` d'un centre commercial ne passait jamais à yes
     et le bâtiment entier était relu chaque minute de jeu.

     Puis vérifier que c'est bien la boutique et pas le centre : `dev` sur cette
     machine liste ses lampes et ses portes (option `HardwareRequired` activée,
     donc seules les pièces équipées apparaissent), et sur un ordinateur d'une
     boutique voisine `dev` ne montre aucune lampe -- ses interrupteurs n'ont pas
     de relais. Attendre 21:00 sur place : les lampes de la boutique s'éteignent,
     celles des voisines restent allumées. [ ]

## AI. Les outils de l'admin et du testeur (fenêtre de débogage, 2e rangée)

Huit boutons de plus sur la fenêtre de débogage, sur une **deuxième rangée** sous la
première, et seulement sur l'onglet **Machines** : ils parlent tous de la machine
sélectionnée. Ils existent pour un développeur et pour un admin de serveur, jamais
pour un joueur, ils sont derrière la même porte que le reste de la fenêtre
(`CeroSec.debugAllowed`), et sur un serveur cette porte s'ouvre maintenant aussi pour
un **admin**. Détail de ce que chacun écrit dans [DEBUG.md](DEBUG.md).

Pour cette section : une machine **préremplie** allumée dans un vrai commerce ou
bureau de la carte (option `PrefilledMachines` activée, et la machine allumée pour la
première fois dans cette partie), la fenêtre de débogage ouverte dessus, et la ligne
de la machine cliquée dans la liste.

340. **La deuxième rangée est là, et seulement où il faut.** Onglet **Machines** →
     sous la rangée de boutons habituelle, une deuxième rangée : **Donner la note de
     root**, **Donner la note d'un employé**, **Montrer les comptes**, **Effacer le
     mot de passe**, une petite case de texte contenant `root`, **Donner la
     disquette**, une liste déroulante de disquettes, **Ouvrir une session root**,
     **Lancer cron maintenant**, **Forcer le câblage**. Attendu : rien ne dépasse du
     bord droit de la fenêtre, les deux rangées ne se chevauchent pas, et le bloc de
     détail est sous la dernière des deux. Cliquer l'onglet **Files** : toute la
     deuxième rangée disparaît, la case et la liste avec, et la première rangée reste.
     Revenir sur **Machines** : tout revient. [ ]

341. **Donner la note de root.** Cliquer **Donner la note de root** → un papier
     arrive dans l'inventaire du personnage, nommé `Sticky note (root)` et disant,
     quand on l'ouvre, `Sticky note: root / <mot>NN`. Attendu : la ligne sous la
     liste répète les mêmes
     lettres, et ces lettres ouvrent vraiment la machine, ouvrir le terminal,
     `login: root`, taper le mot de passe du papier, ça entre. **Puis fouiller un
     bureau ou un classeur du même local** : le papier du tiroir est toujours là (ce
     bouton ne consomme pas la note du lieu). [ ]

342. **Donner la note d'un employé.** Cliquer **Donner la note d'un employé** → un
     second papier, `Note: <login> / <mot>NN`, avec un login qui n'est pas `root`. La
     ligne sous la liste dit de quel emplacement il s'agit (`slot 1`). Attendu : au
     prompt, ce login et ce mot de passe entrent aussi, et le même clic répété donne
     toujours le même compte (c'est le premier emplacement verrouillé, pas un tirage).
     Sur une machine d'un local sans mot de passe root (un logement), le bouton est
     **grisé** et la ligne sous la liste dit pourquoi. [ ]

343. **Montrer les comptes.** Cliquer **Montrer les comptes** → la ligne sous la liste
     dit `accounts on <hôte>: N`, et l'onglet **Log** (bouton **All**) porte une ligne
     par compte : le login, son `home`, `wheel` ou `user`, ses groupes, si son mot de
     passe est mis ou `OPEN (empty)`, et pour les comptes que le catalogue a créés le
     mot de passe **en clair**. Attendu : le compte `root` y est avec les mêmes lettres
     que le papier de l'étape 341, et le nombre de lignes correspond bien au nombre de
     comptes que `cat /etc/passwd` affiche au terminal. [ ]

344. **Effacer le mot de passe.** Laisser `root` dans la case → **Effacer le mot de
     passe**. Attendu : la ligne sous la liste dit que root n'a plus de mot de passe.
     Au terminal : `login: root`, puis **Entrée** sur la demande de mot de passe, et
     la session s'ouvre. Le papier de l'étape 341 ne fonctionne plus (c'est bien un mot
     de passe enlevé et non un mot de passe changé). Taper ensuite un nom qui n'existe
     pas dans la case (`personne`) → refus lisible, `no such user personne`, et rien
     n'a bougé sur la machine. [ ]

345. **Donner la disquette.** Choisir `UTILITIES` dans la liste déroulante →
     **Donner la disquette**. Attendu : une disquette arrive dans le sac avec
     l'étiquette **imprimée** `CeroSec UTILITIES 1.0` et l'icône imprimée ; l'insérer,
     `mount /dev/fd0 /mnt`, `ls /mnt` → les fichiers de cette disquette, exactement
     comme une disquette trouvée dans un tiroir. Recommencer avec `BBS LIST` : le nom
     est **manuscrit** (une des trois écritures), et `NUMBERS.TXT` est d'abord le talon
     puis se remplit des numéros de la région à la première insertion, comme une
     disquette trouvée. Recommencer trois ou quatre fois avec la même entrée
     manuscrite : les étiquettes ne sont pas toutes identiques (le récit est tiré au
     sort, comme dans le monde). [ ]

346. **Ouvrir une session root.** Éteindre la machine, la rallumer, ouvrir le terminal
     et le laisser au `login:`, puis, sur la fenêtre de débogage, **Ouvrir une session
     root**. Attendu : le terminal s'ouvre (ou revient) directement sur le prompt de
     root, avec `login: root` écrit au-dessus, le motd, et un prompt qui finit par `#`.
     `who` nomme root sur `console`, `last` porte son arrivée, `echo $HOME` répond
     `/root`. Cliquer le bouton une seconde fois : **refusé**, la ligne dit
     `somebody is already logged in as root`. Sur une machine éteinte, le bouton est
     **grisé**. [ ]

347. **Lancer cron maintenant.** Au terminal, en root :
     `edit /var/spool/cron/root`, écrire la ligne `* * * * * echo bonjour`, sauver.
     Puis, sans attendre la minute, cliquer **Lancer cron maintenant**. Attendu : la
     ligne sous la liste dit `cron fired 1 line(s) and at started 0 job(s)`, et
     quelques secondes plus tard `mail` au terminal montre un message de `root` avec
     `bonjour` dedans. Sur une machine éteinte, le bouton est **grisé** et la ligne dit
     `it is off`. [ ]

348. **Forcer le câblage.** Dans un local qui a tiré « déjà automatisé » (voir la
     section AE : le bloc de détail de l'onglet Machines dit
     `automated: yes ... wired no  rooms walked K`), cliquer **Forcer le câblage**.
     Attendu : la ligne sous la liste dit combien d'appareillages ont été posés et en
     combien de passes, le bloc de détail passe à `wired yes` **sans compteur** sans
     qu'on ait à faire le tour du bâtiment, et `dev` sur cette machine liste
     maintenant les lampes et les portes du local. Cliquer une deuxième fois :
     **refusé**, `its premises is already wired`. Sur une machine d'un local qui a tiré
     non, le bouton est **grisé** et dit `its premises rolled no`. [ ]

349. **Rien de tout cela pour un joueur.** Mettre `CeroSec.DEV_DEBUG_MENU = false`
     dans `42/media/lua/shared/CeroSec/CeroSecDefs.lua`, relancer le jeu **sans**
     `-debug`, clic droit sur un ordinateur. Attendu : plus d'entrée **Fenêtre de
     débogage** du tout dans le sous-menu **CeroSec (dev)**. En solo c'est toute la
     règle ; sur un serveur dédié, un joueur **admin** la retrouve et un joueur
     ordinaire non. [ ]

## AJ. Nos entrées en haut du clic droit (menus)

Tout ce que ce mod ajoute à un menu contextuel passe devant les entrées du jeu
(Grab, Equip, Place...). Une seule exception, voulue et écrite : le sous-menu
**CeroSec (dev)**, qui reste la dernière entrée du menu (étape 101).

350. **Un ordinateur allumé.** Clic droit sur un ordinateur allumé posé sur un
     bureau, au milieu d'un décor qui donne des entrées au jeu (une chaise, un
     meuble, un objet au sol). Attendu, du haut vers le bas : **Use computer**,
     **Turn off computer**, puis, s'il y a de quoi, **Insert floppy** et
     **Eject floppy**, et SEULEMENT ensuite les entrées du jeu. L'action
     principale d'abord : sur une machine allumée c'est s'en servir, pas
     l'éteindre. [ ]
351. **Un ordinateur éteint.** Même clic droit sur une machine éteinte. Attendu :
     **Turn on computer** est la PREMIÈRE entrée du menu (il n'y a rien à
     utiliser sur un écran noir), le lecteur derrière elle si une disquette est
     en jeu, les entrées du jeu ensuite. [ ]
352. **Une entrée grisée reste en haut.** Se placer hors de portée (derrière un
     comptoir) et refaire l'étape 350. Attendu : les mêmes entrées, dans le même
     ordre et à la même place, grisées avec leur infobulle, une entrée refusée
     se lit là où on la cherche. [ ]
353. **Le sous-menu du matériel.** Électricité 1, tournevis et un module en main,
     clic droit sur un interrupteur. Attendu : **CeroSec hardware** est en haut
     du menu, au-dessus du **Turn on/off** de la lampe qui est au jeu et non à
     nous, et le sous-menu s'ouvre normalement. [ ]
354. **Les objets dans le sac.** Clic droit sur un volume du manuel dans
     l'inventaire → **Read the User's Guide** est la première entrée, au-dessus
     de **Équiper** et de **Déposer**. Même chose pour une disquette avec un
     stylo sur soi (**Étiqueter la disquette**), et pour un `Phonebook`
     (**Chercher un numéro**, au-dessus de l'option vanilla **Lire**, qui doit
     toujours être là). [ ]
355. **Le sous-menu dev reste en bas.** Avec `CeroSec.DEV_DEBUG_MENU = true`,
     clic droit sur un ordinateur : **CeroSec (dev)** est la DERNIÈRE entrée du
     menu, sous les entrées du jeu. C'est l'exception voulue : un outil de
     développeur ne pousse pas les entrées de la machine vers le bas. [ ]

## AK. L'onglet Fichiers dit de qui sont les fichiers (fenêtre de débogage)

Ouvrir la fenêtre de débogage sur une machine allumée et prefillée (clic droit →
**CeroSec (dev)** → **Fenêtre de débogage**).

356. **La bannière nomme la machine.** Onglet **Files**. Attendu : au-dessus de la
     liste, une ligne `<hostname> at x,y,z  (on)` avec le nom d'hôte de la machine
     sélectionnée. Passer à **Devices** puis à **Scheduler** : la même bannière,
     la même machine. Revenir à **Machines** : pas de bannière (c'est l'onglet où
     on choisit la machine). [ ]
357. **Rien de sélectionné.** Fermer la fenêtre, faire un clic droit sur un
     ordinateur que le mod n'a jamais vu (ou ouvrir la fenêtre puis cliquer une
     ligne, ce n'est pas pareil), le plus simple : ouvrir la fenêtre depuis une
     machine dont le morceau de carte est parti et dont aucune ligne n'est
     sélectionnée. Attendu : la bannière dit `no machine selected: pick one on the
     Machines tab`. [ ]
358. **Changer de machine sans quitter l'onglet.** Onglet **Files**, ouvrir la
     liste déroulante à droite de la bannière. Attendu : une ligne par machine que
     le serveur tient, `<hostname> at x,y,z` (une machine jamais allumée n'a que
     ses coordonnées). En choisir une autre : la bannière change de nom, la liste
     de fichiers se vide puis se remplit avec le disque de CETTE machine, et le
     bloc de détail sous la liste parle d'elle. Revenir à l'onglet **Machines** :
     la ligne sélectionnée est la nouvelle machine, pas l'ancienne. [ ]
359. **`/bin` est replié.** Onglet **Files** sur une machine allumée. Attendu :
     UNE ligne `/bin`, type `dir`, dont la dernière colonne dit
     `82 files, click to expand` (le nombre est celui de la machine), et aucune
     ligne `/bin/...`. Cliquer la ligne : les quatre-vingts commandes
     apparaissent et la dernière colonne redevient un nombre. Recliquer : elles
     disparaissent. Le compteur `showing N of M` sous la liste garde le M du
     serveur dans les deux cas. [ ]
360. **Le filtre.** Taper `etc` dans la boîte de la bannière. Attendu : seules les
     lignes dont le chemin contient `etc` restent, au fur et à mesure de la
     frappe, sans aller-retour visible. Taper `ETC` : plus rien (c'est sensible à
     la casse). Taper `.` : seulement les chemins qui contiennent vraiment un
     point. PAS toutes les lignes (ce n'est pas une expression régulière). Vider
     la boîte : tout revient, `/bin` toujours replié. Passer à **Devices** : le
     filtre s'applique aussi au nom du périphérique. [ ]
361. **Lire un fichier.** Onglet **Files**, double-cliquer la ligne
     `/etc/passwd`. Attendu : dans le panneau sous les rangées de boutons, le
     chemin `/etc/passwd` puis les premières lignes du fichier, en lecture seule.
     Double-cliquer un répertoire (`/etc`) : rien n'est demandé et la ligne sous
     la liste dit `cannot read: /etc is a dir`. [ ]
362. **Un fichier plus grand que le panneau.** `cat /var/log/messages` a plus de
     cinq lignes : double-cliquer sa ligne. Attendu : le panneau montre le chemin,
     quatre lignes, et une dernière ligne `[... N more lines of M]`. [ ]
363. **Un octet qu'on ne peut pas imprimer.** Au terminal, sur cette machine :
     `printf 'a\tb\r\n' > /root/ctl.txt`, puis **Refresh** de la fenêtre et
     double-clic sur `/root/ctl.txt`. Attendu : le panneau affiche `a^Ib^M`, la
     tabulation et le retour chariot sont MONTRÉS et non avalés. [ ]
364. **Le panneau se vide quand il doit.** Avec un fichier affiché : changer
     d'onglet (**Devices**) → le panneau est vide. Revenir, réafficher un fichier,
     puis changer de machine par la liste déroulante → vide aussi. Un fichier
     d'une machine sous le nom d'une autre est exactement ce qu'il ne faut pas
     voir. [ ]
365. **Une note tient dans le panneau.** Onglet **Machines**, bouton **Donner le
     mot de passe root** (2e rangée). Attendu : la ligne sous la liste dit la
     phrase comme avant, ET le panneau montre les deux ou trois lignes du papier
     en entier. [ ]
366. **La liste ne rétrécit pas.** Vérifier à l'ouverture que la liste a bien une
     vingtaine de rangées sur l'onglet **Machines** et une de moins sur **Files**
     (la bannière prend la place d'une rangée). Tirer le coin jusqu'au plus petit
     possible : sur **Files** il reste exactement une rangée, rien ne se chevauche,
     et le panneau reste sous les boutons et au-dessus du bloc de détail. [ ]

## AL. Le petit moteur, et les cinq choses qu'un bâtiment sait faire (palier moteur)

Quatre modules de plus, cinq sortes de périphérique de plus, et une pièce que le
jeu n'avait pas : le **petit moteur**. Rien ici n'existe sans l'avoir fabriqué.
Option **Matériel requis** activée (la valeur par défaut). Règles et preuves :
[DEVICES.md](DEVICES.md#the-hardware-modules) et
[notes/actuators.md](notes/actuators.md).

367. **Démonter un séchoir à cheveux.** Se donner un `Base.HairDryer`, un
     tournevis, et le **Guide de câblage CeroSec** (`CeroSec.WiringGuide`). Le
     LIRE. Attendu : dans l'onglet **Électrique** de l'artisanat, deux recettes de
     démontage apparaissent en plus des six autres, et elles portent un NOM :
     **Démonter un appareil pour son moteur** et **Démonter un lecteur CD pour
     son moteur**, jamais `DismantleCeroSecMotorAppliance` en clair (un nom brut
     à l'écran veut dire que la clé manque dans
     `Translate/<LANG>/Recipes.json`). Démonter le séchoir.
     Attendu : **un petit moteur ET un `Base.ElectronicsScrap`**, la ferraille
     que la recette vanille aurait donnée, plus le moteur. Refaire avec une
     tondeuse à moutons et un ventilateur soufflant : même chose. Avec un
     **lecteur CD** : la seconde recette, et **deux** ferrailles, parce que la
     recette vanille en donne deux. Personne n'y perd. [ ]
368. **Fabriquer les quatre modules.** Avec le guide lu, Électricité 3, un
     tournevis, des pinces, et de quoi faire : fabriquer un **moteur de rideau**,
     un **contacteur d'appareil**, un **opérateur de fenêtre** et un **inverseur
     de groupe**. Attendu : les deux qui BOUGENT quelque chose (rideau, fenêtre)
     demandent un petit moteur et un `Base.Receiver` ; les deux qui commutent
     n'en demandent pas. Vérifier aussi que la **gâche** et l'**opérateur de
     porte** demandent maintenant un moteur et un récepteur eux aussi, et que
     l'opérateur garde ses `Base.EngineParts`. [ ]
369. **Le rideau.** Trouver une fenêtre avec un rideau, clic droit **sur le
     rideau** → Matériel CeroSec → Installer Moteur de rideau. Le moteur ne se
     pose que sur un rideau **ouvert** (« le rideau est tiré » sinon), et tous les
     rideaux du monde naissent ouverts, donc juste après la pose, à
     l'ordinateur : `dev` → une ligne `curtainN`, et `cat /dev/curtainN` →
     `open`. `echo close > /dev/curtainN` → **le rideau se tire dans le monde**,
     la pièce s'assombrit, **on entend le tissu**, et `cat` répond `closed`.
     `echo open > /dev/curtainN` le rouvre, avec son bruit lui aussi.
     `dev curtainN toggle` fait l'aller-retour. Retaper deux fois le même mot :
     le rideau ne bouge qu'une fois et on ne l'entend qu'une fois. [ ]
370. **Le rideau d'une porte.** Poser un drap sur une **porte** (interaction
     vanille), puis un moteur de rideau **sur la porte**. Attendu : la porte est
     maintenant `doorN` ET `curtainM`, deux périphériques sur un objet. Ouvrir
     le rideau ne bouge PAS la porte, et ouvrir la porte ne bouge pas le
     rideau. [ ]
371. **La fenêtre : deux périphériques.** Sur une fenêtre, poser un **contact
     magnétique** puis un **opérateur de fenêtre**. Attendu : `dev` montre
     `winN` **et** `windowM`. `winN` reste `cr--r-----` et lit le loquet
     (`locked` / `unlocked`) ; `windowM` est `crw-rw----` et lit le battant
     (`closed`). [ ]
372. **Ouvrir la fenêtre, et ce que ça défait.** Verrouiller la fenêtre à la main
     (clic droit → verrouiller), vérifier `cat /dev/winN` → `locked`. Puis
     `echo open > /dev/windowM`. Attendu : **le battant s'ouvre** dans le monde,
     **on l'entend s'ouvrir** (et se refermer, avec `close`) comme si une main
     l'avait fait,
     et `cat /dev/winN` répond maintenant `unlocked`, le moteur a défait le
     loquet en passant. C'est voulu. Retaper le même ordre : rien ne bouge (c'est
     déjà ouvert). [ ]
373. **L'ALARME DE MAISON. À faire dans une maison où personne n'est entré.**
     Trouver une maison dont l'alarme n'a pas encore sonné, y poser l'ordinateur
     et un opérateur sur une fenêtre, **puis reculer**. `echo open >
     /dev/windowM`. Attendu : la fenêtre s'ouvre **et l'alarme se déclenche**,
     exactement comme si on avait cassé le carreau, le bruit, et ce qu'il
     attire. Ce n'est pas un bogue : c'est écrit dans le Volume 2, chapitre 6, et
     dans les notes de version. Refermer la fenêtre : **aucun** bruit. [ ]
374. **Les trois refus d'une fenêtre.** Barricader la fenêtre (planches) :
     `echo open > /dev/windowM` → `windowM: barricaded`, et le battant ne bouge
     pas derrière ses planches. Casser le carreau : `windowM: smashed`. Trouver
     une fenêtre de décor que le jeu n'ouvre jamais (une vitrine) et y poser un
     opérateur : `windowM: sealed`. [ ]
375. **La cuisinière, le micro-ondes et la cafetière.** Poser un **contacteur
     d'appareil** sur un four. `dev` → `stoveN`. `echo on > /dev/stoveN` →
     le four **s'allume** dans le monde (sprite, et il cuit vraiment : y mettre
     quelque chose et vérifier que ça chauffe). Couper le courant du quartier ou
     éteindre la génératrice : `stoveN: no power`. Recommencer sur un
     **micro-ondes** et sur une **cafetière** : le même module, la même sorte de
     périphérique. [ ]
376. **La laveuse.** Poser un contacteur sur une laveuse (ou une sécheuse, ou une
     machine combinée). `echo on > /dev/washerN` → elle se met en marche.
     `dev washerN toggle` l'arrête. En multijoueur, vérifier sur le **second
     client** que la machine tourne bien de son côté : c'est la seule qui a
     besoin d'un envoi de notre part. [ ]
377. **La génératrice.** Poser un **inverseur de groupe** sur une génératrice
     branchée, avec de l'essence. `cat /dev/genN` → une ligne entière :
     `off fuel 62 condition 80 connected` (les nombres sont ceux de la
     génératrice). `dev` → la colonne d'état ne montre QUE `off` : la phrase ne
     tient pas dans un tableau de 60 colonnes. `echo on > /dev/genN` →
     **elle démarre**, du premier coup, même usée. [ ]
378. **Les trois refus d'une génératrice.** La débrancher :
     `echo on > /dev/genN` → `genN: not connected`. La rebrancher et vider le
     réservoir : `genN: no fuel`. L'abîmer jusqu'à zéro : `genN: broken`.
     Dans les trois cas, `echo off > /dev/genN` est **accepté** : on ne discute
     jamais un arrêt. [ ]
379. **Montrer lequel c'est.** Avec deux fours dans la même cuisine :
     `dev find stove0`. Attendu : **un seul** des deux s'entoure d'un contour sur
     VOTRE écran, six secondes. Refaire avec `curtain0`, `washer0` et `gen0`. Le
     rideau d'une porte (étape 370) doit entourer **la porte**. [ ]
380. **Le monde sans l'option.** Mettre **Matériel requis** sur désactivé et
     recharger. Attendu : chaque rideau, four, laveuse et génératrice du bâtiment
     est sous `/dev` sans qu'on ait rien vissé, c'est plus qu'avant ce palier, et
     c'est ce que dit la note de version. [ ]
381. **Cent tours de boucle ne relisent pas le bâtiment cent fois.** Dans un
     bâtiment avec beaucoup de pièces (un centre commercial), écrire
     `while true; do cat /dev/door0 > /dev/null; sleep 5; done &` et laisser
     tourner une dizaine de minutes de jeu. Attendu : **aucune saccade**, et la
     fenêtre de débogage → **Scheduler** montre les mêmes millisecondes par
     passe qu'avec la boucle arrêtée. Pendant que ça tourne, ouvrir une porte à
     la main et faire `cat /dev/door0` : la lecture est **immédiatement** juste.
     Visser un module sur une autre porte : il apparaît dans `dev` tout de
     suite, sans attendre la minute. [ ]

## AM. La télévision, le poste de radio, et la seule synchro que le mod écrit lui-même (palier tuner)

Un module de plus, deux sortes de périphérique de plus, et **la première fois
qu'un ordre du serveur voyage dans un paquet à nous** : le moteur du jeu ne
transmet jamais un changement d'état de téléviseur fait côté serveur, alors le mod
s'en charge. L'étape 386 est celle qui compte, et elle se fait **à deux clients**.
Option **Matériel requis** activée (la valeur par défaut). Règles et preuves :
[DEVICES.md](DEVICES.md#the-hardware-modules), [PROTOCOL.md](PROTOCOL.md) et
[notes/actuators.md](notes/actuators.md) section 2.

382. **Fabriquer la commande de tuner.** Avec le **Guide de câblage CeroSec** lu,
     Électricité 2, un tournevis, des pinces, un `Base.RadioReceiver`, deux
     ferrailles électroniques, un fil et des vis : fabriquer une **Commande de
     tuner**. Attendu : la recette est dans l'onglet **Électrique**, elle ne
     demande **aucun petit moteur** (rien ne tourne là-dedans), et l'icône se
     distingue des huit autres boîtes dans le sac. [ ]
383. **Rien n'est câblé tant que rien n'est vissé.** À l'ordinateur, sans rien
     avoir posé : `dev`, aucune ligne `tv` ni `rx`, même avec un téléviseur dans
     la pièce. Clic droit sur le **téléviseur** → Matériel CeroSec → Installer
     Commande de tuner. `dev` → une ligne `tv0`. [ ]
384. **Lire le poste.** `cat /dev/tv0` → une ligne entière, par exemple
     `off channel 203 airing 1080-1440`. `dev` → la colonne d'état ne montre QUE
     `off` : la phrase ne tient pas dans un tableau de 60 colonnes, exactement
     comme pour la génératrice. [ ]
385. **L'allumer et changer de poste.** `echo on > /dev/tv0` → **l'écran
     s'allume** dans le monde (l'image, la lueur sur les murs, le son). Puis
     `dev tv0 channel 210` → l'image change de chaîne et la ligne répond
     `tv0: on channel 210`. `echo channel 203 > /dev/tv0` fait la même chose par
     l'autre chemin, c'est celui-là qu'une ligne de crontab écrit. [ ]
386. **LA SYNCHRO, ET IL FAUT DEUX CLIENTS.** Sur un serveur, avec un second
     joueur **dans la même pièce** et qui regarde le téléviseur : depuis
     l'ordinateur, `echo on > /dev/tv0`. Attendu : le poste s'allume **sur les
     deux écrans**, l'image et le son compris. `dev tv0 channel 210` : la chaîne
     change **sur les deux**. C'est l'étape qui prouve le palier, sans le paquet
     que le mod envoie, le second joueur verrait un poste éteint pour toujours.
     Vérifier aussi qu'il n'y a **pas de rebond** : personne ne voit l'écran
     clignoter ni le son se couper à chaque ordre. [ ]
387. **Celui qui arrive après.** Toujours à deux : allumer le poste, puis faire
     **déconnecter et reconnecter** le second joueur (ou le faire partir assez
     loin pour que le morceau de carte se décharge, puis revenir). Attendu : il
     retrouve le poste **allumé et sur la bonne chaîne**. Ça, c'est le moteur du
     jeu qui le fait tout seul et pas nous ; l'étape est là pour le constater. [ ]
388. **Le poste de radio est un second périphérique, pas un remplaçant.** Poser
     une commande de tuner sur un **poste de radio** (pas un émetteur) :
     `dev` → `rx0`, qui s'allume et se règle comme le téléviseur, avec les
     fréquences d'un poste (88000 à 108000). Puis, sur une **radio amateur** qui
     sert déjà de TNC à la machine : poser une commande de tuner dessus.
     Attendu : `/dev/radio0` est **toujours là**, toujours `cr--r-----`, et un
     `rx1` apparaît à côté. La fréquence d'émission reste celle que vous tournez
     à la main ; c'est le poste de réception que la machine commande. [ ]
389. **Les deux refus.** `echo channel 199 > /dev/tv0` → `tv0: out of range` (le
     cadran du poste ne descend pas si bas) et l'image ne bouge pas. Couper le
     courant du quartier et éteindre la génératrice, puis `echo on > /dev/tv0` →
     `tv0: no power`, et l'écran reste noir. Sur un poste à piles, retirer la
     pile : même mot. Rallumer le courant : l'ordre repasse. [ ]
390. **L'horaire, et la ligne de crontab qui en sort.** `cat /dev/tv0` sur la
     chaîne 203 (Life and Living TV) à différentes heures du jour. Attendu :
     `airing 1080-1440` quand une émission passe, `next 360-720` quand il n'y en a
     pas et qu'une autre suit, `idle` quand il ne reste rien aujourd'hui. Les
     nombres sont des **minutes depuis minuit** : 360 = 6 h, 720 = midi,
     1080 = 18 h. Se régler sur une fréquence que personne n'émet (par exemple
     5000) : la ligne s'arrête au cadran, sans mot d'horaire. [ ]
391. **Le poste s'allume pour l'émission, tout seul.** Écrire avec `crontab -e` :
     `0 18 * * * echo on > /dev/tv0` et `0 0 * * * echo off > /dev/tv0`. Laisser
     tourner jusqu'à 18 h de jeu, en étant **dans la pièce**. Attendu : le poste
     s'allume seul à l'heure dite, sur la chaîne où il était. C'est l'exemple que
     tout ce palier existe pour rendre possible. [ ]
392. **Le monde sans l'option.** Mettre **Matériel requis** sur désactivé et
     recharger. Attendu : chaque téléviseur et chaque poste de radio du bâtiment
     est sous `/dev` sans qu'on ait rien vissé. [ ]

## AN. La disquette qui fait tourner le bâtiment (palier automatisation)

Six programmes sur une disquette imprimée, `CeroSec HOME 1.0`. Rien de neuf dans
le moteur : ce sont des scripts `sh`, les périphériques du palier moteur et `cron`.
Ce qui se vérifie ici, c'est la seule chose qu'aucun banc ne peut voir, une porte
qui se referme toute seule sous les yeux du joueur. Option **Matériel requis**
activée. Règles : [CONTENT.md](CONTENT.md#home-automation-the-building-runs-itself)
et [SCRIPTING.md](SCRIPTING.md).

Préparation : un bâtiment avec **deux portes** et un **opérateur de porte** sur
l'une des deux, un **moteur de rideau** sur un rideau, un **relais** sur un
interrupteur, un **contact** sur une fenêtre, une **commande de tuner** sur un
téléviseur et un **interrupteur de génératrice** sur une génératrice branchée.

393. **Trouver la disquette, ou se la faire donner.** Fouiller des tiroirs jusqu'à
     tomber sur une disquette dont l'étiquette **imprimée** dit
     `CeroSec HOME 1.0`, l'infobulle dit *Étiquette imprimée* et l'icône porte la
     vignette blanche. Sinon : fenêtre de débogage (section X) → **Give disk** →
     `HOME AUTOMATION`. Attendu : la disquette arrive dans le sac avec ce nom. [ ]
394. **La monter et la lire.** `mount /dev/fd0 /mnt` puis `ls /mnt` → sept noms :
     `README.TXT` et les six programmes. `cat /mnt/README.TXT` → la page tient
     dans l'écran, sans ligne coupée, et nomme les six. `df` → la ligne `fd0`
     dit environ **4058 de 4096 octets**. [ ]
395. **Les copier, sans rien créer d'abord.** `ls -l /usr` → `local` est là, et
     `ls /usr/local/bin` → vide : la machine livre la chaîne. Puis exactement la
     ligne du README, `sudo cp /mnt/curtains.sh /usr/local/bin`, **aucun
     `mkdir`**. Copier les six de la même façon, puis `sudo chmod 755` sur chacun.
     Attendu : `ls -l /usr/local/bin` les montre tous exécutables. [ ]
395a. **Et ils répondent à leur nom.** `echo $PATH` → `/bin:/usr/local/bin`.
     `which curtains.sh` → `/usr/local/bin/curtains.sh`, puis `curtains.sh close`
     **sans `sh` ni chemin** → les rideaux se ferment. Dans un crontab, la ligne
     `* * * * * genwatch.sh 10` (nom nu, sans chemin) doit partir aussi : attendre
     une minute de jeu, `mail` → la sortie du programme et **jamais**
     `genwatch.sh: command not found`. Les lignes du README avec le chemin complet
     marchent toujours telles quelles. [ ]
396. **LA PORTE SE REFERME, ET C'EST L'ÉTAPE QUI COMPTE.** Lancer
     `sh /usr/local/bin/autoclose.sh start 5 &` → `[1] 43`. Aller **ouvrir la
     porte à la main** dans le monde, et **rester à la regarder**. Attendu : la
     porte se referme toute seule au bout de cinq tours (six à sept secondes de
     vrai temps, un tour est un `sleep 1` plus le travail du tour), avec le
     mouvement et le bruit d'une porte, **le bruit de CETTE porte** : une porte
     de bois et une porte de métal ne claquent pas pareil, et une porte déjà
     fermée ne fait aucun bruit du tout, et la porte **sans opérateur** ne bouge
     jamais. Rouvrir : ça recommence à zéro. [ ]
397. **L'arrêter, des deux façons.** `sh /usr/local/bin/autoclose.sh stop` →
     `autoclose: off`, et `ps` ne montre plus le programme au tour suivant.
     Relancer avec `&`, puis `kill %1` : ça marche aussi. `ls /var/tmp` montre ce
     que le programme garde : `autoclose.on` tant qu'il tourne, et un
     `autoclose.door0` par porte ouverte. [ ]
397b. **IL TOURNE ENCORE QUAND ON REVIENT DANS LA PARTIE.** C'est l'étape du
     rangement : une machine que personne n'a éteinte n'a jamais cessé de
     travailler. Relancer `sh /usr/local/bin/autoclose.sh start 5 &` → `[1] 43`.
     Laisser la machine **allumée**, fermer le terminal, **quitter vers le menu**
     (la partie est sauvegardée), puis recharger la sauvegarde et revenir devant
     le même ordinateur. Attendu : l'écran est celui qu'on avait laissé, `jobs`
     montre **la même ligne** `[1] running` ou `[1] sleeping` avec
     `sh /usr/local/bin/autoclose.sh start 5 &` dedans, et `ps` donne le même
     numéro de travail qu'avant. Ouvrir une porte à la main : elle se **referme
     toujours** toute seule au bout de cinq tours. `ls /var/tmp` montre
     `autoclose.on` encore là. [ ]
397c. **Ce qui ne revient pas, et c'est voulu.** Toujours sur la même machine :
     `shutdown -h +9`, puis quitter vers le menu et recharger. Attendu : la
     machine est **encore allumée** et `jobs` ne montre **aucun** `shutdown` en
     attente, un ordre donné à l'horloge du monde réel ne traverse pas une
     sauvegarde, et le README le dit déjà. Même essai avec un script qui pose une
     question (`read`) : au rechargement l'écran est **revenu à l'invite**, pas à
     la question. Un `&` relancé après ça tourne normalement. [ ]
397d. **L'interrupteur, lui, arrête tout.** Relancer le démon avec `&`, puis
     **éteindre** l'ordinateur au bouton (ou couper le générateur), le rallumer,
     et quitter/recharger. Attendu : `jobs` ne montre rien du tout, l'extinction
     a emporté le travail au moment où elle a eu lieu, et rien ne le ramène. Même
     chose pour une machine **ramassée** puis reposée. [ ]
398. **Les rideaux, à l'heure.** `sh /usr/local/bin/curtains.sh close` → tous les
     rideaux se ferment dans le monde, **et on les entend**, un par rideau.
     Relancer la même ligne tout de suite : le script dit la même chose et plus
     rien ne bouge ni ne se fait entendre. Puis `crontab -e` et les deux lignes du
     README :

         0 7 * * * sh /usr/local/bin/curtains.sh auto
         0 20 * * * sh /usr/local/bin/curtains.sh auto

     Laisser tourner jusqu'à 7 h de jeu **en étant dans la pièce**. Attendu : les
     rideaux s'ouvrent seuls, et se referment seuls à 20 h. `mail` → la sortie de
     la ligne de cron, `2 curtains: open`. [ ]
399. **Le téléviseur pour l'émission.** `crontab -e` et
     `* * * * * sh /usr/local/bin/tvguide.sh 203`. Régler le poste à la main sur
     une autre chaîne, puis attendre une minute de jeu. Attendu : le poste est
     **remis sur 203**, puis allumé quand `cat /dev/tv0` dit `airing` et éteint
     dès que la ligne ne le dit plus. Pendant l'émission, il ne **cligne pas** :
     la chaîne n'est retournée qu'une fois. [ ]
400. **Le réveil, des deux façons.** `sh /usr/local/bin/wake.sh now` → le poste de
     radio s'allume et toutes les lumières avec. Puis
     `sh /usr/local/bin/wake.sh 06:30` → `atq` montre le travail en attente, et à
     6 h 30 de jeu tout s'allume seul. `atrm 1` l'enlève. [ ]
401. **L'alarme.** `sh /usr/local/bin/alarm.sh start &`, puis **ouvrir la fenêtre
     à la main**. Attendu : `ALARM: win0 open` apparaît sur **tous les écrans** de
     la machine (à deux joueurs : sur les deux), et les lumières clignotent trois
     fois dans le monde. Refermer, puis `sh /usr/local/bin/alarm.sh stop` : le
     programme s'arrête au tour suivant, il peut mettre jusqu'à huit secondes s'il
     était en train de clignoter. [ ]
402. **La génératrice.** Vider le réservoir jusque sous 10 %, puis
     `sh /usr/local/bin/genwatch.sh 10`. Attendu : une ligne sur tous les écrans,
     **une** lettre dans `mail` pour root, et `ls /var/tmp` montre
     `genwatch.said`. Le relancer : **rien de plus**. Remplir le réservoir, le
     relancer : le drapeau disparaît et la prochaine panne sèche redonne une
     lettre. [ ]
403. **Ce qu'ils disent quand il n'y a rien.** Sur une machine **sans rien de
     vissé** : `sh /mnt/curtains.sh open` → `curtains.sh: no curtain in /dev`,
     `sh /mnt/tvguide.sh` → `tvguide.sh: no tv0 in /dev`, `sh /mnt/genwatch.sh` →
     `genwatch.sh: gen0 gave no fuel figure`. Et sans argument :
     `sh /mnt/curtains.sh` → la ligne d'usage. Aucun des six ne dit
     `syntax error` ni ne laisse une erreur du shell sur l'écran. [ ]
404. **Sur les machines qui l'avaient déjà.** Dans le magasin d'informatique
     (`showroom`) : `ls bin` sur la machine du comptoir → une chance sur trois d'y
     trouver `autoclose.sh` et `curtains.sh`. Chez CeroSec (`cerosec`) :
     `ls /usr/local/src` → les six, avec les quatorze autres. Attendu :
     **aucune ligne de crontab** ne les appelle nulle part, vérifier avec
     `sudo cat /var/spool/cron/*`. Une maison (`residential`) n'a rien de tout ça
     et n'a pas de crontab du tout. [ ]

## AO. Poser un module : dedans, ouvert, et le refuge (palier pose)

Un module se pose et se retire **de l'intérieur**, sur une chose **ouverte** ou
**éteinte**, et, si le serveur a activé l'option, seulement par un membre du
refuge. Les trois refus sont décidés côté serveur et le menu grise l'entrée avec
le **même mot**. Le tableau complet est dans
[DEVICES.md](DEVICES.md#the-hardware-modules).

405. **Depuis le trottoir, rien.** Une porte extérieure ouverte, un contact
     magnétique, un tournevis et Électricité 1. Se placer **dehors**, clic droit
     sur la porte → Matériel CeroSec → Installer : l'entrée est **grisée**,
     infobulle « Ça se fait de l'intérieur. ». Faire un pas à l'intérieur, même
     clic droit : l'entrée est vivante et la pose se fait. [ ]
406. **Une porte fermée ne prend rien.** Refermer la porte, clic droit →
     l'entrée est grisée, « Ouvrez-la d'abord. ». Rouvrir : elle repart. Même
     essai sur une **fenêtre** fermée avec un opérateur de fenêtre en poche :
     même mot. [ ]
407. **Un rideau tiré, un appareil qui marche.** Rideau fermé + moteur de rideau
     → grisé, « Tirez le rideau d'abord. ». Four allumé + interrupteur
     d'appareil → grisé, « Éteignez-le d'abord. ». Téléviseur allumé + contrôle
     de tuner → même mot. Génératrice en marche + interrupteur de groupe → même
     mot. Éteindre chaque chose : chaque entrée repart. [ ]
408. **La règle du dedans ne vaut que pour l'enveloppe.** Poser un relais sur un
     interrupteur **avec la lumière allumée** : ça passe. Poser un interrupteur de
     groupe sur une génératrice **dehors, sur le trottoir** : ça passe. Poser un
     relais sur une **lampe de galerie** (une *Round Outdoor Lamp* vissée sur le
     mur extérieur d'une maison), **debout sur le trottoir** : ça passe aussi, et
     c'est le cas pour lequel le relais existe, une lumière extérieure sur une
     minuterie. Un four ou un poste de radio qu'un survivant a traîné dehors :
     pareil. Seules la porte, la fenêtre et le rideau demandent qu'on soit
     dedans. [ ]
409. **Retirer demande la même chose.** Avec un module posé sur une porte
     intérieure ouverte : clic droit → Retirer fonctionne. Refermer la porte →
     Retirer est grisé, « Ouvrez-la d'abord. ». Sortir sur le trottoir avec la
     porte ouverte → grisé, « Ça se fait de l'intérieur. ». C'est la moitié qui
     compte : sans elle, n'importe qui dévisse le matériel de dehors. [ ]
410. **Une porte intérieure se câble des deux côtés.** Une porte entre deux
     pièces, ouverte : le menu est vivant depuis l'une **et** depuis l'autre. [ ]
411. **L'option du refuge (multijoueur).** Dans le bac à sable, activer
     **Membres du refuge seulement**. Un joueur revendique un refuge; un autre
     joueur, non membre, se place devant une porte du refuge avec un contact et
     un tournevis → l'entrée est grisée, « C'est le refuge de quelqu'un
     d'autre. », et Retirer l'est aussi. L'ajouter au refuge : les deux entrées
     repartent. Le propriétaire et un **admin** passent sans rien faire de plus.
     Une porte **hors** du rectangle du refuge reste ouverte à tout le monde. [ ]
412. **Et l'option désactivée est la valeur par défaut.** La remettre à
     désactivé (c'est son état d'origine) : le même non-membre pose et retire le
     module sans rien demander à personne. En **solo**, l'option activée ne
     change rien du tout, il n'y a pas de refuge. [ ]
413. **Le bâtiment déjà câblé n'est pas touché.** Dans un commerce pré-équipé
     (section AE), avec l'option du refuge activée et les portes fermées : les
     modules d'avant l'épidémie sont **toujours là** et `dev` les voit. La pose
     de 1991 n'est pas un geste de joueur et ne passe par aucune de ces
     règles. [ ]

414. **Le sous-menu dit ce qu'est chaque boîtier.** Clic droit sur une porte
     **sans rien dans le sac** : l'entrée « Matériel CeroSec » est là et le
     sous-menu montre **exactement trois lignes**, contact magnétique, gâche
     électrique, opérateur de porte, toutes grisées. Chaque infobulle donne
     d'abord ce que le boîtier fait et le périphérique qu'il donne, puis en
     dessous la raison : « Vous n'en avez pas sur vous. » (ou, sans avoir lu le
     manuel de chantier, la ligne qui y renvoie). Aucune ligne pour le relais,
     le moteur de rideau, l'opérateur de fenêtre, l'interrupteur d'appareil,
     l'interrupteur de groupe ni le contrôle de tuner. [ ]
415. **Une ligne par sorte de chose.** Interrupteur → **relais** seulement.
     Fenêtre → contact + opérateur de fenêtre. Rideau → moteur de rideau. Four
     ou laveuse → interrupteur d'appareil. Génératrice → interrupteur de groupe.
     Téléviseur ou poste de radio → contrôle de tuner. Une porte avec un
     **rideau** dessus → les trois de la porte **plus** le moteur de rideau.
     Clic droit sur un frigo → **aucune** entrée « Matériel CeroSec ». [ ]
416. **Électricité 0.** Avec les trois boîtiers de porte et un tournevis en
     main, à Électricité 0 : les trois lignes sont grisées, chacune avec sa
     description **et** « Électricité 1/2/3 requise. » en dessous. Monter la
     compétence : les lignes repartent et gardent leur description. [ ]

417. **La porte du mur sud est un périphérique.** Dans une maison, choisir une
     porte extérieure du mur **sud** (ou **est**), celle qui donne sur la cour ou
     la ruelle derrière, pas celle de la façade nord. Se placer dedans, la porte
     ouverte, poser un **contact magnétique** dessus. Retourner au terminal et
     taper `dev` : la porte est **dans la liste**, avec « exterior », son décalage
     (`0 1S` pour une porte une case au sud du bureau) et son mur (`N`). Poser
     ensuite un contact sur une porte du mur **nord** : les deux sont là. Avant
     0.5.0 seules les portes des murs nord et ouest apparaissaient : une porte de
     mur sud se tient sur la case **dehors**, et la machine n'y allait jamais. [ ]
418. **La lampe de galerie aussi, et pas le lampadaire.** Avec le relais posé à
     l'étape 408 sur la lampe du mur extérieur : `dev` la montre comme un `light`
     de plus, « exterior », sur le mur qu'elle éclaire, et `dev light1 off`
     l'éteint depuis le clavier. Poser un relais sur un **lampadaire** de la rue
     (un poteau, pas un mur) : il ne paraît **jamais** dans `dev`, il n'est
     accroché à aucun mur du bâtiment. C'est le cas que le **câble** existe pour
     (section AQ) ; sans câble, rien ne l'entend. [ ]

## AP. Le module reste sur place quand le support s'en va (palier chute)

Un module vit dans le modData du **support** (la porte, le poste, l'interrupteur).
Avant ce palier, le support partait et le boîtier partait avec lui : c'était le seul
geste qu'un survivant ne pouvait pas défaire. Maintenant, quand le support quitte le
monde, ramassé, démonté, défoncé, **chaque module posé dessus tombe par terre sur
la case où la chose se tenait**, à côté de la poignée et des charnières que la porte
laisse déjà. Les neuf chemins et les deux qui ne doivent rien lâcher sont dans
[notes/modules-proofs.md](notes/modules-proofs.md), section 10.

419. **Ramasser un téléviseur avec un contrôle de tuner dessus.** Poser un
     **contrôle de tuner** sur un téléviseur (étape 372), vérifier qu'il est dans
     `dev` comme `tvN`. Puis ramasser le téléviseur : clic droit → **Ramasser**.
     Attendu : le poste est dans le sac, et le **contrôle de tuner est par terre sur
     la case** où il était, un objet au sol, ramassable, le même item qu'à la
     fabrication. Le reposer ailleurs : il arrive **nu**, `dev` ne montre aucun
     `tvN` tant qu'on n'a pas revissé le boîtier dessus. Revisser le tuner
     ramassé : le poste redevient un `tvN`. [ ]
420. **Défoncer une porte avec un contact et une gâche.** Sur une porte extérieure
     avec un **contact magnétique** et une **gâche électrique** dessus (étapes 229 à
     233), à la masse : clic droit → **Détruire**. Attendu : la porte disparaît, et
     **les deux boîtiers sont au sol dans l'embrasure**, avec la poignée, les
     planches et les charnières que le jeu y laisse. `dev` ne liste plus ni `doorN`
     ni `lockN`, et `dev doorN` répond `doorN: no such device`, le numéro reste
     dépensé, comme toujours. Même chose avec une porte **construite** (IsoThumpable)
     et avec un mur démonté au tournevis (**Démonter**). [ ]
421. **Une fenêtre BRISÉE garde son contact.** Poser un contact sur une fenêtre,
     puis la **briser** (la ramasser et échouer le jet, ou la casser à la main).
     Attendu : la fenêtre est toujours là, **rien n'est tombé**, et `dev winN` répond
     `winN: smashed`. C'est voulu : un châssis brisé est un châssis, et le contact
     est encore vissé dessus. [ ]
422. **Le voisinage qui se décharge ne retire rien.** Avec deux ou trois modules
     posés, s'éloigner assez pour décharger le quartier (section V), revenir :
     **aucun boîtier par terre**, tous encore en place, `dev` identique avec les
     mêmes numéros. Un support que le streamer a rangé n'a pas quitté le monde. [ ]
423. **En multijoueur (si testé).** L'hôte pose un contact sur une porte ; le client
     défonce la porte. Attendu : **les deux** voient le contact tomber au sol dans
     l'embrasure (il est créé par le serveur et diffusé), et sur les deux machines
     `dev` ne liste plus la porte. Le client ramasse le contact : il est dans son
     sac. [ ]
424. **Une sorte au complet en un mot.** Dans un bâtiment avec au moins deux
     fenêtres motorisées, dont une **barricadée** : `dev window` pour lire le
     tableau, puis `dev window close`. Attendu : une ligne de réponse par
     appareil, **dans l'ordre exact du tableau**, chacune ce que l'appareil aurait
     répondu seul, les châssis se ferment dans le monde et la barricadée répond
     `windowN: barricaded`. Puis `echo $?` → **autre chose que 0** parce qu'une a
     refusé ; refaire sans la barricadée (`dev light off`, `dev curtain toggle`,
     chaque rideau part dans SON sens) → `echo $?` → `0`. `dev nothing close` →
     `dev: nothing: unknown kind`. Depuis un compte hors du groupe `sudo` : une
     ligne `permission denied` par appareil et rien ne bouge dans le monde. [ ]

## AQ. Le câble jusqu'à l'ordinateur (palier lien)

Un module posé sur un lampadaire ne sert à rien tant qu'aucune machine ne l'entend :
la machine voit son **bâtiment** et rien d'autre. Le câble est la réponse, un fil
électrique par case, trente cases au plus, rendu quand on le débranche. Le lien est
écrit sur l'**appareil** (la liste des machines et ce que chaque câble a coûté) et sur
la **machine** (la liste des cases à visiter) ; les deux se remettent d'accord tout
seuls au tour de ronde suivant. La règle complète est dans
[DEVICES.md](DEVICES.md#the-cable-when-the-fixture-is-in-no-building).

424. **Le lampadaire de la rue entre dans `dev`.** Sur un **lampadaire** (un poteau,
     pas un mur) à une douzaine de cases d'un ordinateur : poser un **relais**
     dessus (étape 418 : il ne paraît dans aucun `dev`). Avec un tournevis,
     Électricité 1 et une vingtaine de **fils électriques** dans le sac, clic droit
     sur le lampadaire → **Relier à un ordinateur**. Attendu : un sous-menu avec une
     ligne par machine à portée, la plus proche en haut, écrite
     « `ksp-front-01, 12 cases, 12 fils` », le **nom d'hôte** de la machine, la
     distance et le prix. Cliquer : le survivant se tourne vers le poteau, une barre
     de progression, et à la fin **12 fils en moins** dans le sac. Retourner au
     terminal : `dev` liste un `lightN` de plus et `dev lightN off` éteint le
     lampadaire depuis le clavier. [ ]
425. **Ce que le câble a coûté se lit dans `dev find`.** Sur ce même `lightN` :
     `dev find lightN` répond `lightN: blinking, linked, 12 tiles of wire`, le
     lampadaire clignote six secondes comme n'importe quelle lumière, et la ligne
     dit en plus qu'il est au bout d'un câble et ce qu'il a coûté. Sur une lumière
     du bâtiment, **pas** de `linked` : la ligne est celle d'avant. [ ]
426. **Le prix est la distance, à la case près, plus les étages.** Compter les cases
     entre l'appareil et la machine en diagonale : la ligne du menu annonce la
     **distance arrondie au-dessus** et le même nombre de fils. Recommencer vers une
     machine **à l'étage au-dessus**, trois cases plus loin sur le plan : la ligne dit
     « `3 cases, 7 fils` », quatre fils de plus par étage, parce qu'un câble monte
     dans un mur et court dans un plafond. Une machine sur la **case même** de
     l'appareil : 1 fil, jamais 0. [ ]
427. **Trente cases, et pas une de plus.** Une machine à plus de trente cases n'a
     **aucune ligne** dans le sous-menu, rien de grisé, rien du tout : c'est la
     seule chose qu'un survivant ne peut pas corriger d'où il est. Vérifier la
     bordure : à trente cases la ligne est là, à trente et une elle a disparu. Une
     machine à vingt-huit cases mais **un étage plus haut** coûte 32 fils et n'est
     donc pas non plus dans la liste. Une machine dont le quartier n'est **pas
     chargé** n'y est pas non plus. [ ]
428. **Les lignes grisées disent laquelle.** Chaque refus, une ligne grise avec sa
     phrase sous la description :
     - moins de fils qu'il n'en faut → « Il faut 14 fils électriques. » (le nombre
       est celui de ce câble-là) ;
     - un câble déjà tiré entre ces deux-là → « Cet ordinateur y est déjà relié. » ;
     - quatre câbles déjà sur l'appareil → « Cet appareil répond déjà à 4
       ordinateurs. » ;
     - trente-deux câbles déjà sur la machine → « Cet ordinateur a déjà 32
       câbles. » ;
     - sans tournevis → « Il vous faut un tournevis. » ; Électricité trop basse →
       « Électricité 3 requise. » (le niveau du **plus exigeant** des modules posés
       sur l'appareil) ;
     - refuge d'un autre, option activée → « C'est le refuge de quelqu'un
       d'autre. ».
     Un appareil **nu** (aucun module dessus) n'a pas d'entrée **Relier à un
     ordinateur** du tout : c'est le seul refus que le menu cache, et le sous-menu
     du matériel juste au-dessus dit déjà quoi faire. [ ]
429. **Ce qu'un câble ne demande pas.** Debout **sur le trottoir**, la porte du
     bâtiment **fermée**, l'ordinateur **éteint** : la ligne est vivante et le câble
     se tire. Aucune des trois règles de la pose (dedans, ouvert, allumé) ne vaut ici,
     un câble va au dos de la machine, pas à une session, et c'est justement la
     réponse à « je ne peux pas atteindre cette chose ». [ ]
430. **Débrancher rend le fil.** Clic droit sur le lampadaire → **Débrancher de
     ksp-front-01** (une ligne par câble déjà tiré). Attendu : les **12 fils
     reviennent dans le sac**, `dev` ne montre plus le `lightN`, et `dev lightN`
     répond `lightN: no such device`, le numéro reste dépensé, comme toujours.
     Débrancher ne demande ni la portée, ni les fils, ni le tournevis : seulement le
     refuge. [ ]
431. **Un appareil dont le module est parti garde son câble.** Câbler le lampadaire,
     puis **retirer le relais** (clic droit → Retirer). Attendu : le câble est
     toujours là, l'entrée **Débrancher** aussi, et elle rend les fils. Sans ça, le
     seul moyen de récupérer son fil serait d'abattre le poteau. `dev` ne liste plus
     rien pour ce poteau : le fil va à un appareil qui n'a plus de périphérique
     dessus. [ ]
432. **Quatre machines sur le même appareil.** Sur une porte déjà dans le `dev` de la
     machine du bâtiment, tirer un câble vers une **deuxième** machine, dans une autre
     maison à portée. Attendu : la porte est dans les **deux** `dev`, chacune avec son
     propre numéro, et les deux la commandent. Sur la machine du bâtiment,
     `dev find doorN` ne dit **rien de plus** (elle l'a par le bâtiment) ; sur la
     deuxième, la ligne dit `linked, N tiles of wire`. Tirer un troisième et un
     quatrième câble : ça passe. Le **cinquième** est grisé, « Cet appareil répond
     déjà à 4 ordinateurs. ». [ ]
433. **Le quartier qui se décharge ne coupe rien.** Avec deux câbles tirés,
     s'éloigner assez pour décharger le quartier (section V), ouvrir un terminal sur
     une machine hors de portée, puis revenir. Attendu : les câbles sont **toujours
     là**, `dev` remontre les appareils avec les **mêmes numéros** et le même coût
     dans `dev find`. Une case que le jeu n'a pas chargée est gardée telle quelle :
     une machine qui oublierait un câble pendant que le quartier dort serait une
     machine qui a fait payer un câble puis l'a repris. [ ]
434. **Ramasser l'appareil rend les boîtiers ET le fil.** Sur un **interrupteur**
     avec un relais dessus et un câble de 12 cases vers une machine : le ramasser
     (clic droit → Ramasser, ou le démonter). Attendu : sur la case où il était, le
     **relais** par terre **et 12 fils électriques**, ramassables. Retourner au
     terminal de la machine : le `lightN` a disparu de `dev` au tour suivant, sans
     que personne n'ait rien débranché. [ ]
435. **Renommer la machine ne coupe rien.** Sur la machine au bout du câble :
     `hostname ksp-renommee` (ou éditer `/etc/hostname` et redémarrer). Clic droit
     sur l'appareil câblé : les deux lignes, **Relier** et **Débrancher de**,
     portent le **nouveau nom**, et le câble n'a pas bougé. Le lien est écrit sur la
     **case** où la machine se tient, jamais sur son nom. Déplacer la machine d'une
     case (la ramasser et la reposer à côté) : le câble ne la suit **pas**, c'est un
     autre endroit ; la ligne **Débrancher** disparaît et l'appareil sort de son
     `dev` au tour suivant. [ ]
436. **Une sauvegarde d'avant ce palier ne change pas.** Charger une sauvegarde faite
     avant cette version, avec des modules posés (section Z). Attendu : les appareils
     ont exactement les mêmes périphériques et les mêmes numéros, aucune ligne
     **Débrancher** nulle part, et le sous-menu **Relier à un ordinateur** est là,
     vide de câbles. Aucun numéro de version n'a bougé pour ce palier : une machine
     sans câble est une machine sans la clé. [ ]
437. **En multijoueur (si testé).** L'hôte tire un câble d'un lampadaire vers sa
     machine ; le client regarde le même lampadaire : il voit l'entrée **Débrancher
     de** (le lien est diffusé avec le reste du modData de l'appareil) et, sur un
     terminal de cette machine, le `lightN`. Le client débranche : les fils vont dans
     **son** sac, et les deux voient le périphérique disparaître. Toutes les
     vérifications sont refaites côté serveur : ce que le menu décide est ce qu'un
     joueur **voit**, jamais ce qu'il a le droit de faire. [ ]

## Rapport

| Étape | OK/KO | Note |
| --- | --- | --- |
| | | |
