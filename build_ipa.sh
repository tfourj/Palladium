#!/bin/zsh
set -e  # Exit immediately if a command fails

# -----------------------------
# Configuration
# -----------------------------
PROJECT_NAME="Palladium"
SCHEME_NAME="Palladium"
BUILD_DIR="build"

# Extract version from project.pbxproj
VERSION=$(grep 'SHARED_VERSION_NUMBER' Palladium.xcodeproj/project.pbxproj | head -n 1 | sed -E 's/.*SHARED_VERSION_NUMBER = ([0-9\.]+[a-zA-Z0-9]*);.*/\1/')
IPA_NAME="Palladium-${VERSION}-uBeta.ipa"
echo "📦 Extracted version: ${VERSION}"
echo "📦 IPA will be named: ${IPA_NAME}"

# -----------------------------
# Detect SDK
# -----------------------------
echo "🔍 Detecting available iOS SDKs..."
AVAILABLE_SDKS=$(xcodebuild -showsdks | grep iphoneos | awk '{print $NF}')

if echo "$AVAILABLE_SDKS" | grep -q "17"; then
  SDK="iphoneos17.0"
else
  SDK=$(echo "$AVAILABLE_SDKS" | sort -V | tail -n 1)
fi

echo "✅ Using SDK: $SDK"

# Ensure Python extension frameworks are not codesigned in unsigned CI IPA builds.
export PALLADIUM_DISABLE_PYTHON_DYLIB_CODESIGN=1

patch_python_apple_support_utils() {
  local utils_path="Python.xcframework/build/utils.sh"
  if [ ! -f "$utils_path" ]; then
    echo "❌ Missing $utils_path"
    exit 1
  fi

  if grep -q "Skipping framework signing for" "$utils_path"; then
    echo "✅ python-apple-support utils already patched for unsigned builds"
    return
  fi

  echo "🔧 Patching python-apple-support utils.sh for unsigned IPA builds..."
  python3 - "$utils_path" <<'PY'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()

old = """    echo "Signing framework as $EXPANDED_CODE_SIGN_IDENTITY_NAME ($EXPANDED_CODE_SIGN_IDENTITY)..."
    /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" ${OTHER_CODE_SIGN_FLAGS:-} -o runtime --timestamp=none --preserve-metadata=identifier,entitlements,flags --generate-entitlement-der "$CODESIGNING_FOLDER_PATH/$FRAMEWORK_FOLDER"
"""

new = """    SIGN_IDENTITY_TRIMMED=$(echo "${EXPANDED_CODE_SIGN_IDENTITY:-}" | tr -d '[:space:]')
    if [ "$EFFECTIVE_PLATFORM_NAME" = "-iphonesimulator" ] || [ "${CODE_SIGNING_ALLOWED:-YES}" != "YES" ] || [ -z "$SIGN_IDENTITY_TRIMMED" ]; then
        echo "Skipping framework signing for $FRAMEWORK_FOLDER (simulator, unsigned build, or missing identity)."
    else
        echo "Signing framework as $EXPANDED_CODE_SIGN_IDENTITY_NAME ($EXPANDED_CODE_SIGN_IDENTITY)..."
        /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" ${OTHER_CODE_SIGN_FLAGS:-} -o runtime --timestamp=none --preserve-metadata=identifier,entitlements,flags --generate-entitlement-der "$CODESIGNING_FOLDER_PATH/$FRAMEWORK_FOLDER"
    fi
"""

if old not in text:
    if "Skipping framework signing for" in text:
        print("utils.sh already patched; no changes needed")
        sys.exit(0)
    print("expected signing block not found in utils.sh", file=sys.stderr)
    sys.exit(1)

text = text.replace(old, new, 1)
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PY
}

patch_python_apple_support_utils

# -----------------------------
# Clean build directory
# -----------------------------
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# -----------------------------
# Build
# -----------------------------
echo "--- Building project ---"
xcodebuild clean build \
  -project "$PROJECT_NAME.xcodeproj" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -sdk "$SDK" \
  PALLADIUM_DISABLE_PYTHON_DYLIB_CODESIGN=1 \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO || { echo "❌ Build failed"; exit 1; }

# -----------------------------
# Archive
# -----------------------------
echo "--- Archiving project ---"
xcodebuild archive \
  -project "$PROJECT_NAME.xcodeproj" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -archivePath "$BUILD_DIR/archive.xcarchive" \
  -destination "generic/platform=iOS" \
  -sdk "$SDK" \
  PALLADIUM_DISABLE_PYTHON_DYLIB_CODESIGN=1 \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO || { echo "❌ Archive failed"; exit 1; }

# -----------------------------
# Verify archive contents
# -----------------------------
APP_PATH="$BUILD_DIR/archive.xcarchive/Products/Applications/$PROJECT_NAME.app"
if [ ! -d "$APP_PATH" ]; then
  echo "❌ Missing .app file in archive!"
  exit 1
fi

# -----------------------------
# Package IPA
# -----------------------------
echo "--- Packaging IPA ---"
IPA_PATH="$BUILD_DIR/${IPA_NAME}"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"
cd "$BUILD_DIR"
zip -qr "${IPA_NAME}" Payload || { echo "❌ IPA creation failed"; exit 1; }
cd ..
rm -rf "$BUILD_DIR/Payload"

echo "✅ Unsigned IPA created at: $IPA_PATH"
