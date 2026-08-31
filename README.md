# Sotto

Sotto is a private, local-first journal with a quiet 1-bit writing companion.
The current MVP stores entries and reflections in SQLite, tracks writing
progress with Riverpod, and generates a short Socratic question after ten idle
seconds.

## Run

```sh
flutter pub get
flutter run -d macos
```

Without a model, Sotto uses a clearly labelled deterministic demo reflection.
To enable on-device inference, provide an app-accessible GGUF path:

```sh
flutter run -d macos --dart-define=SOTTO_MODEL_PATH=/absolute/path/model.gguf
```

Model files are intentionally not bundled: they are large and have their own
licenses. The `lib_llama_cpp` backend runs inference in a dedicated isolate and
supports Android, iOS, macOS, and Windows.

## Architecture

- `lib/models` — journal and annotation value models
- `lib/services` — cross-platform SQLite and local AI adapters
- `lib/providers` — Riverpod session, word-count, and typing state
- `lib/ui` — distraction-free editor and custom-painted pixel room

Desktop uses `sqflite_common_ffi` where needed; Apple and Android targets use
the native `sqflite` implementation. The editor saves after 700ms of inactivity
and asks the companion to reflect on only the last 150 words after 10 seconds.

## Verify

```sh
flutter analyze
flutter test
flutter build macos --debug
```

Android source is generated, but building it requires an installed Android SDK.
Windows release validation requires a Windows host.
