#!/usr/bin/env bash
# Build a signed test APK of Pocket Lift Log without the Android SDK.
# Needs: a JDK (javac, keytool, jarsigner), python3 with Pillow, and access to Maven Central.
# Output: dist/PocketLiftLog-test.apk
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
CACHE=android/.cache
OUT=android/.build
mkdir -p "$CACHE" dist
rm -rf "$OUT" && mkdir -p "$OUT/classes" "$OUT/stubs"

MAVEN=https://repo.maven.apache.org/maven2
fetch() { # url dest
  [ -s "$2" ] && return 0
  for i in 1 2 3 4 5; do
    curl -fsSL -o "$2" "$1" && [ "$(stat -c %s "$2")" -gt 100000 ] && return 0
    sleep 15
  done
  echo "download failed: $1" >&2; exit 1
}
fetch "$MAVEN/com/google/android/android/4.1.1.4/android-4.1.1.4.jar" "$CACHE/android.jar"
fetch "$MAVEN/com/jakewharton/android/repackaged/dalvik-dx/16.0.1/dalvik-dx-16.0.1.jar" "$CACHE/dx.jar"

# 1. compile against the platform stubs (the JavascriptInterface stub is compile-only)
javac -nowarn --release 8 -cp "$CACHE/android.jar" -d "$OUT/stubs" android/stubs/android/webkit/JavascriptInterface.java
javac -nowarn --release 8 -cp "$CACHE/android.jar:$OUT/stubs" -d "$OUT/classes" \
  android/src/app/pocketlog/MainActivity.java 2>&1 | grep -v 'warning: \[options\]\|^[0-9]* warning' || true

# 2. dex
java -cp "$CACHE/dx.jar" com.android.dx.command.Main --dex --min-sdk-version=21 --output="$OUT/classes.dex" "$OUT/classes"

# 3. package manifest, resources, icon, dex and the web app
python3 android/make_apk.py workout-log.html "$OUT/classes.dex" "$OUT/unsigned.apk" "$CACHE"

# 4. sign (v1 JAR signature; the app targets API 29, where that is accepted).
#    The test key lives in android/.cache so later builds install as updates; it is not committed.
KS="$CACHE/pocketlog-test.keystore"
if [ ! -f "$KS" ]; then
  keytool -genkeypair -keystore "$KS" -storepass pocketlog -keypass pocketlog -alias pocketlog \
    -keyalg RSA -keysize 2048 -validity 3650 -dname "CN=Pocket Lift Log Test" >/dev/null 2>&1
fi
cp "$OUT/unsigned.apk" dist/PocketLiftLog-test.apk
jarsigner -keystore "$KS" -storepass pocketlog -keypass pocketlog -sigalg SHA256withRSA -digestalg SHA-256 \
  dist/PocketLiftLog-test.apk pocketlog >/dev/null
jarsigner -verify dist/PocketLiftLog-test.apk | tail -1
ls -la "$ROOT/dist/PocketLiftLog-test.apk"
