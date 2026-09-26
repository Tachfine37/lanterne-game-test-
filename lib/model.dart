import 'dart:math';
import 'dart:ui';

enum Phase { title, playing, upgrade, shop, paused, won, lost }

enum Kind { mushroom, moth, beetle, tortoise, broodcap, spore, toad, owl }

/// Sound cues emitted by the simulation; the view decides how to play them.
enum Sfx {
  shoot,
  hit,
  crit,
  kill,
  hurt,
  shield,
  explode,
  lob,
  bossAttack,
  waveStart,
  gift,
  win,
  lose,
  coin,
  dash,
  door,
  buy,
}

/// Each biome is five rooms chosen through doors, then a guardian.
const roomsPerBiome = 6;
const totalDepth = roomsPerBiome * 2;
bool isBossDepth(int depth) => depth % roomsPerBiome == 0;
int biomeOf(int depth) => depth <= roomsPerBiome ? 0 : 1;
const biomeNames = ['JARDIN DES MURMURES', 'BASSIN DE LUNE'];

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
  Gift(
    'crit',
    'Étincelle fatale',
    '15 % de chances de porter un coup critique (×2,5).',
    '✧',
  ),
  Gift('sap', 'Sève vive', 'Chaque ombre vaincue te rend 2 PV.', '❦'),
  Gift(
    'bloom',
    'Floraison ardente',
    'Les ombres vaincues explosent et blessent leurs voisines.',
    '✺',
  ),
  Gift(
    'veil',
    'Voile de brume',
    'Un bouclier absorbe un coup, puis se recharge en 8 s.',
    '◎',
  ),
  Gift(
    'frost',
    'Givre lunaire',
    'Tes attaques ralentissent les ennemis de 45 %.',
    '❄',
  ),
  Gift(
    'chain',
    'Arc de lune',
    'Après un impact, ta flamme bondit vers un autre ennemi.',
    '↯',
  ),
  Gift(
    'nova',
    'Colère de braise',
    'Quand tu es touché, tu libères un anneau de flammes.',
    '✹',
  ),
  Gift('regen', 'Mousse tendre', 'Régénère 1,5 PV par seconde.', '♣'),
];

/// Permanent upgrades bought between runs with embers.
class Perk {
  final String id, name, description;
  final int maxLevel;
  const Perk(this.id, this.name, this.description, this.maxLevel);
  int cost(int level) => 30 * (level + 1);
}

const perks = [
  Perk('vitality', 'Racines profondes', '+12 PV maximum', 5),
  Perk('ember', 'Braise ancienne', '+8 % de dégâts', 5),
  Perk('swift', 'Pas de velours', '+6 % de vitesse', 3),
  Perk('fortune', 'Trèfle de lune', '+1 relance de dons par partie', 3),
];

Offset unit(Offset v) => v.distance < .001 ? Offset.zero : v / v.distance;

class Enemy {
  Offset p;
  final Kind kind;
  double hp, maxHp, timer, flash = 0, tell = 0, slow = 0, beat = 0;
  Offset aim = Offset.zero, push = Offset.zero;
  bool charging = false;
  int step = 0, volley = 0;
  Enemy(this.p, this.kind, this.hp, this.timer) : maxHp = hp;
  bool get boss => kind == Kind.tortoise || kind == Kind.owl;
  double get radius => switch (kind) {
    Kind.tortoise => 31,
    Kind.owl => 30,
    Kind.broodcap => 19,
    Kind.spore => 9,
    _ => 15,
  };
  double get contactDamage => boss ? 20 : (kind == Kind.spore ? 7 : 12);
  double get pace => slow > 0 ? .55 : 1;
}

class Bolt {
  Offset p, v;
  final bool hostile;
  final double damage;
  int bounces, pierce, chain;
  final Set<Enemy> hit = {};
  double life = 4;
  Bolt(
    this.p,
    this.v,
    this.hostile,
    this.damage, {
    this.bounces = 0,
    this.pierce = 0,
    this.chain = 0,
  });
}

/// A lobbed projectile that lands on a marked spot.
class Shell {
  final Offset from, to;
  final double duration;
  double t = 0;
  Shell(this.from, this.to, [this.duration = 1.1]);
  double get progress => (t / duration).clamp(0, 1);
  Offset get position =>
      Offset.lerp(from, to, progress)! - Offset(0, sin(progress * pi) * 70);
}

