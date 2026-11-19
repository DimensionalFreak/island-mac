#!/bin/bash
# Builds Island.app and Island-mac.zip. Runs on a Mac (GitHub's cloud Mac does this).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf build
mkdir -p build/Island.app/Contents/MacOS
cp "$BIN/Island" build/Island.app/Contents/MacOS/Island
cp Info.plist build/Island.app/Contents/Info.plist

# Ad-hoc signature (no paid Apple account): macOS still asks you to approve it once.
codesign --force --deep --sign - build/Island.app

(cd build && ditto -c -k --keepParent Island.app Island-mac.zip)
ls -l build
