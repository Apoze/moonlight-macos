# Validation du VRR Metal — écran intégré

Statut : en cours, aucune qualification de fluidité ou de latence physique.
Base de comparaison : PR #1, commit 0a02a249. Les captures et profils restent
dans `.runtime`, hors Git. L'écran externe et PyroWave suivent cette validation.

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
  veille/reprise, mode d'énergie et réseau dégradé.
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
