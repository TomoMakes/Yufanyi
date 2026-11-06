#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$1"
mkdir -p "$SCRATCH"
xcrun swiftc -swift-version 5 -default-isolation MainActor -parse-as-library \
  -module-cache-path "$SCRATCH/module-cache" \
  "$ROOT/scripts/LunaDialogueRegression.swift" \
  "$ROOT/ScreenTranslate/Core/OCR/OCRProvider.swift" \
  "$ROOT/ScreenTranslate/Core/OCR/VisionOCRProvider.swift" \
  "$ROOT/ScreenTranslate/Core/Translation/TranslationProvider.swift" \
  "$ROOT/ScreenTranslate/Core/Translation/LunaPretranslationProvider.swift" \
  "$ROOT/ScreenTranslate/Core/TranslationCoordinator.swift" \
  "$ROOT/ScreenTranslate/Core/Live/LiveTranslationSession.swift" \
  "$ROOT/ScreenTranslate/Core/Live/LiveTextStabilizer.swift" \
  "$ROOT/ScreenTranslate/Core/Live/LiveFrameSource.swift" \
  "$ROOT/ScreenTranslate/Core/Live/LiveOCRPolicy.swift" \
  "$ROOT/ScreenTranslate/Core/Live/FrameFingerprint.swift" \
  -o "$SCRATCH/regression"
"$SCRATCH/regression" "$@"
