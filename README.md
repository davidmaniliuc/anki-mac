# anki-mac

A native macOS frontend for [Anki](https://github.com/ankitects/anki), written in SwiftUI on top of the upstream Rust core (`rslib`).

- `anki/` is the upstream repo as a git submodule. Backend logic, scheduling, sync and the collection format all come from there, unchanged.
- `bridge/` is a small Rust staticlib that exposes `rslib` through a C API (open, close, run method), the same approach as AnkiDroid's `rslib-bridge`.
- `bench/` holds the benchmarks. The baseline is the official Anki desktop app; every change gets measured against it.

- `swiftgen/` generates a Swift method for every backend RPC, with the service and method indices from upstream's `proto_gen`.
- `AnkiKit/` is the Swift package: `AnkiBackend`, the generated bindings, and `ankikit-bench`.

## Building

Requires Xcode 26+, Rust (rustup installs the toolchain upstream pins), and `brew install protobuf swift-protobuf`.

```sh
git clone --recurse-submodules https://github.com/davidmaniliuc/anki-mac
cd anki-mac
./scripts/build-backend.sh     # Rust bridge, xcframework, Swift bindings
cd AnkiKit && swift build -c release
```

Updating to a new Anki release: check out the new tag in `anki/`, rerun `scripts/build-backend.sh`, and fix whatever the Swift compiler flags.

## License

AGPL-3.0-or-later, same as Anki.
