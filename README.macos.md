# Moonlight macOS — base de travail VRR

Fork : https://github.com/Apoze/moonlight-macos

Base : `Nonary/moonlight-qt`, branche `release/6.1.0-vrr18`, commit
`43225b52c934174736123f894580c0decbe4bec2`. Les sous-modules restent épinglés
aux versions de Nonary, notamment `moonlight-common-c` à `d6a11bc`.

## État et périmètre

**Statut expérimental : la fluidité et les hautes cadences ne sont pas encore
validées.** Voir les mesures et limites dans le rapport ci-dessous. Le profil
de référence reste inchangé, VRR désactivé.

La branche `macos/metal-adaptive-presentation` ajoute le présentateur Metal
au contrôleur VRR de Nonary, avec demande de fréquence ProMotion indépendante du rendu,
protection des surfaces GPU et mesures des présentations rapportées par macOS.
Le rendu fixe reste disponible. PyroWave n'est pas ajouté.
Voir [la conception et le protocole](docs/macos-metal-presentation.md).

Premier matériel ciblé : MacBook Pro M5 Pro, écran intégré Liquid Retina XDR
3024 × 1964, mode nominal 120 Hz. L’AORUS FO32U2P USB-C fait maintenant
l’objet de comparaisons séparées, autorisées par l’utilisateur, entre 240 Hz
fixe et Variable 48–240 Hz. La fréquence nominale et ProMotion ne prouvent pas que la dalle
suit les horodatages du flux comme un écran externe Adaptive-Sync.

## Construire sur le Mac

Prérequis : Xcode avec ses outils de compilation, Python 3, Git, accès réseau.

```sh
./scripts/macos/bootstrap.sh
./scripts/macos/build.sh
./scripts/macos/test.sh
./scripts/macos/launch-builtin.command
```

Qt 6.11.1 est installé dans `../.tools/Qt` via aqtinstall 3.3.0. Le chemin
est personnalisable avec `MOONLIGHT_TOOLS_DIR`. Les bibliothèques natives
sont celles de `setup-deps.py`, version v8 du dépôt officiel de dépendances.
Le build utilise ARM64 et huit tâches par défaut (`MOONLIGHT_BUILD_JOBS`).

Application : `build/deploy/Moonlight Mac VRR Dev.app`. Elle contient Qt et
les bibliothèques natives et reçoit une signature ad hoc locale, sans
notarisation Apple. Son identifiant est distinct du client officiel.
Les journaux de compilation et déploiement sont dans `build/macos`.

## Lancer uniquement sur l'écran intégré

Utiliser le lanceur `.command`, pas directement le bundle : il active le mode
portable et `MOONLIGHT_BUILTIN_DISPLAY_ONLY=1`. Le profil, les associations
et les logs restent dans `.runtime/builtin`, exclus de Git. Le premier
lancement initialise HEVC matériel, Metal, 1920 × 1200 à 60 FPS, 30 Mbit/s,
V-sync et cadence fixe, HDR et VRR désactivés pour mesurer la référence.
Les lancements suivants préservent les réglages du profil.

Sur macOS, Qt range ce profil dans
`.runtime/builtin/moonlight-stream.com/Moonlight.ini`, d'après le domaine
de l'organisation. Le dossier portant son nom complet n'est pas utilisé.

Le garde-fou identifie la dalle intégrée via CoreGraphics et l'identité native
de QScreen, sans dépendre de son nom ou d'un numéro d'écran fixe. Il positionne
l'interface sur cette dalle et refuse un écran intégré absent ou en miroir.
La fenêtre vidéo est créée cachée puis vérifiée nativement avant affichage ;
sa zone vidéo entière doit tenir sur la dalle intégrée. Un déplacement de
l'interface sur l'écran externe ferme le client ; un
changement d'écran pendant le flux interrompt la session. La surveillance
s'effectue dans la boucle d'événements ; elle ne verrouille pas les commandes
de fenêtres de macOS. Ne pas déplacer la fenêtre pendant une mesure.
Aucun mode système ni réglage de l'écran externe n'est modifié.

