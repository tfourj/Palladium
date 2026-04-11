#!/bin/sh
set -e

# Unsigned/CI builds can disable extension framework signing explicitly.
if [ "${PALLADIUM_DISABLE_PYTHON_DYLIB_CODESIGN:-}" = "1" ]; then
  export CODE_SIGNING_ALLOWED=NO
  export EXPANDED_CODE_SIGN_IDENTITY=""
  export EXPANDED_CODE_SIGN_IDENTITY_NAME=""
fi

# If Xcode provides an empty/whitespace identity, force-signing should be skipped.
SIGN_IDENTITY_TRIMMED=$(echo "${EXPANDED_CODE_SIGN_IDENTITY:-}" | tr -d '[:space:]')
if [ -z "$SIGN_IDENTITY_TRIMMED" ]; then
  export CODE_SIGNING_ALLOWED=NO
fi

source "$PROJECT_DIR/Frameworks/Python.xcframework/build/utils.sh"
install_python Frameworks/Python.xcframework

copy_privacy_manifest() {
  MANIFEST_NAME=$1
  FRAMEWORK_NAME=$2
  SOURCE_PATH="$PROJECT_DIR/privacy-manifests/python/$MANIFEST_NAME"
  TARGET_FRAMEWORK="$CODESIGNING_FOLDER_PATH/Frameworks/$FRAMEWORK_NAME"
  TARGET_PATH="$TARGET_FRAMEWORK/PrivacyInfo.xcprivacy"

  if [ ! -f "$SOURCE_PATH" ] || [ ! -d "$TARGET_FRAMEWORK" ]; then
    return
  fi

  cp "$SOURCE_PATH" "$TARGET_PATH"
  echo "Installed privacy manifest for $FRAMEWORK_NAME"

  SIGN_IDENTITY_TRIMMED=$(echo "${EXPANDED_CODE_SIGN_IDENTITY:-}" | tr -d '[:space:]')
  if [ "$EFFECTIVE_PLATFORM_NAME" = "-iphonesimulator" ] || [ "${CODE_SIGNING_ALLOWED:-YES}" != "YES" ] || [ -z "$SIGN_IDENTITY_TRIMMED" ]; then
    echo "Skipping framework re-signing for $FRAMEWORK_NAME (simulator or no signing identity)."
    return
  fi

  echo "Re-signing $FRAMEWORK_NAME after privacy manifest update..."
  /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" ${OTHER_CODE_SIGN_FLAGS:-} -o runtime --timestamp=none --preserve-metadata=identifier,entitlements,flags --generate-entitlement-der "$TARGET_FRAMEWORK"
}

copy_privacy_manifest "_ssl.xcprivacy" "_ssl.framework"
copy_privacy_manifest "_hashlib.xcprivacy" "_hashlib.framework"
