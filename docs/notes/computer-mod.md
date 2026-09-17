# CeroSec x Computer Mod — cohabitation et double amorçage

Dossier de CONCEPTION. Lecture seule : aucun fichier de mod n'a été modifié,
aucun fichier de l'autre mod n'a été copié. Analyse faite le 2026-09-17 sur les
sources installées.

## 1. Identification des deux mods de Kumeji

| | Computer Mod | Laptop Addon |
| --- | --- | --- |
| id Workshop | `3725497089` | `3798992436` |
| `id=` de mod.info | **`ComputerModkum`** | **`ComputerModLaptop`** |
| `name=` | Computer Mod | Computer Mod: Laptop Addon |
| `modversion=` | v1.0.0 | v1.0.0 |
| `versionMin=` | 42.20 | 42.20 |
| `require=` | — | `ComputerModkum` |
| dossier | `mods/ComputerMod/42/` | `mods/ComputerModLaptop/42/` |

C'est bien `ComputerModkum` (et non `ComputerMod`) que `getActivatedMods()`
contient : `getActivatedMods()` rend les `id=` de `mod.info`.

Racine des deux : the Workshop folder, `steamapps/workshop/content/108600/<id>/`.

**Licence : aucune.** Pas de fichier LICENSE, COPYING ni mention de droits dans
les deux dossiers (`find -iname "*licen*" -o -iname "*copyright*"` : vide). Donc
tous droits réservés par défaut. Conséquence tenue dans tout ce dossier : on ne
copie AUCUNE ligne de leur code, on ne redistribue AUCUN de leurs fichiers, on
n'inclut pas leurs chaînes traduites. On ne fait qu'appeler des fonctions
globales qu'ils publient eux-mêmes dans `_G`, ce qui est l'interface publique
d'un mod Lua.

Taille : Computer Mod = 36 141 lignes de Lua sur ~90 fichiers, gros mod complet
(BIOS, OS, bureau, fenêtres, courriel, marché, réseau, 25 mini-jeux, composants
486 à installer, CD). Laptop Addon = 372 lignes, un objet d'inventaire.

## 2. Ce que fait Computer Mod aux ordinateurs

### 2.1 Les objets visés — LES MÊMES QUE NOUS, exactement

`ComputerMod_ComputerTypes.lua:171-183` enregistre le type `desktop` avec :

```
spriteNames = {
    "appliances_com_01_72", ... "appliances_com_01_79"
}
```

Les huit tuiles vanille du bureau. `CeroSecDefs.lua:163-176` déclare les mêmes
huit, séparées en `SPRITES_OFF` (72-75) et `SPRITES_ON` (76-79). La même liste
est recopiée deux fois chez eux : `ComputerMod_ContextMenu.lua:504-513` et
`ComputerMod_MoveablePersistence.lua:5-16`.

**Il n'y a donc aucun objet à eux : ils posent leur machine sur les mêmes tuiles
vanille que CeroSec.** Collision de territoire totale sur le bureau. Le portable
de l'addon, lui, est un objet d'INVENTAIRE (`ComputerModLaptop_Core.lua:101-105`
: `dataOnItem = true`, `itemTypes = {...}`, **aucun `spriteNames`**) — hors de
notre monde entièrement.

### 2.2 Par quels crochets

- `Events.OnFillWorldObjectContextMenu.Add(ComputerContextMenu.doMenu)` —
  `ComputerMod_ContextMenu.lua:1029`. Le même événement que nous
  (`CeroSecContextMenu.lua:464`).
- `Events.LoadGridsquare.Add(ComputerModMoveablePersistence.removeDuplicateComputers)`
  — `ComputerMod_MoveablePersistence.lua:274`.
- **Quatre fonctions vanille remplacées** dans `ISMoveableSpriteProps`
  (`ComputerMod_MoveablePersistence.lua:207-271`) : `.new`,
  `:canPickUpMoveableInternal`, `:instanceItem`, `:pickUpMoveableInternal`,
  `:placeMoveableInternal`. Le patch est gardé par
  `ComputerModMoveablePersistencePatched` et chaîne l'original.
- Aucun remplacement de `ISWorldObjectContextMenu.*` : ils ne font que lire
  `ISWorldObjectContextMenu.addToolTip` et `.Test`.

### 2.3 Ce qu'il écrit

Tout dans `object:getModData()` **à plat**, sous des clés préfixées
`ComputerMod...` : `ComputerModPowerOn`, `ComputerModMachineID`,
`ComputerModOSInstalled`, `ComputerModComputerType`, `ComputerModComponents`,
`ComputerModNetworkTerminal`, `ComputerModUsername`, `ComputerModMountedCDLabel`,
etc. (`ComputerMod_ContextMenu.lua:539-560`, `ComputerMod_ComputerTypes.lua:60-70`).

