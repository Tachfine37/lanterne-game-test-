import 'dart:math';
import 'dart:typed_data';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';
import 'audio.dart';
import 'model.dart';

const gold = Color(0xFFFFD18A);
const mint = Color(0xFF8DE1C2);

class GardenGame extends Game {
  final RunModel run;
  final void Function() refresh;
  final Sound sound;
  GardenGame(this.run, this.refresh, this.sound);
  final shaker = Random();
  double clock = 0, uiClock = 0;
  Offset? stickOrigin, stickEnd;
  // The room lives in flat world coordinates (440 × 640). A camera placed
  // behind and above the hero looks at it in perspective, like Archero: the
  // floor recedes toward the north wall and walls stay vertical.
  static const viewW = 480.0, viewH = 820.0;
  static const _f = 1405.0, _cy = 1816.0, _h = 1891.0, _x0 = 240.0;
  static const _y0 = -1406.0, backWall = 100.0, sideWall = 70.0;

  /// A world point (and height above the floor) to the view.
  static Offset project(Offset p, [double z = 0]) {
    final depth = _cy - p.dy;
    return Offset(_x0 + _f * (p.dx - 220) / depth, _y0 + _f * (_h - z) / depth);
  }

  /// How large things look at a given distance: 1 near the hero's spawn.
  static double scaleAt(double y) => _f / (_cy - y) * .9;

  /// The floor plane as a homography, so tiles, telegraphs and rings are
  /// drawn in world units and foreshortened by the canvas itself.
  static final groundMatrix = Float64List.fromList([
    _f, 0, 0, 0, //
    -_x0, -_y0, 0, -1, //
    0, 0, 1, 0, //
    _x0 * _cy - 220 * _f, _y0 * _cy + _f * _h, 0, _cy,
  ]);
  double get scale => min(size.x / viewW, size.y / viewH);
  Offset get inset =>
      Offset((size.x - viewW * scale) / 2, (size.y - viewH * scale) / 2);

  /// Draws an upright sprite standing on a world position, shrinking with
  /// distance; [lift] raises it in the sprite's own units.
  void standing(
    Canvas c,
    Offset world,
    void Function() draw, {
    double lift = 0,
  }) {
    final s = project(world);
    c.save();
    c.translate(s.dx, s.dy);
    c.scale(scaleAt(world.dy));
    c.translate(0, -lift);
    draw();
    c.restore();
  }

  /// Draws in the plane of the north wall, which faces the camera.
  void onWall(Canvas c, double x, double floor, void Function() draw) {
    final base = project(Offset(x, 57));
    c.save();
    c.translate(base.dx, base.dy);
    c.scale(_f / (_cy - 57));
    c.translate(-x, -floor);
    draw();
    c.restore();
  }

  @override
  void update(double dt) {
    clock += min(dt, .04);
    final old = run.phase;
    run.update(dt);
    for (final sfx in run.events) {
      sound.play(sfx);
    }
    run.events.clear();
    uiClock += dt;
    if (uiClock > .1 || old != run.phase) {
      uiClock = 0;
      refresh();
    }
  }

