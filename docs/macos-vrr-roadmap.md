# Validation du VRR Metal — écran intégré

Statut : en cours, aucune qualification de fluidité ou de latence physique.
Base de comparaison : PR #1, commit 0a02a249. Les captures et profils restent
dans `.runtime`, hors Git. L'écran externe et PyroWave suivent cette validation.

Priorité précisée par l'utilisateur : viser un client fiable et des gains
démontrables, pas une perfection du système. Les variantes de présentation
sans gain reproductible sont arrêtées. Une nouvelle campagne nécessite une
hypothèse précise et un contrôle comparable ; les contraintes Wi-Fi/macOS
ne justifient pas à elles seules une réécriture du moteur de rendu.

## Ordre de travail

- [x] Relecture des contrats du worker, des horloges et de la présentation Metal.
- [x] Corrélation des traces existantes : identité RTP + sortie décodeur + numéro
  de soumission ; distinguer pertes du pacer et absence de présentation native.
- [x] Audit Windows de l'identité capture/encode/envoi et des limites des compteurs.
- [x] A/B frais à 60 FPS : deux/trois surfaces, même binaire et même serveur.
- [x] Essai trois surfaces à 100 FPS : acquisition moins bloquante mais callbacks
  de présentation à zéro. Ne pas promouvoir cette option seule.
- [x] Mesurer les échéances natives ProMotion et leur rapport aux soumissions.
- [x] Corriger et valider le retour de complétion GPU au contrôleur/replay
  (capture réelle et régression présentation/annulation : replay exact).
- [ ] Définir puis implémenter la politique de présentation ProMotion selon ces
  mesures. Conserver le code de rendu commun et une politique Adaptive-Sync distincte.
- [ ] Comparaisons répétées 60/120 FPS puis 80/100/116 et cadence variable.
- [ ] Stabilité prolongée et transitions : plein écran, réduction, reconnexion,
  mode d'énergie Mac et réseau dégradé. Aucune mise en veille, extinction ou
  modification d'alimentation du PC Windows n'est autorisée.
- [ ] Mesure finale avec les outils logiciels des deux ordinateurs uniquement,
  conformément au choix utilisateur. La réponse physique des pixels est hors
  périmètre ; ne pas présenter les événements macOS comme une mesure optique.
- [ ] Revue, documentation, publication de la version validée et finalisation PR.

## Protocole d'acceptation

Source mesurée et stable, HEVC matériel, SDR, 1920×1200, 30 Mbit/s, écran
intégré, secteur Automatique et état thermique nominal. Aucun build pendant
les fenêtres de mesure. Restaurer le mode d'énergie et l'état Windows après
les essais. Le profil de référence reste VRR désactivé.

Pour chaque candidat : échauffement d'au moins 15 secondes après départ source,
trois fenêtres de 30 secondes sur connexions distinctes, puis essai prolongé
de dix minutes si les essais courts passent. Comparer avec le contrôle sans
changer la négociation serveur. Identifier le binaire, les paramètres, l'époque
du renderer et les sommes SHA256 des captures.

À 60/120 FPS stables : viser aucune perte inexpliquée après admission, couverture
native d'au moins 99,9 %, absence d'accumulation de retard, et au moins 99 % des
intervalles à moins de 2 ms de la période attendue lorsque le système tient la
cadence correspondante. Comptabiliser séparément les interruptions système et
les écarts de source ; ne pas les retirer silencieusement des résultats.
Ces seuils sont des objectifs de test, pas des résultats acquis.

Pour les cadences intermédiaires, comparer les présentations aux opportunités
réellement mesurées de l'écran. Le critère 2 ms autour de la période source ne
convient pas à une cadence quantifiée. Les mesures de latence doivent inclure
médiane, p95 et p99 ; toute amélioration doit résister aux répétitions et être
comparée à sa variabilité. Les événements macOS ne prouvent pas les photons.

## Attribution obtenue

Sur la fenêtre historique final100 : 3 000 images consécutives entrent dans le
pacer, 2 796 sont présentées, 204 sont abandonnées localement. Il n'y a aucun
trou d'identifiant avant ce pacer dans cette fenêtre. Le temps moyen
d'acquisition d'une surface est de 8,76 ms. Cela localise ces pertes au client,
sans exonérer tout le serveur sur tout autre scénario.

Les sources Vibepollo 2.0.0 et le binaire Windows montrent un identifiant
commun : numéro transmis à NVENC, outputTimeStamp, packet.frame_index puis
NV_VIDEO_PACKET.frameIndex. Le RTP est ajusté par la politique d'émission et
n'est pas l'horodatage brut de capture. Les métriques serveur agrégées sur
deux secondes ne permettent pas de déduire le jitter image par image. Une
instrumentation serveur supplémentaire ne sera nécessaire que si des anomalies
avant admission restent inexpliquées ; ne pas soustraire les horloges PC/Mac.

`scripts/macos/analyze-pipeline.py` prend le CSV du worker décompressé et le CSV
Metal de la même époque. Il analyse une cohorte d'arrivées et ses issues, qui
peuvent se produire après la fenêtre ; ce débit n'est pas le débit instantané
de présentation. `analyze-presentation.py` conserve ce dernier rôle.

## Isolation du réseau et des réglages Continuité

Deux sondes UDP indépendantes du client (client fermé), chacune de 120 secondes
à 100 paquets/s, ont reçu 12 000/12 000 paquets, sans trou de séquence. Les
horodatages sont pris avant `sendto` sous Windows et par `SO_TIMESTAMP` dans
le noyau macOS ; ils ne mesurent pas le départ physique de la carte réseau.

| Réglage | Pauses réception > 40 ms | Maximum réception | Maximum émission |
| --- | ---: | ---: | ---: |
| Handoff actif, AirDrop Personne | 114 | 82,892 ms | 11,350 ms |
| Handoff désactivé, AirDrop Personne | 61 | 82,167 ms | 11,319 ms |