Pas dans `movableData`. **Aucune collision de CLÉ avec nous** : notre état vit
sous `movableData.cerosec` (`CeroSecDefs.lua:191-193`,
`CeroSec.MOVABLE_DATA_KEY = "cerosec"`), et leur copie de données ne prend que
les clés commençant par `ComputerMod` (`copyComputerKeys`,
`ComputerMod_MoveablePersistence.lua:66-88`). Ils ne détruisent pas notre modData
par recopie.

**Ils remplacent le SPRITE**, en revanche : `syncComputerWorldScreen`
(`ComputerMod_ContextMenu.lua:649-687`) appelle `object:setSpriteFromName(...)`
puis `object:transmitUpdatedSpriteToClients()` pour passer 72-75 <-> 76-79 selon
leur drapeau `ComputerModPowerOn`. C'est le point de rupture (§3).

Ils ne remplacent pas l'IsoObject en temps normal, mais ils en SUPPRIMENT :
`removeDuplicateComputers` (`ComputerMod_MoveablePersistence.lua:167-205`) appelle
`square:transmitRemoveItemFromSquare(object)` / `square:RemoveTileObject(object)`
sur ce qu'il juge un doublon. Garde : ne s'exécute que `if isServer()` et
seulement sur des objets dont `getComputerIdentity` rend quelque chose,
c'est-à-dire porteurs d'un `ComputerModMachineID`. Une machine purement CeroSec
n'en a pas — sauf après que leur `doMenu` l'a estampillée (§3.3).

### 2.4 Courant, interface, multijoueur

- Courant : `ComputerModPower.hasComputerPower(computer)`
  (`ComputerMod_ContextMenu.lua:221-223`), leur propre modèle. Nous : le test du
  chargeur de batterie vanille, `square:haveElectricity() or (hasGridPower() and
  getRoom())` (`CeroSecContextMenu.lua:12-16`, cite ISWorldObjectContextMenu.lua:460).
- Interface : `ComputerScreenUI:new(x, y, player, computer)`, une fenêtre ISUI
  centrée d'environ 649x560 mise à l'échelle, **pas plein écran**
  (`ComputerMod_ContextMenu.lua:863-906`). Ils prennent le focus joypad et
  désactivent la barre d'espace.
- Une lumière d'écran à eux : `ComputerModScreenGlow` crée des `IsoLightSource`
  (`ComputerMod_ScreenGlow.lua:184-196`). Nous aussi (`CCeroSecObject.lua:36`).
  Deux halos sur la même case quand les deux croient la machine allumée.
- Multijoueur : oui, commandes client/serveur (`ComputerMod_Network_Server.lua`
  1023 lignes, `ComputerMod_ComputerData_Server.lua`, `ComputerMod_CD_Server.lua`,
  `ComputerModComponentsClient.requestInstall`). Leur UI reste par client.

### 2.5 Leur identité affichée — c'est du PC 486, pas de l'Unix

Écran d'amorçage (`ComputerMod_UI.lua:250-258`, table `bootMessages`) :

```
Phoenix 486 BIOS Version 1.03
CPU: Intel 486DX2-66 Compatible
Base Memory Test: 640K OK
Fixed Disk 0: CONNER 540MB
ATAPI CD-ROM: 4X DRIVE
Keyboard... Detected
Booting from C:
```

**Le nom de leur OS est `PZ OS 3.1`** : "Welcome to PZ OS 3.1",
"Starting PZ OS 3.1...", "PZ OS 3.1 Setup", "Installing PZ OS 3.1", installé
depuis un CD `ComputerMod.SystemCDPZOS` étiqueté "PZ OS 3.1 CD". Leur BIOS a
aussi un nom long, "PZ-486DX ISA/IDE BIOS", et un menu BIOS ("Standard CMOS
Features", "Exit BIOS"). C'est un PC DOS/Windows 3.1 de 1993 avec un bureau à
fenêtres — `Booting from C:`, lettres de lecteur, pas d'Unix.

Nous, en face (`CeroSecDefs.lua:829-846`, `CeroSecOS.lua:217-219, 347`) :

```
CeroSec BIOS 1.0 -- (c) 1993 CeroSec Systems
Memory test: 640K OK
Detecting drives ... hda <taille>
Booting from hda ...
```
puis la bannière de session `CeroSec OS 1.0 (hostname) (ttyN)` et `login:`.

Deux détails qui décident du §4 : le disque s'appelle **`hda`** (nommage IDE de
Linux, pas `C:` ni `hd0` de SCO), et la bannière a la forme du `/etc/issue` des
System V de l'époque. Le voisin est donc **l'autre partition du même disque IDE**,
vu depuis une machine à saveur Linux/SysV. `Booting from hda ...` est exactement
la ligne où un chargeur s'intercale.

## 3. La cause de la casse

### 3.1 La cause PRINCIPALE, prouvée par lecture : le sprite

CeroSec ne garde pas l'état allumé/éteint dans une variable pour le menu : **il
le lit sur le sprite**, et c'est écrit noir sur blanc —
`CeroSecContextMenu.lua:320-321` :

```lua
-- The sprite is the truth for the menu label: it is what the player sees.
local isOn = CeroSec.isOnSprite(computer:getSpriteName())
```

