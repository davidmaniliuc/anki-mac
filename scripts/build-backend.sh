#!/usr/bin/env bash
# Builds the Rust bridge and regenerates every Swift binding from anki/proto.
# Builds upstream's web assets too.
# Run after cloning and after bumping the anki submodule.
# Needs ninja (brew install ninja) for the web build.
set -euo pipefail
cd "$(dirname "$0")/.."

GEN=AnkiKit/Sources/AnkiKit/Generated
FRAMEWORK=AnkiKit/Frameworks/AnkiBridge.xcframework

# Start from upstream's lockfile so rslib gets the dependency versions it ships with.
cp anki/Cargo.lock Cargo.lock

cargo build --release -p anki_bridge
mkdir -p "$GEN/Protos"
cargo run --release -q -p swiftgen -- out/descriptors.bin "$GEN/BackendServices.swift"

rm -rf "$GEN/Protos"/*
protoc --proto_path=anki/proto \
  --swift_opt=Visibility=Public \
  --swift_opt=FileNaming=PathToUnderscores \
  --swift_out="$GEN/Protos" \
  anki/proto/anki/*.proto

rm -rf "$FRAMEWORK"
xcodebuild -create-xcframework \
  -library target/release/libanki_bridge.a \
  -headers bridge/include \
  -output "$FRAMEWORK" >/dev/null
echo "backend ready: $FRAMEWORK"

# Upstream's web assets (reviewer, MathJax, Svelte pages) for the app's card view.
(cd anki && ./ninja qt:aqt:data:web)
echo "web assets ready: anki/out/qt/_aqt/data/web"