Ces pauses existent sans décodage ni rendu Moonlight. Dans le premier essai,
les 114 pauses coïncident avec AWDL actif, aucune avec AWDL inactif. Le second
montre qu'arrêter Handoff ne suffit pas : AWDL continue de s'activer. Les
fenêtres ne couvrent pas les mêmes phases AWDL ; la baisse du nombre de pauses
ne prouve donc pas une amélioration causale. Handoff a été restauré, AirDrop
était déjà sur Personne. Aucun réglage réseau serveur n'a changé.

L'autorisation de capture réseau privilégiée n'était pas disponible. Les
mesures utilisent une socket de test ordinaire, sans modifier les protections
système. Ne pas attribuer ces pauses à Metal ni prétendre qu'une modification
de Moonlight peut supprimer une interruption située avant la réception noyau.

## Placement des fenêtres

L'utilisateur a signalé une image distante immobile sur l'écran externe puis
sa disparition. Le dernier journal disponible avant le signalement indique
une fermeture par raccourci, sans établir l'identité de la fenêtre observée.
Le contrôle est renforcé : fenêtre SDL créée cachée, validation native de toute
la zone vidéo sur l'écran intégré avant affichage, puis contrôle pendant le
flux. Le contrôle Qt vérifie aussi la géométrie entière. Le nouvel essai a
confirmé l'écran intégré avant affichage ; la page source au repos affiche
explicitement « Prêt — aucune animation démarrée ».

## Retour GPU : validation réelle

Le callback de fin de commande Metal produit désormais un résultat d'attente
explicite, conservé jusqu'à présentation ou annulation. Le type de complétion
est distinct du backend de présentation ; aucun événement DXGI ni polling
Vulkan n'est simulé. Le replay contrôle ce contrat et l'encadrement temporel.

La capture HEVC60 `completion60` passe le replay exact (code 0, intégrité et
`baseline_exact` vrais). Une copie dont le type de complétion est altéré est
refusée (code 3). Les sept suites C++ et les quatre tests Python passent.
Sur une fenêtre native de 30 s après 50 s d'échauffement : 1 800/1 800
présentations confirmées, mais 69,30 % de variations d'intervalle > 2 ms ;
décodage→présentation moyen 48,75 ms, p95 54,14 ms. La correction du contrat
rend les observations exploitables ; elle ne valide pas la fluidité et ne
constitue pas une optimisation démontrée de latence.

SHA256 du CSV natif :
`fcc17be917fb217d4b6b79c74c639edf6ec37a09b0919615a18f8aa594c7aa2b`.
SHA256 du CSV worker :
`f8bb8290f24c13194a4895a59744355f27294393826d2c568df26f3d7c05807e`.

## Variantes de présentation écartées

La projection `presentAtTime` testée sur banc local à 60 FPS n'a pas amélioré
la cadence (75,20 % de variations > 2 ms). Elle a été retirée du client, y
compris son paramètre dans le contrat du worker. Une sonde locale distincte
avec `presentAfterMinimumDuration` a réduit ce taux à 12,24 %, mais seulement
59,41 présentations/s et environ 49,12 ms entre disponibilité synthétique et
présentation : elle n'est pas intégrée. Ces sondes ne sont pas des résultats
de décodage vidéo. Le dernier banc vérifie aussi explicitement que la fenêtre
native est sur l'écran intégré, ID 1, avec une géométrie entièrement contenue.

Handoff et le mode secteur Économie d'énergie initial ont été restaurés. La
scène Windows est arrêtée, le serveur HTTP de test fermé et Vibepollo libre.
Les fichiers de mesure sont conservés. La validation globale VRR, les essais
longs, l'écran externe et PyroWave restent à effectuer.

## Diagnostic natif complémentaire — 3 octobre, après 18 h

Les captures Instruments du client et d'un banc Metal local montrent un refus
du chemin « Direct to Display » avec la raison « layer geometry isn't defined
in screen space ». La suggestion générique de désactiver `shouldRasterize`
n'explique pas le résultat : la propriété est déjà fausse et les transformations
de couche inspectées sont identitaires. Désactiver temporairement les Spaces
plein écran de SDL n'a pas supprimé ce refus. Il ne constitue pas, à lui seul,
la preuve de la cause des irrégularités. Aucun changement de politique plein
écran n'est conservé dans le client.

Une capture ScreenCaptureKit continue était observée pendant les premiers
essais. L'utilisateur a ensuite fermé sa connexion RDP ; les relevés `replayd`
suivants ne montrent plus les messages de santé de cette capture. Cela ne
prouve ni son origine ni une amélioration causale. L'état thermique des nouveaux
essais est `fair` (1), secteur Automatique, fenêtre active et visible sur la
dalle intégrée. Ne pas comparer ces essais à un contrôle thermique nominal.

Les premiers prototypes du banc local utilisaient une présentation immédiate
après `commit`, qui peut devancer la programmation GPU, puis un `MTKView`
susceptible d'interagir avec le cycle des surfaces. Ils restent archivés mais
sont exclus comme référence pour choisir l'architecture du client. Le banc
retenu utilise une vue AppKit à couche Metal et demande la présentation depuis
le callback de programmation du command buffer, conformément au contrat
de `MTLCommandBuffer.presentDrawable:`. Le chemin VRR du client attend déjà
la complétion GPU avant de présenter et n'a pas ce défaut du banc.

### Comparaison réelle à 60 images/s

Deux essais HEVC 1920×1200, 30 Mbit/s, négociation serveur VRR identique,
fenêtres de 30 s après 20 s de source animée. Le rendu de référence est choisi
par `MOONLIGHT_METAL_FIXED_CONTROL=1`, sans modifier le profil enregistré.