Le sprite n'est écrit que par le SERVEUR, en un seul endroit,
`SCeroSecObject.lua:328-329` :

```lua
isoObject:setSpriteFromName(want)
isoObject:transmitUpdatedSpriteToClients()
```

En face, `ComputerContextMenu.doMenu` (`ComputerMod_ContextMenu.lua:688`) fait,
**à chaque remplissage de menu contextuel**, sur la machine trouvée :

```
:697  ComputerModComputerTypes.ensureIdentity(clickedComputer, data, definition)
:699  if not data or data.ComputerModNetworkTerminal ~= true then
:700      syncComputerWorldScreen(clickedComputer, data and data.ComputerModPowerOn == true)
```

et `syncComputerWorldScreen` (`:649-687`) rabat le sprite sur l'état de LEUR
drapeau. Sur une machine que CeroSec a allumée, `ComputerModPowerOn` est `nil`
— donc `false` — donc `computerScreenOffSprites["appliances_com_01_76"]` =
`"appliances_com_01_72"`, `setSpriteFromName`, `transmitUpdatedSpriteToClients`.

**La séquence de la casse, pas à pas :**

1. Le joueur allume avec CeroSec. Le serveur met 76. L'écran est allumé.
2. Le joueur reclique droit sur la machine. Les deux gestionnaires sont sur
   `OnFillWorldObjectContextMenu` (le leur `:1029`, le nôtre `:464`).
3. Le leur remet le sprite à 72 et le diffuse. L'écran s'éteint dans le monde,
   sans que rien n'ait été éteint.
4. Notre menu lit le sprite. `isOn` est faux. Il n'y a plus de **« Use
   computer »** (`:335-352`), l'entrée devient **« Turn on computer »**
   (`:354`), et notre session — qui tourne toujours côté serveur — est
   inatteignable depuis le menu.
5. Le joueur clique « Turn on computer ». Le serveur, lui, sait que la machine
   est déjà allumée : divergence client/serveur en plus.

**L'ordre de chargement ne sauve pas.** Même si notre gestionnaire passe le
premier et affiche le bon menu, le leur réécrit le sprite dans le même
remplissage : l'écran s'éteint tout de suite et le clic droit SUIVANT est cassé.
C'est la raison pour laquelle « charger CeroSec après » n'est pas un correctif.

### 3.2 Hypothèses RÉFUTÉES (à ne pas poursuivre)

- « Ils vident ou remplacent le menu contextuel » : **non**. Leur `doMenu`
  n'appelle que `context:addOption` / `addSubMenu`, ne touche pas à
  `context.options`, ne retourne rien qui annule. Les deux menus coexistent.
- « Ils remplacent une fonction vanille que nous appelons » : **non pour le
  menu**. Ils ne réécrivent aucun `ISWorldObjectContextMenu.*`. Ils réécrivent
  `ISMoveableSpriteProps.*` (§3.4), que nous n'appelons pas nous-mêmes.
- « Notre modData part avec l'objet » : **non par recopie**. `copyComputerKeys`
  (`MoveablePersistence.lua:66-88`) ne copie que les clés `ComputerMod*` et
  `pickUpMoveableInternal` chaîne l'original, qui porte `movableData` comme
  vanille. Notre clé `cerosec` survit au ramassage/repose.
- « Ils ferment nos fenêtres » : **non**. Leur seul repli est l'inverse — leur
  `doMenu` s'abstient si LEUR fenêtre est ouverte (`:690`).
- « Conflit de clés de modData » : **non**, préfixes disjoints (§2.3).

### 3.3 Risques SECONDAIRES, réels mais non prouvés sans essai

- **Estampillage puis suppression.** `ensureIdentity` (`:697`) pose un
  `ComputerModMachineID` sur NOS machines dès le premier clic droit. Une fois
  estampillée, la machine entre dans le champ de `removeDuplicateComputers`
  (`Events.LoadGridsquare`, serveur). Si deux objets finissent avec la même
  identité, l'un est retiré de la case par `transmitRemoveItemFromSquare` — et
  notre `movableData.cerosec` part avec l'objet retiré. Chemin plausible, non
  prouvé : il faut deux objets de même identité sur une case.
- **Deux halos.** Leur `IsoLightSource` plus le nôtre sur la même case.
- **Deux courants.** Leur porte dit « No power » là où la nôtre dit oui, et
  l'inverse : deux modèles électriques différents sur le même meuble.
- **Deux menus racine.** « Turn on computer » (nous, en tête) et « Computer > »
  (eux) sur le même clic : le joueur ne sait pas lequel est sa machine.

### 3.4 Effet de bord permanent de leur patch des meubles

`ISMoveableSpriteProps.new` réécrit (`MoveablePersistence.lua:210-226`) pose
`properties.ignoreSurfaceSnap = true` pour les huit sprites — **y compris sur les
machines CeroSec**. Le placement d'un ordinateur cesse d'être celui de vanille
dès que leur mod est actif, que CeroSec fasse quoi que ce soit ou non. Rien à
faire de notre côté ; à savoir.

