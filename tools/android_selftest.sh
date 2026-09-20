#!/usr/bin/env bash
# Run Hexmap's self-test inside an Android device or emulator over adb.
#
#   tools/android_selftest.sh <Hexmap.apk> <out_dir>
#
# Installs the (debug) APK, pushes the placeholder packs into the app's
# private files so pack tests have something to load, drops the
# user://selftest marker, launches the app, waits for user://selftest.done,
# and pulls the log, the screenshots and logcat into <out_dir>. Exits with
# the number of failed checks.
set -euo pipefail

apk="${1:?apk}"
out="${2:?out dir}"
pkg="com.silvergrove.hexmap"
mkdir -p "$out"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

adb wait-for-device
adb shell settings put global window_animation_scale 0 >/dev/null 2>&1 || true
adb install -r "$apk"

# The app's files/ is user://. A debug build lets run-as write there.
adb push "$here/packs" /data/local/tmp/hexmap_packs >/dev/null
adb push "$here/examples" /data/local/tmp/hexmap_examples >/dev/null
adb shell "run-as $pkg sh -c 'mkdir -p files/packs files/examples && cp -r /data/local/tmp/hexmap_packs/. files/packs/ && cp -r /data/local/tmp/hexmap_examples/. files/examples/ && rm -f files/selftest.done && touch files/selftest'"
adb shell run-as "$pkg" ls files

adb logcat -c || true
adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null

echo "waiting for the self-test to finish…"
for i in $(seq 1 90); do
	if adb shell "run-as $pkg test -f files/selftest.done" 2>/dev/null; then
		break
	fi
	sleep 5
done

adb shell "run-as $pkg cat files/selftest.txt" > "$out/selftest.txt" 2>/dev/null || true
for f in selftest_home.png selftest_player.png; do
	adb exec-out "run-as $pkg cat files/$f" > "$out/$f" 2>/dev/null || true
done
adb exec-out screencap -p > "$out/screen.png" 2>/dev/null || true
adb logcat -d > "$out/logcat.txt" 2>/dev/null || true

if ! adb shell "run-as $pkg test -f files/selftest.done" 2>/dev/null; then
	echo "self-test did not finish; last log lines:"
	tail -n 20 "$out/selftest.txt" || true
	grep -i "godot" "$out/logcat.txt" | tail -n 40 || true
	exit 99
fi
fails="$(adb shell "run-as $pkg cat files/selftest.done" | tr -d '[:space:]')"
grep -E "^(RESULT|took|screenshot|Hexmap self-test|  FAIL|skipped)" "$out/selftest.txt" || true
echo "failed checks: $fails"
exit "${fails:-98}"
