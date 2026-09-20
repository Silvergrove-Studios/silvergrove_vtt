#!/usr/bin/env bash
# Hexmap launcher. Works on macOS, Linux/WSL and Git Bash on Windows.
#
#   ./run.sh                          open the app on its home screen
#   ./run.sh examples/forest_road.hexmap
#                                     open a map in the editor
#   ./run.sh editor [map]             the editor (a new map, or this one)
#   ./run.sh table [encounter] [--host] [--turns free|dm|ordered]
#                                     the table: run an encounter (--host: on the LAN at once)
#   ./run.sh player [address]         the player client
#   ./run.sh export <map> <target> <out> [options]
#                                     png | uvtt | foundry | tiled | pdf | bundle | all
#                                     (opens a small window: exports render on the GPU)
#   ./run.sh shot <out.png> [map]     screenshot of the window (home, or the editor with a map)
#   ./run.sh check                    load every script, report parse errors
#   ./run.sh test [filter]            run the unit tests (headless); filter by name
#   ./run.sh examples                 regenerate examples/*.hexmap
#   ./run.sh packs                    regenerate the placeholder art and manifests
#   ./run.sh sheet <pack> <out.png>   contact sheet of a pack's assets
#   ./run.sh edit                     open the Godot editor on this project
#   ./run.sh doctor                   what it found, and what it will use
#
# Finds Godot in $GODOT, on PATH, in the usual macOS app locations, or — failing
# all that — downloads the pinned build to ~/.cache/hexmap/godot and uses that.
# Works from Git Bash on Windows too (the console build, so output shows).
# Rebuilds Godot's script class cache (.godot/, gitignored) when a clone or pull
# has left it missing or stale, so `class_name` lookups don't fail to parse.
#
# Environment:
#   GODOT             path to a Godot binary, overriding every search
#   HEXMAP_RENDERER   rendering driver for windowed runs (default: opengl3
#                     under WSL, Godot's own default elsewhere)

set -euo pipefail

GODOT_VERSION="4.7.1-stable"
GODOT_MIN_MAJOR=4
GODOT_MIN_MINOR=7

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hexmap/godot/$GODOT_VERSION"

die() { printf '%s\n' "run.sh: $*" >&2; exit 1; }
note() { printf '%s\n' "run.sh: $*" >&2; }

# ------------------------------------------------------------------ platform --

is_wsl() {
	[[ -n "${WSL_DISTRO_NAME:-}" ]] && return 0
	[[ -r /proc/sys/kernel/osrelease ]] && grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease
}

godot_asset() {
	case "$(uname -s)" in
		Darwin) printf 'Godot_v%s_macos.universal.zip\n' "$GODOT_VERSION" ;;
		Linux)
			case "$(uname -m)" in
				x86_64|amd64) printf 'Godot_v%s_linux.x86_64.zip\n' "$GODOT_VERSION" ;;
				aarch64|arm64) printf 'Godot_v%s_linux.arm64.zip\n' "$GODOT_VERSION" ;;
				*) die "no pinned Godot build for $(uname -m); install Godot $GODOT_VERSION yourself and set \$GODOT" ;;
			esac ;;
		MINGW*|MSYS*|CYGWIN*) printf 'Godot_v%s_win64.exe.zip\n' "$GODOT_VERSION" ;;   # Git Bash on Windows
		*) die "unsupported platform $(uname -s); set \$GODOT to a Godot binary" ;;
	esac
}

godot_cached_binary() {
	case "$(uname -s)" in
		Darwin) printf '%s/Godot.app/Contents/MacOS/Godot\n' "$CACHE_DIR" ;;
		Linux)
			case "$(uname -m)" in
				x86_64|amd64) printf '%s/Godot_v%s_linux.x86_64\n' "$CACHE_DIR" "$GODOT_VERSION" ;;
				*) printf '%s/Godot_v%s_linux.arm64\n' "$CACHE_DIR" "$GODOT_VERSION" ;;
			esac ;;
		# The console build: it writes to stdout, which scripts and CI need.
		MINGW*|MSYS*|CYGWIN*) printf '%s/Godot_v%s_win64_console.exe\n' "$CACHE_DIR" "$GODOT_VERSION" ;;
	esac
}

# ---------------------------------------------------------------- find godot --