class Spark {
  Offset p, v;
  double life = 1;
  final bool green;
  Spark(this.p, this.v, this.green);
}

/// Expanding shockwave: explosions, shield pops, shell impacts.
class Ring {
  final Offset p;
  final double size;
  final bool hostile;
  double life = 1;
  Ring(this.p, this.size, this.hostile);
}

/// What waits behind a door. Gold rewards last one run, embers are kept.
enum Reward { gift, coins, health, embers, shop, fountain, boss }

bool isCombat(Reward r) =>
    r == Reward.gift ||
    r == Reward.coins ||
    r == Reward.health ||
    r == Reward.embers;

const rewardNames = {
  Reward.gift: 'Lueur d’esprit',
  Reward.coins: 'Nuée de lucioles',
  Reward.health: 'Cœur de rosée',
  Reward.embers: 'Braises anciennes',
  Reward.shop: 'Échoppe de Maître Crapaud',
  Reward.fountain: 'Source de rosée',
  Reward.boss: 'Le gardien',
};

class Door {
  final Offset p;
  final Reward reward;
  final bool elite;
  const Door(this.p, this.reward, {this.elite = false});
}

/// The room's reward, waiting on a pedestal once the room is cleared.
class Pickup {
  final Offset p;
  final Reward reward;
  final bool elite;
  Pickup(this.p, this.reward, this.elite);
}

/// A firefly dropped by a fallen shadow: the run's currency.
class Coin {
  Offset p, v;
  double age = 0;
  Coin(this.p, this.v);
}

/// Afterimage left by a dash.
class Ghost {
  final Offset p;
  double life = 1;
  Ghost(this.p);
}

class Ware {
  final String id, name, description;
  final int price;
  bool sold = false;
  Ware(this.id, this.name, this.description, this.price);
}

/// Floating damage number.
class Popup {
  final String text;
  final bool crit;
  Offset p;
  double life = 1;
  Popup(this.text, this.p, this.crit);
}

/// Simulation independent of Flame: world units and seconds, never screen pixels.
class RunModel {
  final Random random;
  RunModel({int? seed}) : random = Random(seed);
  Phase phase = Phase.title;
  Offset player = const Offset(220, 370), movement = Offset.zero;
  List<Enemy> enemies = [];
  List<Bolt> bolts = [];
  List<Shell> shells = [];
  List<Spark> sparks = [];
  List<Ring> rings = [];
  List<Popup> popups = [];
  List<Gift> choices = [];
  List<Gift> acquired = [];
  List<Door> doors = [];
  List<Coin> loot = [];
  List<Ghost> ghosts = [];
  List<Ware> wares = [];
  Pickup? pickup;
  Door? pendingDoor;
  Reward room = Reward.gift;
  bool elite = false, cleared = false, doorsOpen = false;
  bool shopArmed = true, fountainUsed = false;
  int coins = 0, emberBonus = 0;
  double fade = 0, dashTime = 0, dashCooldown = 0;
  Offset facing = const Offset(0, -1), dashDirection = Offset.zero;
  static const merchant = Offset(220, 205), fountain = Offset(220, 300);
  final List<Sfx> events = [];
  Map<String, int> perkLevels = {};
  int depth = 1, kills = 0, multishot = 1, bounce = 0, pierce = 0, orbits = 0;
  int chain = 0, lifesteal = 0, bloom = 0, veil = 0, frost = 0, nova = 0;
  int regen = 0, rerolls = 0;
  double hp = 100, maxHp = 100, speed = 145, damage = 15, interval = .62;
  double critChance = 0, veilTimer = 0, shake = 0;
  bool veilReady = false;
  double cooldown = 0,
      invincible = 0,
      elapsed = 0,
      waveTime = 0,
      orbitClock = 0;
  double grace = 1.7, orbitCooldown = 0;
  bool get moving => movement.distance > .12;
  bool get finished => phase == Phase.won || phase == Phase.lost;
  int get biome => biomeOf(depth);
  bool get dashing => dashTime > 0;
  int get score =>
      kills * 25 + (depth - 1) * 100 + (phase == Phase.won ? 1000 : 0);
  int get embersEarned => score ~/ 20 + emberBonus;

