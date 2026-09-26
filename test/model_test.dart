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
  void grant(RunModel r, String id) => r
    ..phase = Phase.upgrade
    ..choices = [gift(id)]
    ..choose(gift(id));
  void clearRoom(RunModel r) {
    r.grace = 0;
    while (r.phase == Phase.playing && !r.cleared) {
      for (final e in r.enemies) {
        e.hp = 0;
      }
      r.update(.01);
    }
  }

  void takeReward(RunModel r) {
    final reward = r.pickup;
    if (reward != null) {
      r.player = reward.p;
      r.update(.01);
    }
    if (r.phase == Phase.upgrade) r.choose(r.choices.first);
  }

  void walkThrough(RunModel r, Door door) {
    r.player = Offset(door.p.dx, 82);
    r.update(.01);
    while (r.pendingDoor != null) {
      r.update(.02);
    }
    r.grace = 0;
  }

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
  test('A cleared room leaves its reward, taking it opens the doors', () {
    final r = fresh();
    expect(r.room, Reward.gift);
    clearRoom(r);
    expect(r.phase, Phase.playing);
    expect(r.pickup?.reward, Reward.gift);
    expect(r.doors, isEmpty);
    r.player = r.pickup!.p;
    r.update(.01);
    expect(r.phase, Phase.upgrade);
    expect(r.choices.length, 3);
    r.choose(r.choices.first);
    expect(r.acquired.length, 1);
    expect(r.doorsOpen, isTrue);
    expect(r.doors.length, inInclusiveRange(2, 3));
    expect(r.doors.map((d) => d.reward), contains(Reward.gift));
  });
  test('Walking through a door loads a room holding its reward', () {
    final r = fresh();
    clearRoom(r);
    takeReward(r);
    final door = r.doors.last;
    walkThrough(r, door);
    expect(r.depth, 2);
    expect(r.room, door.reward);
    expect(r.fade, greaterThan(0));
    expect(r.player.dy, greaterThan(500));
  });
  test('Fallen shadows drop fireflies that drift to the player', () {
    final r = fresh();
    final count = r.enemies.length;
    clearRoom(r);
    expect(r.loot.length, count);
    for (var i = 0; i < 200; i++) {
      r.update(.02);
    }
    expect(r.loot, isEmpty);
    expect(r.coins, count);
  });
  test('The guardian door is the only exit before a boss', () {
    final r = fresh()..depth = roomsPerBiome - 1;
    final doors = r.rollDoors();
    expect(doors.single.reward, Reward.boss);
    r.depth = 2;
    for (var i = 0; i < 50; i++) {
      final rewards = r.rollDoors().map((d) => d.reward).toList();
      expect(rewards, contains(Reward.gift));
      expect(rewards.where((x) => x == Reward.shop).length, lessThan(2));
      expect(rewards, isNot(contains(Reward.boss)));
    }
  });
  test('Maître Crapaud sells wares for fireflies', () {
    final r = fresh();
    r.loadRoom(const Door(Offset.zero, Reward.shop));
    r.grace = 0;
    expect(r.doorsOpen, isTrue);
    expect(r.wares.first.id, 'gift');
    r.coins = 100;
    r.player = RunModel.merchant + const Offset(0, 40);
    r.update(.01);
    expect(r.phase, Phase.shop);
    final price = r.wares.first.price;
    r.buy(r.wares.first);
    expect(r.coins, 100 - price);
    expect(r.phase, Phase.upgrade);
    r.choose(r.choices.first);
    expect(r.phase, Phase.playing);
    r.update(.01);
    expect(r.phase, Phase.playing, reason: 'shop stays closed until you leave');
    r.phase = Phase.shop;
    r.buy(r.wares.first);
    expect(r.coins, 100 - price, reason: 'sold wares cannot be bought twice');
    r.coins = 0;
    r.buy(r.wares[1]);
    expect(r.wares[1].sold, isFalse);
    r.leaveShop();
    expect(r.phase, Phase.playing);
  });
  test('The spring heals once', () {
    final r = fresh()..hp = 20;
    r.loadRoom(const Door(Offset.zero, Reward.fountain));
    r.grace = 0;
    r.player = RunModel.fountain;
    r.update(.01);
    expect(r.hp, closeTo(55, .01));
    r.update(.01);
    expect(r.hp, closeTo(55, .01));
  });
  test('Elite rooms are denser and double their reward', () {
    final plain = fresh();
    final elite = fresh();
    elite.depth = plain.depth = 3;
    plain.loadRoom(const Door(Offset.zero, Reward.coins));
    elite.loadRoom(const Door(Offset.zero, Reward.coins, elite: true));
    expect(elite.enemies.length, greaterThan(plain.enemies.length));
    clearRoom(elite);
    final before = elite.coins;
    elite.player = elite.pickup!.p;
    elite.update(.01);
    expect(elite.coins - before, greaterThanOrEqualTo(60));
  });
  test('Dash is fast, invulnerable and on cooldown', () {
    final a = fresh()..enemies.clear();
    final b = fresh()..enemies.clear();
    a.movement = b.movement = const Offset(1, 0);
    a.player = b.player = const Offset(100, 400);
    b.dash();
    expect(b.events, contains(Sfx.dash));
    for (var i = 0; i < 5; i++) {
      a.update(.02);
      b.update(.02);
    }
    expect(b.player.dx - 100, greaterThan((a.player.dx - 100) * 2.5));
    final c = fresh()..dash();
    c.hurt(30);
    expect(c.hp, c.maxHp);
    c.dashTime = 0;
    c.dash();
    expect(c.dashing, isFalse);
  });
  test('Reroll consumes a charge and keeps the number of choices', () {
    final r = fresh();
    clearRoom(r);
    r.player = r.pickup!.p;
    r.update(.01);
    expect(r.rerolls, 1);
    r.reroll();
    expect(r.rerolls, 0);
    expect(r.choices.length, 3);
    final choices = r.choices;
    r.reroll();
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
  test('First guardian heals and offers a four-way gift', () {
    final r = fresh()..depth = roomsPerBiome - 1;
    r.loadRoom(const Door(Offset.zero, Reward.boss));
    expect(r.enemies.single.kind, Kind.tortoise);
    r.hp = 20;
    clearRoom(r);
    expect(r.hp, 60);
    expect(r.pickup!.elite, isTrue);
    r.player = r.pickup!.p;
    r.update(.01);
    expect(r.choices.length, 4);
    r.choose(r.choices.first);
    walkThrough(r, r.doors.first);
    expect(r.biome, 1);
  });
  test('Midnight owl defeat wins and restart resets the run', () {
    final r = fresh()..depth = totalDepth - 1;
    r.loadRoom(const Door(Offset.zero, Reward.boss));
    expect(r.enemies.single.kind, Kind.owl);
    r.kills = 0;
    clearRoom(r);
    expect(r.phase, Phase.won);
    expect(r.score, 25 + (totalDepth - 1) * 100 + 1000);
    r.multishot = 3;
    r.coins = 50;
    r.start();
    expect(r.phase, Phase.playing);
    expect(r.depth, 1);
    expect(r.multishot, 1);
    expect(r.coins, 0);
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
    final r = fresh();
    grant(r, 'veil');
    r.grace = 0;
    r.hurt(30);
    expect(r.hp, r.maxHp);
    expect(r.veilReady, isFalse);
    r.invincible = 0;
    r.hurt(30);
    expect(r.hp, r.maxHp - 30);
    r.veilTimer = .01;
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
  test('Choosing the first door every time reaches victory', () {
    final r = fresh();
    for (var depth = 1; depth <= totalDepth; depth++) {
      expect(r.depth, depth);
      clearRoom(r);
      if (r.phase == Phase.won) break;
      takeReward(r);
      if (r.room == Reward.fountain) {
        r.player = RunModel.fountain;
        r.update(.01);
      }
      expect(r.doorsOpen, isTrue);
      walkThrough(r, r.doors.first);
    }
    expect(r.phase, Phase.won);
    expect(r.depth, totalDepth);
  });

  // A crude bot: fight standing still, sidestep threats, then collect the
  // reward and take a door. It guards against balance regressions only.
  (int, int) botRun(int seed) {
    final r = RunModel(seed: seed)..start();
    var t = 0.0;
    while (!r.finished && t < 1500) {
      if (r.phase == Phase.upgrade) {
        r.choose(r.choices.first);
        continue;
      }
      if (r.phase == Phase.shop) {
        for (final ware in r.wares) {
          r.buy(ware);
          if (r.phase == Phase.upgrade) r.choose(r.choices.first);
          r.phase = Phase.shop;
        }
        r.leaveShop();
        continue;
      }
      Offset? goal;
      if (r.cleared) {
        if (r.pickup != null) {
          goal = r.pickup!.p;
        } else if (r.room == Reward.fountain && !r.fountainUsed) {
          goal = RunModel.fountain;
        } else if (r.doors.isNotEmpty) {
          final door = r.doors.firstWhere(
            (d) => d.reward == Reward.gift,
            orElse: () => r.doors.first,
          );
          goal = Offset(door.p.dx, 70);
        }
      }
      final threats = [
        for (final e in r.enemies)
          if ((e.p - r.player).distance < 90) e.p,
        for (final b in r.bolts)
          if (b.hostile && (b.p - r.player).distance < 60) b.p,
        for (final s in r.shells)
          if ((s.to - r.player).distance < 45) s.to,
      ];
      if (goal != null) {
        r.movement = unit(goal - r.player);
      } else if (threats.isEmpty) {
        r.movement = Offset.zero;
      } else {
        var away = Offset.zero;
        for (final p in threats) {
          away += unit(r.player - p);
        }
        r.movement = unit(away + unit(const Offset(220, 340) - r.player) * .6);
      }
      r.update(1 / 30);
      t += 1 / 30;
    }
    return (r.depth, r.phase == Phase.won ? 1 : 0);
  }

  test('A simple bot survives the opening rooms', () {
    final results = [for (var seed = 0; seed < 8; seed++) botRun(seed)];
    // ignore: avoid_print
    print('Bot (depth, won): $results');
    expect(results.every((r) => r.$1 >= 3), isTrue);
  });
}
