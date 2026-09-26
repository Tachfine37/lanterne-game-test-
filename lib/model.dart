import 'dart:math';
import 'dart:ui';

enum Phase { title, playing, upgrade, paused, won, lost }

class Gift {
  final String id, name, description, symbol;
  const Gift(this.id, this.name, this.description, this.symbol);
}

const gifts = [
  Gift(
    'double',
    'Flamme jumelle',
    'Un projectile supplémentaire à chaque tir.',
    '✦',
  ),
  Gift(
    'power',
    'Cœur de braise',
    'Tes flammes infligent 40 % de dégâts en plus.',
    '◆',
  ),
  Gift('speed', 'Souffle léger', 'Tu te déplaces 18 % plus vite.', '≋'),
  Gift('rate', 'Feu follet', 'Ta lanterne tire 25 % plus rapidement.', 'ϟ'),
  Gift(
    'heal',
    'Rosée de lune',
    'Récupère 35 points de vie et gagne 15 PV maximum.',
    '♡',
  ),
  Gift(
    'orbit',
    'Lune gardienne',
    'Une flamme tourne autour de toi et blesse les ennemis.',
    '◉',
  ),
  Gift(
    'bounce',
    'Écho de lumière',
    'Tes projectiles rebondissent une fois sur les murs.',
    '◇',
  ),
  Gift(
    'pierce',
    'Éclat perçant',
    'Tes projectiles traversent un ennemi supplémentaire.',
    '↑',
  ),
];

Offset unit(Offset v) => v.distance < .001 ? Offset.zero : v / v.distance;

class Enemy {
  Offset p;
  final int type;
  double hp, maxHp, timer, flash = 0, tell = 0;
  Offset aim = Offset.zero;
  bool charging = false;
  Enemy(this.p, this.type, this.hp, this.timer) : maxHp = hp;
  double get radius => type == 3 ? 31 : 15;
}

class Bolt {
  Offset p, v;
  final bool hostile;
  final double damage;
  int bounces, pierce;
  final Set<Enemy> hit = {};
  double life = 4;
  Bolt(
    this.p,
    this.v,
    this.hostile,
    this.damage, {
    this.bounces = 0,
    this.pierce = 0,
  });
}

class Spark {
  Offset p, v;
  double life = 1;
  final bool green;
  Spark(this.p, this.v, this.green);
}

/// Simulation independent of Flame: world units and seconds, never screen pixels.
class RunModel {
  final Random random;
  RunModel({int? seed}) : random = Random(seed);
  Phase phase = Phase.title;
  Offset player = const Offset(220, 370), movement = Offset.zero;
  List<Enemy> enemies = [];
  List<Bolt> bolts = [];
  List<Spark> sparks = [];
  List<Gift> choices = [];
  List<Gift> acquired = [];
  int wave = 1, kills = 0, multishot = 1, bounce = 0, pierce = 0, orbits = 0;
  double hp = 100, maxHp = 100, speed = 145, damage = 15, interval = .62;
  double cooldown = 0,
      invincible = 0,
      elapsed = 0,
      waveTime = 0,
      orbitClock = 0;
  double grace = 1.7, orbitCooldown = 0;
  bool get moving => movement.distance > .12;
  bool get finished => phase == Phase.won || phase == Phase.lost;
  int get score => kills * 25 + (phase == Phase.won ? 500 : 0);

  void start() {
    player = const Offset(220, 410);
    movement = Offset.zero;
    enemies.clear();
    bolts.clear();
    sparks.clear();
    acquired.clear();
    hp = maxHp = 100;
    speed = 145;
    damage = 15;
    interval = .62;
    wave = 1;
    kills = 0;
    multishot = 1;
    bounce = pierce = orbits = 0;
    elapsed = cooldown = invincible = orbitClock = orbitCooldown = 0;
    phase = Phase.playing;
    spawnWave();
  }

