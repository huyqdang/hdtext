#!/bin/bash
# Hardware check for microphone capture: records 4 s from every input device (or the UIDs given)
# through the app's AudioCaptureEngine; exits non-zero if any device delivers much less audio.
# Usage: scripts/mic-check.sh [device-uid ...]
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$PROJECT_DIR/HDText/Services"
OUT="$(mktemp -d)/mic-check"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcrun swiftc -O -o "$OUT" "$PROJECT_DIR/scripts/mic-check/main.swift" \
    "$SRC/Audio/AudioCaptureEngine.swift" "$SRC/Util/HDLog.swift"
"$OUT" "$@" 2>/dev/null