| Chemin local | Images soumises | Présentations confirmées | Décodage → présentation, moyenne / p95 |
| --- | ---: | ---: | ---: |
| VRR partagé, 18:29:08.230–18:29:38.230 | 1 800 | 1 600 (88,89 %) | 44,92 / 47,30 ms |
| Référence Metal, 18:33:33.653–18:34:03.653 | 1 094 | 1 094 (100 %) | 33,21 / 43,18 ms |

Ces essais ne qualifient aucun des deux chemins : le premier a des observations
manquantes, le second ne présente qu'environ 36,46 images/s. Les latences portent
uniquement sur les images confirmées et ne prouvent donc pas un avantage global
du second. La source Windows confirme 1 800 images dans chacune des deux fenêtres,
aucun créneau sauté et un intervalle maximum d'environ 19 ms.

Dans le premier essai, les 1 800 images arrivent au pacer sans trou d'identifiant,
mais 45 intervalles de réception dépassent 40 ms, jusqu'à 87,73 ms. Le décodage
moyen est de 1,90 ms. Sur les 200 présentations non confirmées, 112 appartiennent
aux 100 ms suivant une longue pause de réception ; 88 sont hors de cette fenêtre.
Cette corrélation partielle ne suffit pas à attribuer toutes les anomalies au
réseau. Le replay exact de cette capture passe. Les fenêtres PC/Mac utilisent
une corrélation horloge monotone/heure murale côté Mac, sans mesure de l'écart
des horloges entre machines ; aucune latence PC→Mac n'en est déduite.

Les messages de capture ScreenCaptureKit réapparaissent lors du contrôle visuel
du client. Nos outils peuvent donc perturber les conditions de mesure. Les
essais natifs suivants, sans contrôle visuel, ne montrent plus ces messages,
mais les variantes CADisplayLink immédiate et temporisée conservent des
intervalles irréguliers. Elles ne sont pas intégrées au client. Les essais
historiques du banc à couleur presque uniforme sont distincts du banc final
à barre mobile, validé fonctionnellement seulement.

Captures natives, conservées hors Git :
- `rdpclosed-real60-16856-1791045061708.csv`, SHA256
  `26e9ca007f533c892546718811a490cccff0eb273d138fefb3786793b572008c`.
- `rdpclosed-fixed60-17163-1791045330374.csv`, SHA256
  `58f7de0cc77bf0793a4d0a0ab68c4cb9866f6a969ec234e45a08eaf8dc5f87ff`.

Les mesures répétitives sont closes pour cette étape. Le mode secteur initial
Économie d'énergie du Mac est restauré, le mode batterie Performance inchangé.
Le PC Windows est resté allumé, sans modification d'alimentation, et Vibepollo
est libre. Les corrections de sécurité des surfaces et de complétion GPU restent
acquises ; la qualification globale VRR et une optimisation ProMotion démontrée
restent ouvertes. Ne pas présenter les limites observées comme définitivement
incorrigibles, ni passer à PyroWave en prétendant la validation VRR terminée.

## Comparaison de référence et vraie cadence variable — 3 octobre, 19 h–19 h 40

**La qualification VRR reste en échec.** Les essais fixes 60/120 FPS servent
de contrôles ; ils ne valident pas l'adaptation aux changements de cadence.
Cette campagne ajoute une source réellement variable et vérifie les identifiants
d'images reçues et leurs intervalles RTP, pas seulement la vitesse de l'animation.
Le code de rendu de production n'a pas changé pendant cette campagne.

### Contrôles sur la dalle intégrée

Référence : sources Nonary inchangées au commit
`43225b52c934174736123f894580c0decbe4bec2`, compilées séparément avec les mêmes
dépendances, Qt 6.11.1 et Xcode 27 que le candidat `c902366a`. Seul l'identifiant
du bundle de référence est distinct. Profil de comparaison séparé, HEVC
1920×1200, 30 Mbit/s, ProMotion, secteur Automatique, thermique nominal.
Chaque fenêtre analysée dure 11 secondes, au centre d'une capture Instruments.
La source Windows confirme respectivement 660 ou 1 320 images, sans créneau manqué.

| Client / cadence | Callbacks dans 11 s | Intervalle p95 / p99 / maximum |
| --- | ---: | ---: |
| Original, 60 FPS | 659 | 25 / 25 / 41,67 ms |
| Modifié, VRR désactivé, 60 FPS | 659 | 25 / 25 / 33,33 ms |
| Modifié, VRR activé, 60 FPS | 661 | 58,33 / 66,67 / 83,33 ms |
| Original, 120 FPS | 1 216, dont 211 au statut non validé | Comparaison incomplète |
| Modifié, VRR activé, 120 FPS | 1 256 | 8,33 / 16,67 / 25 ms |

À 60 FPS, le chemin VRR est moins régulier dans cet essai. Aucun gain global
par rapport au client original n'est démontré. La négociation VRR change aussi
la fréquence de capture virtuelle du serveur : 240 Hz pour les contrôles fixes
60 FPS, 480 Hz pour l'original 120 FPS, 1 000 Hz pour les essais VRR. Le contrôle
modifié sans VRR conserve les conditions serveur de l'original 60 FPS ; les
comparaisons VRR activé/original ne permettent pas d'isoler le seul rendu local.

Correction de mesure : l'attribution Instruments `displayed-surfaces-interval`
est incomplète et ne mesure pas le nombre total de présentations. Les intervalles
ci-dessus utilisent `ca-client-presented-handler`. Sur cette exportation Xcode 27,
les différences de son champ temporel nécessitent le facteur `3/125` de
`mach_timebase_info`. Cette conversion a été vérifiée par identité de drawable
contre les horodatages publics Metal sur 920 + 929 + 1 770 événements du candidat,
avec un écart résiduel inférieur à 0,003 µs. Le statut 3 de 211 événements de
l'original 120 FPS n'a pas cette validation indépendante : ne pas les compter
comme des présentations confirmées ni comme des images perdues.

