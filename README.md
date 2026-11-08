# anki-mac

A native macOS frontend for [Anki](https://github.com/ankitects/anki), written in SwiftUI on top of the upstream Rust core (`rslib`).

- `anki/` is the upstream repo as a git submodule. Backend logic, scheduling, sync and the collection format all come from there, unchanged.
- `bridge/` is a small Rust staticlib that exposes `rslib` through a C API (open, close, run method), the same approach as AnkiDroid's `rslib-bridge`.
- `bench/` holds the benchmarks. The baseline is the official Anki desktop app; every change gets measured against it.

Updating to a new Anki release: bump the submodule, rebuild the bridge, regenerate the Swift bindings, and fix whatever the compiler flags.

## License

AGPL-3.0-or-later, same as Anki.