  void circle(Canvas c, Offset p, double r, Color color) =>
      c.drawCircle(p, r, Paint()..color = color);
  void oval(Canvas c, double x, double y, double w, double h, Color color) =>
      c.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: w, height: h),
        Paint()..color = color,
      );
  void line(Canvas c, Offset a, Offset b, Color color, double width) =>
      c.drawLine(
        a,
        b,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
  void rect(Canvas c, Rect r, Color color, [double radius = 0]) => c.drawRRect(
    RRect.fromRectAndRadius(r, Radius.circular(radius)),
    Paint()..color = color,
  );
  void glow(Canvas c, Offset p, double radius, Color color) {
    c.drawCircle(
      p,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: .24), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: p, radius: radius)),
    );
  }

  void label(Canvas c, String text, Offset p, double fontSize, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontFamily: 'Georgia',
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, p - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void render(Canvas canvas) {
    final c = canvas;
    c.save();
    c.translate(inset.dx, inset.dy);
    c.scale(scale);
    c.clipRect(const Rect.fromLTWH(0, 0, viewW, viewH));
    final showPreview = run.phase == Phase.title;
    final moon = !showPreview && run.biome == 1;
    backdrop(c, moon);
    if (run.shake > 0 && run.phase == Phase.playing) {
      final power = run.shake * 16;
      c.translate(
        (shaker.nextDouble() - .5) * power,
        (shaker.nextDouble() - .5) * power,
      );
    }
    // Everything lying on the floor is drawn in room coordinates and
    // projected, so circles become the flattened ellipses of the iso view.
    c.save();
    c.transform(groundMatrix);
    garden(c);
    groundEffects(c, showPreview);
    c.restore();
    backWalls(c, moon);
    final doors = showPreview ? const <Door>[] : run.doors;
    if (!doors.any((d) => d.p.dx == 220)) {
      onWall(c, 220, 76, () => shrine(c));
    }
    for (final door in doors) {
      onWall(c, door.p.dx, 98, () => doorArch(c, door));
      standing(c, Offset(door.p.dx, 57), () => doorSign(c, door), lift: 50);
    }
    for (var i = 0; i < 6; i++) {
      for (final x in const [30.0, 410.0]) {
        standing(
          c,
          Offset(x, 120 + i * 90.0),
          () => leaf(c, Offset.zero, i + x, .7 + (i % 3) * .15),
        );
      }
    }
    for (final coin in run.loot) {
      standing(c, coin.p, () {
        glow(c, Offset.zero, 12, gold);
        circle(c, Offset.zero, 3.2, gold);
        circle(c, Offset.zero, 1.3, const Color(0xFFFFF7E0));
      }, lift: 10 + sin(clock * 6 + coin.p.dx) * 3);
    }
    for (final g in run.ghosts) {
      standing(
        c,
        g.p,
        () => oval(
          c,
          0,
          -18,
          24,
          32,
          gold.withValues(alpha: g.life.clamp(0, 1) * .3),
        ),
      );
    }
    double depth(Offset p) => p.dy;
    final actors = <({double y, void Function() draw})>[
      (
        y: depth(run.player),
        draw: () => standing(c, run.player, () => hero(c, Offset.zero)),
      ),
      for (final e in run.enemies)
        (y: depth(e.p), draw: () => standing(c, e.p, () => enemy(c, e))),
      if (run.room == Reward.shop && !showPreview)
        (
          y: depth(RunModel.merchant),
          draw: () => standing(c, RunModel.merchant, () => merchant(c)),
        ),
      if (run.room == Reward.fountain && !showPreview)
        (
          y: depth(RunModel.fountain),
          draw: () => standing(c, RunModel.fountain, () => spring(c)),
        ),
      if (run.pickup case final reward?)
        (
          y: depth(reward.p),
          draw: () => standing(c, reward.p, () => pedestal(c, reward)),
        ),
      for (final p in const [
        Offset(46, 90),
        Offset(400, 88),
        Offset(40, 590),
        Offset(402, 592),
      ])
        (
          y: depth(p),
          draw: () => standing(c, p, () => lantern(c, Offset.zero)),
        ),
      if (showPreview) ...[
        for (final (p, kind) in const [
          (Offset(95, 200), Kind.mushroom),
          (Offset(345, 220), Kind.moth),
          (Offset(330, 475), Kind.beetle),
        ])
          (
            y: depth(p),
            draw: () => standing(c, p, () => enemy(c, Enemy(p, kind, 30, 2))),
          ),
      ],
    ]..sort((a, b) => a.y.compareTo(b.y));
    for (final actor in actors) {
      actor.draw();
    }
    for (final s in run.shells) {
      final k = s.progress;
      standing(c, Offset.lerp(s.from, s.to, k)!, () {
        glow(c, Offset.zero, 18, const Color(0xFFFFB07A));
        circle(c, Offset.zero, 7, const Color(0xFFE08A5A));
        circle(c, const Offset(-2, -2), 3, const Color(0xFFFFE3B8));
      }, lift: 12 + sin(k * pi) * 110);
    }
    for (final b in run.bolts) {
      final color = b.hostile ? const Color(0xFFFF938C) : gold;
      final tail = unit(b.v) * (b.hostile ? 8 : 14);
      standing(c, b.p, () {
        line(
          c,
          Offset.zero,
          -tail,
          color.withValues(alpha: .4),
          b.hostile ? 7 : 5,
        );
        glow(c, Offset.zero, 15, color);
        circle(c, Offset.zero, b.hostile ? 5 : 4, color);
        circle(c, Offset.zero, 2, const Color(0xFFFFF5DD));
      }, lift: 16);
    }
    for (var i = 0; i < run.orbits; i++) {
      final a = run.orbitClock * 3 + i * pi * 2 / run.orbits;
      standing(c, run.player + Offset(cos(a), sin(a)) * 52, () {
        glow(c, Offset.zero, 22, mint);
        circle(c, Offset.zero, 6, mint);
        circle(c, Offset.zero, 2, const Color(0xFFFFFFFF));
      }, lift: 16);
    }
    for (final s in run.sparks) {
      standing(
        c,
        s.p,
        () => circle(
          c,
          Offset.zero,
          max(0, s.life) * 3,
          (s.green ? mint : gold).withValues(alpha: s.life.clamp(0, 1)),
        ),
        lift: 14,
      );
    }
    for (final p in run.popups) {
      standing(
        c,
        p.p,
        () => label(
          c,
          p.crit ? '${p.text}!' : p.text,
          Offset.zero,
          p.crit ? 17 : 12,
          (p.crit ? const Color(0xFFFFB45E) : const Color(0xFFFFF1D6))
              .withValues(alpha: p.life.clamp(0, 1)),
        ),
        lift: 52 + (1 - p.life) * 34,
      );
    }
    // Drifting fireflies, then the low front rim and foliage framing the room.
    for (var i = 0; i < 18; i++) {
      final x = 30.0 + (i * 97) % 380 + sin(clock * .5 + i) * 9;
      final y = 90.0 + (i * 137) % 500 + cos(clock * .4 + i) * 8;
      standing(
        c,
        Offset(x, y),
        () => circle(
          c,
          Offset.zero,
          1.5,
          mint.withValues(alpha: .2 + (.5 + .5 * sin(clock + i)) * .45),
        ),
        lift: 30 + sin(clock + i) * 8,
      );
    }
    frontRim(c, moon);
    for (var i = 0; i < 7; i++) {
      standing(
        c,
        Offset(20 + i * 67.0, 626),
        () => leaf(c, Offset.zero, i.toDouble(), .9),
      );
    }
    if (run.phase == Phase.playing && run.grace > 0) {
      rect(
        c,
        Rect.fromCenter(center: const Offset(240, 360), width: 400, height: 92),
        const Color(0xE6153033),
        22,
      );
      label(
        c,
        switch (run.room) {
          Reward.boss when run.depth == totalDepth => 'MINUIT APPROCHE',
          Reward.boss => 'LE SANCTUAIRE S’ÉVEILLE',
          Reward.shop => 'L’ÉCHOPPE',
          Reward.fountain => 'LA SOURCE',
          _ => 'SALLE ${run.depth}${run.elite ? '  ·  ÉPREUVE' : ''}',
        },
        const Offset(240, 345),
        22,
        run.elite ? const Color(0xFFFF9F86) : gold,
      );
      label(
        c,
        switch (run.room) {
          Reward.boss => 'Garde tes distances.',
          Reward.shop => 'Approche-toi de Maître Crapaud.',
          Reward.fountain => 'Bois à la source pour te soigner.',
          _ when run.elite => 'Plus d’ombres, récompense doublée.',
          _ when run.depth == roomsPerBiome + 1 => 'Le bassin de lune s’ouvre.',
          _ => 'Récompense : ${rewardNames[run.room]}',
        },
        const Offset(240, 378),
        14,
        mint,
      );
    }
    vignette(c);
    if (run.fade > 0) {
      c.drawRect(
        const Rect.fromLTWH(-40, -40, viewW + 80, viewH + 80),
        Paint()..color = const Color(0xFF0D2027).withValues(alpha: run.fade),
      );
    }
    c.restore();
    // The thumb stick is drawn in screen space, where the finger is.
    if (stickOrigin != null && run.phase == Phase.playing) {
      final a = stickOrigin!, b = stickEnd!;
      circle(c, a, 38, const Color(0x22FFFFFF));
      c.drawCircle(
        a,
        38,
        Paint()
          ..color = const Color(0x55FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      circle(
        c,
        a + unit(b - a) * min(28, (b - a).distance),
        15,
        const Color(0x99FFDFAC),
      );
    }
  }

  void backdrop(Canvas c, bool moon) {
    const area = Rect.fromLTWH(0, 0, viewW, viewH);
    c.drawRect(
      area,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -.1),
          radius: .9,
          colors: moon
              ? const [Color(0xFF1B2744), Color(0xFF080C19)]
              : const [Color(0xFF1C3836), Color(0xFF061215)],
        ).createShader(area),
    );
  }

  void vignette(Canvas c) {
    const area = Rect.fromLTWH(0, 0, viewW, viewH);
    c.drawRect(
      area,
      Paint()
        ..shader = const RadialGradient(
          radius: .85,
          colors: [Color(0x00000000), Color(0x00000000), Color(0x8C02080A)],
          stops: [0, .6, 1],
        ).createShader(area),
    );
  }

  /// Floor-level effects: the lantern's light pool, telegraphs, impacts.
  void groundEffects(Canvas c, bool showPreview) {
    c.drawCircle(
      run.player,
      150,
      Paint()
        ..shader = RadialGradient(
          colors: [gold.withValues(alpha: .16), gold.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: run.player, radius: 150)),
    );
    if (!showPreview) {
      for (final door in run.doors) {
        final tint = rewardColor(door.reward, elite: door.elite);
        final breathe = .75 + sin(clock * 3 + door.p.dx) * .25;
        oval(c, door.p.dx, 78, 60, 34, tint.withValues(alpha: .22 * breathe));
      }
    }
    for (final e in run.enemies) {
      if (e.tell > 0 && e.kind != Kind.toad) {
        if (e.boss) {
          c.drawCircle(
            e.p,
            48 + sin(clock * 12) * 3,
            Paint()
              ..color = const Color(0x66FF8E81)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3,
          );
        } else {
          line(
            c,
            e.p,
            e.p + e.aim * (e.kind == Kind.beetle ? 175 : 140),
            const Color(0x55FF9F86),
            e.kind == Kind.beetle ? 22 : 3,
          );
        }
      }
    }
    for (final s in run.shells) {
      c.drawCircle(
        s.to,
        34,
        Paint()
          ..color = const Color(0x88FF8E81)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      circle(c, s.to, 34 * s.progress, const Color(0x33FF8E81));
    }
    for (final r in run.rings) {
      c.drawCircle(
        r.p,
        r.size * (.35 + .65 * (1 - r.life)),
        Paint()
          ..color = (r.hostile ? const Color(0xFFFF9F86) : gold).withValues(
            alpha: r.life.clamp(0, 1) * .8,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5 * r.life + 1,
      );
    }
  }

  /// A stone wall standing on the floor between two points, [h] high.
  void wall(Canvas c, Offset a, Offset b, double h, Color color, Color cap) {
    final pa = project(a), pb = project(b);
    final ta = project(a, h), tb = project(b, h);
    final face = Path()
      ..moveTo(pa.dx, pa.dy)
      ..lineTo(pb.dx, pb.dy)
      ..lineTo(tb.dx, tb.dy)
      ..lineTo(ta.dx, ta.dy)
      ..close();
    c.drawPath(
      face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color.lerp(color, const Color(0xFF000000), .45)!, color],
        ).createShader(face.getBounds()),
    );
    final courses = max(1, (h / 22).round());
    final steps = max(2, ((b - a).distance / 46).round());
    Offset at(double t, double z) => project(Offset.lerp(a, b, t)!, z);
    for (var k = 0; k < courses; k++) {
      final z0 = h * k / courses, z1 = h * (k + 1) / courses;
      if (k > 0) line(c, at(0, z0), at(1, z0), const Color(0x26000000), 1.2);
      for (var i = 1; i < steps; i++) {
        final t = (i + (k.isOdd ? .5 : 0)) / steps;
        if (t >= 1) continue;
        line(c, at(t, z0), at(t, z1), const Color(0x1C000000), 1);
      }
    }
    line(c, ta, tb, cap, 5);
    line(c, at(0, h - 3), at(1, h - 3), const Color(0x33000000), 2);
  }

  void backWalls(Canvas c, bool moon) {
    final lit = moon ? const Color(0xFF465580) : const Color(0xFF3F5E55);
    final shade = moon ? const Color(0xFF323D63) : const Color(0xFF2E4842);
    final cap = moon ? const Color(0xFF7686B5) : const Color(0xFF6C8C7C);
    wall(c, const Offset(20, 57), const Offset(420, 57), backWall, lit, cap);
    wall(c, const Offset(20, 607), const Offset(20, 57), sideWall, shade, cap);
    wall(
      c,
      const Offset(420, 57),
      const Offset(420, 607),
      sideWall,
      shade,
      cap,
    );
  }

  void frontRim(Canvas c, bool moon) {
    final color = moon ? const Color(0xFF28324F) : const Color(0xFF223B36);
    final cap = moon ? const Color(0xFF55648F) : const Color(0xFF4F6D60);
    wall(c, const Offset(20, 607), const Offset(420, 607), 14, color, cap);
  }

  void garden(Canvas c) {
    final moon = run.phase != Phase.title && run.biome == 1;
    final accent = moon ? const Color(0xFFA9B8FF) : const Color(0xFF3ED8B1);
    // Raised stone edging and staggered, mossy (or moonlit) paving.
    rect(
      c,
      const Rect.fromLTWH(17, 60, 406, 560),
      Color(moon ? 0xFF0B1328 : 0xFF0C252B),
      25,
    );
    rect(
      c,
      const Rect.fromLTWH(20, 57, 400, 550),
      Color(moon ? 0xFF4A5A80 : 0xFF416057),
      23,
    );
    rect(
      c,
      const Rect.fromLTWH(27, 63, 386, 540),
      Color(moon ? 0xFF28324F : 0xFF28453F),
      19,
    );
    c.save();
    c.clipRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(29, 65, 382, 535),
        const Radius.circular(18),
      ),
    );
    for (var row = 0; row < 12; row++) {
      for (var col = 0; col < 7; col++) {
        final x = col * 72.0 - (row % 2) * 36;
        final y = 68 + row * 47.0;
        final n = (row * 13 + col * 7) % 5;
        final colors = moon
            ? const [0xFF2A3656, 0xFF2E3B5E, 0xFF283352, 0xFF334266, 0xFF2B3759]
            : const [
                0xFF2C4842,
                0xFF304D45,
                0xFF29433F,
                0xFF355046,
                0xFF2C4741,
              ];
        rect(c, Rect.fromLTWH(x + 2, y + 2, 68, 43), Color(colors[n]), 5);
        line(
          c,
          Offset(x + 9, y + 4),
          Offset(x + 57, y + 4),
          accent.withValues(alpha: .09),
          1,
        );
        if (n == 2) {
          line(
            c,
            Offset(x + 28, y + 23),
            Offset(x + 38, y + 30),
            const Color(0x5530493D),
            1,
          );
        }
      }
    }
    if (moon) {
      // Still pools with lily pads catch the moonlight.
      for (final (p, w) in [
        (const Offset(92, 250), 86.0),
        (const Offset(352, 470), 96.0),
        (const Offset(330, 160), 64.0),
      ]) {
        oval(c, p.dx, p.dy, w, w * .45, const Color(0xFF1A2A4A));
        oval(c, p.dx - 4, p.dy - 2, w * .8, w * .32, const Color(0xFF223A63));
        oval(c, p.dx - w * .18, p.dy - 4, w * .3, 3, const Color(0x55CFE0FF));
        oval(c, p.dx + w * .2, p.dy + 3, 18, 9, const Color(0xFF3C6B5A));
        circle(
          c,
          Offset(p.dx + w * .2, p.dy + 1),
          2.5,
          const Color(0xFFF0C8E0),
        );
      }
    }
    c.restore();
    final center = const Offset(220, 320);
    c.drawCircle(
      center,
      95,
      Paint()
        ..color = accent.withValues(alpha: .09)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    c.drawCircle(
      center,
      84,
      Paint()
        ..color = accent.withValues(alpha: .09)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    for (var i = 0; i < 8; i++) {
      final a = i * pi / 4;
      circle(
        c,
        center + Offset(cos(a), sin(a)) * 95,
        3,
        accent.withValues(alpha: .19),
      );
    }
    decorations(c);
  }

  void shrine(Canvas c) {
    oval(c, 220, 67, 142, 29, const Color(0x5505141D));
    rect(c, const Rect.fromLTWH(168, 20, 104, 48), const Color(0xFF193037), 8);
    rect(c, const Rect.fromLTWH(183, 14, 74, 49), const Color(0xFF46635B), 30);
    rect(c, const Rect.fromLTWH(193, 22, 54, 43), const Color(0xFF173537), 23);
    glow(c, const Offset(220, 39), 42, mint);
    label(c, '✦', const Offset(220, 40), 28, mint);
  }

  void decorations(Canvas c) {
    for (final p in [
      const Offset(21, 228),
      const Offset(415, 367),
      const Offset(20, 500),
      const Offset(407, 172),
    ]) {
      glow(c, p, 20, mint);
      for (var i = 0; i < 5; i++) {
        final a = i * pi * 2 / 5;
        oval(c, p.dx + cos(a) * 4, p.dy + sin(a) * 4, 6, 5, mint);
      }
      circle(c, p, 2, gold);
    }
  }

  /// Door colours follow Hades' laurels: gold lasts one run, blue is kept,
  /// red warns of a guardian or a harder room.
  Color rewardColor(Reward reward, {bool elite = false}) {
    if (elite || reward == Reward.boss) return const Color(0xFFFF9F86);
    if (reward == Reward.embers) return const Color(0xFF9FC4FF);
    return gold;
  }

  void rewardIcon(Canvas c, Offset p, Reward reward, double s) {
    final fill = Paint();
    switch (reward) {
      case Reward.gift:
        glow(c, p, s * 2.4, mint);
        final star = Path();
        for (var i = 0; i < 8; i++) {
          final a = i * pi / 4 - pi / 2 + clock * .6;
          final r = i.isEven ? s : s * .38;
          final q = p + Offset(cos(a), sin(a)) * r;
          i == 0 ? star.moveTo(q.dx, q.dy) : star.lineTo(q.dx, q.dy);
        }
        c.drawPath(star..close(), fill..color = const Color(0xFFE9FFF6));
        circle(c, p, s * .3, mint);
      case Reward.coins:
        for (final d in const [Offset(-5, 3), Offset(5, 3), Offset(0, -5)]) {
          final q = p + d * (s / 10);
          glow(c, q, s, gold);
          circle(c, q, s * .38, gold);
          circle(c, q, s * .15, const Color(0xFFFFF7E0));
        }
      case Reward.health:
        final heart = Path()
          ..moveTo(p.dx, p.dy + s * .75)
          ..cubicTo(
            p.dx - s * 1.3,
            p.dy - s * .1,
            p.dx - s * .6,
            p.dy - s * 1.1,
            p.dx,
            p.dy - s * .35,
          )
          ..cubicTo(
            p.dx + s * .6,
            p.dy - s * 1.1,
            p.dx + s * 1.3,
            p.dy - s * .1,
            p.dx,
            p.dy + s * .75,
          );
        glow(c, p, s * 2.2, const Color(0xFFFF9FB8));
        c.drawPath(heart, fill..color = const Color(0xFFF08AA6));
        circle(
          c,
          p + Offset(-s * .35, -s * .35),
          s * .14,
          const Color(0xFFFFE2EA),
        );
      case Reward.embers:
        final flame = Path()
          ..moveTo(p.dx, p.dy - s)
          ..quadraticBezierTo(p.dx + s * .9, p.dy, p.dx + s * .5, p.dy + s * .6)
          ..quadraticBezierTo(
            p.dx,
            p.dy + s * .95,
            p.dx - s * .5,
            p.dy + s * .6,
          )
          ..quadraticBezierTo(p.dx - s * .9, p.dy, p.dx, p.dy - s);
        glow(c, p, s * 2.2, const Color(0xFFFFA25E));
        c.drawPath(flame, fill..color = const Color(0xFFFF9A52));
        oval(c, p.dx, p.dy + s * .3, s * .6, s * .8, const Color(0xFFFFE0A0));
      case Reward.shop:
        oval(c, p.dx, p.dy + s * .2, s * 1.7, s * 1.5, const Color(0xFF9C7A52));
        rect(
          c,
          Rect.fromCenter(
            center: p - Offset(0, s * .6),
            width: s * .9,
            height: s * .35,
          ),
          const Color(0xFF7A5C3C),
          2,
        );
        circle(c, p + Offset(0, s * .25), s * .35, gold);
      case Reward.fountain:
        final drop = Path()
          ..moveTo(p.dx, p.dy - s)
          ..cubicTo(
            p.dx + s,
            p.dy,
            p.dx + s * .7,
            p.dy + s * .8,
            p.dx,
            p.dy + s * .8,
          )
          ..cubicTo(
            p.dx - s * .7,
            p.dy + s * .8,
            p.dx - s,
            p.dy,
            p.dx,
            p.dy - s,
          );
        glow(c, p, s * 2.2, const Color(0xFF8FD0FF));
        c.drawPath(drop, fill..color = const Color(0xFF8FD0FF));
        circle(
          c,
          p + Offset(-s * .25, s * .1),
          s * .15,
          const Color(0xFFFFFFFF),
        );
      case Reward.boss:
        glow(c, p, s * 2.2, const Color(0xFFFF8E81));
        circle(c, p - Offset(0, s * .15), s * .85, const Color(0xFFE8DCC8));
        rect(
          c,
          Rect.fromCenter(
            center: p + Offset(0, s * .6),
            width: s * .9,
            height: s * .5,
          ),
          const Color(0xFFE8DCC8),
          2,
        );
        circle(
          c,
          p + Offset(-s * .32, -s * .15),
          s * .24,
          const Color(0xFF3A1F24),
        );
        circle(
          c,
          p + Offset(s * .32, -s * .15),
          s * .24,
          const Color(0xFF3A1F24),
        );
    }
  }

  /// A stone archway on the north wall; its light and icon show the reward.
  /// The stone archway itself, drawn in the plane of the north wall.
  void doorArch(Canvas c, Door door) {
    final x = door.p.dx;
    final tint = rewardColor(door.reward, elite: door.elite);
    final breathe = .75 + sin(clock * 3 + x) * .25;
    rect(c, Rect.fromLTWH(x - 34, 16, 68, 84), const Color(0xFF1A3036), 32);
    rect(c, Rect.fromLTWH(x - 30, 12, 60, 86), const Color(0xFF55736A), 30);
    rect(c, Rect.fromLTWH(x - 22, 24, 44, 74), const Color(0xFF0B171B), 22);
    glow(c, Offset(x, 70), 50, tint.withValues(alpha: breathe));
  }

  /// The floating reward sign in front of a door: ring, icon, elite skull.
  void doorSign(Canvas c, Door door) {
    final tint = rewardColor(door.reward, elite: door.elite);
    final bob = sin(clock * 2.5 + door.p.dx) * 1.5;
    c.drawCircle(
      Offset(0, bob),
      21,
      Paint()
        ..color = tint.withValues(alpha: .85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8,
    );
    rewardIcon(c, Offset(0, bob), door.reward, 11.5);
    if (door.elite) rewardIcon(c, const Offset(23, -23), Reward.boss, 6);
  }

  void pedestal(Canvas c, Pickup reward) {
    const p = Offset.zero;
    final lift = sin(clock * 2.4) * 3;
    oval(c, p.dx, p.dy + 4, 50, 16, const Color(0x66061318));
    rect(
      c,
      Rect.fromCenter(center: p, width: 34, height: 16),
      const Color(0xFF557468),
      6,
    );
    oval(c, p.dx, p.dy - 7, 38, 12, const Color(0xFF7C9A8B));
    final ring = rewardColor(reward.reward, elite: reward.elite);
    c.drawCircle(
      p - Offset(0, 34 + lift),
      19,
      Paint()
        ..color = ring.withValues(alpha: .8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    rewardIcon(c, p - Offset(0, 34 + lift), reward.reward, 11);
  }

  void spring(Canvas c) {
    const p = Offset.zero;
    final full = !run.fountainUsed;
    oval(c, p.dx, p.dy + 10, 112, 40, const Color(0x66061318));
    oval(c, p.dx, p.dy, 104, 46, const Color(0xFF4E6A60));
    oval(c, p.dx, p.dy - 3, 88, 34, const Color(0xFF2A3F45));
    oval(
      c,
      p.dx,
      p.dy - 3,
      80,
      28,
      full ? const Color(0xFF5FA8D8) : const Color(0xFF2E4E62),
    );
    if (full) {
      glow(c, p - const Offset(0, 10), 70, const Color(0xFF8FD0FF));
      for (var i = 0; i < 5; i++) {
        final t = (clock * .8 + i / 5) % 1;
        circle(
          c,
          p + Offset(sin(i * 2.1) * 10, -8 - t * 34),
          2.4 * (1 - t),
          const Color(0xCCE6F6FF),
        );
      }
    }
    rect(
      c,
      Rect.fromCenter(center: p - const Offset(0, 16), width: 12, height: 26),
      const Color(0xFF7C9A8B),
      4,
    );
  }

  /// Maître Crapaud: a merchant toad in a violet cloak, lantern in hand.
  void merchant(Canvas c) {
    const p = Offset.zero;
    final bob = sin(clock * 1.6) * 1.5;
    oval(c, p.dx, p.dy + 6, 120, 34, const Color(0xFF3B2F55));
    oval(c, p.dx, p.dy + 4, 104, 26, const Color(0xFF55457A));
    for (final (i, color) in const [
      Color(0xFFF08AA6),
      Color(0xFF8FD0FF),
      Color(0xFFFFB45E),
    ].indexed) {
      final q = p + Offset(-40 + i * 12.0, 4);
      rect(
        c,
        Rect.fromCenter(center: q - const Offset(0, 6), width: 8, height: 12),
        color,
        3,
      );
      circle(c, q - const Offset(0, 14), 2, const Color(0xFFE8DCC8));
    }
    c.save();
    c.translate(p.dx + 10, p.dy + bob);
    oval(c, 0, -2, 58, 20, const Color(0x66061318));
    final cloak = Path()
      ..moveTo(-24, -34)
      ..quadraticBezierTo(-32, -8, -28, 2)
      ..quadraticBezierTo(0, 10, 28, 2)
      ..quadraticBezierTo(32, -8, 24, -34)
      ..close();
    c.drawPath(cloak, Paint()..color = const Color(0xFF6B5494));
    oval(c, 0, -20, 34, 30, const Color(0xFFCFE0B4));
    oval(c, 0, -42, 50, 32, const Color(0xFF6E9C74));
    circle(c, const Offset(-13, -56), 8, const Color(0xFF6E9C74));
    circle(c, const Offset(13, -56), 8, const Color(0xFF6E9C74));
    circle(c, const Offset(-13, -57), 4, gold);
    circle(c, const Offset(13, -57), 4, gold);
    circle(c, const Offset(-13, -57), 1.8, const Color(0xFF23302C));
    circle(c, const Offset(13, -57), 1.8, const Color(0xFF23302C));
    line(
      c,
      const Offset(-10, -36),
      const Offset(10, -36),
      const Color(0xFF3F5E48),
      2,
    );
    // Tall hat with a gold band.
    rect(c, const Rect.fromLTWH(-20, -70, 40, 5), const Color(0xFF2B2440), 2);
    rect(c, const Rect.fromLTWH(-12, -90, 24, 22), const Color(0xFF2B2440), 3);
    rect(c, const Rect.fromLTWH(-12, -74, 24, 4), gold, 1);
    line(
      c,
      const Offset(30, -60),
      const Offset(30, 4),
      const Color(0xFF916D51),
      3,
    );
    glow(c, const Offset(30, -64), 30, gold);
    rect(c, const Rect.fromLTWH(24, -72, 12, 14), const Color(0xFFFFE7A7), 3);
    c.restore();
    if (run.shopArmed && (run.player - RunModel.merchant).distance < 160) {
      rect(
        c,
        Rect.fromCenter(
          center: p + const Offset(10, -112),
          width: 26,
          height: 22,
        ),
        const Color(0xE6FFF1D6),
        8,
      );
      label(c, '!', p + const Offset(10, -112), 15, const Color(0xFF3B2F55));
    }
  }

  void leaf(Canvas c, Offset p, double angle, double size) {
    c.save();
    c.translate(p.dx, p.dy);
    c.rotate(sin(angle) * .5);
    c.scale(size);
    for (var i = 0; i < 4; i++) {
      final path = Path()
        ..moveTo(0, 8)
        ..quadraticBezierTo(-35 + i * 16, -29 - i * 5, -24 + i * 16, -39)
        ..quadraticBezierTo(8 + i * 3, -15, 0, 8);
      c.drawPath(
        path,
        Paint()..color = Color(i.isEven ? 0xFF234E48 : 0xFF326859),
      );
      line(
        c,
        const Offset(0, 8),
        Offset(-24 + i * 16, -34),
        const Color(0xFF447F67),
        .7,
      );
    }
    c.restore();
  }

  void lantern(Canvas c, Offset p) {
    oval(c, p.dx, p.dy + 9, 34, 15, const Color(0x550B1B22));
    rect(
      c,
      Rect.fromCenter(center: p + const Offset(0, 3), width: 22, height: 17),
      const Color(0xFF526C5D),
      3,
    );
    rect(
      c,
      Rect.fromCenter(center: p - const Offset(0, 10), width: 17, height: 24),
      const Color(0xFF1E383C),
      3,
    );
    glow(c, p - const Offset(0, 13), 40, gold);
    rect(
      c,
      Rect.fromCenter(center: p - const Offset(0, 12), width: 9, height: 14),
      gold,
      2,
    );
    rect(
      c,
      Rect.fromCenter(center: p - const Offset(0, 26), width: 26, height: 6),
      const Color(0xFF658273),
      3,
    );
  }

  void hero(Canvas c, Offset p) {
    c.save();
    c.translate(p.dx, p.dy);
    if (run.invincible > 0 && (clock * 15).floor().isEven) {
      c.restore();
      return;
    }
    final bob = run.moving ? sin(clock * 17) * 2 : sin(clock * 2) * 1.1;
    oval(c, 0, 3, 35, 14, const Color(0x660D2027));
    if (run.veilReady) {
      c.drawCircle(
        const Offset(0, -18),
        30 + sin(clock * 3) * 1.5,
        Paint()
          ..color = mint.withValues(alpha: .45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    glow(c, const Offset(20, -21), 42, gold);
    oval(c, -7, -1, 10, 9, const Color(0xFF162B35));
    oval(c, 7, -1, 10, 9, const Color(0xFF162B35));
    c.translate(0, bob);
    final cloak = Path()
      ..moveTo(-12, -30)
      ..quadraticBezierTo(-16, -12, -20, -6)
      ..quadraticBezierTo(0, 3, 20, -6)
      ..lineTo(11, -30)
      ..close();
    c.drawPath(cloak, Paint()..color = const Color(0xFFDA9971));
    final fold = Path()
      ..moveTo(0, -25)
      ..lineTo(5, -3)
      ..lineTo(18, -6)
      ..lineTo(11, -30)
      ..close();
    c.drawPath(fold, Paint()..color = const Color(0xFFAA6555));
    oval(c, 0, -31, 34, 36, const Color(0xFFF0BA81));
    oval(c, 0, -29, 23, 24, const Color(0xFF263D43));
    oval(c, 0, -26, 18, 15, const Color(0xFFF9E8C2));
    circle(c, const Offset(-4, -27), 1.6, const Color(0xFF34474B));
    circle(c, const Offset(4, -27), 1.6, const Color(0xFF34474B));
    line(
      c,
      const Offset(20, -35),
      const Offset(20, -3),
      const Color(0xFF916D51),
      3,
    );
    line(c, const Offset(20, -35), const Offset(30, -35), gold, 2);
    rect(c, const Rect.fromLTWH(24, -32, 12, 16), const Color(0xFFB88653), 3);
    rect(c, const Rect.fromLTWH(27, -29, 6, 10), const Color(0xFFFFE7A7), 2);
    circle(c, const Offset(-11, -40), 3, gold);
    c.restore();
  }

  void enemy(Canvas c, Enemy e) {
    c.save();
    final bob = sin(clock * 3 + e.p.dx) * 2;
    final shadow = switch (e.kind) {
      Kind.tortoise || Kind.owl => 72.0,
      Kind.broodcap => 40.0,
      Kind.spore => 18.0,
      _ => 32.0,
    };
    oval(c, 0, 3, shadow, shadow / 3, const Color(0x660C2025));
    c.translate(0, bob);
    switch (e.kind) {
      case Kind.mushroom:
        rect(
          c,
          const Rect.fromLTWH(-9, -19, 18, 21),
          const Color(0xFFC3C7A2),
          7,
        );
        oval(c, 0, -23, 39, 27, const Color(0xFFAC759F));
        oval(c, -3, -28, 29, 13, const Color(0xFFCEA2BC));
        circle(c, const Offset(-10, -25), 3, const Color(0xFFE6C4CE));
        circle(c, const Offset(8, -28), 4, const Color(0xFFE6C4CE));
        circle(c, const Offset(-4, -9), 2, const Color(0xFF273C41));
        circle(c, const Offset(4, -9), 2, const Color(0xFF273C41));
      case Kind.moth:
        glow(c, const Offset(0, -19), 25, const Color(0xFFBBBDFF));
        oval(c, -13, -22 + sin(clock * 20) * 3, 20, 9, const Color(0x889FAFD8));
        oval(c, 13, -22 - sin(clock * 20) * 3, 20, 9, const Color(0x889FAFD8));
        oval(c, 0, -18, 19, 25, const Color(0xFF858BBC));
        circle(c, const Offset(0, -11), 6, const Color(0xFFE3D0FF));
        circle(c, const Offset(-4, -24), 2, const Color(0xFFFFE7C0));
        circle(c, const Offset(4, -24), 2, const Color(0xFFFFE7C0));
      case Kind.beetle:
        for (var i = 0; i < 3; i++) {
          line(
            c,
            Offset(-9, -15 + i * 6),
            Offset(-21, -20 + i * 10),
            const Color(0xFF779E96),
            3,
          );
          line(
            c,
            Offset(9, -15 + i * 6),
            Offset(21, -20 + i * 10),
            const Color(0xFF779E96),
            3,
          );
        }
        oval(c, 0, -12, 29, 31, const Color(0xFF477D79));
        oval(c, -3, -17, 19, 19, const Color(0xFF74A59B));
        line(
          c,
          const Offset(0, -26),
          const Offset(0, -1),
          const Color(0xFF315D62),
          2,
        );
        circle(c, const Offset(-5, -5), 2, gold);
        circle(c, const Offset(5, -5), 2, gold);
      case Kind.broodcap:
        // Swollen mother mushroom; its cap pulses before it bursts.
        final swell = 1 + sin(clock * 4 + e.maxHp) * .04;
        rect(
          c,
          const Rect.fromLTWH(-11, -20, 22, 24),
          const Color(0xFFD8CBA6),
          8,
        );
        oval(c, 0, -28, 52 * swell, 36 * swell, const Color(0xFFD08A4E));
        oval(c, -4, -34, 38, 16, const Color(0xFFE9A866));
        for (final d in const [
          Offset(-14, -30),
          Offset(9, -36),
          Offset(15, -24),
          Offset(-3, -40),
        ]) {
          circle(c, d, 3.5, const Color(0xFFFBE2B6));
        }
        circle(c, const Offset(-5, -9), 2.2, const Color(0xFF273C41));
        circle(c, const Offset(5, -9), 2.2, const Color(0xFF273C41));
      case Kind.spore:
        glow(c, const Offset(0, -10), 16, const Color(0xFFFFC98A));
        oval(c, 0, -10, 17, 15, const Color(0xFFE9A866));
        oval(c, -2, -13, 9, 6, const Color(0xFFFBE2B6));
        circle(c, const Offset(-3, -9), 1.5, const Color(0xFF273C41));
        circle(c, const Offset(3, -9), 1.5, const Color(0xFF273C41));
      case Kind.toad:
        // Lantern toad: it inflates while aiming its lob.
        final puff = e.tell > 0 ? 1 + (1 - e.tell / .9) * .25 : 1.0;
        oval(c, -12, -4, 14, 9, const Color(0xFF4E7A5C));
        oval(c, 12, -4, 14, 9, const Color(0xFF4E7A5C));
        oval(c, 0, -14, 36 * puff, 26 * puff, const Color(0xFF5E9170));
        oval(c, 0, -8, 24 * puff, 12 * puff, const Color(0xFFCFE0B4));
        circle(c, const Offset(-9, -26), 5, const Color(0xFF5E9170));
        circle(c, const Offset(9, -26), 5, const Color(0xFF5E9170));
        circle(c, const Offset(-9, -27), 2.4, gold);
        circle(c, const Offset(9, -27), 2.4, gold);
        glow(c, const Offset(0, -30), 20, const Color(0xFFFFB07A));
        rect(c, const Rect.fromLTWH(-4, -36, 8, 9), const Color(0xFFFFB07A), 2);
      case Kind.tortoise:
        for (final x in [-27.0, 27.0]) {
          oval(c, x, -4, 18, 23, const Color(0xFF8AA891));
          oval(c, x, -30, 18, 20, const Color(0xFF8AA891));
        }
        oval(c, 0, -21, 67, 62, const Color(0xFF557F70));
        oval(c, 0, -27, 54, 46, const Color(0xFF86A084));
        for (var i = 0; i < 5; i++) {
          final a = i * pi * 2 / 5;
          oval(
            c,
            cos(a) * 18,
            -27 + sin(a) * 13,
            17,
            17,
            const Color(0xFF668D77),
          );
        }
        rect(
          c,
          const Rect.fromLTWH(-16, -67, 32, 33),
          const Color(0xFF456660),
          5,
        );
        rect(
          c,
          const Rect.fromLTWH(-23, -72, 46, 9),
          const Color(0xFF9AA78B),
          3,
        );
        glow(c, const Offset(0, -53), 35, mint);
        rect(c, const Rect.fromLTWH(-5, -61, 10, 18), mint, 4);
        oval(c, 0, 4, 25, 22, const Color(0xFFA0B399));
        circle(c, const Offset(-6, 2), 3, gold);
        circle(c, const Offset(6, 2), 3, gold);
      case Kind.owl:
        final flap = sin(clock * 5) * 6;
        final enraged = e.hp < e.maxHp / 2;
        final eyes = enraged
            ? const Color(0xFFFF8E81)
            : const Color(0xFFBFD0FF);
        glow(c, const Offset(0, -30), 70, eyes);
        for (final side in [-1.0, 1.0]) {
          final wing = Path()
            ..moveTo(side * 16, -44)
            ..quadraticBezierTo(side * 58, -40 + flap, side * 52, -2 + flap)
            ..quadraticBezierTo(side * 34, -12, side * 14, -10)
            ..close();
          c.drawPath(wing, Paint()..color = const Color(0xFF3E4670));
        }
        oval(c, 0, -26, 48, 58, const Color(0xFF59628F));
        oval(c, 0, -16, 30, 34, const Color(0xFFB9B3D6));
        for (var i = 0; i < 3; i++) {
          oval(c, 0, -22 + i * 8.0, 16, 3, const Color(0x5559628F));
        }
        final ear = Path()
          ..moveTo(-20, -44)
          ..lineTo(-15, -64)
          ..lineTo(-6, -50)
          ..lineTo(6, -50)
          ..lineTo(15, -64)
          ..lineTo(20, -44)
          ..close();
        c.drawPath(ear, Paint()..color = const Color(0xFF59628F));
        for (final x in [-10.0, 10.0]) {
          circle(c, Offset(x, -40), 10, const Color(0xFF232A4A));
          glow(c, Offset(x, -40), 18, eyes);
          circle(c, Offset(x, -40), 6, eyes);
          circle(c, Offset(x, -41), 2, const Color(0xFFFFFFFF));
        }
        final beak = Path()
          ..moveTo(-4, -32)
          ..lineTo(4, -32)
          ..lineTo(0, -24)
          ..close();
        c.drawPath(beak, Paint()..color = gold);
        // A crescent crown marks the queen of midnight.
        circle(c, const Offset(0, -70), 7, gold);
        circle(c, const Offset(3, -72), 6, const Color(0xFF59628F));
    }
    if (e.slow > 0) {
      circle(
        c,
        Offset(0, -e.radius * .8),
        e.radius + 3,
        const Color(0x3398C8FF),
      );
    }
    if (e.flash > 0) {
      circle(c, const Offset(0, -15), e.radius, const Color(0x66FFF2CC));
    }
    if (e.hp < e.maxHp && !e.boss) {
      rect(c, const Rect.fromLTWH(-15, -48, 30, 3), const Color(0xFF153237), 2);
      rect(c, Rect.fromLTWH(-15, -48, 30 * max(0, e.hp / e.maxHp), 3), mint, 2);
    }
    c.restore();
  }
}