Un nouvel appairage PIN avec Vibepollo peut être nécessaire car ce profil est
indépendant. Ne jamais committer son fichier INI, certificats ou journaux.

## Validation de l’intégration

Le présentateur est développé sur `macos/metal-adaptive-presentation`.
Les mesures utilisent `MTLDrawable.presentedTime`, et les horodatages de sortie du décodeur. L’overlay seul ne suffit pas.
Les CSV bruts et associations restent dans `.runtime`, jamais dans Git.

Les sept suites déterministes couvrent le contrôleur partagé, ses politiques,
le worker, les configurations de replay, les observations Metal et leurs conversions
d’horloge. Les traces réelles passent aussi le replay exact. Le test de complétion GPU
couvre présentation et annulation, avec un replay exact automatisé ; les
huit tests Python vérifient la corrélation des étapes du pipeline et la
distinction entre complétion GPU et présentation dans le banc natif.
Voir [la roadmap et les résultats récents](docs/macos-vrr-roadmap.md).
Cela ne valide pas à lui seul le scanout physique ou la latence clic-à-photon.

Les premiers essais de l’écran externe sont décrits dans la roadmap ; ils ne
constituent pas une qualification VRR. PyroWave reste une étape séparée. HDR, AV1, audio perçu et longues sessions
nécessitent leurs propres essais.

## Vérification de la base — 3 octobre 2026

- Compilation Release ARM64 avec Xcode 26.6 et Qt 6.11.1.
- Six suites passent : contrôleur, politique de fréquence, worker, configuration
  du replay, politique de rendu et politique de liaison D3D11 (test logique).
- `vrrreplay --help` fonctionne. Les chemins d'en-têtes SDL et FFmpeg manquants
  dans trois projets de tests ont été corrigés pour macOS.
- Bundle autonome signé localement et signature vérifiée ; interface ouverte
  sur la dalle intégrée, découverte réseau fonctionnelle. Le garde-fou refuse
  aussi un lancement sans écran natif (test offscreen, code de sortie 2).
- Appairage Vibepollo effectué avec un client dédié ; lancement, clavier et
  souris autorisés sur ce client. Profil corrigé pour le chemin Qt macOS.
- Session HEVC réelle de 85 secondes : bureau Windows visible sur l'écran
  intégré, VideoToolbox matériel et Metal, flux négocié 1920 × 1200 à 60 FPS,
  30 Mbit/s, SDR, V-sync actif et VRR désactivé. Le serveur confirme la capture
  virtuelle 1920 × 1200 et HEVC NVENC. Arrêt Desktop confirmé par le serveur.
- Sur ce bureau essentiellement statique : 16,39 images/s reçues et rendues,
  aucune image perdue par le réseau ou le pacing, décodage moyen 3,41 ms,
  réseau moyen 11 ms. Cela ne valide pas 60 FPS soutenus sur du contenu animé,
  ni la latence physique de bout en bout. Un premier essai sur l'écran de
  connexion a été interrompu par un redémarrage serveur lors d'un changement
  de session Windows ; il est exclu de cette mesure.
- Test animé supplémentaire sur la même configuration : deux relevés de
  l'overlay, espacés de 41 secondes, montrent 60,14 puis 60,07 FPS reçus,
  décodés et rendus, avec 0 % de pertes réseau et de pertes par le pacing.
  Au second relevé : réseau 3 ms, décodage 2,64 ms, traitement hôte 1,6 ms.
  Le compteur 240 Hz de la page mesure le navigateur Windows, pas le flux.
  Cette vérification courte valide le transport HEVC à environ 60 FPS ; elle
  ne mesure pas la cadence physique de la dalle ni sa réponse adaptative.
- Cette référence historique précède le présentateur décrit ci-dessus. AV1,
  l’audio perçu et la stabilité sur de longues sessions restent à valider.
