/// Synthesized sound effects and ambient music. Web Audio in the browser,
/// silent everywhere else (tests, and native builds until assets exist).
library;

export 'audio_stub.dart' if (dart.library.js_interop) 'audio_web.dart';
