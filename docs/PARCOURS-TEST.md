# Parcours de test CeroSec

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
7. Personnage déjà debout sur le carré devant l'écran, clic droit, bascule → pas
   de marche du tout, directement l'animation. [ ]
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
61. `admin`, `sudo adduser bob`, mot de passe vide → `bob: created` puis
    `adduser: set a password with passwd bob`. `ls -l /home` → `bob`,
    `drwxr-x---`. `id bob` → `uid=bob flag=user groups=bob`. [ ]
62. `adduser Bob` → `adduser: Bob: invalid name`. `adduser admin` →
    `adduser: admin: already exists`. `adduser -a kate` puis `id kate` →
    `flag=admin`, mais `sudo ls` en `kate` reste
    `kate is not in the sudoers file.` [ ]
63. `deluser root` → `deluser: root: cannot remove`. `admin`,
    `sudo deluser admin` → `deluser: admin: user is logged in`. `deluser bob`
    sans `-r` → `id bob` devient `no such user` mais `ls -l /home` montre
    encore le dossier `bob`. `deluser -r carl` → le dossier disparaît. [ ]
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
68. `sudo adduser bob`, `passwd bob`, se reconnecter en `bob`,
    `echo off > /dev/light0` → `light0: permission denied`, la lumière reste
    allumée. [ ]
69. `root`, ajouter une ligne `bob` à `/etc/sudoers`, puis `bob`, `id` →
    `groups=bob,sudo`, et `echo off > /dev/light0` fonctionne. Retirer la
    ligne : ça s'arrête, sans redémarrer la machine. [ ]
70. `admin` : `sudo groupadd crew`, `sudo gpasswd -a bob crew`,
    `mkdir /home/admin/shared`, `chgrp crew /home/admin/shared`,
    `chmod 770 /home/admin/shared`, `chmod 755 /home/admin`. `bob` :
    `cd /home/admin/shared`, `write note.txt hi`, `ls -l` → le fichier est là,
    propriété de `bob`, groupe `bob`. `admin` : `cat shared/note.txt` → `hi`. [ ]
71. `sudo adduser kate`, se reconnecter en `kate`, `ls /home/admin/shared` →
    `permission denied` (troisième compte, pas membre). [ ]
72. `admin`, `chmod 700 /home/admin/shared` → `bob` refusé à `ls`. Remettre
    `770` → `bob` rentre de nouveau. [ ]
73. `root`, `groupdel crew` → `ls -l /home/admin` montre encore `crew` dans la
    colonne groupe, personne dedans ; `chgrp crew /home/admin/shared` répond
    ensuite `chgrp: crew: no such group`. `groupdel root`, `groupdel sudo` et
    `groupdel users` répondent tous `cannot remove`. [ ]

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
    `write /bin/ls "list a directory"`, `chmod 755 /bin/ls` → `ls` refonctionne. [ ]
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
    `chgrp`, `gpasswd`, `groupadd`, etc.) et `cat /etc/sudoers` (en `root`)
    montre la liste livrée, sans que rien d'existant sur le disque ait
    bougé. [ ]

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
     (`Base.MotionSensor`) — le module électronique : il se ramasse dans le
     butin d'électronique, se démonte d'une `HomeAlarm`
     (`recipes_electrical.txt:78`), ou se donne en debug — et le **laisser
     tomber par terre** dans la pièce nommée où se trouve l'ordinateur.
     `dev sensor` → une ligne `sensorN`, description = le nom brut de la pièce,
     colonne côté **vide**, position juste, état `clear`. `ls -l /dev` sur cette
     ligne → `cr--r-----` et non `crw-rw----` : mode `440`. Lâcher un marteau à
     côté → il n'apparaît **pas**. [ ]
