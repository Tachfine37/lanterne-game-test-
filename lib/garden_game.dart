import 'dart:math';
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
  double get scale => min(size.x / 440, size.y / 640);
  Offset get inset =>
      Offset((size.x - 440 * scale) / 2, (size.y - 640 * scale) / 2);
  @override
  Color backgroundColor() => const Color(0xFF122C30);
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
    c.clipRect(const Rect.fromLTWH(0, 0, 440, 640));
    if (run.shake > 0 && run.phase == Phase.playing) {
      final power = run.shake * 9;
      c.translate(
        (shaker.nextDouble() - .5) * power,
        (shaker.nextDouble() - .5) * power,
      );
    }
    garden(c);
    final showPreview = run.phase == Phase.title;
    final actors = <({double y, void Function() draw})>[
      (y: run.player.dy, draw: () => hero(c, run.player)),
      for (final e in run.enemies) (y: e.p.dy, draw: () => enemy(c, e)),
      if (showPreview) ...[
        (y: 200, draw: () => preview(c, const Offset(95, 200), Kind.mushroom)),
        (y: 220, draw: () => preview(c, const Offset(345, 220), Kind.moth)),
        (y: 475, draw: () => preview(c, const Offset(330, 475), Kind.beetle)),
      ],
    ]..sort((a, b) => a.y.compareTo(b.y));
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
      final k = s.progress;
      c.drawCircle(
        s.to,
        34,
        Paint()
          ..color = const Color(0x88FF8E81)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      circle(c, s.to, 34 * k, const Color(0x33FF8E81));
    }
    for (final actor in actors) {
      actor.draw();
    }
    for (final s in run.shells) {
      final p = s.position - const Offset(0, 10);
      glow(c, p, 18, const Color(0xFFFFB07A));
      circle(c, p, 7, const Color(0xFFE08A5A));
      circle(c, p - const Offset(2, 2), 3, const Color(0xFFFFE3B8));
    }
    for (final r in run.rings) {
      final k = 1 - r.life;
      c.drawCircle(
        r.p - const Offset(0, 8),
        r.size * (.35 + .65 * k),
        Paint()
          ..color = (r.hostile ? const Color(0xFFFF9F86) : gold).withValues(
            alpha: r.life.clamp(0, 1) * .8,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5 * r.life + 1,
      );
    }
    for (final b in run.bolts) {
      final color = b.hostile ? const Color(0xFFFF938C) : gold;
      final p = b.p - const Offset(0, 12);
      line(
        c,
        p,
        p - unit(b.v) * (b.hostile ? 8 : 14),
        color.withValues(alpha: .4),
        b.hostile ? 7 : 5,
      );
      glow(c, p, 15, color);
      circle(c, p, b.hostile ? 5 : 4, color);
      circle(c, p, 2, const Color(0xFFFFF5DD));
    }
    for (var i = 0; i < run.orbits; i++) {
      final a = run.orbitClock * 3 + i * pi * 2 / run.orbits;
      final p = run.player + Offset(cos(a), sin(a)) * 52 - const Offset(0, 12);
      glow(c, p, 22, mint);
      circle(c, p, 6, mint);
      circle(c, p, 2, const Color(0xFFFFFFFF));
    }
    for (final s in run.sparks) {
      circle(
        c,
        s.p - const Offset(0, 10),
        max(0, s.life) * 3,
        (s.green ? mint : gold).withValues(alpha: s.life.clamp(0, 1)),
      );
    }
    for (final p in run.popups) {
      label(
        c,
        p.crit ? '${p.text}!' : p.text,
        p.p,
        p.crit ? 17 : 12,
        (p.crit ? const Color(0xFFFFB45E) : const Color(0xFFFFF1D6)).withValues(
          alpha: p.life.clamp(0, 1),
        ),
      );
    }
    // Fireflies and foreground foliage frame the playable area.
    for (var i = 0; i < 15; i++) {
      final x = 25.0 + (i * 97) % 395 + sin(clock * .5 + i) * 9;
      final y = 85.0 + (i * 137) % 490 + cos(clock * .4 + i) * 8;
      circle(
        c,
        Offset(x, y),
        1.4,
        mint.withValues(alpha: .2 + (.5 + .5 * sin(clock + i)) * .45),
      );
    }
    for (var i = 0; i < 9; i++) {
      leaf(c, Offset(i * 58.0 - 10, 637), i.toDouble(), 1.2);
    }
    if (run.phase == Phase.playing && run.grace > 0) {
      rect(
        c,
        const Rect.fromLTWH(76, 268, 288, 78),
        const Color(0xE6153033),
        18,
      );
      label(
        c,
        run.wave == 5
            ? 'LE SANCTUAIRE S’ÉVEILLE'
            : run.wave == totalWaves
            ? 'MINUIT APPROCHE'
            : 'VAGUE ${run.wave}',
        const Offset(220, 296),
        18,
        gold,
      );
      label(
        c,
        isBossWave(run.wave)
            ? 'Garde tes distances.'
            : run.wave == 6
            ? 'Le bassin de lune s’ouvre.'
            : 'Protège la lumière.',
        const Offset(220, 323),
        13,
        mint,
      );
    }
    if (stickOrigin != null && run.phase == Phase.playing) {
      final a = (stickOrigin! - inset) / scale;
      final b = (stickEnd! - inset) / scale;
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
    c.restore();
  }

  void garden(Canvas c) {
    final moon = run.phase != Phase.title && run.biome == 1;
    final accent = moon ? const Color(0xFFA9B8FF) : const Color(0xFF3ED8B1);
    c.drawRect(
      const Rect.fromLTWH(0, 0, 440, 640),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: moon
              ? const [Color(0xFF161F38), Color(0xFF22304F), Color(0xFF121B30)]
              : const [Color(0xFF162C34), Color(0xFF254640), Color(0xFF132F32)],
        ).createShader(const Rect.fromLTWH(0, 0, 440, 640)),
    );
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
    // Distant shrine, moonstone door and lanterns.
    oval(c, 220, 67, 142, 29, const Color(0x5505141D));
    rect(c, const Rect.fromLTWH(168, 20, 104, 48), const Color(0xFF193037), 8);
    rect(c, const Rect.fromLTWH(183, 14, 74, 49), const Color(0xFF46635B), 30);
    rect(c, const Rect.fromLTWH(193, 22, 54, 43), const Color(0xFF173537), 23);
    glow(c, const Offset(220, 39), 42, mint);
    label(c, '✦', const Offset(220, 40), 28, mint);
    for (final p in [
      const Offset(46, 102),
      const Offset(394, 102),
      const Offset(43, 567),
      const Offset(397, 567),
    ]) {
      lantern(c, p);
    }
    for (var i = 0; i < 12; i++) {
      leaf(
        c,
        Offset(i.isEven ? 12 : 430, 100 + i * 45.0),
        i.toDouble(),
        .8 + (i % 3) * .2,
      );
    }
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

  void preview(Canvas c, Offset p, Kind kind) =>
      enemy(c, Enemy(p, kind, 30, 2));

  void enemy(Canvas c, Enemy e) {
    c.save();
    c.translate(e.p.dx, e.p.dy);
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
