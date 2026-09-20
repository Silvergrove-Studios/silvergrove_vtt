#!/usr/bin/env bash
# Run Hexmap's self-test inside an iOS simulator.
#
#   tools/ios_selftest.sh <Hexmap.app (simulator build)> <out_dir>
#
# Boots the first available iPhone simulator, installs the app, puts the
# placeholder packs, the examples and the user://selftest marker in the
# app's Documents folder (Godot's user:// on iOS), launches it, waits for
# selftest.done, and copies the log, the screenshots and the simulator's
# own screenshot and log into <out_dir>. Exits with the failed-check count.
set -euo pipefail

app="${1:?app bundle}"
out="${2:?out dir}"
bundle="com.silvergrove.hexmap"
mkdir -p "$out"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

udid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
picks = []
for runtime, devs in d.items():
    if "iOS" not in runtime:
        continue
    for dev in devs:
        if dev.get("isAvailable") and dev["name"].startswith("iPhone"):
            picks.append((runtime, dev["name"], dev["udid"]))
picks.sort()
print(picks[-1][2] if picks else "")
')"
[ -n "$udid" ] || { echo "no iPhone simulator available"; xcrun simctl list devices available; exit 97; }
echo "simulator: $(xcrun simctl list devices | grep "$udid")"
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b
# An x86_64 build on an Apple-silicon host runs under Rosetta in the simulator.
xcrun simctl install "$udid" "$app"
lipo -info "$app/Hexmap" 2>/dev/null || true

container="$(xcrun simctl get_app_container "$udid" "$bundle" data)"
docs="$container/Documents"
mkdir -p "$docs/packs" "$docs/examples"
cp -R "$here/packs/." "$docs/packs/"
cp -R "$here/examples/." "$docs/examples/"
rm -f "$docs/selftest.done"
touch "$docs/selftest"
ls "$docs"

xcrun simctl launch "$udid" "$bundle"
echo "waiting for the self-test to finish..."
for i in $(seq 1 90); do
	[ -f "$docs/selftest.done" ] && break
	sleep 5
done

cp "$docs/selftest.txt" "$out/" 2>/dev/null || true
cp "$docs"/selftest_*.png "$out/" 2>/dev/null || true
xcrun simctl io "$udid" screenshot "$out/screen.png" >/dev/null 2>&1 || true
xcrun simctl spawn "$udid" log show --last 15m --predicate 'process == "Hexmap"' > "$out/log.txt" 2>/dev/null || true
xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true

if [ ! -f "$docs/selftest.done" ]; then
	echo "self-test did not finish; Documents holds:"; ls -la "$docs" || true
	echo "last log lines:"; tail -n 20 "$out/selftest.txt" 2>/dev/null || true
	tail -n 40 "$out/log.txt" || true
	exit 99
fi
fails="$(tr -d '[:space:]' < "$docs/selftest.done")"
grep -E "^(RESULT|took|screenshot|Hexmap self-test|  FAIL|skipped)" "$out/selftest.txt" || true
echo "failed checks: $fails"
exit "${fails:-98}"
