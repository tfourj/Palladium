#!/bin/sh
set -e

PLIST_PATH="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"

if [ ! -f "$PLIST_PATH" ]; then
  echo "error: Info.plist not found at $PLIST_PATH"
  exit 1
fi

GIT_COMMIT_ID=$(git -C "$PROJECT_DIR" rev-parse --short=7 HEAD)

APP_FINAL=false
if [ -n "$(git -C "$PROJECT_DIR" tag --points-at HEAD)" ]; then
  APP_FINAL=true
fi

set_plist_value() {
  KEY=$1
  TYPE=$2
  VALUE=$3

  /usr/libexec/PlistBuddy -c "Delete :$KEY" "$PLIST_PATH" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :$KEY $TYPE $VALUE" "$PLIST_PATH"
}

set_plist_value GIT_COMMIT_ID string "$GIT_COMMIT_ID"
set_plist_value APP_FINAL bool "$APP_FINAL"

if [ -n "${SCRIPT_OUTPUT_FILE_0:-}" ]; then
  touch "$SCRIPT_OUTPUT_FILE_0"
fi

echo "Updated build metadata: GIT_COMMIT_ID=$GIT_COMMIT_ID APP_FINAL=$APP_FINAL"
