# Lanterne — Les jardins du crépuscule

Prototype de roguelite **Flutter + Flame** en **vue isométrique 2,5D** façon Hades : la simulation reste en 2D, le sol est projeté à 45°, les murs sont extrudés et les personnages dessinés debout, triés par profondeur. Tout est dessiné avec Canvas, aucun asset externe requis. Le jeu se joue en paysage ; sur téléphone, tourner l'appareil.

## Jouer

Version web : https://Tachfine37.github.io/lanterne-game-test-/

- Mobile (en paysage) : maintenir et glisser le doigt dans le jardin ; relâcher pour tirer ; bouton ⚡ pour esquiver. Les directions suivent l'écran, pas les axes de la salle.
- Ordinateur : flèches, WASD ou ZQSD ; Espace ou Maj pour esquiver ; P / Échap pour la pause ; M pour couper le son.
- Structure à la Hades : 12 salles sur 2 biomes (Jardin des murmures, Bassin de lune), chacun terminé par un gardien.
- Chaque salle vidée laisse sa récompense sur un piédestal ; la prendre ouvre 2 ou 3 portes qui montrent chacune ce qui attend derrière : don d'esprit, lucioles, cœur de rosée (+PV max), braises (anneau bleu : conservées), échoppe ou source de soin. Une porte marquée d'un crâne mène à une salle d'épreuve : plus d'ombres, récompense doublée.
- Les ombres vaincues lâchent des lucioles, la monnaie de la partie ; une fois la salle sûre, elles viennent à toi.
- Maître Crapaud tient l'échoppe : un don, des soins, des PV max, des relances ou des braises contre des lucioles.
- Esquive : une ruée courte et invincible, avec un temps de recharge.
- 6 types d'ennemis, 2 gardiens (la Tortue-sanctuaire et la Chouette de minuit), 16 dons cumulables avec synergies.
- Chaque partie rapporte des braises à dépenser à l'autel des braises en améliorations permanentes.
- Dégâts flottants, critiques, recul, tremblement d'écran ; sons et musique synthétisés en direct (Web Audio).
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
- `lib/garden_game.dart` : boucle Flame, projection isométrique (`iso`, `fromScreen`) et dessins procéduraux : sol projeté, murs extrudés, sprites debout.
- `lib/main.dart` : interface Flutter, joystick, clavier, pause, autel des braises et stockage local.
- `lib/audio_web.dart` : synthèse Web Audio des effets et de la musique ; `lib/audio_stub.dart` la remplace hors navigateur (tests, futures versions natives).
- `test/model_test.dart` : règles de combat, nouveaux ennemis, dons, autel, et un bot qui joue des parties complètes pour détecter les régressions d'équilibrage.

## Limites du prototype

Deux biomes sur la même arène (les salles ne changent que par leur contenu), pas encore de hub ni de dialogues, pas de multijoueur. Les sons sont synthétisés : pas encore de vrais bruitages ni de sons sur les builds natifs. Les végétaux et lanternes sur les bords sont décoratifs. Le build web n'est pas une application iOS native ; les performances Safari/iPhone nécessitent des essais sur appareil réel.

Pour préparer iOS sur un Mac : `flutter create --platforms=ios .`, configurer la signature Xcode puis tester sur iPhone. Une migration Unity/Godot nécessite une réécriture ; règles et direction artistique restent réutilisables.