### 3.5 Ce qui n'est PAS prouvé, et pourquoi

the game log (`console.txt`) (session du 2026-09-17 13:04) montre **CeroSec chargé et
Computer Mod absent** : `grep "ComputerMod" console.txt` ne rend rien, seules les
lignes `loading CeroSec` sont là. **Il n'existe donc aucune trace en jeu des deux
mods actifs ensemble.** Aucune erreur Lua n'est attribuable à la cohabitation
dans ce journal ; les seules erreurs sont vanille (mannequins, métagrille).

Tout le §3.1 est prouvé par LECTURE des deux sources, pas par un essai. Ce qui
demande une partie réelle : l'ordre effectif des deux gestionnaires, le fait que
`transmitUpdatedSpriteToClients` en solo n'est pas un no-op, et tout le §3.3.

## 4. Le modèle de 1993 : LILO

### 4.1 Pourquoi LILO et pas SCO

Trois modèles réels existaient pour offrir un autre système au démarrage :

1. **SCO UNIX / XENIX** : l'amorceur imprime `Boot` puis `:` et attend ; taper
   `dos` amorce la partition DOS. Source : `boot(HW)`, SCO UNIX System V/386.
2. **OS/2 Boot Manager** (IBM, 1992) : une partition de 1 Mo, un menu plein
   écran avec flèches et minuterie.
3. **LILO**, LInux LOader, Werner Almesberger, 1992. Invite `boot:`, étiquettes,
   Tab pour la liste, minuterie, défaut configuré ; amorçage d'un système
   étranger par chaînage. Source : `lilo.conf(5)` et le *LILO User's Guide*.

**Notre machine dit `hda`** (`CeroSecDefs.lua:838`, `Detecting drives ... hda`).
`hda` est le nom IDE de Linux — ce n'est ni le `C:` d'un PC ni le `hd0` de SCO.
Une machine qui appelle son disque `hda` est amorcée par LILO. C'est le seul des
trois qui n'oblige pas à contredire une ligne déjà écrite dans le mod.

Les éléments de LILO retenus, tous réels, **à revérifier sur `lilo.conf(5)` de
l'époque avant d'écrire une seule chaîne** (le contrat CeroSec exige la source
citée dans le commentaire, et la présente note est de mémoire) :

- `prompt` — affiche l'invite au lieu d'amorcer directement ;
- `timeout=<dixièmes de seconde>` — attente avant d'amorcer le défaut ;
- `default=<étiquette>` — quelle image part si personne ne répond ;
- `label=` — le nom qu'on tape ;
- `image=` pour le système du disque, **`other=<partition>`** pour l'autre
  système (chaînage du secteur d'amorçage voisin) ;
- Tab (ou `?`) à l'invite : la liste des étiquettes connues ;
- sans `prompt`, maintenir Shift/Ctrl/Alt au démarrage fait apparaître l'invite.

`other=` est exactement le mot du fichier de configuration pour « la partition
de l'autre système ». C'est le modèle demandé, textuellement.

### 4.2 L'écran proposé (60 colonnes, le terminal fait 60x20)

L'écran d'amorçage actuel n'est pas touché ; le chargeur s'insère entre la
détection du disque et `Booting from hda ...` :

```
CeroSec BIOS 1.0 -- (c) 1993 CeroSec Systems
Memory test: 640K OK
Detecting drives ... hda 64K
Ethernet: eth0 10.0.0.12
LILO
boot: _
```

Sur Tab, la vraie réponse de LILO — la liste des étiquettes, sur une ligne :

```
boot:
cerosec  pzos
boot: _
```

- `cerosec` amorce comme aujourd'hui : la ligne `Booting from hda ...` reste,
  puis la bannière et `login:`. Rien d'autre ne change.
- `pzos` **ne dit rien de plus** : LILO chaîne le secteur voisin et rend l'écran.
  Notre fenêtre se ferme, la leur s'ouvre sur `Phoenix 486 BIOS Version 1.03`.
  Aucune ligne inventée : le silence EST le comportement réel du chaînage.
- L'étiquette `pzos` est **leur vrai nom d'OS abaissé en étiquette** (« PZ OS
  3.1 »), traité comme la partition de l'autre système. On n'invente pas un nom.
- Minuterie : `timeout=50`, cinq secondes. Une touche l'annule (comportement réel
  de LILO : toute frappe au clavier arrête le compte à rebours).
- Personne ne répond : le défaut part. Le défaut est **la dernière étiquette
  choisie sur CETTE machine** — c'est le `default=` du fichier, mis à jour par
  l'administrateur ; ici, par le geste du joueur. Un joueur qui prend toujours
  PZ OS ne tape qu'une fois.

### 4.3 Est-ce une déviation à déclarer ?

