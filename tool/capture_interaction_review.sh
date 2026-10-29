#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter test --dart-define=CHH_INTERACTION_REVIEW=true test/interaction_review_capture_test.dart
