import 'dart:math';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio.dart';
import 'garden_game.dart';
import 'model.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LanternApp());
}

const ink = Color(0xFF0D2027);
const muted = Color(0xFF92ABA7);

class LanternApp extends StatelessWidget {
  const LanternApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Lanterne — Les jardins du crépuscule',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: ink,
      colorScheme: const ColorScheme.dark(
        primary: gold,
        secondary: mint,
        surface: Color(0xFF193238),
      ),
      fontFamily: 'Arial',
      useMaterial3: true,
    ),
    home: const GardenScreen(),
  );
}

class GardenScreen extends StatefulWidget {
  const GardenScreen({super.key});
  @override
  State<GardenScreen> createState() => _GardenScreenState();
}

class _GardenScreenState extends State<GardenScreen>
    with WidgetsBindingObserver {
  final run = RunModel();
  final sound = Sound();
  late final GardenGame game;
  final focus = FocusNode();
  final Set<LogicalKeyboardKey> keys = {};
  int? pointer;
  int best = 0, embers = 0;
  bool recorded = false, altar = false;
  SharedPreferences? prefs;

  @override
  void initState() {
    super.initState();
    game = GardenGame(run, tick, sound);
    WidgetsBinding.instance.addObserver(this);
    loadRecord();
  }

  Future<void> loadRecord() async {
    try {
      prefs = await SharedPreferences.getInstance();
      final p = prefs!;
      if (!mounted) return;
      setState(() {
        best = p.getInt('lanterne.best') ?? 0;
        embers = p.getInt('lanterne.embers') ?? 0;
        sound.muted = p.getBool('lanterne.muted') ?? false;
        for (final perk in perks) {
          run.perkLevels[perk.id] = p.getInt('lanterne.perk.${perk.id}') ?? 0;
        }
      });
    } catch (_) {
      /* Private browsing may disable storage. */
    }
  }

  void tick() {
    if (!mounted) return;
    if (run.finished && !recorded) {
      recorded = true;
      embers += run.embersEarned;
      prefs?.setInt('lanterne.embers', embers);
      if (run.score > best) {
        best = run.score;
        prefs?.setInt('lanterne.best', best);
      }
    }
    sound.music(
      on: run.phase != Phase.title && !run.finished,
      biome: run.biome,
    );
    setState(() {});
  }

  void clearInput() {
    keys.clear();
    pointer = null;
    run.movement = Offset.zero;
    game.stickOrigin = null;
    game.stickEnd = null;
  }

  void start() {
    sound.unlock();
    clearInput();
    recorded = false;
    altar = false;
    setState(run.start);
    focus.requestFocus();
  }

  void toggleMute() {
    setState(() => sound.muted = !sound.muted);
    prefs?.setBool('lanterne.muted', sound.muted);
    if (!sound.muted) sound.unlock();
    focus.requestFocus();
  }

  void buyPerk(Perk perk) {
    final level = run.perk(perk.id);
    if (level >= perk.maxLevel || embers < perk.cost(level)) return;
    setState(() {
      embers -= perk.cost(level);
      run.perkLevels[perk.id] = level + 1;
    });
    prefs?.setInt('lanterne.embers', embers);
    prefs?.setInt('lanterne.perk.${perk.id}', level + 1);
    sound.unlock();
    sound.play(Sfx.gift);
  }

  void togglePause() {
    clearInput();
    setState(() => run.phase == Phase.paused ? run.resume() : run.pause());
    focus.requestFocus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      clearInput();
      setState(run.pause);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    focus.dispose();
    sound.dispose();
    super.dispose();
  }

  KeyEventResult onKey(FocusNode node, KeyEvent event) {
    final movementKeys = {
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.keyW,
      LogicalKeyboardKey.keyA,
      LogicalKeyboardKey.keyS,
      LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.keyZ,
      LogicalKeyboardKey.keyQ,
    };
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.keyP)) {
      if (run.phase == Phase.playing || run.phase == Phase.paused) {
        togglePause();
      }
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyM) {
      toggleMute();
      return KeyEventResult.handled;
    }
    if (!movementKeys.contains(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyUpEvent) {
      keys.remove(event.logicalKey);
    } else {
      keys.add(event.logicalKey);
    }
    if (run.phase == Phase.playing && pointer == null) {
      bool has(List<LogicalKeyboardKey> values) => values.any(keys.contains);
      run.movement = Offset(
        (has([LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.keyD])
                ? 1
                : 0) -
            (has([
                  LogicalKeyboardKey.arrowLeft,
                  LogicalKeyboardKey.keyA,
                  LogicalKeyboardKey.keyQ,
                ])
                ? 1
                : 0),
        (has([LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.keyS]) ? 1 : 0) -
            (has([
                  LogicalKeyboardKey.arrowUp,
                  LogicalKeyboardKey.keyW,
                  LogicalKeyboardKey.keyZ,
                ])
                ? 1
                : 0),
      );
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focus,
    autofocus: true,
    onKeyEvent: onKey,
    onFocusChange: (value) {
      if (!value) {
        clearInput();
        if (run.phase == Phase.playing) setState(run.pause);
      }
    },
    child: Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(.2, -.1),
            radius: 1.1,
            colors: [Color(0xFF203B3D), ink, Color(0xFF091A22)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= 980;
              return Column(
                children: [
                  if (wide) header(),
                  Expanded(
                    child: wide
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(width: 244, child: leftPanel()),
                              const SizedBox(width: 40),
                              Flexible(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                  ),
                                  child: gamePanel(),
                                ),
                              ),
                              const SizedBox(width: 40),
                              SizedBox(width: 222, child: rightPanel()),
                            ],
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: gamePanel(),
                          ),
                  ),
                  if (wide)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 0, 32, 18),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          small(
                            'UN PETIT MONDE. UNE GRANDE LUMIÈRE.',
                            spacing: 2,
                          ),
                          small(
                            'PROTOTYPE 01  ·  FLUTTER + FLAME',
                            spacing: 1.5,
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget small(String s, {Color color = muted, double spacing = 0}) => Text(
    s,
    style: TextStyle(
      fontSize: 10,
      color: color,
      letterSpacing: spacing,
      height: 1.5,
    ),
  );
  Widget heading(String s, {double size = 28, Color color = gold}) => Text(
    s,
    style: TextStyle(
      fontFamily: 'Georgia',
      fontSize: size,
      color: color,
      height: 1.12,
    ),
  );
  Widget header() => Padding(
    padding: const EdgeInsets.fromLTRB(38, 24, 38, 8),
    child: Row(
      children: [
        const Icon(Icons.flare_rounded, color: gold, size: 27),
        const SizedBox(width: 12),
        const Text(
          'L A N T E R N E',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: gold,
          ),
        ),
        const SizedBox(width: 18),
        Container(width: 1, height: 18, color: Colors.white12),
        const SizedBox(width: 18),
        small('LES JARDINS DU CRÉPUSCULE', spacing: 2),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: mint.withValues(alpha: .25)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const Icon(Icons.local_fire_department, size: 12, color: gold),
              const SizedBox(width: 7),
              small('$embers BRAISES', color: gold, spacing: 1),
            ],
          ),
        ),
      ],
    ),
  );

  Widget sidePanel(Widget child) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: box.maxHeight),
        child: Center(child: child),
      ),
    ),
  );

  Widget leftPanel() => sidePanel(
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          small('CHAPITRE I', color: mint, spacing: 3),
          const SizedBox(height: 18),
          heading('Une lueur\ndans la nuit.', size: 39),
          const SizedBox(height: 20),
          const Text(
            'Le jardin s’est endormi.\nSes ombres, elles, sont éveillées.\nRallume ce qui reste de lumière.',
            style: TextStyle(color: muted, fontSize: 14, height: 1.8),
          ),
          const SizedBox(height: 30),
          Container(height: 1, color: Colors.white10),
          const SizedBox(height: 26),
          small('LE CARNET DU GARDIEN', spacing: 2),
          const SizedBox(height: 18),
          tip(
            Icons.open_with_rounded,
            'Déplace-toi',
            'Flèches, ZQSD ou WASD.\nSur mobile, glisse le doigt.',
          ),
          const SizedBox(height: 18),
          tip(
            Icons.auto_awesome,
            'Arrête-toi pour tirer',
            'Ta lanterne vise toute seule.\nTrouve le bon moment.',
          ),
          const SizedBox(height: 18),
          tip(
            Icons.spa_outlined,
            'Compose tes pouvoirs',
            'Choisis un don après chaque\nvague. Fais grandir ta lumière.',
          ),
          const SizedBox(height: 25),
          small('P / ÉCHAP  ·  PAUSE     M  ·  SON', spacing: 1),
        ],
      ),
    ),
  );
  Widget tip(IconData icon, String title, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: mint.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: mint),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 13, color: Color(0xFFE0E9DC)),
            ),
            const SizedBox(height: 5),
            Text(
              text,
              style: const TextStyle(fontSize: 12, height: 1.6, color: muted),
            ),
          ],
        ),
      ),
    ],
  );
  Widget rightPanel() => sidePanel(
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        small('TON EXPÉDITION', spacing: 2),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0x661B343A),
            border: Border.all(color: Colors.white10),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.nightlight_round, color: gold, size: 24),
              const SizedBox(height: 15),
              heading(
                run.biome == 0
                    ? 'Le jardin\ndes murmures'
                    : 'Le bassin\nde lune',
                size: 23,
              ),
              const SizedBox(height: 14),
              small('10 VAGUES  ·  2 GARDIENS', spacing: .8),
              const SizedBox(height: 22),
              Row(
                children: List.generate(
                  totalWaves,
                  (i) => Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.only(right: 3),
                      decoration: BoxDecoration(
                        color: i < run.wave
                            ? (isBossWave(i + 1)
                                  ? const Color(0xFFD59DAB)
                                  : gold)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              small('Vague ${run.wave} sur $totalWaves', color: gold),
              const SizedBox(height: 3),
              small(biomeNames[run.biome], spacing: 1),
            ],
          ),
        ),
        const SizedBox(height: 27),
        small('DONS DE LA LANTERNE', spacing: 1.6),
        const SizedBox(height: 13),
        if (run.acquired.isEmpty)
          const Text(
            'Ta lumière attend\nson premier pouvoir.',
            style: TextStyle(fontSize: 13, color: muted, height: 1.7),
          ),
        for (final gift in run.acquired)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Text(
                  gift.symbol,
                  style: const TextStyle(color: gold, fontSize: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    gift.name,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFD4DED3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 28),
        small('MEILLEURE EXPÉDITION', spacing: 1.5),
        const SizedBox(height: 7),
        heading('$best', size: 30),
        small('éclats de lumière'),
        const SizedBox(height: 22),
        small('BRAISES', spacing: 1.5),
        const SizedBox(height: 7),
        heading('$embers', size: 24),
        small('à offrir à l’autel'),
      ],
    ),
  );

  Widget gamePanel() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF132D33),
              border: Border.all(color: const Color(0xFF3D554E)),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.local_fire_department_rounded,
                  color: gold,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: small(
                                'LE GARDIEN',
                                color: gold,
                                spacing: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          small('${run.hp.ceil()}', color: gold),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (run.hp / run.maxHp).clamp(0, 1),
                          minHeight: 5,
                          color: mint,
                          backgroundColor: Colors.white10,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  children: [
                    small('VAGUE', spacing: 1),
                    Text(
                      '${run.wave} / $totalWaves',
                      style: const TextStyle(fontSize: 15, color: gold),
                    ),
                  ],
                ),
                const SizedBox(width: 5),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 40,
                  ),
                  tooltip: sound.muted ? 'Activer le son' : 'Couper le son',
                  onPressed: toggleMute,
                  icon: Icon(
                    sound.muted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    size: 20,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 40,
                  ),
                  tooltip: run.phase == Phase.paused ? 'Reprendre' : 'Pause',
                  onPressed:
                      run.phase == Phase.playing || run.phase == Phase.paused
                      ? togglePause
                      : null,
                  icon: Icon(
                    run.phase == Phase.paused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: AspectRatio(
              aspectRatio: 440 / 640,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(18),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Listener(
                      onPointerDown: (e) {
                        if (run.phase != Phase.playing || pointer != null) {
                          return;
                        }
                        focus.requestFocus();
                        pointer = e.pointer;
                        game.stickOrigin = e.localPosition;
                        game.stickEnd = e.localPosition;
                      },
                      onPointerMove: (e) {
                        if (e.pointer != pointer ||
                            run.phase != Phase.playing) {
                          return;
                        }
                        game.stickEnd = e.localPosition;
                        final delta = e.localPosition - game.stickOrigin!;
                        run.movement = delta.distance < 7
                            ? Offset.zero
                            : unit(delta);
                      },
                      onPointerUp: (e) {
                        if (e.pointer == pointer) clearInput();
                      },
                      onPointerCancel: (e) {
                        if (e.pointer == pointer) clearInput();
                      },
                      child: GameWidget(game: game),
                    ),
                    if (run.phase == Phase.playing)
                      Positioned(
                        top: 12,
                        left: 16,
                        right: 16,
                        child: IgnorePointer(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: small(
                                    switch (run.boss?.kind) {
                                      Kind.tortoise => 'LE GARDIEN ANCIEN',
                                      Kind.owl => 'LE COMBAT FINAL',
                                      _ => biomeNames[run.biome],
                                    },
                                    color: const Color(0xFFD1DDD1),
                                    spacing: 1.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              small('${run.kills} ✦', color: gold),
                            ],
                          ),
                        ),
                      ),
                    if (run.phase == Phase.playing && run.boss != null)
                      Positioned(
                        top: 36,
                        left: 50,
                        right: 50,
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: max(0, run.boss!.hp / run.boss!.maxHp),
                                minHeight: 6,
                                color: const Color(0xFFD59DAB),
                                backgroundColor: ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            small(
                              run.boss!.kind == Kind.owl
                                  ? 'LA CHOUETTE DE MINUIT'
                                  : 'LA TORTUE-SANCTUAIRE',
                              color: const Color(0xFFE5C1CB),
                              spacing: 1,
                            ),
                          ],
                        ),
                      ),
                    if (run.phase == Phase.playing && run.elapsed < 12)
                      Positioned(
                        bottom: 25,
                        left: 16,
                        right: 16,
                        child: IgnorePointer(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: ink.withValues(alpha: .8),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: const Text(
                                'Glisse pour bouger · Relâche pour tirer',
                                style: TextStyle(fontSize: 11, color: gold),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (run.phase != Phase.playing) overlay(),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: small(
              run.phase == Phase.playing
                  ? '${run.moving ? 'EN MOUVEMENT' : 'TIR AUTOMATIQUE'}   ·   ${run.acquired.length} DONS   ·   ${run.elapsed.floor()} s'
                  : 'UNE EXPÉDITION À LA LUEUR DES LANTERNES',
              spacing: 1.2,
            ),
          ),
        ],
      ),
    ),
  );

  Widget button(
    String text,
    VoidCallback onPressed, {
    IconData icon = Icons.arrow_forward_rounded,
  }) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: gold,
        foregroundColor: ink,
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Icon(icon, size: 18),
        ],
      ),
    ),
  );

  Widget overlay() {
    final title = run.phase == Phase.title;
    return Container(
      color: ink.withValues(alpha: title ? .48 : .86),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(27),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (altar)
                ...altarView()
              else if (title) ...[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: gold.withValues(alpha: .09),
                    border: Border.all(color: gold.withValues(alpha: .25)),
                  ),
                  child: const Icon(Icons.flare_rounded, color: gold, size: 40),
                ),
                const SizedBox(height: 24),
                small('LES JARDINS DU CRÉPUSCULE', color: mint, spacing: 2.1),
                const SizedBox(height: 12),
                heading('Lanterne', size: 58),
                const SizedBox(height: 18),
                const Text(
                  'Même la plus petite lumière\npeut réveiller un monde.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFE0E7D9),
                    height: 1.7,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 34),
                button('Entrer dans le jardin', start),
                const SizedBox(height: 16),
                small(
                  'Glisse pour esquiver. Arrête-toi pour attaquer.',
                  color: const Color(0xFFC5D6CC),
                ),
                const SizedBox(height: 5),
                small('Clavier : flèches / ZQSD / WASD  ·  M : son'),
                const SizedBox(height: 18),
                secondary(
                  'Autel des braises  ·  $embers',
                  () => setState(() => altar = true),
                  icon: Icons.local_fire_department_rounded,
                ),
              ] else if (run.phase == Phase.upgrade) ...[
                const Icon(Icons.auto_awesome, color: gold, size: 32),
                const SizedBox(height: 12),
                small(
                  run.wave == 5
                      ? 'LE GARDIEN EST TOMBÉ'
                      : 'VAGUE ${run.wave} TRAVERSÉE',
                  color: mint,
                  spacing: 2,
                ),
                const SizedBox(height: 10),
                heading(
                  run.wave == 5
                      ? 'Le bassin de lune\ns’ouvre à toi.'
                      : 'Fais grandir\nta lumière.',
                  size: 33,
                ),
                const SizedBox(height: 12),
                Text(
                  run.wave == 5
                      ? 'Tu reprends des forces. Choisis un don.'
                      : 'Choisis un don pour la suite du voyage.',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 22),
                for (final gift in run.choices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OutlinedButton(
                      onPressed: () {
                        clearInput();
                        setState(() => run.choose(gift));
                        focus.requestFocus();
                      },
                      style: OutlinedButton.styleFrom(
                        backgroundColor: const Color(0xFF223D40),
                        foregroundColor: gold,
                        side: const BorderSide(color: Color(0xFF587064)),
                        padding: const EdgeInsets.all(16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 34,
                            child: Text(
                              gift.symbol,
                              style: const TextStyle(fontSize: 26, color: gold),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  gift.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  gift.description,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.add_rounded, size: 17),
                        ],
                      ),
                    ),
                  ),
                if (run.rerolls > 0)
                  secondary(
                    'Relancer les dons  ·  ${run.rerolls}',
                    () => setState(run.reroll),
                    icon: Icons.casino_outlined,
                  ),
              ] else if (run.phase == Phase.paused) ...[
                const Icon(Icons.nightlight_round, size: 40, color: gold),
                const SizedBox(height: 20),
                heading('Un instant\nde calme.', size: 38),
                const SizedBox(height: 16),
                const Text(
                  'Ta lumière t’attend.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 30),
                button(
                  'Reprendre le voyage',
                  togglePause,
                  icon: Icons.play_arrow_rounded,
                ),
              ] else ...[
                Icon(
                  run.phase == Phase.won
                      ? Icons.wb_sunny_outlined
                      : Icons.nightlight_round,
                  size: 48,
                  color: gold,
                ),
                const SizedBox(height: 20),
                small(
                  run.phase == Phase.won
                      ? 'LE JARDIN RESPIRE À NOUVEAU'
                      : 'LA NUIT A GAGNÉ CETTE FOIS',
                  color: mint,
                  spacing: 1.5,
                ),
                const SizedBox(height: 14),
                heading(
                  run.phase == Phase.won
                      ? 'La lumière\nest revenue.'
                      : 'Une braise\nsuffit à renaître.',
                  size: 36,
                ),
                const SizedBox(height: 10),
                small(
                  'Vague ${run.wave} sur $totalWaves  ·  +${run.embersEarned} braises',
                  color: gold,
                  spacing: 1,
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    stat('${run.score}', 'ÉCLATS'),
                    stat('${run.kills}', 'OMBRES'),
                    stat('${run.elapsed.floor()} s', 'VOYAGE'),
                  ],
                ),
                const SizedBox(height: 25),
                button(
                  'Rallumer la lanterne',
                  start,
                  icon: Icons.refresh_rounded,
                ),
                const SizedBox(height: 10),
                secondary(
                  'Autel des braises  ·  $embers',
                  () => setState(() => altar = true),
                  icon: Icons.local_fire_department_rounded,
                ),
                const SizedBox(height: 12),
                small('Meilleure expédition : $best éclats'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget secondary(String text, VoidCallback onPressed, {IconData? icon}) =>
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon ?? Icons.arrow_back_rounded, size: 17),
          label: Text(text, textAlign: TextAlign.center),
          style: OutlinedButton.styleFrom(
            foregroundColor: gold,
            side: BorderSide(color: gold.withValues(alpha: .35)),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );

  /// Permanent upgrades bought with embers earned at the end of each run.
  List<Widget> altarView() => [
    const Icon(Icons.local_fire_department_rounded, color: gold, size: 36),
    const SizedBox(height: 12),
    small('L’AUTEL DES BRAISES', color: mint, spacing: 2),
    const SizedBox(height: 10),
    heading('$embers braises', size: 32),
    const SizedBox(height: 8),
    const Text(
      'Chaque expédition rapporte des braises.\nOffre-les pour renforcer ta lanterne.',
      textAlign: TextAlign.center,
      style: TextStyle(color: muted, fontSize: 12, height: 1.5),
    ),
    const SizedBox(height: 20),
    for (final perk in perks) perkRow(perk),
    const SizedBox(height: 8),
    secondary(
      run.phase == Phase.title ? 'Retour' : 'Retour au bilan',
      () => setState(() => altar = false),
    ),
  ];

  Widget perkRow(Perk perk) {
    final level = run.perk(perk.id);
    final maxed = level >= perk.maxLevel;
    final cost = perk.cost(level);
    final affordable = !maxed && embers >= cost;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF223D40),
        border: Border.all(color: const Color(0xFF587064)),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  perk.name,
                  style: const TextStyle(
                    color: gold,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  perk.description,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var i = 0; i < perk.maxLevel; i++)
                      Container(
                        width: 14,
                        height: 4,
                        margin: const EdgeInsets.only(right: 3),
                        decoration: BoxDecoration(
                          color: i < level ? gold : Colors.white10,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: affordable ? () => buyPerk(perk) : null,
            style: FilledButton.styleFrom(
              backgroundColor: gold,
              foregroundColor: ink,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(maxed ? 'Max' : '$cost ✦'),
          ),
        ],
      ),
    );
  }

  Widget stat(String value, String label) => Column(
    children: [
      heading(value, size: 25),
      const SizedBox(height: 6),
      small(label, spacing: 1),
    ],
  );
}