**Non.** Chaque élément a son modèle réel et sa page de manuel : l'invite, les
étiquettes, Tab, la minuterie, le défaut, le chaînage de la partition voisine.
Rien n'est inventé. Un point à trancher, qui n'est pas une déviation non plus :
LILO amorçait des noyaux Linux, et CeroSec OS a la bannière d'un System V. Rien
à l'écran ne l'affirme (`image=` et `other=` ne sont pas montrés au joueur), donc
la machine ne ment sur rien. Si l'équipe préfère malgré tout un chargeur au nom
de la maison, il copie le comportement de LILO à la lettre et le nom seul est
fiction — une fiction du même ordre que « CeroSec Systems », donc toujours pas
une déviation. **Recommandation : garder `LILO`, le vrai article.**

En revanche, si `pzos` est proposé alors que l'autre mod n'est PAS installé sur
cette machine (leur `ComputerModOSInstalled` faux), la machine annoncerait une
partition qui n'existe pas — ça, ce serait un BIOS qui ment, ce que le mod
refuse déjà explicitement (`CeroSecDefs.lua:839-842`). Donc : l'entrée `pzos`
n'apparaît que si leur mod est actif ET que leur état dit l'OS installé.

### 4.4 Où vit la préférence

Dans NOTRE clé, jamais la leur : un champ de plus dans l'état de la machine sous
`movableData.cerosec` (`CeroSec.MOVABLE_DATA_KEY`), par exemple
`state.bootDefault` valant `"cerosec"` ou `"other"`, et `state.bootedInto` pour
savoir quel système tourne en ce moment. Absent = `"cerosec"` : une sauvegarde
d'avant ne change pas d'un iota, ce que le contrat de compatibilité exige. Rien
n'est supprimé, un champ est ajouté avec une valeur par défaut — la montée de
version suit la règle de `docs/CONTRIBUTING.md`, à relire avant de l'écrire.

## 5. La prise de main : un seul chemin d'allumage

### 5.1 LE PIÈGE, à savoir avant de concevoir quoi que ce soit

`ComputerMod_ContextMenu.lua:16-18` :

```lua
ComputerModContextMenu = ComputerModContextMenu or {}
local ComputerContextMenu = ComputerModContextMenu
_G.ComputerContextMenu = ComputerModContextMenu
```

Deux noms globaux, **une seule table**. Et `:1029` :

```lua
Events.OnFillWorldObjectContextMenu.Add(ComputerContextMenu.doMenu)
```

L'événement reçoit **la VALEUR de la fonction**, pas la table plus le nom du
champ. Conséquence dure : **enrober `ComputerModContextMenu.doMenu` après coup
n'intercepte RIEN.** L'événement continue d'appeler l'ancienne fonction, notre
enrobage n'est jamais atteint, et le sprite se fait réécrire pendant qu'on croit
avoir pris la main. C'est le genre de correctif qui passe tous les bancs hors jeu
et ne fait rien en jeu.

Le chemin qui marche est le retrait, pas l'enrobage :

```lua
local theirs = ComputerModContextMenu and ComputerModContextMenu.doMenu
Events.OnFillWorldObjectContextMenu.Remove(theirs)   -- avant toute écriture
Events.OnFillWorldObjectContextMenu.Add(CeroSecCompat.fill)
```

`Events.<X>.Remove` existe bien dans le Lua vanille : `ISWorldObjectContextMenu
.lua:2795` (`Events.OnDeadBodySpawn.Remove(func)`), `FishingManager.lua:53`,
`Tutorial/Steps.lua:914`. Le champ `.doMenu` de la table tient encore la valeur
enregistrée tant qu'on n'a rien écrit dessus : c'est pour ça qu'on retire AVANT.

Quand : à `OnGameStart`, une seule fois. Leur `Add` a lieu au chargement du
fichier, donc bien avant. Notre gestionnaire à nous reste enregistré au
chargement, comme aujourd'hui ; notre relais passe en dernier, ce qui est sans
importance puisqu'il ne fait que relayer.

### 5.2 Le relais — chirurgical, pas un rouleau compresseur

Retirer leur `doMenu` sec **tuerait aussi le portable de l'addon** : un portable
posé au sol passe par le même `doMenu` (leur `getDefinition` résout l'objet par
`getInventoryItem` puis `byItemType`, `ComputerMod_ComputerTypes.lua:51-57`). Il
faut donc leur rendre les clics qui ne nous regardent pas :

```
CeroSecCompat.fill(player, context, worldobjects, test):
    si CeroSecContextMenu.findComputer(worldobjects, player) rend une machine
        -> ne rien faire : ce clic est à nous, notre menu l'a déjà rempli
    sinon
        -> pcall(theirs, player, context, worldobjects, test)
```

