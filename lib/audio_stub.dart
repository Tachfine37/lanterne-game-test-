import 'model.dart';

class Sound {
  bool muted = false;
  void unlock() {}
  void play(Sfx sfx) {}
  void music({required bool on, int biome = 0}) {}
  void dispose() {}
}
