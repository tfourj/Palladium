#!/bin/zsh
set -e  # Exit immediately if a command fails

# -----------------------------
# Configuration
# -----------------------------
PROJECT_NAME="Palladium"
SCHEME_NAME="Palladium"
BUILD_DIR="build"
XCODEBUILD_OVERRIDES=()

HEAD_TAG=$(git tag --points-at HEAD --sort=-v:refname | head -n 1)
if [ -n "$HEAD_TAG" ]; then
  BUILD_REF="$HEAD_TAG"
  echo "📦 Using tag on current commit for IPA name: ${BUILD_REF}"
else
  BUILD_REF=$(git rev-parse --short HEAD)
  echo "📦 Current commit has no tag, using commit for IPA name: ${BUILD_REF}"
fi

IPA_NAME="Palladium-${BUILD_REF}.ipa"
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

# Ensure Python extension frameworks are not codesigned in unsigned IPA builds.
export PALLADIUM_DISABLE_PYTHON_DYLIB_CODESIGN=1

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
  "${XCODEBUILD_OVERRIDES[@]}" \
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
  "${XCODEBUILD_OVERRIDES[@]}" \
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