### Écran USB-C et contrôle Metal indépendant

L'AORUS FO32U2P connecté en USB-C propose effectivement **Variable 48–240 Hz**
dans macOS. Dans ce mode, NSScreen rapporte un intervalle minimal de 4,167 ms,
maximal de 20,833 ms et une granularité nulle. En 240 Hz fixe, minimum et maximum
valent 4,167 ms. Cela confirme la disponibilité de la liaison Adaptive-Sync,
pas que le client l'exploite correctement. Apple documente cette connexion
[USB-C/DisplayPort et le choix Variable](https://support.apple.com/en-us/102144).

Huit contrôles locaux à barre mobile ont été effectués : 60, 90, 120 FPS et
cycle 60/90/120 dans chacun des deux modes d'écran. Fenêtre explicitement sur
l'écran externe, visible et active, zéro erreur GPU, retours de présentation
complets. Le banc CAMetalDisplayLink n'atteint cependant pas ses consignes :
environ 54/70/98 présentations/s en mode fixe, 48/59/63 en Variable pour les
trois cadences constantes. Le premier contrôle Variable 60 chevauche brièvement
un export Instruments et ne constitue pas une comparaison de performance isolée.

Ce banc est distinct du worker VRR de production qui acquiert avec `nextDrawable`.
Il n'est donc pas encore une référence de performance fiable et ne démontre
aucun plafond matériel de la dalle. La sélection explicite d'écran, la cadence
90 et le cycle variable sont conservés comme fonctions de diagnostic uniquement.

### Flux variable réel : trois séquences comparables

Chaque séquence dure 150 secondes : échauffement 60 FPS, puis sept plateaux
60 → 80 → 100 → 116 → 100 → 80 → 60 de 20 secondes. Les mesures portent sur
les 10 secondes centrales de chaque plateau. Le serveur confirme 12 520 images
par séquence, aucun créneau manqué, et 600/800/1 000/1 160/1 000/800/600 images
dans les fenêtres centrales. Même client, codec, débit et négociation serveur
dans les trois essais ; aucune capture Instruments durant ces séquences.

| Source cible | E1 : Variable, 2 surfaces | E2 : fixe 240 Hz, repli VSync | E3 : Variable, 3 surfaces |
| ---: | ---: | ---: | ---: |
| 60 FPS | 57,55 | 48,28 | 60,12 |
| 80 FPS | 61,75 | 59,25 | 63,35 |
| 100 FPS | 62,08 | 56,69 | 63,52 |
| 116 FPS | 61,56 | 56,10 | 63,25 |
| 100 FPS | 61,46 | 49,26 | 63,53 |
| 80 FPS | 61,91 | 56,37 | 63,72 |
| 60 FPS | 58,39 | 53,80 | 59,99 |

Les valeurs sont les cadences des événements natifs de présentation confirmés,
en images/s. La couverture est de 100 % des **images soumises**, pas des images
reçues. Les identifiants uniques et les intervalles RTP des traces E1/E3 prouvent
que la cadence entrante change réellement. Le chemin fixe E2 n'émet pas la trace
du worker VRR ; ne pas lui inventer de compte d'arrivées client.

Dans la fenêtre 116 FPS d'E1, le worker reçoit 1 162 images sans trou d'identifiant
et en soumet 616. Il en écarte 405 devenues anciennes dans la file, 122 pour
capacité et 19 pour ancienneté après admission. Sur les images présentées :

| Étape logicielle | E1 moyenne / p95 | E3 moyenne / p95 |
| --- | ---: | ---: |
| Décodage | 1,56 / 1,99 ms | 1,58 / 1,99 ms |
| Attente dans le worker | 19,18 / 25,28 ms | 18,86 / 25,45 ms |
| Acquisition d'une surface Metal | 12,33 / 15,27 ms | 12,00 / 15,24 ms |
| Soumission → présentation | 17,74 / 20,16 ms | 32,90 / 37,36 ms |
| Sortie décodage → présentation | 51,83 / 60,78 ms | 66,32 / 77,46 ms |

L'attente de réutilisation des surfaces est un blocage mesuré du chemin local.
Augmenter leur nombre de deux à trois ne lève pas le plafond et ajoute de la
latence : **cette modification est rejetée**, aucun défaut de production changé.
Cela ne prouve pas encore si l'origine est la configuration de la couche,
le contrat de présentation ou une interaction avec WindowServer/le pilote.
Les deux fenêtres comportent aussi 22 pauses de réception supérieures à 40 ms :
le réseau contribue aux irrégularités, sans expliquer seul la limitation observée.
Le repli fixe E2 est lui aussi insuffisant ; sa latence inférieure ne constitue
pas un avantage global puisqu'il présente moins d'images.

Les fenêtres PC/Mac sont corrélées par heure murale et horloge monotone Mac,
sans mesure de l'écart des horloges des deux machines. Les centres des plateaux
évitent les transitions ; aucune latence PC→Mac ou réponse physique du pixel
n'est déduite. Les variations instantanées, fréquences sous 48 Hz et endurance
ne sont pas qualifiées par cette campagne à plateaux.

### Vérification, conservation et suite

Les replays exacts des captures E1 et E3 passent. Cela valide la reconstruction
du worker, pas la fluidité. Le banc final compile et est signé ; les huit tests
Python passent et cinq arguments malformés sont rejetés avant création de fenêtre.
Captures, profils, binaires de référence, sommes SHA256 et analyses sont conservés
localement sous `.runtime/comparison-20261003/`, hors Git. Les nouveaux réglages
du banc n'affectent pas le client installé ni le contrôleur partagé.

Les essais sont arrêtés des deux côtés. L'écran externe est restauré en 240 Hz
fixe et le secteur Mac en Économie d'énergie, vérifié dans l'interface et par
`pmset`. Le mode batterie est observé Automatique en fin de campagne, contrairement
au relevé initial Performance ; aucune action sur son réglage n'a été émise,
il n'a donc pas été écrasé. Aucune alimentation Windows n'a été modifiée.

La prochaine investigation doit isoler la rétention/présentation des surfaces
avec une référence Metal plein écran dont la cadence est d'abord démontrée,
puis comparer ce contrat au client. Retoucher les constantes du contrôleur ou
augmenter la file sans résoudre cette limite n'est pas justifié. La stabilisation
VRR reste ouverte ; PyroWave n'a pas commencé.

## Isolation courte et inspection d'autres intégrations — 3 octobre, après 20 h

À la demande de l'utilisateur, les nouveaux essais locaux durent 10 ou 12 s
(plus 3 s de transition plein écran). Aucun navigateur, flux Windows ni réglage
serveur n'intervient. Ils réutilisent le dessin du banc, avec une boucle dédiée,
un autorelease pool par image, des mesures d'acquisition des surfaces et un
contrôle d'écran sur le thread principal. Trois opérations sont comparées :
présentation attachée au command buffer, durée minimale native et attente GPU
suivie de `present`, cette dernière reproduisant l'ordre du client sans ses files.

### Références inspectées et limites de transposition

- [Andy Grundman, `57088f1a`](https://github.com/andygrundman/moonlight-qt/blob/57088f1a22bd7a3f1ced1af5102444edcc422241/app/streaming/video/ffmpeg-renderers/vt_metal.mm) :
  VRR continu conditionné au plein écran, ProMotion distingué par défaut,
  présentation dans un scheduled handler, `presentAfterMinimumDuration` fondé
  sur le temps GPU moyen ou, en option expérimentale, les écarts PTS. Acquisition
  suivante après présentation. Son pacer immédiat remplace l'ordonnancement
  habituel : ce n'est pas une fonction isolée à greffer au worker Nonary.
- [RetroArch, `dca728ca`](https://github.com/libretro/RetroArch/blob/dca728cad854a1f9eb1188cc0094d8f8e7c5cbe2/gfx/drivers/metal.m) :
  scheduled handler, libération du drawable puis acquisition du suivant pour
  réguler la boucle. Cette régulation ne garantit pas la restitution des PTS
  d'un flux réseau variable.
- [MoltenVK, `52aa21f5`](https://github.com/KhronosGroup/MoltenVK/blob/52aa21f54d7a84c5c441fc26359692b0980b384c/MoltenVK/MoltenVK/GPUObjects/MVKImage.mm) :
  présentation depuis un scheduled handler et rétention explicite jusqu'à
  complétion ; acquisition et observation de présentation restent distinctes.
  Le contexte est une swapchain Vulkan, pas le worker vidéo de ce fork.
- [Exemple Apple CAMetalDisplayLink](https://developer.apple.com/documentation/metal/achieving-smooth-frame-rates-with-a-metal-display-link) :
  `preferredFrameLatency=2`, drawable fourni par le lien et présentation attachée
  au command buffer. Il ne faut pas mélanger ce fournisseur de drawables avec
  `nextDrawable` sur la même couche. L'[exemple Adaptive-Sync Apple](https://developer.apple.com/videos/play/wwdc2021/10147/)
  décrit aussi une boucle indépendante utilisant une durée minimale native.

Le code de couche Metal de mpv a également été lu : il traite notamment
l'opacité et les transitions de couche avec MoltenVK, mais ne constitue pas
une implémentation de remplacement du pacing vidéo de Moonlight. Aucun de ces
programmes n'a été déclaré validé sur cette machine à partir de sa seule source.

### Résultats discriminants

Les premières comparaisons constantes ont reçu des callbacks avec
`presentedTime=0`, y compris avec l'ancien binaire du banc et en 240 Hz fixe.
Un contrôle visuel distinct confirme que l'image est visible. Ces captures
ne permettent donc pas de déduire un nombre d'images affichées ou perdues.
L'attachement d'Instruments coïncide avec le retour des horodatages positifs
et un débit inférieur ; les horodatages restent disponibles après son arrêt.
Ce changement d'état empêche de traiter l'ensemble comme un A/B de performances
isolé. L'origine exacte de cet effet persistant n'est pas établie.

L'attachement initial a expiré avant de produire une trace complète. Une capture
séparée lancée par Instruments a ensuite été enregistrée et exportée ; elle
rapporte encore le refus Direct to Display pour géométrie de couche. Ce motif
n'est toujours pas une preuve suffisante de la cause du débit. Le contrôle
`fixed120-after-clean-stop` est exclu comme baseline : export concomitant et
garde d'écran invalidé en fin de capture. Aucune erreur GPU n'est utilisée comme
synonyme de callback manquant.

Après ces contrôles, trois séquences comparables de 12 s sur l'AORUS Variable
ont fourni des horodatages positifs pour toutes les soumissions des fenêtres
centrales (2 s par plateau). Aucun Instruments, export ou contrôle visuel pendant
ces trois séquences ; même binaire, dessin, couche AppKit et trois drawables.

| Consigne | Attendre le GPU puis `present` | Présentation par command buffer | Durée minimale native |
| ---: | ---: | ---: | ---: |
| 60 FPS | 60,19 | 60,03 | 54,65 |
| 90 FPS | 89,83 | 90,00 | 82,07 |
| 120 FPS | 120,02 | 119,97 | 115,01 |
| 90 FPS | 89,95 | 90,09 | 80,93 |

Cadences en événements de présentation/s, pas réponse physique des pixels.
Dans le plateau 120 FPS, l'acquisition moyenne prend environ 0,015 ms avec les
deux premières méthodes, contre 8,63 ms avec la durée minimale qui régule
volontairement la boucle. Cette dernière utilise ici 1/FPS, pas l'algorithme
GPU moyen d'Andy : le tableau ne compare pas directement son client au nôtre.

À 120 FPS, les intervalles p95/p99 sont 9,60/10,01 ms après attente GPU,
9,49/12,51 ms par command buffer et 12,51/15,74 ms avec durée minimale.
Les moyennes correctes ne signifient donc pas une absence de variations :
le banc est une référence de débit court, pas une qualification de fluidité.

Trois contrôles supplémentaires de 12 s rapprochent le banc du client :

| Variante du contrôle après attente GPU | Cadence confirmée au plateau 120 | Acquisition moyenne |
| --- | ---: | ---: |
| Couche AppKit, Rec.709, trois surfaces | 120,06 FPS | 0,015 ms |
| Même contrôle, deux surfaces | 103,32 FPS | 8,62 ms |
| Fenêtre et vue Metal SDL, Rec.709, trois surfaces | 106,44 FPS | 8,13 ms |

Ces trois contrôles ont des retours de présentation complets et terminent
normalement. Le contrôle SDL remplace ensemble la fenêtre et la vue Metal ;
il n'isole pas encore laquelle de leurs propriétés explique l'écart. Ce sont
des essais uniques, non une preuve statistique de régression SDL. Le profil
Rec.709 seul ne reproduit pas le plafond ; deux surfaces font réapparaître de
la pression, mais trois surfaces n'avaient pas corrigé le client réel. Il faut
donc examiner la combinaison fenêtre/couche et ordonnanceur vidéo, pas promouvoir
automatiquement un pool plus grand ou supprimer l'attente GPU.

**Le plafond de 62–63 FPS n'est donc pas intrinsèque à Metal ou à cet écran,
et attendre la complétion GPU avant `present` ne suffit pas à le provoquer.**
Le blocage d'acquisition observé dans Moonlight reste réel dans ses captures,
mais l'attribuer à ce seul ordre d'appels était prématuré. Les essais courts
ne qualifient ni l'endurance ni la latence du flux ; aucun changement de rendu
de production n'est justifié par la seule suppression de l'attente GPU.

Les captures et variantes locales sont conservées sous
`.runtime/surface-isolation-20261003/`, avec versions des références et sommes
de contrôle, hors Git. Les nouveaux champs du banc distinguent échéance absente,
enregistrement d'une demande et présentation ; un test de non-régression empêche
de fabriquer des retards à partir des échéances nulles des boucles indépendantes.
Le banc final compile et sa signature passe la vérification ; cinq tests du
banc et quatre tests de corrélation du pipeline passent. Le client de production
est inchangé. Le mode externe 240 Hz fixe et le secteur Économie d'énergie sont
restaurés ; la batterie reste Automatique. Aucun essai ni changement Windows
n'a été réalisé pendant cette isolation locale.

## Décisions et corrections après comparaison des clients — 3 octobre, après 20 h 45

### Fenêtre SDL : réécriture écartée

Quatre contrôles courts sur l'AORUS Variable comparent la vue SDL, une vue Metal
native ajoutée à la même fenêtre SDL, une vue native remplaçant son contenu et
le banc AppKit d'origine. Ils terminent normalement sur le CGDisplayID 5,
3840×2160, secteur Automatique. Au plateau 120, ils présentent respectivement
77,61 / 83,33 / 81,88 / 82,83 événements/s. Le contrôle natif qui atteignait
120 auparavant ne le reproduit pas dans cette campagne. Ces essais uniques
ne prouvent donc pas une cause propre à SDL. Aucun remplacement de fenêtre/vue
n'est intégré. Un contrôle remplaçant uniquement `present` après complétion par
`presentAfterMinimumDuration:0` donne 81,34 événements/s : il est aussi écarté.

### Une erreur de sélection du plein écran corrigée

`--display-mode fullscreen` choisissait le mode historique sans Space native.
La session VRR forçait ensuite `WM_FULLSCREEN_DESKTOP`, mais conservait le hint
macOS choisi d'après l'ancienne préférence. Le client annonçait ainsi une
présentation adaptative sans vérifier le drapeau natif. Andy metal-v6 refuse
explicitement le VRR dans cet état, ce qui a permis d'isoler cette incohérence.

La demande VRR choisit maintenant les Spaces **avant la création des fenêtres
SDL**, après la politique d'encoche. Une première tentative changeant le hint
dans le snapshot de présentation était trop tardive avec sdl2-compat ; le
contrôle réel l'a rejetée. Le code final garde la préférence utilisateur et
journalise l'identité CoreGraphics, le caractère intégré et le plein écran natif.
L'Adaptive-Sync continu est refusé si le plein écran natif manque, avec repli
V-sync. Le cas `fullscreen` est ensuite confirmé `display=5 built_in=0
native_fullscreen=1`, et le contrôle interne `display=1 built_in=1
native_fullscreen=1`. Cette correction d'éligibilité ne résout pas le plafond
externe à elle seule.

### Comparaison réelle avec Andy

Le bundle officiel **metal-v6** est copié uniquement sous `.runtime`, sans
remplacer une installation utilisateur. Son DMG correspond au SHA256 publié
`5770e7394a23bb892ece96c3374637527e583897301a5c8ba06dc6bf0254632e`.
Source du tag : `bbc412fcaa209f69142bfb783b34a250cb0e41d1` ; ne pas confondre
ce tag avec la branche plus récente inspectée précédemment.

Un observateur local identique des acquisitions `CAMetalLayer.nextDrawable`
ajoute un callback de présentation dans les deux clients, sans remplacer leurs
appels de présentation. Sur notre contrôle, 2 262 horodatages positifs coïncident
exactement avec le journal natif du client après sélection de la bonne couche
(les identifiants de drawable seuls ne sont pas uniques entre couches).
Cet observateur ne couvre pas les drawables fournis par CAMetalDisplayLink :
le repli fixe ci-dessous est analysé avec le journal natif de Moonlight.

Animation Chrome 120 FPS sur Windows, fenêtres centrales de 12 s dans des
animations d'environ 15 s ; les attentes de connexion/orchestration sont hors
fenêtre mesurée. Les sources A/B/C exportent chacune 1 440 dessins, aucun créneau
manqué. Les mesures Mac et Windows sont corrélées par heure murale et une paire
horloge murale/monotone Mac ; l'écart d'horloge entre machines n'est pas mesuré.
Les marges de deux secondes évitent les transitions, aucune latence PC→Mac
n'est déduite.

| Contrôle externe | Acquisitions | Présentations positives | Événements/s | Intervalle p95 / p99 |
| --- | ---: | ---: | ---: | ---: |
| Notre A, mode historique non natif | 1 110 | 838 | 69,83 | 37,90 / 59,86 ms |
| Andy B, plein écran natif, VRR confirmé | 1 015 | 1 015 | 84,62 | 14,29 / 14,99 ms |
| Notre C, plein écran natif, worker adaptatif | 937 | 937 | 77,96 | 16,12 / 37,54 ms |

Ce n'est pas un A/B isolé du moteur : Andy embarque SDL3 3.4.9, notre client
3.4.12, leurs protocoles/pacers diffèrent. L'hôte annonce 1000 Hz virtuels pour A,
480 pour B **et C**, mais seul notre client demande sa politique VRR faible
latence. Ces fréquences virtuelles ne sont pas le débit vidéo. Les callbacks
nuls de A ne sont pas convertis en preuve d'images invisibles. Andy plante à
l'arrêt SIGTERM du lanceur après sa borne de connexion de 120 s, après la
fenêtre mesurée ; le rapport situe le crash dans Moonlight sur la file principale.
La causalité et une éventuelle interaction avec l'observateur ne sont pas
établies. Ce contrôle ne qualifie donc ni sa stabilité, ni une supériorité
générale ; il n'atteint pas non plus 120 présentations/s ici. Aucun import de
son pacer n'est retenu.

### ProMotion : retour au chemin natif fixe, gain mesuré

Le worker Adaptive-Sync n'est plus sélectionné pour une dalle à cadence
discrète (`displayUpdateGranularity > 0`). Le chemin Metal fixe existant est
conservé, y compris lorsque VRR est demandé. La demande CADisplayLink indépendante
est supprimée du code et du build, plutôt que laissée inactive. Les anciennes
colonnes de ticks du CSV sont conservées pour lire les captures historiques,
et restent nulles lorsqu'aucun observateur ne les renseigne.

Sur l'écran intégré seul, gardé par l'identité native, mêmes dessins Chrome
60 FPS et fenêtres de 12 s :

| Chemin interne | Présentations positives | Événements/s | Intervalle p95 / p99 / maximum |
| --- | ---: | ---: | ---: |
| Worker adaptatif D | 717 / 717 | 59,96 | 50,00 / 75,00 / 83,33 ms |
| Repli Metal fixe E | 713 / 713 | 59,37 | 25,00 / 25,00 / 29,17 ms |

Les sources D/E consignent 720 dessins sans créneau manqué. Le repli réduit
nettement les longues variations dans ces contrôles, au prix d'un débit mesuré
légèrement inférieur ; ce n'est pas une restitution parfaite à 16,67 ms.
La latence logicielle sortie décodeur→présentation augmente en moyenne de
28,36 à 34,48 ms (+6,12 ms), p95 de 41,63 à 46,66 ms. Le gain de régularité
n'est donc pas gratuit et ne constitue pas un optimum de latence.
Il rejoint les résultats fixes antérieurs et évite d'annoncer du VRR continu
sur ProMotion. Le plafond externe reste ouvert ; PyroWave n'est pas commencé.

### Source variable courte : contrôle rejeté comme qualification VRR

Le banc WinForms/GDI autonome créé côté Windows a effectivement terminé en
12,002 s, focus et écran virtuel capturé DISPLAY10 vérifiés. Il dessine
180/269/322/270 images dans les paliers 60/90/120/90 ; le palier 120 manque donc
38 dessins. Surtout, le Mac reçoit **120 RTP/s sur chacun des quatre paliers**.
Les 240 arrivées par fenêtre centrale de 2 s ne constituent pas un flux variable.
Les présentations mesurées (80,71 / 86,64 / 80,14 / 82,17 événements/s) ne sont
pas utilisées pour prétendre suivre ces changements de cadence. Le replay exact
et l'intégrité de cette capture passent ; ils valident la reconstruction du
worker, pas le protocole source ni sa fluidité.

La première tentative F n'avait produit aucune animation : la connexion avait
expiré pendant la préparation et le banc a refusé l'écran virtuel disparu.
F2 a utilisé une borne de connexion plus large, sans allonger les 12 s de dessin.
Les sources et rapports Windows sont conservés dans le dossier de vérification
`vrr/native-source`, les captures Mac sous `.runtime/window-isolation-20261003/`.
La validation d'un **flux** variable court reste ouverte : elle doit commencer
par vérifier les intervalles RTP effectivement reçus, avant de comparer les
présentations ou de régler le contrôleur. Un compteur de dessin seul ne suffit pas.

### Reprise après déverrouillage : contrôle local court

Deux nouveaux contrôles AppKit/Metal de 12 s, même binaire Rec.709 et écran
AORUS ID 5 en Variable, secteur Automatique, retrouvent respectivement
60,01 / 89,97 / 121,19 / 89,96 puis 60,06 / 90,02 / 109,50 / 89,98
présentations/s dans les fenêtres centrales des paliers 60/90/120/90.
Toutes les acquisitions de ces fenêtres ont un callback positif, sans perte
de visibilité ou d'activité. Le premier contrôle conserve la session de contrôle
d'interface ; le second suit sa réinitialisation. Celle-ci ne prouve pas l'arrêt
d'une capture système et ne montre aucun bénéfice dans ces deux essais.
Le résultat antérieur proche de 83 événements/s n'est donc pas un plafond
matériel constant ; ni sa cause ni celle de la variation restante ne sont isolées.
Ces contrôles synthétiques n'incluent ni réseau ni décodeur vidéo.

Une assertion `caffeinate -diu -t 3600` maintient temporairement le Mac éveillé
pendant la reprise, à la demande de l'utilisateur. Elle ne modifie aucun réglage
permanent d'authentification ou d'alimentation. Les données sont conservées sous
`appkit-cua-active` et `appkit-cua-reset` dans le dossier de campagne ignoré.

### Source DXGI courte : cadence source correcte, flux encore fixe

Le banc D3D11/DXGI utilise flip-discard, deux buffers, une latence maximale
de 1, `Present(0, ALLOW_TEARING)` et des échéances QPC absolues. Le lancement
G3 du 3 octobre à 19:52:02.466 UTC dure 12,00001 s sur DISPLAY10 vérifié.
Les appels Present réussis sont exactement 180/270/360/270 pour les quatre
paliers de trois secondes 60/90/120/90, sans créneau manqué. Leur retard
p95 reste inférieur à 0,327 ms et leur maximum à 0,773 ms. Ce sont des
soumissions CPU réussies, pas des preuves du scanout Windows.

G1 et G2 avaient été annulés avant toute animation par le garde-fou de focus.
Le banc a été corrigé pour présenter une image d'attente, exposer sa fenêtre
avec `WS_EX_APPWINDOW` et attendre Espace après activation explicite. G3
confirme son ouverture, son focus et sa fermeture automatique. La cause exacte
du filtrage des anciennes fenêtres par l'outil de contrôle n'est pas prouvée.

Sur le Mac, écran AORUS ID 5, plein écran natif et mode Variable confirmés :

| Source demandée | Appels Present source/s | Images reçues/s | Intervalle RTP moyen | Présentations Metal/s |
| --- | ---: | ---: | ---: | ---: |
| 60 | 60 | 120,5 | 8,334 ms | 89,18 |
| 90 | 90 | 120 | 8,331 ms | 108,30 |
| 120 | 120 | 120 | 8,327 ms | 89,45 |
| 90 | 90 | 120 | 8,333 ms | 96,33 |

Fenêtres centrales de 2 s ; alignement des horloges civiles sans mesure de
l'offset entre machines. Tous les callbacks de présentation du Mac sont
positifs dans ces fenêtres. Le p99 des intervalles est 24,17 / 16,42 / 16,74 /
16,70 ms. Le replay exact de la trace passe et la fermeture du client retourne 0.

Le flux reçu reste donc fixe, même avec cette source GPU correctement cadencée.
Ce contrôle ne qualifie pas le suivi VRR variable. La prochaine investigation
doit localiser la production de cette cadence dans la capture, l'encodage et
les horodatages du serveur ; modifier le contrôleur client sur cette seule
base ne permettrait pas de résoudre cette absence de variabilité. L'identité
visuelle des images n'est pas décodée ici : ne pas affirmer qu'il s'agit de
duplications exactes sur la seule cadence RTP.

Sources et exports Windows : dossier de vérification `vrr/dxgi-source`.
Captures Mac : `ours-dxgi-variable-g3*`, synthèse source transmise par le helper
et manifeste SHA256 dans `.runtime/window-isolation-20261003/`.

L'inspection Windows retrouve ensuite le journal du helper WGC : une fenêtre
de 15,0152 s terminant à 21:52:16.729 heure locale, qui englobe G3, rapporte
583,743 captures/s et 314,482 publications/s. La fenêtre précédente, avant
l'animation, rapporte déjà 571,436 et 312,225. La capture du bureau fournit donc
bien plus d'événements que les appels Present du banc ; le prélèvement limité
à 120 explique la cadence reçue sans supposer un simple réétiquetage RTP.
Le code du helper incrémente son ID à chaque publication sans comparaison des
pixels. Cela ne prouve toujours pas que les contenus sont identiques, ni quel
composant du bureau provoque les événements supplémentaires. La configuration
ne sélectionne pas `wgcc`, le mode de répétition explicite : il n'est pas retenu
comme cause. Journal conservé côté Windows sous `G3-wgc-helper.log`.

Une comparaison DDX a été préparée, mais sa première tentative de configuration
a échoué en écriture sous Program Files. Le hash du fichier d'origine est resté
identique. La connexion Mac ouverte sur une annonce prématurée de réussite a
été fermée normalement, sans lancement du banc : ce G4 n'est pas un résultat
DDX et doit être exclu. Toute reprise exige de vérifier la méthode de capture
effectivement sélectionnée avant le départ du banc.

### Vérifications et restauration

Le bundle ARM64 final est reconstruit, déployé dans le bundle de développement
et sa signature vérifiée. Sept suites C++, neuf tests Python, le replay exact
du fixture command-buffer et celui de la capture F2 passent. Les journaux, sources
des variantes, binaires et captures sont conservés avec leurs SHA256 hors Git.
Le réglage externe 240 Hz fixe et le secteur Économie d'énergie sont restaurés,
la batterie reste Automatique. Aucun réglage d'alimentation Windows n'est changé.
