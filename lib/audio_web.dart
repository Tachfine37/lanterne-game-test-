import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'model.dart';

/// Every sound is built from oscillators and a noise buffer: no assets.
class Sound {
  web.AudioContext? _context;
  web.GainNode? _master, _musicBus;
  web.AudioBuffer? _noise;
  Timer? _music;
  bool _muted = false;
  int _beat = 0, _biome = 0;
  final _lastPlayed = <Sfx, int>{};
  final _random = Random();
  final _clock = Stopwatch()..start();

  bool get muted => _muted;
  set muted(bool value) {
    _muted = value;
    _master?.gain.value = value ? 0 : .8;
  }

  /// Created lazily from a user gesture so browsers allow playback.
  web.AudioContext? get _audio {
    try {
      final context = _context ??= web.AudioContext();
      if (_master == null) {
        _master = context.createGain()..gain.value = _muted ? 0 : .8;
        _master!.connect(context.destination);
        _musicBus = context.createGain()..gain.value = .55;
        _musicBus!.connect(_master!);
        final length = context.sampleRate.round();
        _noise = context.createBuffer(1, length, context.sampleRate);
        final data = Float32List(length);
        for (var i = 0; i < length; i++) {
          data[i] = _random.nextDouble() * 2 - 1;
        }
        _noise!.copyToChannel(data.toJS, 0);
      }
      if (context.state == 'suspended') context.resume();
      return context;
    } catch (_) {
      return null;
    }
  }

  void _tone(
    double from,
    double to,
    double duration, {
    String wave = 'sine',
    double volume = .06,
    double delay = 0,
    web.AudioNode? bus,
  }) {
    final context = _audio;
    if (context == null) return;
    final start = context.currentTime + delay;
    final oscillator = context.createOscillator()..type = wave;
    oscillator.frequency
      ..setValueAtTime(from, start)
      ..exponentialRampToValueAtTime(max(20, to), start + duration);
    final gain = context.createGain();
    gain.gain
      ..setValueAtTime(0.0001, start)
      ..linearRampToValueAtTime(volume, start + .012)
      ..exponentialRampToValueAtTime(0.0001, start + duration);
    oscillator.connect(gain);
    gain.connect(bus ?? _master!);
    oscillator.start(start);
    oscillator.stop(start + duration + .05);
  }

  void _hiss(double duration, double cutoff, {double volume = .08}) {
    final context = _audio;
    if (context == null) return;
    final start = context.currentTime;
    final source = context.createBufferSource()..buffer = _noise;
    final filter = context.createBiquadFilter()..type = 'lowpass';
    filter.frequency
      ..setValueAtTime(cutoff, start)
      ..exponentialRampToValueAtTime(80, start + duration);
    final gain = context.createGain();
    gain.gain
      ..setValueAtTime(volume, start)
      ..exponentialRampToValueAtTime(0.0001, start + duration);
    source.connect(filter);
    filter.connect(gain);
    gain.connect(_master!);
    source.start(start);
    source.stop(start + duration + .05);
  }

  /// Call from a tap handler: iOS Safari only starts audio inside a gesture.
  void unlock() => _audio;

  void play(Sfx sfx) {
    if (_muted) return;
    // Rapid-fire cues (hits, shots) are throttled so they never turn to noise.
    final now = _clock.elapsedMilliseconds;
    final gap = switch (sfx) {
      Sfx.hit || Sfx.crit || Sfx.kill || Sfx.explode => 45,
      Sfx.shoot => 90,
      _ => 0,
    };
    if (now - (_lastPlayed[sfx] ?? -1000) < gap) return;
    _lastPlayed[sfx] = now;
    final pitch = 1 + (_random.nextDouble() - .5) * .08;
    switch (sfx) {
      case Sfx.shoot:
        _tone(900 * pitch, 620 * pitch, .07, volume: .025);
      case Sfx.hit:
        _tone(320 * pitch, 170, .06, wave: 'triangle', volume: .05);
      case Sfx.crit:
        _tone(1200 * pitch, 700, .09, wave: 'square', volume: .025);
        _tone(420, 200, .08, wave: 'triangle', volume: .05);
      case Sfx.kill:
        _tone(520 * pitch, 1040 * pitch, .1, volume: .05);
        _tone(780 * pitch, 1300 * pitch, .12, volume: .03, delay: .05);
      case Sfx.hurt:
        _tone(220, 70, .25, wave: 'sawtooth', volume: .06);
        _hiss(.2, 1800, volume: .06);
      case Sfx.shield:
        _tone(600, 1500, .25, wave: 'triangle', volume: .05);
      case Sfx.explode:
        _hiss(.32, 1200, volume: .09);
        _tone(120, 45, .3, volume: .08);
      case Sfx.lob:
        _tone(180, 420, .18, wave: 'triangle', volume: .04);
      case Sfx.bossAttack:
        _tone(110, 55, .4, wave: 'square', volume: .035);
        _hiss(.25, 600, volume: .04);
      case Sfx.waveStart:
        _tone(392, 392, .3, volume: .045);
        _tone(587, 587, .45, volume: .04, delay: .14);
      case Sfx.gift:
        for (final (i, note) in [523.0, 659.0, 784.0, 1047.0].indexed) {
          _tone(note, note, .3, volume: .045, delay: i * .07);
        }
      case Sfx.win:
        for (final (i, note) in [523.0, 659.0, 784.0, 1047.0, 1319.0].indexed) {
          _tone(note, note, .6, wave: 'triangle', volume: .06, delay: i * .12);
        }
      case Sfx.lose:
        for (final (i, note) in [392.0, 330.0, 262.0, 196.0].indexed) {
          _tone(
            note,
            note * .98,
            .5,
            wave: 'triangle',
            volume: .06,
            delay: i * .18,
          );
        }
    }
  }

  /// Soft pentatonic arpeggio; the second biome plays lower and slower.
  void music({required bool on, int biome = 0}) {
    _biome = biome;
    if (!on) {
      _music?.cancel();
      _music = null;
      return;
    }
    if (_music != null) return;
    _music = Timer.periodic(const Duration(milliseconds: 420), (_) {
      if (_muted || _context == null) return;
      final root = _biome == 0 ? 293.66 : 246.94;
      const scale = [0, 3, 5, 7, 10, 12, 15];
      _beat++;
      if (_beat % 8 == 1) {
        _tone(root / 2, root / 2, 3.2, volume: .05, bus: _musicBus);
      }
      if (_random.nextDouble() < (_biome == 0 ? .7 : .55)) {
        final step = scale[_random.nextInt(scale.length)];
        final note = root * pow(2, step / 12);
        _tone(note, note, 1.4, volume: .028, bus: _musicBus);
      }
    });
  }

  void dispose() {
    _music?.cancel();
    _context?.close();
  }
}
