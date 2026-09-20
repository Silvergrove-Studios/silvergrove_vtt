#!/usr/bin/env bash
# Make an Android device or emulator join a running Table and play a move.
#
#   tools/android_join_test.sh <Hexmap.apk> <host:port | --usb> <out_dir>
#
# Installs the (debug) APK, tells the app which table to join
# (user://selftest_join), launches it, waits, and pulls the log into
# <out_dir>. With --usb the phone reaches a Table on this machine through
# the cable: `adb reverse` maps the phone's 127.0.0.1:47777 to ours, so no
# wifi, subnet or discovery is involved — the joining itself is what is
# tested. With host:port the device connects over the network (a phone on
# the wifi, or an emulator reaching its host at 10.0.2.2). Exits with the
# failed-check count.
set -euo pipefail

apk="${1:?apk}"
target="${2:?host:port or --usb}"
out="${3:?out dir}"
pkg="com.silvergrove.hexmap"
mkdir -p "$out"

adb wait-for-device
adb install -r "$apk" >/dev/null
if [ "$target" = "--usb" ]; then
	adb reverse tcp:47777 tcp:47777
	target="127.0.0.1:47777"
fi
adb shell "run-as $pkg sh -c 'mkdir -p files && rm -f files/selftest.done files/selftest.txt files/selftest && printf %s \"$target\" > files/selftest_join'"
activity="$(adb shell cmd package resolve-activity --brief -c android.intent.category.LAUNCHER "$pkg" | tail -n 1 | tr -d '\r')"
adb shell am force-stop "$pkg" >/dev/null 2>&1 || true
adb logcat -c || true
adb shell am start -W -n "$activity" >/dev/null

echo "waiting for the device to join $target..."
for i in $(seq 1 24); do
	adb shell "run-as $pkg test -f files/selftest.done" 2>/dev/null && break
	sleep 5
done
adb shell "run-as $pkg cat files/selftest.txt" > "$out/join.txt" 2>/dev/null || true
adb logcat -d > "$out/join_logcat.txt" 2>/dev/null || true
adb shell am force-stop "$pkg" >/dev/null 2>&1 || true
if ! adb shell "run-as $pkg test -f files/selftest.done" 2>/dev/null; then
	echo "the device never finished; log so far:"; cat "$out/join.txt" || true
	exit 99
fi
cat "$out/join.txt"
fails="$(adb shell "run-as $pkg cat files/selftest.done" | tr -d '[:space:]')"
echo "failed checks: $fails"
exit "${fails:-98}"
