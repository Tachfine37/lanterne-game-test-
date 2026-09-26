import 'package:flutter_test/flutter_test.dart';
import 'package:lanterne/model.dart';

void main() {
  RunModel fresh() => RunModel(seed: 7)
    ..start()
    ..grace = 0;
  Gift gift(String id) => gifts.firstWhere((g) => g.id == id);
  RunModel alone(Enemy e) => fresh()
    ..enemies.clear()
    ..enemies.add(e)
    ..cooldown = 100;

  test('Diagonal movement is normalized and remains inside the arena', () {
    final a = fresh(), b = fresh();
    a.movement = const Offset(1, 0);
    b.movement = const Offset(1, 1);
    final initial = a.player;
    a.update(.02);
    b.update(.02);
    expect(
      (a.player - initial).distance,
      closeTo((b.player - initial).distance, .001),
    );
    for (var i = 0; i < 500; i++) {
      b.update(.02);
    }
    expect(b.player.dx, lessThanOrEqualTo(408));
    expect(b.player.dy, lessThanOrEqualTo(592));
  });
  test('Movement prevents auto fire, releasing movement fires', () {
    final r = fresh()..movement = const Offset(1, 0);
    r.update(.02);
    expect(r.bolts.where((b) => !b.hostile), isEmpty);
    r.movement = Offset.zero;
    r.update(.02);
    expect(r.bolts.where((b) => !b.hostile), isNotEmpty);
    expect(r.events, contains(Sfx.shoot));
  });
  test(
    'Invulnerability prevents stacked contact damage and death is terminal',
    () {
      final r = fresh();
      r.hurt(12);
      r.hurt(12);
      expect(r.hp, 88);
      r.invincible = 0;
      r.hurt(200);
      expect(r.phase, Phase.lost);
      expect(r.hp, 0);
      final elapsed = r.elapsed;
      r.update(.02);
      expect(r.elapsed, elapsed);
    },
  );
  test('Wave clear grants three choices and chosen gift persists', () {
    final r = fresh();
    r.enemies.clear();
    r.update(.02);
    expect(r.phase, Phase.upgrade);
    expect(r.choices.length, 3);
    final gift = r.choices.first;
    r.choose(gift);
    expect(r.phase, Phase.playing);
    expect(r.wave, 2);
    expect(r.acquired, [gift]);
    expect(r.enemies, isNotEmpty);
  });
  test('Reroll consumes a charge and cannot go negative', () {
    final r = fresh();
    r.enemies.clear();
    r.update(.02);
    expect(r.rerolls, 1);
    r.reroll();
    expect(r.rerolls, 0);
    expect(r.choices.length, 3);
    final choices = r.choices;
    r.reroll();
    expect(r.rerolls, 0);
    expect(r.choices, same(choices));
  });
  test('Paused simulation is frozen and resume clears no progression', () {
    final r = fresh()..movement = const Offset(1, 0);
    r.pause();
    final p = r.player;
    r.update(.04);
    expect(r.player, p);
    expect(r.elapsed, 0);
    expect(r.movement, Offset.zero);
    r.resume();
    r.update(.02);
    expect(r.elapsed, greaterThan(0));
  });
  test('First guardian opens the second biome instead of ending the run', () {
    final r = fresh();
    r.wave = 5;
    r.enemies.clear();
    r.spawnWave();
    r.grace = 0;
    expect(r.enemies.single.kind, Kind.tortoise);
    r.hp = 20;
    r.enemies.single.hp = 0;
    r.update(.02);
    expect(r.phase, Phase.upgrade);
    expect(r.hp, 60);
    r.choose(r.choices.first);
    expect(r.biome, 1);
  });
  test('Midnight owl defeat wins and restart resets upgrades', () {
    final r = fresh();
    r.wave = totalWaves;
    r.enemies.clear();
    r.spawnWave();
    r.grace = 0;
    expect(r.enemies.single.kind, Kind.owl);
    r.enemies.single.hp = 0;
    r.update(.02);
    expect(r.phase, Phase.won);
    expect(r.score, 25 + 900 + 1000);
    r.multishot = 3;
    r.start();
    expect(r.phase, Phase.playing);
    expect(r.multishot, 1);
    expect(r.kills, 0);
    expect(r.bolts, isEmpty);
  });
  test('Piercing bolts cannot repeatedly damage the same enemy', () {
    final e = Enemy(const Offset(100, 100), Kind.moth, 100, 20);
    final r = alone(e);
    r.bolts.add(Bolt(e.p, Offset.zero, false, 10, pierce: 2));
    r.update(.01);
    r.update(.01);
    expect(e.hp, 90);
  });
  test('Broodcap splits into three spores when it dies', () {
    final r = alone(Enemy(const Offset(220, 200), Kind.broodcap, 1, 20));
    r.enemies.single.hp = 0;
    r.update(.01);
    expect(r.kills, 1);
    expect(r.enemies.length, 3);
    expect(r.enemies.every((e) => e.kind == Kind.spore), isTrue);
    expect(r.phase, Phase.playing);
  });
  test('Toad shells land on a marked spot and hurt the player there', () {
    final toad = Enemy(const Offset(220, 150), Kind.toad, 100, .01);
    final r = alone(toad);
    r.update(.02);
    expect(r.shells.length, 1);
    final target = r.shells.single.to;
    expect((target - r.player).distance, lessThan(1));
    for (var i = 0; i < 60; i++) {
      r.update(.02);
    }
    expect(r.shells, isEmpty);
    expect(r.hp, lessThan(r.maxHp));
  });
  test('Veil absorbs one hit then recharges', () {
    final r = fresh()..enemies.clear();
    r.update(.02);
    r.choices = [gift('veil')];
    r.choose(gift('veil'));
    r.grace = 0;
    r.hurt(30);
    expect(r.hp, r.maxHp);
    expect(r.veilReady, isFalse);
    r.invincible = 0;
    r.hurt(30);
    expect(r.hp, r.maxHp - 30);
    r.enemies.clear();
    r.veilTimer = .01;
    r.phase = Phase.playing;
    r.enemies.add(Enemy(const Offset(60, 100), Kind.moth, 100, 99));
    r.update(.02);
    expect(r.veilReady, isTrue);
  });
  test('Bloom explosions chain through a crowd', () {
    final r = fresh()
      ..enemies.clear()
      ..bloom = 3
      ..cooldown = 100;
    for (var i = 0; i < 4; i++) {
      r.enemies.add(
        Enemy(Offset(100 + i * 40.0, 150), Kind.mushroom, r.damage, 20),
      );
    }
    r.enemies.first.hp = 0;
    r.update(.01);
    expect(r.enemies, isEmpty);
    expect(r.kills, 4);
  });
  test('Chain bolts jump to a second enemy', () {
    final a = Enemy(const Offset(100, 150), Kind.moth, 100, 20);
    final b = Enemy(const Offset(200, 150), Kind.moth, 100, 20);
    final r = alone(a)..enemies.add(b);
    r.bolts.add(Bolt(a.p, const Offset(1, 0), false, 10, chain: 1));
    for (var i = 0; i < 30; i++) {
      r.update(.01);
    }
    expect(a.hp, 90);
    expect(b.hp, 90);
  });
  test('Altar perks shape the next run', () {
    final r = RunModel(seed: 1)
      ..perkLevels = {'vitality': 2, 'ember': 5, 'fortune': 1}
      ..start();
    expect(r.maxHp, 124);
    expect(r.damage, closeTo(21, .001));
    expect(r.rerolls, 2);
    expect(Perk('x', 'x', 'x', 3).cost(2), 90);
  });
  test('Complete ten-wave progression reaches victory', () {
    final r = fresh();
    for (var wave = 1; wave <= totalWaves; wave++) {
      expect(r.wave, wave);
      r.grace = 0;
      while (r.phase == Phase.playing) {
        for (final e in r.enemies) {
          e.hp = 0;
        }
        r.update(.01);
      }
      if (wave < totalWaves) {
        expect(r.phase, Phase.upgrade);
        r.choose(r.choices.first);
      }
    }
    expect(r.phase, Phase.won);
    expect(r.kills, greaterThan(60));
  });

  // A crude bot: stand still to fire, sidestep when threatened. It only
  // guards against balance regressions that make early waves unwinnable.
  int botRun(int seed) {
    final r = RunModel(seed: seed)..start();
    var t = 0.0;
    while (!r.finished && t < 900) {
      if (r.phase == Phase.upgrade) {
        r.choose(r.choices.first);
        continue;
      }
      final threats = [
        for (final e in r.enemies)
          if ((e.p - r.player).distance < 90) e.p,
        for (final b in r.bolts)
          if (b.hostile && (b.p - r.player).distance < 60) b.p,
        for (final s in r.shells)
          if ((s.to - r.player).distance < 45) s.to,
      ];
      if (threats.isEmpty) {
        r.movement = Offset.zero;
      } else {
        var away = Offset.zero;
        for (final p in threats) {
          away += unit(r.player - p);
        }
        final center = unit(const Offset(220, 340) - r.player) * .6;
        r.movement = unit(away + center);
      }
      r.update(1 / 30);
      t += 1 / 30;
    }
    return r.wave;
  }

  test('A simple bot survives the opening waves', () {
    final reached = [for (var seed = 0; seed < 8; seed++) botRun(seed)];
    // ignore: avoid_print
    print('Bot reached waves: $reached');
    expect(reached.every((w) => w >= 3), isTrue);
  });
}
