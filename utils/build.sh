#!/usr/bin/env bash
# Builds straight from the source in /src. Gradle 9 needs that folder writable, but its writes (build/, .gradle/,
# .kotlin/, the problems report) are sent to /utils/cache or turned off, so the repository stays as it is. The APKs are
# copied to /utils/output. /utils is the host's utils folder, written as the host user.
set -euo pipefail

TASK="${GRADLE_TASK:-assembleDebug}"
read -ra tasks <<< "$TASK" # one or more, e.g. "testDebugUnitTest assembleRelease"
CACHE=/utils/cache
OUTPUT=/utils/output
export GRADLE_USER_HOME="$CACHE/gradle" # Gradle itself and the dependencies
# The debug keystore lives here: kept between builds, so a new debug APK installs over the last one.
export ANDROID_USER_HOME="$CACHE/android"

# local.properties may point sdk.dir at the host's SDK, which doesn't exist here: link that path to this SDK.
if [ -f /src/local.properties ]; then
    sdk_dir="$(sed -n 's/^sdk\.dir=//p' /src/local.properties)"
    if [ -n "$sdk_dir" ] && [ ! -e "$sdk_dir" ]; then
        mkdir -p "$(dirname "$sdk_dir")" 2>/dev/null && ln -s "$ANDROID_HOME" "$sdk_dir" \
            || echo "warning: can't link sdk.dir ($sdk_dir) to $ANDROID_HOME; remove it from local.properties if the build can't find the SDK" >&2
    fi
fi

# Release builds are signed with the key in utils/keys when there is one (see README.md), through the Android Gradle
# plugin's injected signing properties (what Android Studio's "Generate Signed APK" uses). They take over from the
# repo's keystore.properties setup, whose "not found" warning can then be ignored. Without a key: the debug key.
KEYSTORE="${SIGNING_KEYSTORE:-/utils/keys/release.jks}"
signing=()
if [[ "$TASK" == *Release* && -f "$KEYSTORE" ]]; then
    : "${SIGNING_STORE_PASSWORD:?$KEYSTORE is there but SIGNING_STORE_PASSWORD is not set (utils/.env)}"
    signing=(
        -Pandroid.injected.signing.store.file="$KEYSTORE"
        -Pandroid.injected.signing.store.password="$SIGNING_STORE_PASSWORD"
        -Pandroid.injected.signing.key.alias="${SIGNING_KEY_ALIAS:-alder}"
        -Pandroid.injected.signing.key.password="${SIGNING_KEY_PASSWORD:-$SIGNING_STORE_PASSWORD}"
    )
    echo "Signing with $KEYSTORE, key ${SIGNING_KEY_ALIAS:-alder}"
elif [[ "$TASK" == *Release* ]]; then
    echo "No $KEYSTORE: signing with the debug key"
fi

echo "Application ID: ${APP_ID:-dev.alder (build.gradle.kts)}"

# APP_NAME: the name on the TV's home screen and app list, in a res folder of its own (docker.init.gradle.kts adds it).
name_res="$CACHE/app-name/res"
rm -rf "$CACHE/app-name"
if [ -n "${APP_NAME:-}" ]; then
    # Android string resources: XML escapes, then backslash, quotes, and a leading @ or ? escaped with a backslash.
    name=$(printf '%s' "$APP_NAME" | sed \
        -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
        -e 's/\\/\\\\/g' -e "s/'/\\\\'/g" -e 's/"/\\"/g' \
        -e 's/^[@?]/\\&/')
    mkdir -p "$name_res/values"
    printf '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <string name="app_name" translatable="false">%s</string>\n</resources>\n' \
        "$name" > "$name_res/values/strings.xml"
    export APP_NAME_RES="$name_res"
    echo "App name: $APP_NAME"
fi

# Overrides (images, banners, etc...)
ORIGINALS_DIR="$(mktemp -d)"; overridden=() ; originals=()
override() { printf "overriding %s\n" "$2" ; local copy="$ORIGINALS_DIR/${#overridden[@]}" ; overridden+=("$2") ; originals+=("$copy") ; cp -p "$2" "$copy" ; cp "$1" "$2" ; }
restore_originals() { for ((i = ${#overridden[@]} - 1; i >= 0; i--)); do cp -p "${originals[i]}" "${overridden[i]}"; done ; rm -rf "$ORIGINALS_DIR" ; }
trap restore_originals EXIT

override /utils/custom/banner.png /src/branding/house-lights/alder_tv_banner_1280x720.png
override /utils/custom/banner.webp /src/app/src/main/res/drawable-nodpi/banner.webp


# Build
cd /src
sh ./gradlew --no-daemon \
    --init-script /usr/local/share/docker.init.gradle.kts \
    --project-cache-dir "$CACHE/project" \
    --no-problems-report \
    -Pkotlin.project.persistent.dir="$CACHE/kotlin" \
    "${signing[@]}" \
    "${tasks[@]}"

mkdir -p "$OUTPUT"
rm -f "$OUTPUT"/*.apk
find "$CACHE/build/app/outputs/apk" -name '*.apk' -exec cp -v {} "$OUTPUT/" \;
