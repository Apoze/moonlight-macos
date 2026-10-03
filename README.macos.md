# Moonlight macOS — base de travail VRR

Fork : https://github.com/Apoze/moonlight-macos

Base : `Nonary/moonlight-qt`, branche `release/6.1.0-vrr18`, commit
`43225b52c934174736123f894580c0decbe4bec2`. Les sous-modules restent épinglés
aux versions de Nonary, notamment `moonlight-common-c` à `d6a11bc`.

## État et périmètre

Cette première branche prépare une application macOS ARM64 reproductible,
un profil de test isolé et un garde-fou pour l'écran intégré. Elle ne porte
pas encore le présentateur VRR Metal de la PR #3 et n'ajoute pas PyroWave.
Le pipeline VideoToolbox/Metal de Nonary constitue la référence initiale.

Premier matériel ciblé : MacBook Pro M5 Pro, écran intégré Liquid Retina XDR
3024 × 1964, mode nominal 120 Hz. L'écran externe reste connecté mais exclu
des essais. La fréquence nominale et ProMotion ne prouvent pas que la dalle
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
Un déplacement de l'interface sur l'écran externe ferme le client ; un
changement d'écran pendant le flux interrompt la session. La surveillance
s'effectue dans la boucle d'événements ; elle ne verrouille pas les commandes
de fenêtres de macOS. Ne pas déplacer la fenêtre pendant une mesure.
Aucun mode système ni réglage de l'écran externe n'est modifié.

Un nouvel appairage PIN avec Vibepollo peut être nécessaire car ce profil est
indépendant. Ne jamais committer son fichier INI, certificats ou journaux.

## Étapes suivantes

1. Compléter la référence HEVC avec du contenu animé et tester AV1.
2. Adapter et auditer le travail Metal de [la PR #3](https://github.com/Nonary/moonlight-qt/pull/3)
   contre les contrats de présentation actuels de VRR18. Étudier la branche
   d'Andy comme référence ; ne pas importer globalement ses changements.
3. Comparer les cadences sur l'écran intégré avec des sessions reproductibles.
   Distinguer rendu soumis, présentation rapportée par macOS et affichage physique.
4. Traiter ensuite l'écran externe, puis le décodeur PyroWave Metal séparément.

Les tests déterministes couvrent le contrôleur partagé, les politiques et le
worker ; ils ne valident pas à eux seuls le rendu Metal ou un flux réel.
Ne pas annoncer le VRR Metal ou PyroWave opérationnels sur cette branche.

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
- Le port Metal VRR, AV1, l'audio perçu et les mesures sur contenu animé
  restent à valider dans les prochaines étapes.