  /// Combat difficulty on the scale of the original ten waves.
  double get tier {
    final k = (depth - 1) % roomsPerBiome;
    return (biome == 0 ? 1 : 6) + k * .8;
  }

  Enemy? get boss {
    for (final e in enemies) {
      if (e.boss) return e;
    }
    return null;
  }

  int perk(String id) => perkLevels[id] ?? 0;

  void start() {
    player = const Offset(220, 410);
    movement = Offset.zero;
    enemies.clear();
    bolts.clear();
    shells.clear();
    sparks.clear();
    rings.clear();
    popups.clear();
    events.clear();
    acquired.clear();
    loot.clear();
    ghosts.clear();
    coins = emberBonus = 0;
    fade = dashTime = dashCooldown = 0;
    pendingDoor = null;
    hp = maxHp = 100 + 12.0 * perk('vitality');
    speed = 145 * (1 + .06 * perk('swift'));
    damage = 15 * (1 + .08 * perk('ember'));
    rerolls = 1 + perk('fortune');
    interval = .62;
    depth = 0;
    kills = 0;
    multishot = 1;
    bounce = pierce = orbits = 0;
    chain = lifesteal = bloom = veil = frost = nova = regen = 0;
    critChance = veilTimer = shake = 0;
    veilReady = false;
    elapsed = cooldown = invincible = orbitClock = orbitCooldown = 0;
    phase = Phase.playing;
    loadRoom(const Door(Offset.zero, Reward.gift));
  }

  static List<Kind> roster(int wave) => switch (wave) {
    1 => const [Kind.mushroom, Kind.moth],
    2 || 3 => const [Kind.mushroom, Kind.moth, Kind.beetle],
    4 => const [Kind.mushroom, Kind.moth, Kind.beetle, Kind.broodcap],
    6 => const [Kind.mushroom, Kind.toad, Kind.broodcap],
    7 => const [Kind.moth, Kind.beetle, Kind.toad, Kind.broodcap],
    _ => const [
      Kind.mushroom,
      Kind.moth,
      Kind.beetle,
      Kind.toad,
      Kind.broodcap,
    ],
  };

  static double baseHp(Kind kind) => switch (kind) {
    Kind.beetle => 37,
    Kind.broodcap => 48,
    Kind.toad => 34,
    Kind.spore => 8,
    _ => 27,
  };

  /// Enters the next room: the door's reward decides what the room holds.
  void loadRoom(Door door) {
    depth++;
    room = door.reward;
    elite = door.elite;
    enemies.clear();
    bolts.clear();
    shells.clear();
    loot.clear();
    doors = [];
    wares = [];
    pickup = null;
    cleared = doorsOpen = fountainUsed = false;
    shopArmed = true;
    movement = Offset.zero;
    dashTime = 0;
    waveTime = 0;
    grace = 1.5;
    player = const Offset(220, 548);
    events.add(Sfx.waveStart);
    switch (room) {
      case Reward.boss:
        enemies.add(
          depth == totalDepth
              ? Enemy(const Offset(220, 150), Kind.owl, 1800, 2.5)
              : Enemy(const Offset(220, 155), Kind.tortoise, 650, 2),
        );
      case Reward.shop:
        wares = rollWares();
        cleared = true;
        openDoors();
      case Reward.fountain:
        cleared = true;
        openDoors();
      default:
        spawnEnemies();
    }
  }

  void spawnEnemies() {
    final t = tier;
    final kinds = roster(t.floor());
    var count = (t < 5 ? 3 + t * 2 : 6 + (t - 5) * 2).round();
    if (elite) count = (count * 1.25).round();
    for (var i = 0; i < count; i++) {
      final kind = kinds[i % kinds.length];
      final x = 65.0 + (i % 4) * 100 + random.nextDouble() * 12;
      final y = 120.0 + (i ~/ 4) * 70;
      final hp = (baseHp(kind) + t * (t < 5 ? 5 : 8)) * (elite ? 1.3 : 1);
      enemies.add(Enemy(Offset(x, y), kind, hp, 1 + random.nextDouble() * 2));
    }
  }

