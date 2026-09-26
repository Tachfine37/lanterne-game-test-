# Lanterne — Les jardins du crépuscule

Prototype de roguelite **Flutter + Flame**. Gameplay 2D, représentation en volume dessinée avec Canvas : ombres, sol surélevé et tri des personnages par profondeur. Aucun asset externe requis.

## Jouer

Version web : https://Tachfine37.github.io/lanterne-game-test-/

- Mobile : maintenir et glisser le doigt dans le jardin ; relâcher pour tirer.
- Ordinateur : flèches, WASD ou ZQSD ; P / Échap pour la pause ; M pour couper le son.
- 10 vagues sur 2 biomes : le Jardin des murmures puis le Bassin de lune.
- 6 types d'ennemis : champignon, phalène (tir), scarabée (charge), champignon-mère (se divise en spores), crapaud-mortier (tir en cloche avec zone d'impact annoncée).
- 2 gardiens : la Tortue-sanctuaire (vague 5) et la Chouette de minuit (vague 10, spirales, éventails et invocations, enragée sous 50 % de vie).
- 16 dons cumulables, avec synergies (critiques, explosions en chaîne, rebonds vers un autre ennemi, bouclier, givre, vol de vie…). Une relance des dons par partie.
- Chaque partie rapporte des braises à dépenser à l'autel des braises en améliorations permanentes : PV, dégâts, vitesse, relances.
- Ressenti : dégâts flottants, coups critiques, recul des ennemis, tremblement d'écran, ondes de choc.
- Sons et musique synthétisés en direct (Web Audio), sans fichier audio.
- Meilleur score, braises, améliorations et réglage du son enregistrés localement si le navigateur autorise le stockage.

## Développer

```sh
flutter pub get
flutter run -d chrome
flutter analyze
flutter test
flutter build web --release --base-href /lanterne-game-test-/
```

Le workflow `.github/workflows/pages.yml` vérifie et publie `main`. GitHub Pages est configuré avec la source **GitHub Actions**. Chaque push sur `main` reconstruit le jeu.

## Organisation

- `lib/model.dart` : simulation, vagues, ennemis, dons, autel et progression ; aucune dépendance à Flame, mais `dart:ui` pour les vecteurs. Émet des événements sonores (`Sfx`) sans les jouer.
- `lib/garden_game.dart` : boucle Flame et dessins procéduraux.
- `lib/main.dart` : interface Flutter, joystick, clavier, pause, autel des braises et stockage local.
- `lib/audio_web.dart` : synthèse Web Audio des effets et de la musique ; `lib/audio_stub.dart` la remplace hors navigateur (tests, futures versions natives).
- `test/model_test.dart` : règles de combat, nouveaux ennemis, dons, autel, et un bot qui joue des parties complètes pour détecter les régressions d'équilibrage.

## Limites du prototype

Deux biomes sur la même arène, pas de multijoueur. Les sons sont synthétisés : pas encore de vrais bruitages ni de sons sur les builds natifs. Les végétaux et lanternes sur les bords sont décoratifs. Le build web n'est pas une application iOS native ; les performances Safari/iPhone nécessitent des essais sur appareil réel.

Pour préparer iOS sur un Mac : `flutter create --platforms=ios .`, configurer la signature Xcode puis tester sur iPhone. Une migration Unity/Godot nécessite une réécriture ; règles et direction artistique restent réutilisables.