100f'. **Et la bombe n'en est pas un.** Fabriquer (ou se donner) un
     `PipeBombSensorV1` — une bombe artisanale avec un détecteur dessus — et le
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
102. Menu debug → Items list, filtre `CeroSec` → quatre objets :
     `CeroSec.ManualUser`, `CeroSec.ManualAdmin`, `CeroSec.ManualProgrammer` et
     `CeroSec.Manual`. Catégorie affichée Literature pour les quatre, noms
     "CeroSec OS User's Guide", "... System Administrator's Guide",
     "... Programmer's Guide", "CeroSec OS User's Manual". Faire apparaître les
     trois volumes dans l'inventaire → trois icônes DIFFÉRENTES : le même livre
     à petit écran vert, relié bleu marqué 1, vert marqué 2, rouge marqué 3.
     Jamais un point d'interrogation blanc, et le chiffre reste lisible à la
     taille où l'inventaire les dessine. [ ]
103. Clic droit sur chaque volume dans l'inventaire → "Read the User's Guide" /
     "Read the System Administrator's Guide" / "Read the Programmer's Guide",
     une seule option et la bonne ; pas de "Read" ni "Write" ni "Look at
     pictures" de la vanille. Sélectionner les trois ensemble → trois options,
     dans l'ordre 1, 2, 3. Et `CeroSec.Manual`, le livre d'avant le coffret :
     "Read the manual", qui ouvre le **volume 1** -- le volume qu'il est devenu.
     L'ancien livre unique n'existe plus comme texte : vérifier que sa
     couverture dit bien `CeroSec OS 1.0 User's Guide` et que sa table des
     matières est celle du volume 1 (`1. Your first day`), et non celle de
     l'ancien livre (`1. Your machine`). [ ]
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
     `CeroSec.ManualProgrammer` à 1, dans cet ordre, et `CeroSec.Manual`
     ABSENT de la liste. Liste `UniversityDesk_Computer` :
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
capture d'écran de Mathieu qui les a fait écrire (`while: command not found`).

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
142. `x=5` puis `echo $x` → `5`. Fermer la fenêtre, s'éloigner, revenir,
     rouvrir → `echo $x` répond encore `5`. `exit` puis se reconnecter →
     `echo [$x]` répond `[]` : une déconnexion emporte les variables. Vérifier
     aussi que `cd /etc` à l'invite déplace bien l'invite (`pwd`), alors que
     `cd /etc` **dans** un script ne la déplace pas. [ ]
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
147. En `root` : `shutdown -r +2` → `The system is going down for reboot in 2
     minutes!` s'affiche sur **tous** les écrans ouverts sur la machine.
     `shutdown -h +5` → `shutdown: already scheduled`. Attendre une minute →
     `... in 1 minute!`. `shutdown -c` → `shutdown: cancelled`, et la machine
     reste allumée passé le délai. Refaire `shutdown -r +1`, laisser filer →
     `The system is going down for reboot NOW!`, la machine s'éteint et la
     fenêtre se ferme, puis trois secondes de noir, puis le BIOS et `login:`
     dans une fenêtre rouverte toute seule — un `reboot` programmé est le même
     `reboot`. `halt` se comporte comme avant : la machine s'éteint et rien ne
     revient.
     Enfin : `shutdown -r +10`, **sauvegarder et recharger la partie** → le
     compte à rebours est oublié et la machine reste allumée (c'est voulu et
     c'est écrit dans le manuel). `halt` en `root` → la machine s'éteint. [ ]
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
     personne ; `sudo cd /` ne déplace toujours rien. [ ]
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

## L. Tubes, cron et `fg` (palier 5b)

166. Au shell : `ls /bin | wc` puis `ls /bin | grep sort`. La première ligne doit
     donner trois nombres (lignes, mots, octets) sans nom de fichier derrière,
     la seconde le seul mot `sort`. Confirmer surtout que rien de l'étage de
     gauche n'apparaît à l'écran : ce qui traverse le tube n'est pas affiché. [ ]
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
175. `sh watch.sh &` (n'importe quel script qui dort et écrit), puis `jobs`,
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
     Dans la session sur `gate` : `sudo adduser bob`, puis
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

193. `PATH`. À l'invite : `echo $PATH` → `/bin`. Puis `echo $HOME` →
     `/home/admin`. `type ls` → `ls is /bin/ls`, `type cd` →
     `cd is a shell builtin`, `type if` → `if is a shell keyword`,
     `which ls` → `/bin/ls`, et `which frobnicate` → **aucune ligne** (et rien
     d'autre non plus). [ ]
194. Une commande à soi. `mkdir bin`, `edit bin/hello` avec une seule ligne
     `echo salut`, sauver, `chmod 755 bin/hello`. Puis `hello` →
     `hello: command not found`. Ensuite `PATH=$PATH:$HOME/bin` et `hello` →
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
     `readlink lien` → `notes.txt`. Puis `rm lien` → `notes.txt` est toujours
     là (`cat notes.txt`). Refaire le lien, `mv lien deplace`,
     `readlink deplace` → toujours `notes.txt`. `ln -s rien casse` puis
     `cat casse` → `casse: no such file`, mais `ls -l casse` montre encore la
     flèche. `ln -s a b` et `ln -s b a` puis `cat a` →
     `too many levels of symbolic links`. Enfin `ln notes.txt dur` (sans `-s`)
     → la ligne d'usage `ln: usage: ln -s <target> <name>`. [ ]
197. `/dev/null`. `cat /dev/null` → **rien du tout** (pas même une ligne vide).
     `echo bruit > /dev/null` → rien, et `cat /dev/null` toujours rien.
     `df` avant et après doit donner exactement les mêmes nombres.
     `ls -l /dev` → une ligne `crw-rw-rw-  root  root  null` parmi les
     appareils, et `dev` (la commande) ne la montre pas. `rm /dev/null` →
     `rm: /dev/null: is a device`. [ ]
198. `/var/tmp` et `ls` dans un tube. `ls -l /var` → `tmp` est en
     `drwxrwxrwx`. `echo a moi > /var/tmp/mien.txt`, puis
     `sudo adduser bob`, `su bob` (mot de passe vide : Entrée), et depuis bob :
     `rm /var/tmp/mien.txt` → `permission denied`, alors que
     `echo a bob > /var/tmp/bob.txt` marche et que `rm /var/tmp/bob.txt` marche
     aussi. `exit` pour revenir. Ensuite, avec des lumières dans le bâtiment :
     `ls /dev` à l'écran affiche des colonnes, tandis que
     `for l in $(ls /dev | grep light); do dev $l off; done` doit éteindre
     chaque lumière et ne rien dire d'autre (aucun `invalid value`). [ ]

## R. La disquette (palier 4e)

Il faut une disquette : elle se trouve dans les bureaux, les cybercafés, les
magasins d'électronique et les caisses d'informatique — ou, en mode debug, par le
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
     rouvrir le clic droit** : **Insert floppy** est là et n'est PAS grisé — pas
     d'infobulle *Eject the floppy first* — et **Eject floppy** a disparu. C'est
     la copie du client qui est en cause et non la machine : le menu montrait la
     fente encore pleine alors que la disquette était dans les mains du
     survivant. [ ]
200. **Le lecteur, éteint.** Éteindre l'ordinateur (Turn off), puis clic droit :
     Insert et Eject sont toujours proposés — une fente est mécanique.
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
     `echo ... >> /mnt/gros.txt`) jusqu'à `disk full` — puis vérifier que
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
208. **Reprendre la machine avec la disquette dedans.** Disquette insérée et
     montée, ramasser l'ordinateur (clic droit → Pick up / prendre le meuble),
     le reposer ailleurs, le rallumer et se connecter : `ls /dev` → `fd0` est
     toujours là, rien n'est monté (`mount` ne liste que `hda`), et un seul
     `mount /dev/fd0 /mnt` retrouve les fichiers. [ ]
209. **Les droits sur le lecteur.** `sudo adduser bob`, `su bob`, puis
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

Depuis cette vague, la ligne appartient au **local** (« premises ») et non au
bâtiment : une maison est un local, un centre commercial en est trente. Les pas
215b et 215c sont là pour ça, et ils demandent un mall (le mall de Louisville ou
celui de West Point) avec deux boutiques différentes.

210. **Le numéro.** Allumer les deux et regarder le BIOS de chacun : sous la
     ligne `Ethernet: eth0 10.x.y.z` il doit y avoir une ligne
     `Phone line: NNN-NNNN` — **sept** chiffres, et le premier des trois premiers
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
     `là-bas`). **Rien ne s'affiche pendant environ quatre secondes** — c'est le
     modem qui compose et le poste d'en face qui sonne ; compter, ça doit se
     sentir — puis `CONNECT 2400`, puis `Connected.`, puis le `login:` de l'autre
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
     appeler son numéro : **rien pendant quinze secondes**, puis `NO CARRIER` —
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
     diffèrent, et sur chacun une ligne `Phone line: NNN-NNNN (NomDeLaZone)` — le
     nom de la boutique entre parenthèses. Depuis l'une, écrire l'adresse de
     l'autre dans `/etc/hosts` puis `ping <nom>` → 100 % de perte et
     `rlogin <nom>` → `No route to host` : ce n'est pas le même câble. Puis
     `cu` vers son numéro → l'appel passe. Poser un troisième ordinateur dans le
     **couloir** du mall (hors de toute boutique) : troisième numéro, troisième
     segment, et **aucun** nom entre parenthèses. Enfin, sur cette machine du
     couloir, `dev | wc -l` : le mall entier est **un** bâtiment pour `/dev`, donc
     la liste peut passer 96 entrées (le plafond est 256) et elle doit tenir
     jusqu'au bout — `dev light`, `dev door`, `dev win` kind par kind pour la
     lire. [ ]
215c. **Une maison reste un seul local.** Dans une maison ordinaire (pas un mall),
     poser deux ordinateurs dans deux pièces différentes, les allumer : **même**
     numéro de téléphone, **même** segment, et aucun nom entre parenthèses — les
     zones nommées qui couvrent une maison sont plus grandes qu'elle, donc elles
     ne comptent pas. Vérifier au passage qu'un appel vers ce numéro sonne sur la
     machine à l'adresse la plus basse (`who` là-bas), et que pendant ce temps
     l'autre machine de la maison ne peut pas appeler (`BUSY`). [ ]
215d. **Une sauvegarde d'avant cette vague.** Sur un monde créé avec une version
     précédente du mod, où un ordinateur avait déjà été allumé : le rallumer. Le
     BIOS doit afficher l'adresse `Ethernet:` comme avant **et** une ligne
     `Phone line:` (le central est calculé au moment où la machine revoit son
     carré). Une machine dont on regarde l'écran sans l'allumer doit aussi
     l'obtenir dès qu'on ouvre la fenêtre dessus. [ ]

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
217. **La liaison.** Régler les deux radios sur la **même** fréquence et les
     allumer. Depuis `ici` : `call <indicatif de là-bas>` (en majuscules) →
     `*** CONNECTED to <indicatif>`, puis le `login:` de l'autre machine. S'y
     connecter : l'invite devient `admin@<là-bas>`, `hostname` répond son nom.
     Vérifier que le mot de passe est demandé **même** avec le nom de `ici` dans
     `/etc/hosts.equiv` de `là-bas`. Puis là-bas : `who` → `ttyp0` avec
     `(<indicatif de ici>)` entre parenthèses, et `last` pareil. Ressortir avec
     `exit` → `*** DISCONNECTED` (et **pas** `Disconnected.`, qui est le
     téléphone, ni `Connection closed.`, qui est le fil). Rappeler et taper `~.`
     seul sur la ligne : même résultat, et l'écran revient à l'invite locale. [ ]
218. **Tout le comté écoute.** Prendre un talkie dans l'inventaire, le régler sur
     la **même** fréquence que les deux postes, l'allumer, et rester à portée.
     Refaire un `call` : dans la fenêtre du talkie doit apparaître une ligne
     `<indicatif appelé> de <indicatif appelant> *** CONNECTED`. Raccrocher : une
     deuxième ligne, la même avec `*** DISCONNECTED`. Changer la fréquence du
     talkie et refaire un appel : plus rien. C'est la leçon de sécurité du
     palier — la radio ne peut pas se taire, et la seule défense est de changer de
     fréquence. [ ]
219. **Les six silences.** Chacun de ces six cas doit répondre exactement
     `*** retry count exceeded`, et rien d'autre : (a) la radio de `là-bas`
     éteinte ; (b) sa pile retirée ; (c) sa fréquence changée (les deux postes
     allumés, mais pas sur la même) ; (d) la machine `là-bas` éteinte ;
     (e) un indicatif que personne n'a (`call W4ZZZ`) ; (f) son propre indicatif.
     Vérifier aussi les deux refus que la machine dit en son **propre** nom sans
     émettre : enlever la radio de la pièce de `ici` → `call: no radio` (et
     `dev radio` ne liste plus rien) ; la remettre, puis `rm /etc/callsign` en
     root → `call: no callsign`. [ ]
220. **La distance et le chargement du monde.** Laisser les deux postes allumés et
     accordés, puis s'éloigner : une liaison ne tient que jusqu'à la **plus
     petite** des deux portées (7500 tuiles pour un poste amateur). Plus
     intéressant et plus facile à provoquer : ouvrir une liaison, puis faire
     éteindre la radio d'en face (ou la déplacer hors de la pièce) pendant que la
     session est ouverte, et taper n'importe quoi → `*** retry count exceeded` et
     retour à l'invite locale (et **pas** `*** DISCONNECTED` : la liaison est
     tombée, personne n'a raccroché). Enfin le cas propre à la radio : s'éloigner
     assez pour que le morceau de carte de `là-bas` ne soit plus chargé, puis
     `call <son indicatif>` → `*** retry count exceeded`, alors que
     `cu 555-NNNN` vers la **même** machine marche toujours. Une radio est une
     tuile ; un disque, non. [ ]
221. **Un poste, une liaison, et ce qui ne s'émet pas.** Mettre **une seule**
     radio dans une pièce où il y a **deux** ordinateurs (la paire de la section
     N). Ouvrir une liaison depuis le premier, puis aller au second et faire
     `call <même indicatif>` → `*** BUSY`. Raccrocher, puis vérifier qu'une
     liaison ne se laisse pas automatiser : `crontab -e` avec
     `* * * * * call <indicatif>`, attendre une minute → `mail` dit
     `call: not a terminal`, **aucune** session ne s'est ouverte là-bas, et — le
     point important — **rien n'est passé sur les ondes** (le talkie de l'étape
     218, accordé et allumé, ne doit rien afficher). Finir par `crontab -r`.
     Vérifier aussi la lenteur : lancer `ls /bin` sur la machine d'en face, les
     lignes doivent arriver **deux par seconde**, visiblement plus lentement
     qu'un appel téléphonique (quatre) et rien ne doit manquer à la fin. [ ]

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
     230 — `doorN` n'a pas changé — mais `ls -l /dev` montre maintenant
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
     des quatre modules n'est proposé. C'est le changement de cette vague ;
     s'ils sont déjà là, la recette s'auto-apprend encore au niveau qui la
     fabrique. Se donner un `CeroSec.WiringGuide` : il s'appelle **Guide de
     câblage CeroSec**, il pèse 0,5, il est rangé sous **Ressource de recette**
     et son infobulle nomme les quatre modules. Clic droit → **Lire** — c'est
     l'entrée *vanilla*, aucune des nôtres, et le personnage s'assoit et lit.
     Attendu : à la fin, les quatre recettes sont apprises d'un coup, et un
     deuxième clic droit propose **Relire**. [ ]
