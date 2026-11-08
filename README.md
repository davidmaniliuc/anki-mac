# anki-mac

A native macOS frontend for [Anki](https://github.com/ankitects/anki), written in SwiftUI on top of the upstream Rust core (`rslib`).

- `anki/` is the upstream repo as a git submodule. Backend logic, scheduling, sync and the collection format all come from there, unchanged.
- `bridge/` is a small Rust staticlib that exposes `rslib` through a C API (open, close, run method), the same approach as AnkiDroid's `rslib-bridge`.
- `bench/` holds the benchmarks. The baseline is the official Anki desktop app; every change gets measured against it.

- `swiftgen/` generates a Swift method for every backend RPC, with the service and method indices from upstream's `proto_gen`.
- `AnkiKit/` is the Swift package: `AnkiBackend`, the generated bindings, and `ankikit-bench`.
- `App/` is the SwiftUI app (`project.yml` for XcodeGen). Every colour, size and spacing value is in `App/AnkiMac/Theme.swift`. Cards are shown in a WKWebView running upstream's own `reviewer.js` and CSS, served through an `anki://` scheme handler that also serves the collection's media. Audio plays natively.

## Building

Requires Xcode 26+, Rust (rustup installs the toolchain upstream pins), Node (for upstream's web build), and `brew install protobuf swift-protobuf ninja xcodegen`.

```sh
git clone --recurse-submodules https://github.com/davidmaniliuc/anki-mac
cd anki-mac
./scripts/build-backend.sh     # Rust bridge, xcframework, Swift bindings, web assets
./scripts/build-app.sh         # generates App/AnkiMac.xcodeproj, builds out/app/AnkiMac.app
```

The app keeps its own collection in `~/Library/Application Support/AnkiMac/User 1/`. To open a different one (always a copy, never the profile the official app uses), pass `-CollectionPath /path/to/collection.anki2`.

Updating to a new Anki release: check out the new tag in `anki/`, rerun `scripts/build-backend.sh` and `scripts/build-app.sh`, and fix whatever the Swift compiler flags.

## License

AGPL-3.0-or-later, same as Anki.