  /// Exits appear once the reward is taken; each shows what lies beyond.
  void openDoors() {
    doorsOpen = true;
    doors = rollDoors();
  }

  List<Door> rollDoors() {
    final next = depth + 1;
    if (depth >= totalDepth) return [];
    if (isBossDepth(next)) {
      return [const Door(Offset(220, 70), Reward.boss)];
    }
    final count = random.nextDouble() < .35 ? 3 : 2;
    // A spirit's gift is always on offer so no path leaves you powerless.
    final rewards = <Reward>[Reward.gift];
    const weights = {
      Reward.gift: 30,
      Reward.coins: 22,
      Reward.health: 14,
      Reward.embers: 12,
      Reward.shop: 14,
      Reward.fountain: 8,
    };
    final total = weights.values.reduce((a, b) => a + b);
    while (rewards.length < count) {
      var roll = random.nextInt(total);
      var reward = Reward.gift;
      for (final entry in weights.entries) {
        roll -= entry.value;
        if (roll < 0) {
          reward = entry.key;
          break;
        }
      }
      final special = reward == Reward.shop || reward == Reward.fountain;
      if (special && (rewards.contains(reward) || room == reward)) continue;
      if (reward == Reward.fountain && next < 3) continue;
      rewards.add(reward);
    }
    rewards.shuffle(random);
    final xs = count == 2 ? const [140.0, 300.0] : const [95.0, 220.0, 345.0];
    return [
      for (var i = 0; i < count; i++)
        Door(
          Offset(xs[i], 70),
          rewards[i],
          elite: isCombat(rewards[i]) && next >= 3 && random.nextDouble() < .2,
        ),
    ];
  }

  List<Ware> rollWares() {
    final scale = biome == 0 ? 1.0 : 1.4;
    int price(int base) => (base * scale).round();
    final others = [
      Ware('dew', 'Fiole de rosée', 'Récupère 40 PV.', price(20)),
      Ware('heart', 'Cœur de mousse', '+20 PV maximum.', price(35)),
      Ware('clover', 'Trèfle de lune', '+1 relance de dons.', price(18)),
      Ware('ember', 'Braise scellée', '+15 braises pour l’autel.', price(25)),
    ]..shuffle(random);
    return [
      Ware('gift', 'Lueur d’esprit', 'Choisis un don parmi trois.', price(45)),
      ...others.take(2),
    ];
  }

  void buy(Ware ware) {
    if (phase != Phase.shop || ware.sold || coins < ware.price) return;
    coins -= ware.price;
    ware.sold = true;
    events.add(Sfx.buy);
    switch (ware.id) {
      case 'gift':
        phase = Phase.upgrade;
        choices = rollChoices();
      case 'dew':
        hp = min(maxHp, hp + 40);
      case 'heart':
        maxHp += 20;
        hp += 20;
      case 'clover':
        rerolls++;
      case 'ember':
        emberBonus += 15;
    }
  }

  void leaveShop() {
    if (phase != Phase.shop) return;
    phase = Phase.playing;
    shopArmed = false;
  }

  /// A short burst with invulnerability, in the movement or facing direction.
  void dash() {
    if (phase != Phase.playing || grace > 0 || fade > 0) return;
    if (dashCooldown > 0 || dashing) return;
    dashDirection = moving ? unit(movement) : facing;
    dashTime = .17;
    dashCooldown = .85;
    events.add(Sfx.dash);
  }

  void collect(Pickup reward) {
    pickup = null;
    final bonus = reward.elite ? 2 : 1;
    burst(reward.p, count: 16);
    rings.add(Ring(reward.p, 50, false));
    switch (reward.reward) {
      case Reward.gift:
        phase = Phase.upgrade;
        choices = rollChoices(reward.elite ? 4 : 3);
        events.add(Sfx.gift);
        return;
      case Reward.coins:
        coins += 30 * bonus;
        popups.add(Popup('+${30 * bonus} lucioles', reward.p, true));
        events.add(Sfx.buy);
      case Reward.health:
        maxHp += 15.0 * bonus;
        hp = min(maxHp, hp + 25.0 * bonus);
        popups.add(Popup('+${15 * bonus} PV max', reward.p, true));
        events.add(Sfx.shield);
      case Reward.embers:
        emberBonus += 12 * bonus;
        popups.add(Popup('+${12 * bonus} braises', reward.p, true));
        events.add(Sfx.buy);
      default:
    }
    openDoors();
  }