godot_new_enough() {
	local v major minor
	v="$("$1" --version 2>/dev/null | tail -n 1 | tr -d '\r')" || return 1
	[[ $v =~ ^([0-9]+)\.([0-9]+) ]] || return 1
	major="${BASH_REMATCH[1]}"; minor="${BASH_REMATCH[2]}"
	(( major > GODOT_MIN_MAJOR )) && return 0
	(( major == GODOT_MIN_MAJOR && minor >= GODOT_MIN_MINOR ))
}

download_godot() {
	local asset url tmp
	asset="$(godot_asset)"
	url="https://github.com/godotengine/godot/releases/download/$GODOT_VERSION/$asset"
	command -v unzip >/dev/null || die "unzip is needed to install Godot (apt install unzip)"
	command -v curl >/dev/null || die "curl is needed to install Godot"
	note "downloading Godot $GODOT_VERSION -> $CACHE_DIR"
	mkdir -p "$CACHE_DIR"
	tmp="$CACHE_DIR/.download.zip"
	curl -fL --retry 3 --progress-bar -o "$tmp" "$url" || die "download failed: $url"
	unzip -q -o "$tmp" -d "$CACHE_DIR" || die "could not unpack $tmp"
	rm -f "$tmp"
	[[ "$(uname -s)" == Darwin ]] && xattr -dr com.apple.quarantine "$CACHE_DIR/Godot.app" 2>/dev/null
	chmod +x "$(godot_cached_binary)" 2>/dev/null || true
	[[ -x "$(godot_cached_binary)" ]] || die "downloaded archive did not contain the expected binary"
}

find_godot() {
	local c cached
	if [[ -n "${GODOT:-}" ]]; then
		[[ -x "$GODOT" ]] || die "\$GODOT is not an executable: $GODOT"
		GODOT_BIN="$GODOT"
		godot_new_enough "$GODOT_BIN" || note "warning: \$GODOT is older than $GODOT_MIN_MAJOR.$GODOT_MIN_MINOR; this project needs 4.7+"
		return
	fi
	cached="$(godot_cached_binary)"
	for c in \
		"$(command -v godot 2>/dev/null || true)" \
		"$(command -v godot4 2>/dev/null || true)" \
		"$(command -v Godot 2>/dev/null || true)" \
		"/Applications/Godot.app/Contents/MacOS/Godot" \
		"$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
		"/opt/homebrew/bin/godot" \
		"/usr/local/bin/godot" \
		"$cached"
	do
		[[ -n "$c" && -x "$c" ]] || continue
		if godot_new_enough "$c"; then GODOT_BIN="$c"; return; fi
	done
	download_godot
	GODOT_BIN="$cached"
}

# ------------------------------------------------------------- class cache --

# `class_name` identifiers resolve through .godot/global_script_class_cache.cfg,
# which only an editor/import pass writes. .godot/ is gitignored, so a fresh
# clone arrives without it and every script naming another class fails to
# parse. A headless import rebuilds it in a couple of seconds.
CLASS_CACHE="$PROJECT_DIR/.godot/global_script_class_cache.cfg"

class_cache_stale() {
	[[ -f "$CLASS_CACHE" ]] || return 0
	local f name res
	while IFS= read -r f; do
		name="$(sed -n 's/^class_name[[:space:]]\{1,\}\([A-Za-z_][A-Za-z0-9_]*\).*/\1/p' "$f" | head -n 1)"
		[[ -n "$name" ]] || continue
		res="res://${f#"$PROJECT_DIR"/}"
		grep -q "\"class\": &\"$name\"" "$CLASS_CACHE" && grep -q "\"path\": \"$res\"" "$CLASS_CACHE" || return 0
	done < <(find "$PROJECT_DIR/hexmap" "$PROJECT_DIR/tools" "$PROJECT_DIR/tests" -name '*.gd')
	return 1
}

refresh_class_cache() {
	class_cache_stale || return 0
	note "script class cache is missing or stale; rebuilding it"
	"$GODOT_BIN" --headless --path "$PROJECT_DIR" --import >/dev/null 2>&1 || true
	class_cache_stale && note "warning: class cache is still stale; open the editor once (./run.sh edit) and quit"
	return 0
}

# ---------------------------------------------------------------- graphics --

