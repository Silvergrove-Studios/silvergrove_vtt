#!/usr/bin/env bash
# What the android-test workflow runs inside the emulator step: the unit
# suite on the device, then a Table hosted on this machine (under xvfb,
# Mesa software GL) that the emulator joins at the host's address.
#
#   tools/android_ci.sh <Hexmap.apk> <out_dir>
set -euo pipefail
apk="${1:?apk}"; out="${2:?out}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$out"

"$here/tools/android_selftest.sh" "$apk" "$out"

echo "hosting a table on this machine for the emulator to join"
rm -f "$here"/examples/*.autosave
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x800x24" \
	"$here/run.sh" table examples/chapel_ambush.encounter --host --turns free > "$out/table.log" 2>&1 &
table_pid=$!
for i in $(seq 1 30); do
	grep -q "^hosting" "$out/table.log" 2>/dev/null && break
	sleep 2
done
grep "^hosting" "$out/table.log" || { echo "the table never started:"; tail -n 20 "$out/table.log"; kill $table_pid || true; exit 97; }

# The emulator reaches its host at 10.0.2.2.
set +e
"$here/tools/android_join_test.sh" "$apk" 10.0.2.2:47777 "$out"
code=$?
set -e
kill $table_pid 2>/dev/null || true
grep -E "discovery|joined|left" "$out/table.log" | tail -n 5 || true
exit $code
