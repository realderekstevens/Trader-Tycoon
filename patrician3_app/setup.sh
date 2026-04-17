#!/usr/bin/env bash
# =============================================================================
#  setup.sh  —  run ONCE after flutter create . to wire everything up
#
#  Usage (from patrician3_app/ directory):
#    bash setup.sh
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "── Patrician III setup ──────────────────────────────────────────────────"

# 1. Verify we're in the right place
if [[ ! -f "pubspec.yaml" ]]; then
  echo "❌  Run this from inside the patrician3_app/ directory."
  exit 1
fi

# 2. Make sure lib/ exists (flutter create . already does this, but be safe)
mkdir -p lib

# 3. Check that our source files are present
for f in main.dart hex_map_screen.dart; do
  if [[ ! -f "lib/$f" ]]; then
    echo "❌  lib/$f not found. Make sure you copied the delivered files into lib/."
    exit 1
  fi
done

# 4. Delete the stub widget_test so it doesn't conflict
if [[ -f "test/widget_test.dart" ]]; then
  echo "Removing stub test/widget_test.dart (it references the default counter app)"
  rm test/widget_test.dart
fi

# 5. Fetch packages
echo "Running flutter pub get..."
flutter pub get

# 6. Confirm available targets
echo ""
echo "Available run targets:"
flutter devices

echo ""
echo "✅  Setup complete. Run the app with:"
echo "    flutter run -d linux        # Linux desktop"
echo "    flutter run -d android      # Android"
echo "    flutter run -d chrome       # Web (requires web support)"
echo ""
echo "First-time config: open the app, go to CONFIG tab,"
echo "set your PostgREST URL (default: http://localhost:3000), tap CONNECT."
