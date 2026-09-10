# Parcours de test CeroSec

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

L'option **Read the CeroSec manual (dev)** est déjà présente sur tous les
ordinateurs (`CeroSec.DEV_MANUAL_MENU = true`). Un ordinateur de bureau
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
27. `root`, `reboot` → la fenêtre reste ouverte, l'écran rejoue
    `CeroSec BIOS 1.0`, compte la mémoire, détecte le disque, affiche le motd,
    s'arrête à `login:`. [ ]

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
36. `df` → deux lignes, `hda` (taille 32768) et `nodes` (256) ; écrire un gros
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
    interrupteur, porte verrouillable et fenêtre de **tout le bâtiment**, pas
    seulement la pièce de l'ordinateur ; colonnes `c` + mode, `root`, l'id, la
    description, le côté, l'état, rien de plus large que l'écran. [ ]
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
87. Porte intérieure verrouillée : `cat /dev/lockN` → `locked`.
     `echo unlock > /dev/lockN`, ouvrir à la main sans clé, sans message de
     porte verrouillée. `echo lock > /dev/lockN`, essayer encore → refusé. [ ]
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
     `echo unlock`, passer à travers ; `echo lock`, refusé de nouveau. Une
     porte du joueur sans cadenas ni clé répond `lockN: no padlock` aux deux
     mots. [ ]
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
     `id  description  côté  état`, trié par sorte puis par numéro (`light2`
     avant `light10`), rien de plus large que l'écran, l'écran défile.
     `dev light`, `dev lock`, `dev win` → seulement cette sorte. `dev toaster`
     → `dev: toaster: unknown kind`, `dev light99` →
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

## I. Manuel

99. Clic droit sur un ordinateur, dernière entrée du menu → "Read the CeroSec
     manual (dev)" ouvre le lecteur sans copie du livre dans l'inventaire, sur
     un ordinateur allumé ou éteint, à portée ou pas. [ ]
100. Menu debug → Items list, filtre `CeroSec` → `CeroSec.Manual` présent,
     catégorie affichée Literature, nom "CeroSec OS User's Manual". Faire
     apparaître un exemplaire dans l'inventaire → icône navy avec petit écran
     vert sur la couverture, jamais un point d'interrogation blanc. [ ]
101. Clic droit sur l'exemplaire dans l'inventaire → "Read the manual"
     seulement ; pas de "Read" ni "Write" ni "Look at pictures" de la
     vanille. [ ]
102. Ouvrir le livre → deux feuilles crème côte à côte, numéros de page aux
     coins extérieurs, boutons `< Back`, `Contents`, `Next >` sous le livre. [ ]
103. Marcher, ouvrir une porte, se faire mordre avec le livre ouvert → il reste
     ouvert, aucune animation de lecture, rien en file d'action. [ ]
104. Page 1 : titre centré `CeroSec OS 1.0 User's Manual`, une règle dessous,
     `First Edition, 1993` en dessous encore, en encre plus pâle. Page 2 :
     Contents. [ ]
105. Table des matières : chaque ligne reprend exactement le titre du chapitre
     tel qu'il apparaît sur sa propre feuille (`1. Your machine`, jamais
     `1.  1. Your machine`), numéro de page aligné à droite. Cliquer sur
     chaque ligne → ouvre au premier feuillet du bon chapitre, et le numéro
     affiché sur la table correspond au numéro écrit au pied de la feuille. [ ]
106. Flèche droite fait ce que fait `Next >`, flèche gauche ce que fait
     `< Back`. Au tout début du livre, `< Back` et la flèche gauche ne font
     rien ; à la toute fin, `Next >` et la flèche droite ne font rien. [ ]
