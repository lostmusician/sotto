# Sotto

Sotto is a private, local-first journal built around a quiet session ritual.
Each session moves deliberately through Arrival, Writing, and Reflection, with
a chronological Archive for returning to earlier days. Journal text, mood
coordinates, questions, and replies stay on-device.

## Run

```sh
flutter pub get
flutter run -d macos
```

Reflection begins only when the writer chooses **Close session**. Without a
model, Sotto uses a clearly labelled deterministic fallback question and never
blocks session completion.
To enable on-device inference, provide an app-accessible GGUF path:

```sh
flutter run -d macos --dart-define=SOTTO_MODEL_PATH=/absolute/path/model.gguf
```

Model files are intentionally not bundled: they are large and have their own
licenses. The `lib_llama_cpp` backend runs inference in a dedicated isolate and
supports Android, iOS, macOS, and Windows.

## Architecture

- `lib/models` — entries, daily check-ins, phases, and archive cursors
- `lib/services` — schema-v2 SQLite storage and local reflection adapters
- `lib/providers` — explicit session transitions and archive pagination state
- `lib/ui` — mood dial, immersive editor, reflection close, and archive zooms

Desktop uses `sqflite_common_ffi` where needed; Apple and Android targets use
the native `sqflite` implementation. Drafts save after 700ms of inactivity.
Archive pages use a stable `(closed_at, id)` cursor, and entry/week/month views
retain relative scroll context while zooming. Theme analysis and embedding
interfaces are reserved for a later semantic-graph milestone.

## Verify

```sh
flutter analyze
flutter test
flutter build macos --debug
```

Android source is generated, but building it requires an installed Android SDK.
Windows release validation requires a Windows host.
