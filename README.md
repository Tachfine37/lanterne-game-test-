# Lanterne — Les jardins du crépuscule

Prototype de roguelite **Flutter + Flame**. Gameplay 2D, représentation en volume dessinée avec Canvas : ombres, sol surélevé et tri des personnages par profondeur. Aucun asset externe requis.

## Jouer

Version web : https://Tachfine37.github.io/lanterne-game-test-/

- Mobile : maintenir et glisser le doigt dans le jardin ; relâcher pour tirer.
- Ordinateur : flèches, WASD ou ZQSD ; P / Échap pour mettre en pause.
- 5 vagues, 3 types d'ennemis, 8 dons possibles, un boss à deux cadences d'attaque.
- Choisir un don après chaque vague. Les pouvoirs se cumulent.
- Meilleur score enregistré localement si le navigateur autorise le stockage.

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

- `lib/model.dart` : simulation, vagues, dégâts, pouvoirs et progression ; aucune dépendance à Flame, mais `dart:ui` pour les vecteurs.
- `lib/garden_game.dart` : boucle Flame et dessins procéduraux.
- `lib/main.dart` : interface Flutter, joystick, clavier, pause et stockage local.
- `test/model_test.dart` : règles de combat et progression.

## Limites du prototype

Une arène, pas de son, pas de multijoueur ni de boutique. Les végétaux et lanternes sur les bords sont décoratifs. Le build web n'est pas une application iOS native ; les performances Safari/iPhone nécessitent des essais sur appareil réel.

Pour préparer iOS sur un Mac : `flutter create --platforms=ios .`, configurer la signature Xcode puis tester sur iPhone. Une migration Unity/Godot nécessite une réécriture ; règles et direction artistique restent réutilisables.