107. Tourner à un endroit au milieu du livre, fermer avec Escape, rouvrir →
     même feuillet exactement. Sauvegarder, quitter, recharger, rouvrir →
     encore le même feuillet (le signet vit sur l'objet, dans sa modData). [ ]
108. Faire apparaître un second exemplaire, le laisser sur une autre page que
     le premier → chacun garde son propre signet, indépendant de l'autre. [ ]
109. Vérifier que la version affichée est la même partout : la bannière de
     démarrage et `/etc/motd` disent `CeroSec OS 1.0`, la couverture du
     manuel dit `CeroSec OS 1.0 User's Manual`, et le BIOS affiche
     `CeroSec BIOS 1.0` comme un numéro séparé. Aucun de ces trois textes ne
     doit afficher un quatrième numéro de version. [ ]

## J. Sons et animation

110. Taper un mot lentement dans le terminal → un clic court par touche, pas
     toujours le même échantillon (quatre au hasard) ; tenir une touche →
     clics réguliers et rapides, jamais deux collés en moins de 40 ms. [ ]
111. Entrée au shell, puis Entrée dans l'éditeur pour une nouvelle ligne → un
     clic plus lourd et plus long que celui d'une lettre, dans les deux cas. [ ]
112. Flèches haut et bas (historique au shell, curseur dans l'éditeur)
     cliquent ; gauche, droite, Home et End ne cliquent pas. [ ]
113. Ouvrir le terminal debout, taper → animation de fouille, mains sur le
     clavier, arrêt environ une seconde et demie après la dernière touche.
     Lire sans taper → le personnage reste immobile face au moniteur. [ ]
114. Avec une chaise, assis, taper au clavier → noter si l'animation joue
     depuis la chaise ou si le personnage reste simplement assis face à
     l'écran sans animation superposée. [ ]

## K. Mode Héberger

115. Hôte allume un ordinateur → le client voit le sprite passer à l'écran
     allumé sans recharger, et voit la lueur apparaître la nuit sans
     s'éloigner et revenir. [ ]
116. Deux joueurs au même ordinateur, terminal ouvert des deux côtés : le
     premier tape `ls -l /`, la ligne tapée et sa sortie apparaissent en
     direct sur l'écran de l'autre. [ ]
117. L'un des deux tape `edit notes.txt` ; l'écran de l'autre montre le même
     éditeur avec `Another user is editing`, ses touches ne font rien, son
     Escape ferme seulement sa fenêtre. [ ]
118. Un joueur `echo on > /dev/light0` ; l'autre, debout dans la pièce
     concernée, voit la lumière s'allumer sans se reconnecter ni s'éloigner
     et revenir. [ ]
119. Un joueur déverrouille une porte à clé depuis l'ordinateur ; l'autre
     l'ouvre à la main. Puis le premier la reverrouille depuis l'ordinateur ;
     le second est refusé en essayant de l'ouvrir. [ ]
120. L'un des deux tape `reboot` en `root` : les deux fenêtres restent
     ouvertes et rejouent le BIOS ensemble jusqu'à `login:`, aucune des deux
     ne se ferme et aucune ne reste sur l'ancien écran. [ ]
121. Un joueur ferme sa fenêtre en pleine partie (ou quitte) ; l'autre continue
     de taper, et dans la minute qui suit, la machine ne compte plus la
     fenêtre partie dans ses balayages. [ ]

## L. Les doutes ouverts

Ce sont les points que les programmeurs ont signalés comme réglables seulement
en observant le jeu réel, pas par un banc de test.

122. Comparer `date` à l'horloge du HUD au même instant, plusieurs fois à des
     heures différentes : l'heure et la minute doivent toujours correspondre à
     ce que le jeu affiche, jamais à l'heure réelle de l'ordinateur qui fait
     tourner le jeu. [ ]
123. Reprendre l'étape 1 en se tenant déjà sur le carré devant l'écran, dos au
     mur derrière, à l'étape du bord de la case plutôt qu'au centre : vérifier
     que le point de position d'assise (avec une chaise) et le point de départ
     de l'animation (sans chaise) sont bien à l'intérieur du carré devant
     l'écran, jamais décalés vers une case voisine. [ ]
124. À l'étape 4, noter les hauteurs exactes des deux caisses empilées et si le
     seuil de blocage se déclenche vraiment à deux caisses ou déjà à une seule
     selon leurs sprites : ça dépend de la valeur `Surface` de chaque caisse,
     pas d'un nombre fixe dans le mod. [ ]
125. À l'étape 84, vérifier sur une vraie porte extérieure quel côté du mot
     `exterior` correspond au côté réel de la porte, et si un couloir entre
     deux pièces donne bien `<pièce-du-carré-de-la-porte>-<autre-pièce>` dans
     ce sens précis. [ ]
126. À l'étape 90, tester un interrupteur de lumière posé sur une case qui n'a
     elle-même aucune pièce définie (pas de plancher de maison dessous) mais
     qui est dans le rayon de dix cases d'une base : confirmer qu'il apparaît
     tout de même dans `ls -l /dev`. [ ]
127. Après une sauvegarde et un rechargement en pleine chaîne `su` (deux
     comptes de profondeur ou plus), vérifier que `console.stack` a gardé
     exactement la même profondeur et la bonne invite, sans qu'un `exit` de
     trop ou de moins soit nécessaire pour ressortir. [ ]
128. `sudo su bob` en tant que `admin` : confirmer que rien ne change à
     l'invite affichée (comme pour `sudo cd`), et que `whoami` répond toujours
     `admin` immédiatement après. [ ]
129. En mode Hôte, allumer ou éteindre un ordinateur en étant l'hôte lui-même :
     noter si l'hôte entend son propre son de bascule ou seulement si le
     client distant l'entend. [ ]
130. S'éloigner d'un ordinateur allumé jusqu'à décharger son chunk, puis
     revenir : compter exactement une lueur autour de l'écran, jamais deux
     superposées et jamais aucune. [ ]
131. Comparer la taille de l'icône du manuel dans l'inventaire à celle d'un
     livre vanille de même catégorie (Literature) : noter si elle paraît trop
     grande, trop petite, ou pareille. [ ]
132. Au premier démarrage d'une partie avec le mod actif, confirmer dans
     `~/Zomboid/console.txt` qu'aucune erreur de script ne nomme
     `items_cerosec.txt` (le script d'objets chargé depuis `common/`) et que
     la ligne `manual added to 12 distribution lists` apparaît une fois. [ ]

## Rapport

| Étape | OK/KO | Note |
| --- | --- | --- |
| | | |