235b. **Fabriquer les quatre.** Le guide lu, avec Électricité 1 : le contact
     magnétique et le module relais sont dans l'onglet **Électrique** de
     l'établi. À 2 la gâche apparaît, à 3 l'opérateur — la compétence barre
     toujours la fabrication, le livre n'enlève que l'ignorance. Vérifier qu'un
     tournevis est demandé et **rendu** (il est toujours là après la
     fabrication), et que l'opérateur mange bien une boîte de pièces de
     moteur. [ ]
235c. **L'électricien chevronné s'en passe.** Personnage monté à **Électricité
     7** sans avoir jamais vu le guide : le contact et le relais sont là quand
     même (la gâche à 8, l'opérateur à 9). C'est la forme vanilla — le
     magazine avance l'accès, il n'en est pas la seule porte. [ ]
236. **Le butin.** Dans une camionnette d'électricien, une boutique
     d'électronique, une caisse d'entrepôt, une quincaillerie ou un garage : on
     trouve des contacts assez souvent, des relais moins, des gâches encore
     moins et un opérateur rarement. Aucun module sur un bureau de bureau ni
     dans une bibliothèque — ce ne sont pas les mêmes étagères que les
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
Elle ne change que trois choses : allumer, éteindre, et où le personnage se
trouve. Tout le reste est en lecture. Détails et protocole dans
[DEBUG.md](DEBUG.md).

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
242. **L'onglet Machines.** Attendu : une ligne par ordinateur que le serveur
     tient, y compris celui du bâtiment loin, avec sa position, son orientation,
     on/off, si son morceau de carte est chargé, son nom, son adresse, son numéro
     de téléphone, son indicatif, ses jobs et le nombre de fenêtres ouvertes
     dessus. La machine devant laquelle on est est déjà sélectionnée. [ ]
243. **Sous la liste.** Attendu : le détail de la machine sélectionnée sur
     plusieurs lignes — son sprite, la version de son état, `sysv`, si le système
     passe, et sa console (qui est connecté, dans quel répertoire, combien de
     lignes à l'écran). Ouvrir le terminal dessus, taper `ls`, revenir à la
     fenêtre : le nombre de lignes a bougé dans les deux secondes. [ ]
243b. **Où la machine se trouve.** Toujours sous la liste, après la console :
     l'empreinte du bâtiment (coin, coin opposé, taille, superficie, nombre de
     pièces) ou `outdoors` pour une machine dans une base construite, le nom de la
     pièce, et une ligne par zone dans laquelle le carré se trouve — son type, son
     nom, sa position, `w x h`, sa boîte (`w*h`) et sa superficie réelle. Faire
     l'essai **dans un centre commercial** : attendu, la zone nommée du magasin est
     plus petite que le bâtiment autour d'elle, et pour une zone de forme
     irrégulière la superficie réelle est plus petite que sa boîte. Sur une machine
     dont le morceau de carte n'est pas chargé : `premises: no square (the chunk is
     away)` et rien d'autre — personne n'est là pour répondre. [ ]
244. **Sélectionner une autre machine.** Cliquer la ligne de l'ordinateur du
     bâtiment loin. Attendu : la liste garde ses lignes et la ligne cliquée reste
     surlignée, le détail dessous devient celui de cette machine, et les onglets
     Files et Devices se vident puis se remplissent avec ceux de la nouvelle
     machine — jamais le disque de l'ancienne sous le nom de la nouvelle. [ ]
245. **La machine dont le quartier n'est pas chargé.** Sa colonne **chunk** dit
     `away` et sa colonne **wire** dit `-` et pas `no` : personne n'est là pour
     répondre sur le courant. Attendu : elle est quand même **allumée** (`on`), et
     son nom et son adresse sont là, parce que le serveur tient son disque quoi
     que fasse le streamer. [ ]
246. **Éteindre à distance.** Machine loin sélectionnée, cliquer **Éteindre**.
     Attendu : sa colonne on/off passe à `off` dans les deux secondes. Rallumer
     avec **Allumer** : elle ne se rallume **que** si son morceau de carte est
     chargé (le courant se demande à un carré), sinon rien ne bouge — et c'est la
     bonne réponse. [ ]
247. **S'y téléporter.** Machine loin sélectionnée, cliquer **S'y téléporter** →
     le personnage se retrouve au milieu du carré de cette machine (pas sur le
     coin), le quartier se charge, et la colonne **chunk** de cette ligne passe à
     `here` au rafraîchissement suivant. [ ]
248. **Ouvrir le terminal.** Sur une machine allumée dont le quartier est chargé
     et à côté de laquelle on se trouve, cliquer **Ouvrir le terminal** → le
     terminal s'ouvre comme si on avait utilisé l'ordinateur par devant, sans la
     marche et sans la chaise. Sur une machine loin : rien ne s'ouvre (avec
     `CeroSec.DEBUG = true`, une ligne le dit dans la console). [ ]
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
251. **L'onglet Devices.** Attendu : une ligne par entrée de `/dev` de la machine
     sélectionnée, avec le même nom et le même état que `ls -l /dev` dans son
     terminal, plus ce que le terminal ne montre pas : le carré absolu de l'objet,
     la « poignée » qu'un `dev find` enverrait (le nom de sprite d'une porte, le
     type d'objet d'un détecteur posé par terre, **rien** pour un interrupteur —
     un interrupteur clignote au lieu d'être entouré), et si l'objet est encore
     là. Sous la liste : le carnet de numéros et un enregistrement par détecteur.
     [ ]
252. **Un périphérique qui s'en va.** Ramasser le détecteur posé par terre.
     Attendu : au rafraîchissement suivant sa ligne dit que l'objet est parti
     (`gone`) et son numéro reste dépensé — c'est la différence entre un
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
     le slot `[1]`, le nom, l'état, les pas, le temps processeur et la dette —
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
     Attendu aussi : il y a des lignes **même avec `CeroSec.DEBUG = false`** —
     l'impression dans la console est conditionnée par ce réglage, l'anneau non.
     [ ]
259. **Deux fenêtres, une seule.** Ouvrir la fenêtre, puis la rouvrir par le menu
     d'un autre ordinateur → la première se ferme, il n'y en a jamais deux. [ ]
260. **Redimensionner.** Tirer le coin de la fenêtre → la liste et les colonnes
     suivent le bord, les boutons restent sous la liste, et le bloc de détail
     reste lisible en bas. [ ]
261. **Fermer, et le rafraîchissement qui s'arrête.** Mettre
     `CeroSec.DEBUG = true`, ouvrir la fenêtre, la fermer par sa croix, et
     regarder la console pendant une minute. Attendu : plus rien de la fenêtre —
     elle ne demande plus rien au serveur. (C'est la fuite que
     `tests/debug_ui_test.lua` garde, mais elle se voit aussi comme ça.) [ ]
262. **Le drapeau.** Mettre `CeroSec.DEV_DEBUG_MENU = false` et
     `CeroSec.DEV_MANUAL_MENU = false`, recharger la partie. Attendu : plus de
     sous-menu **CeroSec (dev)** du tout sur le menu d'un ordinateur. Relancer le
     jeu avec `-debug` : le sous-menu revient avec **Fenêtre de débogage** dedans
     et **rien** d'autre — le manuel se trouve ou ne se lit pas. [ ]

## Rapport

| Étape | OK/KO | Note |
| --- | --- | --- |
| | | |
