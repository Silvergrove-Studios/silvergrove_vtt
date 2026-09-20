#!/usr/bin/env bash
# Everything a Gradle-based Android export needs, beyond the SDK: Godot's
# Android build template unpacked into android/build, and the Hexmap NSD
# plugin built into addons/hexmap_nsd/bin/hexmap_nsd.aar.
#
#   tools/android_build_setup.sh <export templates dir>
#
# Needs JAVA_HOME (17), ANDROID_HOME and `gradle` on PATH. Idempotent.
set -euo pipefail
tpl="${1:?export templates dir (the one holding android_source.zip)}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

version="$(cat "$tpl/version.txt" 2>/dev/null || echo "4.7.1.stable")"
if [ ! -f "$here/android/.build_version" ] || [ "$(cat "$here/android/.build_version")" != "$version" ]; then
	rm -rf "$here/android"
	mkdir -p "$here/android/build"
	unzip -q "$tpl/android_source.zip" -d "$here/android/build"
	echo "$version" > "$here/android/.build_version"
	echo "installed the Android build template $version"
fi

(cd "$here/plugins/android/nsd" && echo "sdk.dir=$ANDROID_HOME" > local.properties && gradle assembleRelease --no-daemon -q 2>&1 | grep -v "^Warning: SDK processing" || true)
aar="$here/plugins/android/nsd/build/outputs/aar/hexmap_nsd-release.aar"
[ -f "$aar" ] || { echo "the NSD plugin did not build"; exit 1; }
mkdir -p "$here/addons/hexmap_nsd/bin"
cp "$aar" "$here/addons/hexmap_nsd/bin/hexmap_nsd.aar"
ls -la "$here/addons/hexmap_nsd/bin/hexmap_nsd.aar"
