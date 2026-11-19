#!/usr/bin/env bash
# Builds straight from the read-only source in /src. Gradle's writes (build/, .gradle/, .kotlin/) go to /utils/cache
# instead and the APKs are copied to /utils/output: /utils is the host's utils folder, written as the host user.
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
    : "${SIGNING_STORE_PASSWORD:?$KEYSTORE is there but SIGNING_STORE_PASSWORD is not set (utils/keys/signing.env)}"
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

cd /src
sh ./gradlew --no-daemon \
    --init-script /usr/local/share/build-dirs.init.gradle.kts \
    --project-cache-dir "$CACHE/project" \
    -Pkotlin.project.persistent.dir="$CACHE/kotlin" \
    "${signing[@]}" \
    "${tasks[@]}"

mkdir -p "$OUTPUT"
rm -f "$OUTPUT"/*.apk
find "$CACHE/build/app/outputs/apk" -name '*.apk' -exec cp -v {} "$OUTPUT/" \;
