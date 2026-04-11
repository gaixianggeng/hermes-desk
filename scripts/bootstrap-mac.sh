#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "[1/3] Generating Xcode project with xcodegen..."
xcodegen generate

echo "[2/3] Running AppCore tests..."
(cd Packages/AppCore && swift test)

echo "[3/3] Running HermesKit tests..."
(cd Packages/HermesKit && swift test)

echo
printf 'Bootstrap complete. If xcodebuild still fails on this machine, check Xcode first-launch state.\n'