setup_graphics() {
	GUI_FLAGS=()
	is_wsl || return 0
	[[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] || note "warning: no DISPLAY or WAYLAND_DISPLAY; WSLg may not be running"
	if [[ -z "${GALLIUM_DRIVER:-}" && -e /usr/lib/wsl/lib/libd3d12.so ]]; then
		export GALLIUM_DRIVER=d3d12
	fi
	GUI_FLAGS+=(--rendering-driver "${HEXMAP_RENDERER:-opengl3}")
	if ! ldconfig -p 2>/dev/null | grep -q 'libasound\.so\.2\|libpulse\.so\.0'; then
		GUI_FLAGS+=(--audio-driver Dummy)
	fi
}

# ---------------------------------------------------------------- commands --

usage() {
	sed -n '2,/^[^#]/p' "${BASH_SOURCE[0]}" | sed '$d; s/^#\{1,\} \{0,1\}//'
}

main() {
	local cmd="${1:-app}"
	case "$cmd" in
		-h|--help|help) usage; return 0 ;;
	esac
	case "$cmd" in
		app|edit|godot-editor|editor|table|player|export|shot|check|test|examples|packs|sheet|godot|install|doctor) shift || true ;;
		*) cmd="app" ;;
	esac

	find_godot
	setup_graphics
	case "$cmd" in
		app|editor|table|player|shot|export|check|test|examples|packs|sheet) refresh_class_cache ;;
	esac

	case "$cmd" in
		install)
			download_godot
			note "installed: $(godot_cached_binary)"
			;;
		doctor)
			printf 'godot       %s\n' "$GODOT_BIN"
			printf 'version     %s\n' "$("$GODOT_BIN" --version 2>/dev/null | tail -n 1)"
			printf 'project     %s\n' "$PROJECT_DIR"
			printf 'platform    %s %s%s\n' "$(uname -s)" "$(uname -m)" "$(is_wsl && echo ' (WSL)')"
			printf 'gui flags   %s\n' "${GUI_FLAGS[*]:-}"
			printf 'class cache %s\n' "$(class_cache_stale && echo 'missing or stale (rebuilt on next run)' || echo ok)"
			;;
		app)
			exec "$GODOT_BIN" --path "$PROJECT_DIR" ${GUI_FLAGS[@]+"${GUI_FLAGS[@]}"} -- "$@"
			;;
		editor|table|player)
			exec "$GODOT_BIN" --path "$PROJECT_DIR" ${GUI_FLAGS[@]+"${GUI_FLAGS[@]}"} -- "--$cmd" "$@"
			;;
		edit|godot-editor)
			exec "$GODOT_BIN" --editor --path "$PROJECT_DIR" ${GUI_FLAGS[@]+"${GUI_FLAGS[@]}"}
			;;
		shot)
			[[ $# -ge 1 ]] || die "usage: ./run.sh shot <out.png> [map.hexmap]"
			exec "$GODOT_BIN" --path "$PROJECT_DIR" --resolution 1600x1000 ${GUI_FLAGS[@]+"${GUI_FLAGS[@]}"} -- ${2:+"$2"} --shot "$1"
			;;
		export)
			[[ $# -ge 3 ]] || die "usage: ./run.sh export <map.hexmap> <png|uvtt|foundry|tiled|pdf|bundle|all> <out> [options]"
			exec "$GODOT_BIN" --path "$PROJECT_DIR" --resolution 480x320 ${GUI_FLAGS[@]+"${GUI_FLAGS[@]}"} -s tools/export_cli.gd -- "$@"
			;;
		check)
			exec "$GODOT_BIN" --headless --path "$PROJECT_DIR" -s tools/check_scripts.gd
			;;
		test)
			exec "$GODOT_BIN" --headless --path "$PROJECT_DIR" -s tests/run_tests.gd ${1:+-- "$1"}
			;;
		examples)
			exec "$GODOT_BIN" --headless --path "$PROJECT_DIR" -s tools/make_examples.gd
			;;
		packs)
			exec "$GODOT_BIN" --headless --path "$PROJECT_DIR" -s tools/gen_pack_art.gd
			;;
		sheet)
			[[ $# -ge 2 ]] || die "usage: ./run.sh sheet <pack_id> <out.png> [cell_px]"
			exec "$GODOT_BIN" --headless --path "$PROJECT_DIR" -s tools/pack_sheet.gd -- "$@"
			;;
		godot)
			exec "$GODOT_BIN" "$@"
			;;
	esac
}

main "$@"
