import 'dart:math';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';
import 'model.dart';

const gold = Color(0xFFFFD18A);
const mint = Color(0xFF8DE1C2);

class GardenGame extends Game {
  final RunModel run;
  final void Function() refresh;
  GardenGame(this.run, this.refresh);
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
    garden(c);
    final showPreview = run.phase == Phase.title;
    final actors = <({double y, void Function() draw})>[
      (y: run.player.dy, draw: () => hero(c, run.player)),
      for (final e in run.enemies) (y: e.p.dy, draw: () => enemy(c, e)),
      if (showPreview) ...[
        (y: 200, draw: () => enemy(c, Enemy(const Offset(95, 200), 0, 30, 2))),
        (y: 220, draw: () => enemy(c, Enemy(const Offset(345, 220), 1, 30, 2))),
        (y: 475, draw: () => enemy(c, Enemy(const Offset(330, 475), 2, 40, 2))),
      ],
    ]..sort((a, b) => a.y.compareTo(b.y));
    for (final e in run.enemies) {
      if (e.tell > 0) {
        if (e.type == 3) {
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
            e.p + e.aim * (e.type == 2 ? 175 : 140),
            const Color(0x55FF9F86),
            e.type == 2 ? 22 : 3,
          );
        }
      }
    }
    for (final actor in actors) {
      actor.draw();
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
        run.wave == 5 ? 'LE SANCTUAIRE S’ÉVEILLE' : 'VAGUE ${run.wave}',
        const Offset(220, 296),
        18,
        gold,
      );
      label(
        c,
        run.wave == 5 ? 'Garde tes distances.' : 'Protège la lumière.',
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
    c.drawRect(
      const Rect.fromLTWH(0, 0, 440, 640),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF162C34), Color(0xFF254640), Color(0xFF132F32)],
        ).createShader(const Rect.fromLTWH(0, 0, 440, 640)),
    );
    // Raised stone edging and staggered, mossy paving.
    rect(c, const Rect.fromLTWH(17, 60, 406, 560), const Color(0xFF0C252B), 25);
    rect(c, const Rect.fromLTWH(20, 57, 400, 550), const Color(0xFF416057), 23);
    rect(c, const Rect.fromLTWH(27, 63, 386, 540), const Color(0xFF28453F), 19);
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
        final colors = [
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
          const Color(0x184EE3BD),
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
    c.restore();
    final center = const Offset(220, 320);
    c.drawCircle(
      center,
      95,
      Paint()
        ..color = const Color(0x163ED8B1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    c.drawCircle(
      center,
      84,
      Paint()
        ..color = const Color(0x163ED8B1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    for (var i = 0; i < 8; i++) {
      final a = i * pi / 4;
      circle(
        c,
        center + Offset(cos(a), sin(a)) * 95,
        3,
        const Color(0x305CE1BF),
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
    c.translate(e.p.dx, e.p.dy);
    final bob = sin(clock * 3 + e.p.dx) * 2;
    oval(
      c,
      0,
      3,
      e.type == 3 ? 72 : 32,
      e.type == 3 ? 24 : 12,
      const Color(0x660C2025),
    );
    c.translate(0, bob);
    if (e.type == 0) {
      rect(c, const Rect.fromLTWH(-9, -19, 18, 21), const Color(0xFFC3C7A2), 7);
      oval(c, 0, -23, 39, 27, const Color(0xFFAC759F));
      oval(c, -3, -28, 29, 13, const Color(0xFFCEA2BC));
      circle(c, const Offset(-10, -25), 3, const Color(0xFFE6C4CE));
      circle(c, const Offset(8, -28), 4, const Color(0xFFE6C4CE));
      circle(c, const Offset(-4, -9), 2, const Color(0xFF273C41));
      circle(c, const Offset(4, -9), 2, const Color(0xFF273C41));
    } else if (e.type == 1) {
      glow(c, const Offset(0, -19), 25, const Color(0xFFBBBDFF));
      oval(c, -13, -22 + sin(clock * 20) * 3, 20, 9, const Color(0x889FAFD8));
      oval(c, 13, -22 - sin(clock * 20) * 3, 20, 9, const Color(0x889FAFD8));
      oval(c, 0, -18, 19, 25, const Color(0xFF858BBC));
      circle(c, const Offset(0, -11), 6, const Color(0xFFE3D0FF));
      circle(c, const Offset(-4, -24), 2, const Color(0xFFFFE7C0));
      circle(c, const Offset(4, -24), 2, const Color(0xFFFFE7C0));
    } else if (e.type == 2) {
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
    } else {
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
      rect(c, const Rect.fromLTWH(-23, -72, 46, 9), const Color(0xFF9AA78B), 3);
      glow(c, const Offset(0, -53), 35, mint);
      rect(c, const Rect.fromLTWH(-5, -61, 10, 18), mint, 4);
      oval(c, 0, 4, 25, 22, const Color(0xFFA0B399));
      circle(c, const Offset(-6, 2), 3, gold);
      circle(c, const Offset(6, 2), 3, gold);
    }
    if (e.flash > 0) {
      circle(c, const Offset(0, -15), e.radius, const Color(0x66FFF2CC));
    }
    if (e.hp < e.maxHp && e.type != 3) {
      rect(c, const Rect.fromLTWH(-15, -48, 30, 3), const Color(0xFF153237), 2);
      rect(c, Rect.fromLTWH(-15, -48, 30 * max(0, e.hp / e.maxHp), 3), mint, 2);
    }
    c.restore();
  }
}