  void spawnWave() {
    bolts.clear();
    movement = Offset.zero;
    waveTime = 0;
    grace = 1.5;
    player = const Offset(220, 440);
    if (wave == 5) {
      enemies.add(Enemy(const Offset(220, 155), 3, 650, 2));
      return;
    }
    for (var i = 0; i < 3 + wave * 2; i++) {
      final type = wave == 1 ? i % 2 : i % 3;
      final x = 65.0 + (i % 4) * 100 + random.nextDouble() * 12;
      final y = 120.0 + (i ~/ 4) * 78;
      enemies.add(
        Enemy(
          Offset(x, y),
          type,
          (type == 2 ? 37 : 27) + wave * 5,
          1 + random.nextDouble() * 2,
        ),
      );
    }
  }

  void pause() {
    if (phase == Phase.playing) {
      phase = Phase.paused;
      movement = Offset.zero;
    }
  }

  void resume() {
    if (phase == Phase.paused) phase = Phase.playing;
  }

  void choose(Gift gift) {
    if (phase != Phase.upgrade || !choices.contains(gift)) return;
    acquired.add(gift);
    switch (gift.id) {
      case 'double':
        multishot++;
        break;
      case 'power':
        damage *= 1.4;
        break;
      case 'speed':
        speed *= 1.18;
        break;
      case 'rate':
        interval *= .75;
        break;
      case 'heal':
        maxHp += 15;
        hp = min(maxHp, hp + 35);
        break;
      case 'orbit':
        orbits++;
        break;
      case 'bounce':
        bounce++;
        break;
      case 'pierce':
        pierce++;
        break;
    }
    wave++;
    phase = Phase.playing;
    spawnWave();
  }

  void burst(Offset p, {bool green = false}) {
    for (var i = 0; i < 9; i++) {
      final a = random.nextDouble() * pi * 2;
      sparks.add(
        Spark(
          p,
          Offset(cos(a), sin(a)) * (25 + random.nextDouble() * 65),
          green,
        ),
      );
    }
  }

  void hurt(double amount) {
    if (invincible > 0 || phase != Phase.playing) return;
    hp = max(0, hp - amount);
    invincible = 1.0;
    burst(player);
    if (hp == 0) {
      phase = Phase.lost;
      movement = Offset.zero;
    }
  }

  Offset bounded(Offset p, [double margin = 32]) =>
      Offset(p.dx.clamp(margin, 440 - margin), p.dy.clamp(80, 592));