`findComputer` est notre code (`CeroSecContextMenu.lua:278`), on ne copie pas
leur détection. Effet : sur les huit sprites vanille, CeroSec est seul maître et
`syncComputerWorldScreen` ne tourne plus jamais — **la cause du §3.1 disparaît**,
et l'estampillage du §3.3 aussi, puisque `ensureIdentity` est dans `doMenu`.
Partout ailleurs (portable posé, tout type qu'ils ajouteront), leur menu est
intact, appelé par nous avec leurs arguments d'origine.

**Prix à payer, à dire franchement :** leur contenu propre au bureau passe sous
le double amorçage. Leurs composants 486 à installer, leurs CD de jeux, leur
« Network Terminal » ne sont plus dans le menu du clic droit ; ils sont derrière
`boot: pzos`, c'est-à-dire dans LEUR fenêtre, où ils ont toujours été. Ce qui
disparaît vraiment, c'est l'installation d'un composant sur une machine éteinte,
qu'ils refusent quand la machine est allumée (`:752`). À accepter ou à traiter
par une entrée de menu de plus.

### 5.3 Lancer leur OS

Un seul appel, sur la table globale qu'ils publient :

```
ComputerModContextMenu.openComputerUI(worldobjects, playerIndex, computer)
```

(`ComputerMod_ContextMenu.lua:863`). Attention : le deuxième argument est
l'INDICE du joueur, pas l'objet — ils font `getSpecificPlayer(player)` en
première ligne. Ils vérifient eux-mêmes la distance (2,6 tuiles) et le courant,
et disent « I need to get closer » / « No power » à notre place.

**Nous n'écrivons aucune clé `ComputerMod*`.** `ComputerModPowerOn` et le reste
sont écrits par leur propre code quand leur fenêtre s'ouvre. C'est la règle : on
appelle, on n'écrit pas.

### 5.4 Le cycle de vie complet

- **Machine éteinte, clic droit.** Une seule entrée, la nôtre : « Turn on
  computer ». Rien de changé pour personne.
- **Allumage.** Notre action habituelle, le serveur met le sprite allumé.
- **« Use computer ».** Notre terminal s'ouvre, le BIOS s'écrit, puis `LILO` /
  `boot:` si et seulement si les deux mods sont là et leur OS est installé.
- **`cerosec` ou minuterie écoulée sur ce défaut.** Rien de plus : le mod se
  comporte comme s'ils n'existaient pas.
- **`pzos`.** Notre fenêtre se ferme, `openComputerUI` ouvre la leur. Le serveur
  a d'abord écrit `bootedInto = "other"` dans notre état.
- **Machine déjà allumée sous l'autre OS, clic droit.** « Use computer » rouvre
  LEUR fenêtre — le routage se lit sur `bootedInto`, pas sur qui clique.
- **Changer de système.** Il faut éteindre et rallumer. C'est le vrai
  comportement d'un double amorçage de 1993 et ça ne coûte rien à écrire.
- **Extinction.** Notre extinction, comme aujourd'hui, plus `bootedInto` remis à
  rien. Leur fenêtre, si elle est ouverte : nous ne la fermons pas — nous n'en
  sommes pas propriétaires. Leur UI teste le courant de son côté. **Non prouvé :
  ce qu'affiche leur fenêtre quand la machine s'éteint sous elle.**
- **Deuxième joueur.** `bootedInto` est dans l'état de la MACHINE, côté serveur,
  synchronisé comme le reste : le deuxième joueur atterrit dans le même système
  que le premier. Que leur fenêtre supporte deux clients à la fois est leur
  affaire, et **non prouvé**.
- **Multijoueur, qui décide : le serveur.** La frappe à l'invite `boot:` part
  par le chemin d'entrée du terminal existant ; c'est le serveur qui écrit
  `bootDefault` et `bootedInto` et qui les diffuse. Le client n'ouvre la fenêtre
  de l'autre mod qu'après le retour du serveur. Jamais une décision de client.
- **Le portable.** `ComputerModLaptop` n'a aucun `spriteNames` et
  `CeroSec.isComputerSprite` ne connaît que les huit tuiles vanille : CeroSec ne
  voit jamais un portable. **On n'y touche pas**, ni double amorçage ni rien. Le
  relais du §5.2 suffit à le laisser vivre.

## 6. Les gardes

1. **Détection par id, une fois.** `getActivatedMods():contains("ComputerModkum")`
   à `OnGameStart`. Jamais par la présence d'une globale : une globale peut venir
   d'ailleurs, un id est un fait. (Vérifier la forme exacte de `getActivatedMods`
   dans le Lua vanille avant de l'écrire — CeroSec ne l'utilise nulle part
   aujourd'hui, `grep getActivatedMods` sur tout le mod : aucun résultat.)
2. **Trois vérifications d'existence**, pas une : la table
   (`type(ComputerModContextMenu) == "table"`), `doMenu`
   (`type(...) == "function"`) et `openComputerUI` (idem). Les trois manquantes
   ou renommées par une de leurs mises à jour = **on ne fait rien du tout** :
   pas de retrait, pas de relais, pas d'entrée `pzos` à l'invite. On retombe
   exactement sur l'état d'aujourd'hui — les deux menus coexistent, CeroSec
   fonctionne seul. Leur mise à jour ne peut pas casser le nôtre, au pire elle
   lui retire la cohabitation.
3. **Tout appel chez eux sous `pcall`.** Une erreur dans leur `doMenu` relayé ne
   doit pas emporter le remplissage de menu de la partie.
4. **Aucune écriture chez eux.** Zéro affectation d'une clé `ComputerMod*`.
   Vérifiable par un grep de garde dans `tests/`, sur le modèle des gardes qui
   existent déjà (`public-check.sh`, `kahlua-check.sh`).
5. **Leur mod disparaît, notre état est intact.** `bootDefault`/`bootedInto`
   vivent chez nous ; absents ou pointant vers un système qui n'est plus là,
   ils se lisent comme `"cerosec"`. Une machine laissée sous PZ OS puis
   désabonnée redémarre sous CeroSec OS. Rien n'est supprimé, contrat tenu.
6. **Un banc hors jeu est possible et prouverait peu.** Une doublure
   (`ComputerModContextMenu` factice avec `doMenu` et `openComputerUI` compteurs,
   un faux `Events` avec Add/Remove, un faux `getActivatedMods`) prouve : que le
   retrait vise la bonne valeur, que le relais laisse passer un clic hors sprite
   vanille et retient un clic sur sprite vanille, que trois absences sur trois
   donnent zéro geste, que l'entrée `pzos` n'existe pas sans leur mod. Elle **ne
   prouve pas** l'ordre réel des gestionnaires, ni que le sprite cesse d'être
   réécrit, ni qu'une fenêtre s'ouvre. Leçon applicable mot pour mot :
   *« Une doublure posée au-dessus de la porte ne voit pas la porte »*.
7. **L'étape du parcours qui tranche** (`docs/PARCOURS-TEST.md`, en français, à
   ajouter dans le même changement) : les deux mods actifs, allumer une machine,
   **recliquer droit dessus** et constater que l'écran reste allumé et que
   « Use computer » est toujours là — c'est la contre-épreuve directe du §3.1.
   Puis : `boot:` visible, Tab liste `cerosec  pzos`, `pzos` ouvre leur fenêtre,
   éteindre/rallumer ramène le choix, `cerosec` donne `login:`. Et l'étape
   négative, la plus importante : **sans leur mod, aucune ligne de plus à
   l'écran** et le parcours existant passe inchangé.

