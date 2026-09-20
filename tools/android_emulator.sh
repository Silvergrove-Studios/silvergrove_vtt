#!/usr/bin/env bash
# A headless Android emulator on this machine, for tools/android_join_test.sh
# and tools/android_selftest.sh without a phone.
#
#   tools/android_emulator.sh setup     install the SDK pieces and create the AVD (once)
#   tools/android_emulator.sh start     boot it headless and wait for it
#   tools/android_emulator.sh stop
#   tools/android_emulator.sh env       print the exports for adb/emulator on PATH
#
# macOS via Homebrew (no sudo): `brew install openjdk@17` and
# `brew install --cask android-commandlinetools` first. The first `adb` and
# `emulator` will trigger macOS firewall prompts that someone at the
# machine must click Allow on; the JDK is keg-only, hence JAVA_HOME below.
# From the emulator, this machine is 10.0.2.2.
set -euo pipefail

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
if [ -z "${JAVA_HOME:-}" ] && command -v brew >/dev/null; then
	export JAVA_HOME="$(brew --prefix openjdk@17 2>/dev/null)/libexec/openjdk.jdk/Contents/Home"
fi
tools_root="$(brew --prefix 2>/dev/null)/share/android-commandlinetools"
image="system-images;android-34;default;$(uname -m | sed 's/x86_64/x86_64/; s/arm64/arm64-v8a/')"
avd="hexmap"

case "${1:-}" in
	setup)
		sdkm="$tools_root/cmdline-tools/latest/bin/sdkmanager"
		mkdir -p "$ANDROID_HOME"
		yes | "$sdkm" --sdk_root="$ANDROID_HOME" --licenses >/dev/null 2>&1 || true
		"$sdkm" --sdk_root="$ANDROID_HOME" "platform-tools" "emulator" "$image"
		# avdmanager looks for packages under its own root, not ANDROID_HOME.
		for d in system-images platform-tools emulator licenses; do
			[ -e "$tools_root/$d" ] || ln -s "$ANDROID_HOME/$d" "$tools_root/$d"
		done
		echo no | "$tools_root/cmdline-tools/latest/bin/avdmanager" create avd -n "$avd" -k "$image" -d pixel_6 --force
		echo "created AVD $avd"
		;;
	start)
		nohup emulator -avd "$avd" -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect > /tmp/hexmap-emulator.log 2>&1 &
		echo "booting (log: /tmp/hexmap-emulator.log)"
		adb wait-for-device
		until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 3; done
		echo "booted: $(adb devices | sed -n 2p)"
		;;
	stop)
		adb emu kill >/dev/null 2>&1 || pkill -f "emulator -avd $avd" || true
		echo stopped
		;;
	env)
		echo "export ANDROID_HOME=\"$ANDROID_HOME\" ANDROID_SDK_ROOT=\"$ANDROID_HOME\" JAVA_HOME=\"${JAVA_HOME:-}\" PATH=\"$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:\$PATH\""
		;;
	*)
		sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
		exit 2
		;;
esac