  void update(double dt) {
    if (phase != Phase.playing) return;
    dt = min(dt, .04);
    elapsed += dt;
    waveTime += dt;
    orbitClock += dt;
    invincible = max(0, invincible - dt);
    cooldown -= dt;
    orbitCooldown -= dt;
    for (final s in sparks) {
      s.p += s.v * dt;
      s.life -= dt * 2;
    }
    sparks.removeWhere((s) => s.life <= 0);
    if (grace > 0) {
      grace -= dt;
      return;
    }
    if (moving) player = bounded(player + unit(movement) * speed * dt);
    if (!moving && cooldown <= 0 && enemies.isNotEmpty) {
      final target = enemies.reduce(
        (a, b) =>
            (a.p - player).distanceSquared < (b.p - player).distanceSquared
            ? a
            : b,
      );
      final a = atan2(target.p.dy - player.dy, target.p.dx - player.dx);
      for (var i = 0; i < multishot; i++) {
        final angle = a + (i - (multishot - 1) / 2) * .12;
        bolts.add(
          Bolt(
            player,
            Offset(cos(angle), sin(angle)) * 350,
            false,
            damage,
            bounces: bounce,
            pierce: pierce,
          ),
        );
      }
      cooldown = interval;
    }
    for (final e in enemies) {
      e.flash = max(0, e.flash - dt);
      e.timer -= dt;
      final direction = unit(player - e.p);
      if (e.type == 0) {
        e.p += direction * (31 + wave * 3) * dt;
      } else if (e.type == 1) {
        final distance = (player - e.p).distance;
        if (distance > 235) e.p += direction * 28 * dt;
        if (distance < 140) e.p -= direction * 24 * dt;
        if (e.timer < .65 && e.tell == 0) {
          e.tell = .65;
          e.aim = direction;
        }
        if (e.timer <= 0) {
          bolts.add(Bolt(e.p, e.aim * 130, true, 12));
          e.timer = 2.8;
          e.tell = 0;
        }
      } else if (e.type == 2) {
        if (e.charging) {
          e.p += e.aim * 245 * dt;
          if (e.timer <= 0) {
            e.charging = false;
            e.timer = 2.3;
          }
        } else if (e.timer < .8) {
          if (e.tell == 0) {
            e.tell = .8;
            e.aim = direction;
          }
          if (e.timer <= 0) {
            e.charging = true;
            e.timer = .7;
            e.tell = 0;
          }
        } else {
          e.p += direction * 22 * dt;
        }
      } else {
        e.p += direction * 17 * dt;
        if (e.timer < .9) e.tell = .9;
        if (e.timer <= 0) {
          for (var i = 0; i < 12; i++) {
            final a = i * pi / 6 + orbitClock * .3;
            bolts.add(Bolt(e.p, Offset(cos(a), sin(a)) * 110, true, 16));
          }
          e.timer = e.hp < e.maxHp / 2 ? 1.7 : 2.5;
          e.tell = 0;
        }
      }
      e.p = bounded(e.p, e.radius + 12);
      if ((e.p - player).distance < e.radius + 12) hurt(e.type == 3 ? 20 : 12);
      if (orbits > 0 && orbitCooldown <= 0) {
        for (var i = 0; i < orbits; i++) {
          final a = orbitClock * 3 + i * pi * 2 / orbits;
          final p = player + Offset(cos(a), sin(a)) * 52;
          if ((p - e.p).distance < e.radius + 10) {
            e.hp -= damage;
            e.flash = .15;
            orbitCooldown = .25;
          }
        }
      }
    }
    for (final b in bolts) {
      b.p += b.v * dt;
      b.life -= dt;
      if (b.p.dx < 25 || b.p.dx > 415 || b.p.dy < 72 || b.p.dy > 607) {
        if (b.bounces > 0) {
          b.v = Offset(
            b.p.dx < 25 || b.p.dx > 415 ? -b.v.dx : b.v.dx,
            b.p.dy < 72 || b.p.dy > 607 ? -b.v.dy : b.v.dy,
          );
          b.p = Offset(b.p.dx.clamp(25, 415), b.p.dy.clamp(72, 607));
          b.bounces--;
        } else {
          b.life = 0;
        }
      }
      if (b.life <= 0) continue;
      if (b.hostile) {
        if ((b.p - player).distance < 16) {
          hurt(b.damage);
          b.life = 0;
        }
      } else {
        for (final e in enemies) {
          if (e.hp > 0 &&
              !b.hit.contains(e) &&
              (b.p - e.p).distance < e.radius + 5) {
            e.hp -= b.damage;
            e.flash = .12;
            b.hit.add(e);
            burst(b.p);
            if (b.pierce > 0) {
              b.pierce--;
            } else {
              b.life = 0;
              break;
            }
          }
        }
      }
    }
    for (final e in enemies.where((e) => e.hp <= 0)) {
      kills++;
      burst(e.p, green: true);
    }
    enemies.removeWhere((e) => e.hp <= 0);
    bolts.removeWhere((b) => b.life <= 0);
    if (phase != Phase.playing) return;
    if (enemies.isEmpty) {
      movement = Offset.zero;
      bolts.clear();
      if (wave == 5) {
        phase = Phase.won;
      } else {
        phase = Phase.upgrade;
        final pool = List<Gift>.of(gifts)..shuffle(random);
        choices = pool.take(3).toList();
      }
    }
  }
}