## 7. Découpage, risques, calendrier

### 7.1 Les fichiers

| Fichier | Geste | Lignes (densité de commentaires CeroSec) |
| --- | --- | --- |
| `client/CeroSec/CeroSecCompatComputerMod.lua` (neuf) | détection par id, retrait, relais, appel de `openComputerUI` | ~180 |
| `shared/CeroSec/CeroSecCompat.lua` (neuf) | les faits partagés client/serveur : l'autre mod est-il actif, son OS est-il installé sur CETTE machine | ~60 |
| `shared/CeroSec/CeroSecDefs.lua` | le texte de l'invite, les étiquettes, la minuterie, l'état `waiting == "boot"` à côté de `"login"` (`:1084`) | ~50 |
| `client/CeroSec/CeroSecTerminal.lua` | la frappe à l'invite, Tab, la fermeture-passation | ~60 |
| `server/CeroSec/SCeroSecObject.lua`, `SCeroSecSystem.lua` | `bootDefault` / `bootedInto` : écriture, synchronisation, décision | ~90 |
| `client/CeroSec/CeroSecContextMenu.lua` | routage de « Use computer » sur `bootedInto` | ~25 |
| Manuel Volume 1, `docs/PARCOURS-TEST.md`, `CHANGELOG.md` | dans le même changement, règle du contrat du dépôt | ~70 |
| `tests/` — banc à doublure | ce que le §6.6 prouve, et pas plus | ~150 |

**~700 lignes sur 9 fichiers, dont les deux parties les plus porteuses du mod :
la machine à états de l'amorçage et l'état synchronisé de la machine.**

### 7.2 Risques classés

1. **ÉLEVÉ — toucher la machine à états d'amorçage/session la veille d'une
   sortie.** Un nouvel état `waiting` est un état dans lequel une sauvegarde peut
   être prise. Une machine sauvegardée à l'invite `boot:` doit se recharger
   proprement ; c'est exactement le genre de chose qui ne se voit qu'en jeu.
2. **ÉLEVÉ — rien ici n'est prouvable sans une partie.** La cause elle-même
   (§3.1) est prouvée par lecture des deux sources, pas par un essai : le journal
   ne contient aucune session où les deux mods étaient chargés.
3. **MOYEN — on retire le menu d'un mod auquel le joueur est abonné.** S'ils
   renomment `doMenu` en v1.1, notre repli est silencieux et correct (les deux
   menus reviennent), mais le joueur ne comprendra pas pourquoi.
4. **MOYEN — `removeDuplicateComputers` (serveur).** Retirer leur `doMenu` coupe
   le chemin d'estampillage principal, pas forcément tous. **À faire avant
   d'écrire : `grep -rn "ensureIdentity" ` sur leur mod** pour recenser les
   autres appelants.
5. **FAIBLE — deux halos, deux modèles de courant, `ignoreSurfaceSnap`.**
   Cosmétique ou hors de notre portée.
