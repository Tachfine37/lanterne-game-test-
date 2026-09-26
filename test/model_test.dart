import 'package:flutter_test/flutter_test.dart';
import 'package:lanterne/model.dart';

void main() {
  RunModel fresh() => RunModel(seed: 7)
    ..start()
    ..grace = 0;
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
  test('Boss defeat wins and restart resets upgrades and projectiles', () {
    final r = fresh();
    r.wave = 5;
    r.enemies.clear();
    r.spawnWave();
    r.grace = 0;
    expect(r.enemies.single.type, 3);
    r.enemies.single.hp = 0;
    r.update(.02);
    expect(r.phase, Phase.won);
    expect(r.score, 525);
    r.multishot = 3;
    r.start();
    expect(r.phase, Phase.playing);
    expect(r.multishot, 1);
    expect(r.kills, 0);
    expect(r.bolts, isEmpty);
  });
  test('Piercing bolts cannot repeatedly damage the same enemy', () {
    final r = fresh();
    r.enemies.clear();
    final e = Enemy(const Offset(100, 100), 1, 100, 20);
    r.enemies.add(e);
    r.cooldown = 100;
    r.bolts.add(Bolt(e.p, Offset.zero, false, 10, pierce: 2));
    r.update(.01);
    r.update(.01);
    expect(e.hp, 90);
  });
  test('Complete five-wave progression reaches victory', () {
    final r = fresh();
    for (var wave = 1; wave <= 5; wave++) {
      expect(r.wave, wave);
      r.grace = 0;
      for (final e in r.enemies) {
        e.hp = 0;
      }
      r.update(.01);
      if (wave < 5) {
        expect(r.phase, Phase.upgrade);
        r.choose(r.choices.first);
      }
    }
    expect(r.phase, Phase.won);
    expect(r.kills, 33);
  });
}
