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

install_curl_cffi_payload() {
  PAYLOAD_ZIP="$PROJECT_DIR/Frameworks/SwiftCurlCffi-iOS/Sources/SwiftCurlCffiIOS/Resources/curl_cffi_ios_payload.zip"
  TARGET_PACKAGES="$CODESIGNING_FOLDER_PATH/python-packages"

  if [ ! -f "$PAYLOAD_ZIP" ]; then
    echo "curl-cffi iOS payload not found: $PAYLOAD_ZIP"
    exit 1
  fi

  if [ "$EFFECTIVE_PLATFORM_NAME" = "-iphoneos" ]; then
    PAYLOAD_SITE_PACKAGES="site-packages-iphoneos"
  elif [ "$EFFECTIVE_PLATFORM_NAME" = "-iphonesimulator" ]; then
    PAYLOAD_SITE_PACKAGES="site-packages-iphonesimulator"
  else
    echo "Skipping curl-cffi payload for unsupported platform $EFFECTIVE_PLATFORM_NAME"
    return
  fi

  TMP_PAYLOAD="$TARGET_TEMP_DIR/curl-cffi-payload"
  rm -rf "$TMP_PAYLOAD" "$TARGET_PACKAGES"
  mkdir -p "$TMP_PAYLOAD" "$TARGET_PACKAGES"
  /usr/bin/unzip -q "$PAYLOAD_ZIP" -d "$TMP_PAYLOAD"

  SOURCE_PACKAGES="$TMP_PAYLOAD/curl_cffi_ios_payload/$PAYLOAD_SITE_PACKAGES"
  if [ ! -d "$SOURCE_PACKAGES" ]; then
    echo "curl-cffi payload site-packages missing: $SOURCE_PACKAGES"
    exit 1
  fi

  rsync -au "$SOURCE_PACKAGES/" "$TARGET_PACKAGES/"
  echo "Installed curl-cffi payload from $PAYLOAD_SITE_PACKAGES"
}

install_curl_cffi_payload
install_python Frameworks/Python.xcframework python-packages

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
