# Sotto

Sotto is a private, local-first journal organized like a daily binder. Each
recorded date has one pinned Daily Journal, a gratitude footer, a shared mood
check-in, and room for any number of separate additional entries. Journal text,
gratitude, mood coordinates, and preferences stay on-device.

## Run

```sh
flutter pub get
flutter run -d macos
```

Before the configured evening time, Sotto opens directly to an unfinished Daily
Journal. In the evening it asks for mood first. Once both are recorded, the
horizontal binder becomes home; mood and writing remain editable at any time.

## Architecture

- `lib/models` — journal days, day entries, mood check-ins, phases, and cursors
- `lib/services` — schema-v3 SQLite storage and legacy migration
- `lib/providers` — time-aware routing, editor state, and binder pagination
- `lib/ui` — mood dial, vertical entry stack, and horizontal binder zooms

Desktop uses `sqflite_common_ffi` where needed; Apple and Android targets use
the native `sqflite` implementation. Drafts save after 700ms of inactivity.
Recorded dates paginate with stable date-key cursors, while day/week/month views
retain the focused date as their zoom anchor. AI prompts, summaries, tagging,
and embeddings are intentionally outside this version.

## Verify

```sh
flutter analyze
flutter test
flutter build macos --debug
```

Android source is generated, but building it requires an installed Android SDK.
Windows release validation requires a Windows host.
