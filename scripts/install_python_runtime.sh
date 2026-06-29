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

max_version() {
  /usr/bin/awk -v a="$1" -v b="$2" '
    function part(version, idx, pieces) {
      split(version, pieces, ".")
      return pieces[idx] + 0
    }

    BEGIN {
      for (i = 1; i <= 4; i++) {
        if (part(a, i) > part(b, i)) {
          print a
          exit
        }
        if (part(b, i) > part(a, i)) {
          print b
          exit
        }
      }
      print a
    }
  '
}

macho_minimum_os_version() {
  /usr/bin/otool -l "$1" 2>/dev/null | /usr/bin/awk '
    $1 == "cmd" && $2 == "LC_BUILD_VERSION" {
      reading_build_version = 1
      reading_version_min = 0
      next
    }
    reading_build_version && $1 == "minos" {
      print $2
      exit
    }
    $1 == "cmd" && $2 == "LC_VERSION_MIN_IPHONEOS" {
      reading_build_version = 0
      reading_version_min = 1
      next
    }
    reading_version_min && $1 == "version" {
      print $2
      exit
    }
    $1 == "cmd" {
      reading_build_version = 0
      reading_version_min = 0
    }
  '
}

resign_framework_if_needed() {
  FRAMEWORK_NAME=$1
  TARGET_FRAMEWORK=$2

  SIGN_IDENTITY_TRIMMED=$(echo "${EXPANDED_CODE_SIGN_IDENTITY:-}" | tr -d '[:space:]')
  if [ "$EFFECTIVE_PLATFORM_NAME" = "-iphonesimulator" ] || [ "${CODE_SIGNING_ALLOWED:-YES}" != "YES" ] || [ -z "$SIGN_IDENTITY_TRIMMED" ]; then
    echo "Skipping framework re-signing for $FRAMEWORK_NAME (simulator or no signing identity)."
    return
  fi

  echo "Re-signing $FRAMEWORK_NAME after metadata update..."
  /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" ${OTHER_CODE_SIGN_FLAGS:-} -o runtime --timestamp=none --preserve-metadata=identifier,entitlements,flags --generate-entitlement-der "$TARGET_FRAMEWORK"
}

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

normalize_python_extension_minimum_os_versions() {
  FRAMEWORKS_DIR="$CODESIGNING_FOLDER_PATH/Frameworks"

  if [ ! -d "$FRAMEWORKS_DIR" ]; then
    return
  fi

  for TARGET_FRAMEWORK in "$FRAMEWORKS_DIR"/*.framework; do
    if [ ! -d "$TARGET_FRAMEWORK" ]; then
      continue
    fi

    ORIGIN_MARKER=$(find "$TARGET_FRAMEWORK" -name "*.origin" -print | head -n 1)
    if [ -z "$ORIGIN_MARKER" ]; then
      continue
    fi

    INFO_PLIST="$TARGET_FRAMEWORK/Info.plist"
    if [ ! -f "$INFO_PLIST" ]; then
      continue
    fi

    EXECUTABLE_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$INFO_PLIST" 2>/dev/null || true)
    if [ -z "$EXECUTABLE_NAME" ]; then
      continue
    fi

    FRAMEWORK_BINARY="$TARGET_FRAMEWORK/$EXECUTABLE_NAME"
    if [ ! -f "$FRAMEWORK_BINARY" ]; then
      continue
    fi

    CURRENT_MINIMUM_OS=$(/usr/libexec/PlistBuddy -c "Print :MinimumOSVersion" "$INFO_PLIST" 2>/dev/null || true)
    if [ -z "$CURRENT_MINIMUM_OS" ]; then
      CURRENT_MINIMUM_OS="${IPHONEOS_DEPLOYMENT_TARGET:-}"
    fi

    BINARY_MINIMUM_OS=$(macho_minimum_os_version "$FRAMEWORK_BINARY")
    if [ -z "$CURRENT_MINIMUM_OS" ] || [ -z "$BINARY_MINIMUM_OS" ]; then
      continue
    fi

    EXPECTED_MINIMUM_OS=$(max_version "$CURRENT_MINIMUM_OS" "$BINARY_MINIMUM_OS")
    if [ "$CURRENT_MINIMUM_OS" = "$EXPECTED_MINIMUM_OS" ]; then
      continue
    fi

    FRAMEWORK_NAME=$(basename "$TARGET_FRAMEWORK")
    /usr/bin/plutil -replace MinimumOSVersion -string "$EXPECTED_MINIMUM_OS" "$INFO_PLIST"
    echo "Set $FRAMEWORK_NAME MinimumOSVersion to $EXPECTED_MINIMUM_OS"
    resign_framework_if_needed "$FRAMEWORK_NAME" "$TARGET_FRAMEWORK"
  done
}

install_curl_cffi_payload
install_python Frameworks/Python.xcframework python-packages
normalize_python_extension_minimum_os_versions

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

  resign_framework_if_needed "$FRAMEWORK_NAME" "$TARGET_FRAMEWORK"
}

copy_privacy_manifest "_ssl.xcprivacy" "_ssl.framework"
copy_privacy_manifest "_hashlib.xcprivacy" "_hashlib.framework"