  void dropCoins(Offset p, int count) {
    for (var i = 0; i < count; i++) {
      final a = random.nextDouble() * pi * 2;
      loot.add(
        Coin(p, Offset(cos(a), sin(a)) * (60 + random.nextDouble() * 90)),
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

  List<Gift> rollChoices([int count = 3]) =>
      (List<Gift>.of(gifts)..shuffle(random)).take(count).toList();

  void reroll() {
    if (phase != Phase.upgrade || rerolls <= 0) return;
    rerolls--;
    choices = rollChoices(choices.length);
  }

  void choose(Gift gift) {
    if (phase != Phase.upgrade || !choices.contains(gift)) return;
    acquired.add(gift);
    switch (gift.id) {
      case 'double':
        multishot++;
      case 'power':
        damage *= 1.4;
      case 'speed':
        speed *= 1.18;
      case 'rate':
        interval *= .75;
      case 'heal':
        maxHp += 15;
        hp = min(maxHp, hp + 35);
      case 'orbit':
        orbits++;
      case 'bounce':
        bounce++;
      case 'pierce':
        pierce++;
      case 'crit':
        critChance = min(.75, critChance + .15);
      case 'sap':
        lifesteal++;
      case 'bloom':
        bloom++;
      case 'veil':
        veil++;
        veilReady = true;
      case 'frost':
        frost++;
      case 'chain':
        chain++;
      case 'nova':
        nova++;
      case 'regen':
        regen++;
    }
    events.add(Sfx.gift);
    phase = Phase.playing;
    if (cleared && !doorsOpen) openDoors();
  }

  void burst(Offset p, {bool green = false, int count = 9}) {
    for (var i = 0; i < count; i++) {
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
    if (invincible > 0 || dashing || phase != Phase.playing) return;
    if (veilReady) {
      veilReady = false;
      veilTimer = 8 * pow(.7, veil - 1).toDouble();
      invincible = .6;
      rings.add(Ring(player, 44, false));
      events.add(Sfx.shield);
      return;
    }
    hp = max(0, hp - amount);
    invincible = 1.0;
    shake = max(shake, .35);
    burst(player);
    events.add(Sfx.hurt);
    if (nova > 0) {
      for (var i = 0; i < 10; i++) {
        final a = i * pi / 5;
        bolts.add(
          Bolt(
            player,
            Offset(cos(a), sin(a)) * 300,
            false,
            damage * (.5 + .5 * nova),
            pierce: 1,
          ),
        );
      }
    }
    if (hp == 0) {
      phase = Phase.lost;
      movement = Offset.zero;
      events.add(Sfx.lose);
    }
  }

  /// Every source of player damage goes through here: crits, frost, knockback.
  void strike(Enemy e, double amount, {Offset? from, bool canCrit = true}) {
    var crit = false;
    if (canCrit && critChance > 0 && random.nextDouble() < critChance) {
      amount *= 2.5;
      crit = true;
    }
    e.hp -= amount;
    e.flash = .12;
    if (frost > 0) e.slow = max(e.slow, 1 + frost * .5);
    if (from != null && !e.boss) e.push += unit(from) * 90;
    popups.add(
      Popup(
        '${amount.round()}',
        e.p + Offset(random.nextDouble() * 16 - 8, 0),
        crit,
      ),
    );
    if (popups.length > 40) popups.removeAt(0);
    events.add(crit ? Sfx.crit : Sfx.hit);
  }

  Offset bounded(Offset p, [double margin = 32]) =>
      Offset(p.dx.clamp(margin, 440 - margin), p.dy.clamp(80, 592));

  Enemy? nearest(Offset from, {Set<Enemy> skip = const {}, double? within}) {
    Enemy? best;
    var bestDistance = within == null ? double.infinity : within * within;
    for (final e in enemies) {
      if (e.hp <= 0 || skip.contains(e)) continue;
      final d = (e.p - from).distanceSquared;
      if (d < bestDistance) {
        best = e;
        bestDistance = d;
      }
    }
    return best;
  }

  Enemy spore(Offset p, Offset push) => Enemy(
    p,
    Kind.spore,
    baseHp(Kind.spore) + tier * 2,
    1 + random.nextDouble(),
  )..push = push;

  void update(double dt) {
    if (phase != Phase.playing) return;
    dt = min(dt, .04);
    elapsed += dt;
    waveTime += dt;
    orbitClock += dt;
    invincible = max(0, invincible - dt);
    shake = max(0, shake - dt * 2.5);
    cooldown -= dt;
    orbitCooldown -= dt;
    for (final s in sparks) {
      s.p += s.v * dt;
      s.life -= dt * 2;
    }
    sparks.removeWhere((s) => s.life <= 0);
    for (final r in rings) {
      r.life -= dt * 2.5;
    }
    rings.removeWhere((r) => r.life <= 0);
    for (final p in popups) {
      p.life -= dt * 1.4;
    }
    popups.removeWhere((p) => p.life <= 0);
    for (final g in ghosts) {
      g.life -= dt * 4;
    }
    ghosts.removeWhere((g) => g.life <= 0);
    dashCooldown = max(0, dashCooldown - dt);
    // Walking through a door fades out, loads the next room, then fades in.
    if (pendingDoor != null) {
      fade = min(1, fade + dt * 3.5);
      if (fade >= 1) {
        loadRoom(pendingDoor!);
        pendingDoor = null;
      }
      return;
    }
    if (fade > 0) fade = max(0, fade - dt * 3.5);
    if (grace > 0) {
      grace -= dt;
      return;
    }
    if (regen > 0) hp = min(maxHp, hp + 1.5 * regen * dt);
    if (veil > 0 && !veilReady) {
      veilTimer -= dt;
      if (veilTimer <= 0) veilReady = true;
    }
    if (moving) facing = unit(movement);
    if (dashing) {
      dashTime -= dt;
      player = bounded(player + dashDirection * speed * 3.6 * dt);
      ghosts.add(Ghost(player));
    } else if (moving) {
      player = bounded(player + unit(movement) * speed * dt);
    }
    updateRoom(dt);
    if (phase != Phase.playing || pendingDoor != null) return;
    final target = nearest(player);
    if (!moving && !dashing && cooldown <= 0 && target != null) {
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
            chain: chain,
          ),
        );
      }
      events.add(Sfx.shoot);
      cooldown = interval;
    }
    final spawned = <Enemy>[];
    for (final e in enemies) {
      e.flash = max(0, e.flash - dt);
      e.slow = max(0, e.slow - dt);
      e.timer -= dt;
      e.p += e.push * dt;
      e.push *= max(0, 1 - dt * 9);
      final pace = e.pace;
      final toPlayer = player - e.p;
      final direction = unit(toPlayer);
      final distance = toPlayer.distance;
      switch (e.kind) {
        case Kind.mushroom:
          e.p += direction * (31 + min(tier, 8) * 3) * pace * dt;
        case Kind.moth:
          if (distance > 235) e.p += direction * 28 * pace * dt;
          if (distance < 140) e.p -= direction * 24 * pace * dt;
          if (e.timer < .65 && e.tell == 0) {
            e.tell = .65;
            e.aim = direction;
          }
          if (e.timer <= 0) {
            // Moonlit moths fire a small fan instead of a single bolt.
            final spread = biome == 1 ? const [-.22, 0.0, .22] : const [0.0];
            final a = atan2(e.aim.dy, e.aim.dx);
            for (final d in spread) {
              bolts.add(
                Bolt(e.p, Offset(cos(a + d), sin(a + d)) * 135, true, 12),
              );
            }
            e.timer = 2.8;
            e.tell = 0;
          }
        case Kind.beetle:
          if (e.charging) {
            e.p += e.aim * 245 * pace * dt;
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
            e.p += direction * 22 * pace * dt;
          }
        case Kind.broodcap:
          e.p += direction * 19 * pace * dt;
        case Kind.spore:
          final side = Offset(-direction.dy, direction.dx);
          e.p +=
              (direction + side * sin(elapsed * 6 + e.maxHp) * .6) *
              (68 + tier * 2) *
              pace *
              dt;
        case Kind.toad:
          if (distance > 260) e.p += direction * 25 * pace * dt;
          if (distance < 170) e.p -= direction * 30 * pace * dt;
          if (e.timer < .9 && e.tell == 0) e.tell = .9;
          if (e.timer <= 0) {
            final lead = moving ? unit(movement) * 55 : Offset.zero;
            shells.add(Shell(e.p, bounded(player + lead, 40)));
            events.add(Sfx.lob);
            e.timer = 2.8;
            e.tell = 0;
          }
        case Kind.tortoise:
          e.p += direction * 17 * dt;
          if (e.timer < .9) e.tell = .9;
          if (e.timer <= 0) {
            for (var i = 0; i < 12; i++) {
              final a = i * pi / 6 + orbitClock * .3;
              bolts.add(Bolt(e.p, Offset(cos(a), sin(a)) * 110, true, 16));
            }
            e.timer = e.hp < e.maxHp / 2 ? 1.7 : 2.5;
            e.tell = 0;
            shake = max(shake, .15);
            events.add(Sfx.bossAttack);
          }
        case Kind.owl:
          final enraged = e.hp < e.maxHp / 2;
          final anchor = Offset(
            220 + sin(elapsed * .5) * 110,
            165 + sin(elapsed * .9) * 25,
          );
          e.p += unit(anchor - e.p) * min(70, (anchor - e.p).distance * 3) * dt;
          if (e.volley > 0) {
            e.timer += dt;
            e.beat -= dt;
            if (e.beat <= 0) {
              e.beat = .09;
              e.volley--;
              final arms = enraged ? 4 : 3;
              for (var i = 0; i < arms; i++) {
                final a = e.volley * .23 + i * pi * 2 / arms;
                bolts.add(Bolt(e.p, Offset(cos(a), sin(a)) * 130, true, 14));
              }
            }
          } else {
            if (e.timer < .9) e.tell = .9;
            if (e.timer <= 0) {
              e.tell = 0;
              switch (e.step % 3) {
                case 0:
                  e.volley = enraged ? 26 : 20;
                  e.beat = 0;
                case 1:
                  final count = enraged ? 7 : 5;
                  final a = atan2(direction.dy, direction.dx);
                  for (var i = 0; i < count; i++) {
                    final angle = a + (i - (count - 1) / 2) * .2;
                    bolts.add(
                      Bolt(e.p, Offset(cos(angle), sin(angle)) * 165, true, 14),
                    );
                  }
                default:
                  if (enemies.length < 7) {
                    for (var i = 0; i < 3; i++) {
                      final a = i * pi * 2 / 3 + elapsed;
                      final offset = Offset(cos(a), sin(a));
                      spawned.add(spore(e.p + offset * 36, offset * 120));
                    }
                  }
              }
              e.step++;
              e.timer = enraged ? 1.7 : 2.4;
              shake = max(shake, .15);
              events.add(Sfx.bossAttack);
            }
          }
      }
      e.p = bounded(e.p, e.radius + 12);
      if ((e.p - player).distance < e.radius + 12) hurt(e.contactDamage);
      if (orbits > 0 && orbitCooldown <= 0) {
        for (var i = 0; i < orbits; i++) {
          final a = orbitClock * 3 + i * pi * 2 / orbits;
          final p = player + Offset(cos(a), sin(a)) * 52;
          if ((p - e.p).distance < e.radius + 10) {
            strike(e, damage, from: e.p - player);
            orbitCooldown = .25;
          }
        }
      }
    }
    enemies.addAll(spawned);
    for (final s in shells) {
      s.t += dt;
      if (s.t >= s.duration) {
        rings.add(Ring(s.to, 38, true));
        events.add(Sfx.explode);
        if ((player - s.to).distance < 34) hurt(14);
      }
    }
    shells.removeWhere((s) => s.t >= s.duration);
    // Iterate a copy: a hit can trigger Colère de braise, which adds bolts.
    for (final b in [...bolts]) {
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
            strike(e, b.damage, from: b.v);
            b.hit.add(e);
            burst(b.p);
            if (b.chain > 0) {
              final next = nearest(b.p, skip: b.hit, within: 190);
              if (next != null) {
                b.chain--;
                b.v = unit(next.p - b.p) * 350;
                b.life = max(b.life, 1);
                break;
              }
            }
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
    resolveDeaths();
    bolts.removeWhere((b) => b.life <= 0);
    if (phase != Phase.playing) return;
    if (enemies.isEmpty && !cleared) {
      cleared = true;
      bolts.clear();
      shells.clear();
      if (room == Reward.boss && depth == totalDepth) {
        phase = Phase.won;
        movement = Offset.zero;
        events.add(Sfx.win);
      } else if (room == Reward.boss) {
        hp = min(maxHp, hp + maxHp * .4);
        pickup = Pickup(const Offset(220, 300), Reward.gift, true);
      } else {
        pickup = Pickup(const Offset(220, 300), room, elite);
      }
    }
  }

  /// Fireflies, the reward pedestal, the fountain, the merchant and doors.
  void updateRoom(double dt) {
    for (final c in loot) {
      c.age += dt;
      c.p = bounded(c.p + c.v * dt, 30);
      c.v *= max(0, 1 - dt * 4);
      final toPlayer = player - c.p;
      // Once the room is safe, the fireflies drift to you on their own.
      if (cleared && c.age > .4) {
        c.p += unit(toPlayer) * min(toPlayer.distance, 420 * dt);
      }
      if (toPlayer.distance < 22 && c.age > .25) {
        c.age = -1;
        coins++;
        events.add(Sfx.coin);
      }
    }
    loot.removeWhere((c) => c.age < 0);
    final reward = pickup;
    if (reward != null && (player - reward.p).distance < 30) collect(reward);
    if (phase != Phase.playing) return;
    if (room == Reward.fountain &&
        !fountainUsed &&
        (player - fountain).distance < 48) {
      fountainUsed = true;
      final heal = maxHp * .35;
      hp = min(maxHp, hp + heal);
      rings.add(Ring(fountain, 70, false));
      popups.add(Popup('+${heal.round()} PV', fountain, true));
      events.add(Sfx.shield);
    }
    if (room == Reward.shop) {
      final distance = (player - merchant).distance;
      if (shopArmed && distance < 66) {
        shopArmed = false;
        phase = Phase.shop;
        movement = Offset.zero;
        return;
      }
      if (distance > 105) shopArmed = true;
    }
    if (doorsOpen && pendingDoor == null) {
      for (final door in doors) {
        if ((player.dx - door.p.dx).abs() < 30 && player.dy < 96) {
          pendingDoor = door;
          movement = Offset.zero;
          events.add(Sfx.door);
          break;
        }
      }
    }
  }

  /// Removes the dead, including enemies killed by chained explosions.
  void resolveDeaths() {
    var dead = enemies.where((e) => e.hp <= 0).toList();
    while (dead.isNotEmpty) {
      enemies.removeWhere((e) => e.hp <= 0);
      for (final e in dead) {
        kills++;
        burst(e.p, green: true, count: e.boss ? 40 : 9);
        events.add(Sfx.kill);
        if (lifesteal > 0) hp = min(maxHp, hp + 2.0 * lifesteal);
        if (e.boss) shake = .7;
        final drops = e.boss
            ? 12
            : e.kind == Kind.broodcap
            ? 2
            : e.kind == Kind.spore
            ? (random.nextDouble() < .35 ? 1 : 0)
            : 1;
        dropCoins(e.p, elite ? drops * 2 : drops);
        if (bloom > 0) {
          final reach = 45.0 + 10 * bloom;
          rings.add(Ring(e.p, reach, false));
          events.add(Sfx.explode);
          for (final o in enemies) {
            if (o.hp > 0 && (o.p - e.p).distance < reach + o.radius) {
              strike(o, damage * .5 * bloom, canCrit: false, from: o.p - e.p);
            }
          }
        }
        if (e.kind == Kind.broodcap) {
          for (var i = 0; i < 3; i++) {
            final a = i * pi * 2 / 3 + random.nextDouble();
            final offset = Offset(cos(a), sin(a));
            enemies.add(spore(e.p + offset * 10, offset * 160));
          }
        }
      }
      dead = enemies.where((e) => e.hp <= 0).toList();
    }
  }
}