6. **FAIBLE — Kahlua.** Rien d'exotique dans ce qui précède.

### 7.3 Le correctif minimal de cohabitation — oui, il tient en peu de lignes

**Sans aucun double amorçage**, les §5.1 et §5.2 seuls suffisent à ne plus être
cassé : un fichier client neuf, une détection par id à `OnGameStart`, un
`Events.OnFillWorldObjectContextMenu.Remove` et un relais de six lignes.
**Aucun changement d'état persistant, aucune montée de version, aucune page de
manuel, aucune traduction.** CeroSec redevient exactement ce qu'il est sans leur
mod, et leur portable continue de fonctionner.

Son prix, à écrire dans le changelog en toutes lettres : sur les ordinateurs de
bureau, le contenu de Computer Mod devient inatteignable tant que le double
amorçage n'est pas livré.

### 7.4 Recommandation franche

**Le double amorçage n'entre pas dans la 0.5.0. Il vise la 0.6.0.** Sept cents
lignes dans la machine à états d'amorçage, la veille d'une sortie, sur une
fonctionnalité dont la preuve exige une partie avec deux mods : c'est le profil
exact d'une régression qui sort le jour de la sortie. Le penchant de l’équipe est
le bon.

Pour demain, deux options honnêtes, au choix :

- **(a) Ne rien livrer** et écrire une ligne sur la page Workshop : incompatible
  avec Computer Mod sur les ordinateurs de bureau, la cohabitation arrive.
  Risque nul.
- **(b) Livrer le correctif minimal du §7.3**, à une condition ferme : qu'il ait
  été **essayé en jeu** avec les deux mods abonnés avant la publication (allumer,
  recliquer droit, l'écran reste allumé). Non essayé = ne pas livrer. Le mod
  interdit déjà de prouver un changement en démarrant le jeu ; ici c'est
  l'inverse, c'est le SEUL endroit où la preuve existe, et un banc à doublure ne
  la remplace pas.

Ma recommandation : préparer (b) ce soir sur une branche, ne rien fusionner,
l'essayer demain matin, et publier 0.5.0 avec (b) si l'étape passe, avec (a)
sinon. Le double amorçage se conçoit et s'écrit après la sortie, au calme.

## 8. Ce qui n'est prouvable qu'en jeu

1. Que l'écran s'éteint bien au clic droit (§3.1) — la séquence est prouvée par
   lecture, jamais observée.
2. L'ordre réel des deux gestionnaires sur `OnFillWorldObjectContextMenu`.
3. Que le retrait de leur `doMenu` ne casse rien d'autre chez eux (portable posé,
   terminaux réseau, composants).
4. Que `openComputerUI` appelé depuis notre terminal ouvre leur fenêtre
   proprement (focus joypad, barre d'espace, fermeture de la nôtre).
5. Ce que leur fenêtre affiche quand la machine s'éteint sous elle.
6. Le comportement à deux joueurs sur une machine amorcée sous PZ OS.
7. Le §3.3 en entier : estampillage puis suppression d'un objet par
   `removeDuplicateComputers`, double halo, désaccord des deux modèles de courant.

## 9. Addenda vérifiés après rédaction

- **Risque 7.2 #4, précisé.** `ensureIdentity` a cinq appelants chez eux :
  `ComputerMod_ContextMenu.lua:426` et `:699` (client, le menu), et
  `ComputerMod_ComputerTypes.lua:131` et `:145` dans `registry.findOnSquare`,
  atteint depuis leurs commandes serveur (`ComputerMod_Components_Server.lua:136`).
  Retirer leur `doMenu` ferme les deux chemins client. Les chemins serveur ne
  sont atteints que si un client leur envoie une commande visant cette machine —
  ce que le relais du §5.2 empêche, mais **par conséquence, pas par
  construction**. Conclusion inchangée : le risque tombe très bas, il ne tombe
  pas à zéro par preuve.
- **`getActivatedMods()`** est bien une fonction du Lua vanille
  (`ISPauseModListUI.lua:19`, `ServerSettingsScreen.lua:2295`). La forme exacte
  de l'objet rendu et l'existence de `:contains(id)` sont **à confirmer sur le
  vanille avant d'écrire la ligne**, conformément à la règle des sources de
  vérité du contrat du dépôt : un appel jamais prouvé n'est pas une erreur de syntaxe,
  c'est un appel nil.
- **Correction, et elle compte.** Le vanille n'utilise `getActivatedMods()` que
  par `:size()` et `:get(i-1)` (`ServerSettingsScreen.lua:2295-2297`,
  `ISPauseModListUI.lua:19`). **`:contains(id)` n'est prouvé nulle part dans le
  Lua vanille.** La détection s'écrit donc par la boucle prouvée :

  ```
  local mods = getActivatedMods()
  for i = 1, mods:size() do
      if mods:get(i - 1) == "ComputerModkum" then ... end
  end
  ```

  C'est précisément le cas que le contrat du dépôt décrit : `:contains` passerait
  `luac5.1 -p` et serait un appel nil une fois par partie.
