#!/usr/bin/env bash
# Export this machine's own desktop build and run the self-test inside it —
# the binary a user would download, rendering on the real OS.
#
#   tools/desktop_selftest.sh <out_dir>
#
# Picks the preset for the OS it runs on, exports a release build, puts the
# placeholder packs beside it, launches it with --selftest, and copies the
# log and screenshots into <out_dir>. Exits with the failed-check count.
# Needs a display: on Linux run it under xvfb-run with Mesa's software GL;
# on Windows the exported app is asked for ANGLE (D3D11), which the WARP
# software adapter on a headless machine provides. HEXMAP_SKIP_EXPORT=1
# reuses an export already at out/desktop.
set -euo pipefail

out="${1:?out dir}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$out"
godot="$("$here/run.sh" doctor | awk '/^godot/ {print $2}')"

case "$(uname -s)" in
	Darwin)
		preset="macOS"; target="$here/out/desktop/Hexmap.zip"
		userdir="$HOME/Library/Application Support/Godot/app_userdata/Hexmap"
		;;
	Linux)
		preset="Linux"; target="$here/out/desktop/Hexmap.x86_64"
		userdir="$HOME/.local/share/godot/app_userdata/Hexmap"
		;;
	*)
		preset="Windows Desktop"; target="$here/out/desktop/Hexmap.exe"
		userdir="$APPDATA/Godot/app_userdata/Hexmap"
		;;
esac
mkdir -p "$(dirname "$target")"
rm -f "$userdir/selftest.done" "$userdir/selftest.txt" 2>/dev/null || true

if [ -n "${HEXMAP_SKIP_EXPORT:-}" ] && [ -e "$target" ]; then
	echo "reusing $target"
else
	echo "exporting '$preset' -> $target"
	"$godot" --headless --path "$here" --export-release "$preset" "$target" 2>&1 | tee "$out/export.log" | grep -E "^ERROR|savepack.*DONE" || true
	! grep -q "^ERROR" "$out/export.log"
fi

case "$preset" in
	macOS)
		rm -rf "$here/out/desktop/app" && mkdir -p "$here/out/desktop/app"
		(cd "$here/out/desktop/app" && unzip -q ../Hexmap.zip)
		cp -R "$here/packs" "$here/out/desktop/app/packs"
		xattr -dr com.apple.quarantine "$here/out/desktop/app" 2>/dev/null || true
		bin="$here/out/desktop/app/Hexmap.app/Contents/MacOS/Hexmap"
		extra=()
		;;
	Linux)
		cp -R "$here/packs" "$here/out/desktop/packs"
		chmod +x "$target"
		bin="$target"
		extra=()
		;;
	*)
		cp -R "$here/packs" "$here/out/desktop/packs"
		bin="$target"
		extra=(--rendering-driver opengl3_angle)
		;;
esac

echo "running the self-test in $bin"
set +e
"$bin" --resolution 1280x800 ${extra[@]+"${extra[@]}"} -- --selftest > "$out/run.log" 2>&1
code=$?
set -e
echo "exit code $code"
cp "$userdir/selftest.txt" "$out/" 2>/dev/null || true
cp "$userdir"/selftest_*.png "$out/" 2>/dev/null || true
if [ ! -f "$userdir/selftest.done" ]; then
	echo "self-test did not finish"; tail -n 30 "$out/run.log" || true; exit 99
fi
grep -E "^(RESULT|took|screenshot|Hexmap self-test|  FAIL|skipped)" "$out/selftest.txt" || true
fails="$(tr -d '[:space:]' < "$userdir/selftest.done")"
echo "failed checks: $fails"
exit "${fails:-98}"
