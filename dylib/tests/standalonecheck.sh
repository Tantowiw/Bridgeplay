#!/bin/sh
# shellcheck disable=SC2016 # the sh -ec programs expand their own variables
set -e
SRC="${1:-$(dirname "$0")/../feats/compat_run.sh}"
[ -f "$SRC" ] || { echo "standalonecheck: $SRC not present, skipped"; exit 0; }

# The BRIDGEPLAY_ mapping and the standalone block that follows it, the client lookup the
# bridge staging ends with, and the two functions that touch Steam's own folders.
top=$(sed -n '/^for np_name in /,/^fi$/p' "$SRC")
case "$top" in
  *'np_standalone=1'*) ;;
  *) echo "FAIL: the standalone block not found after the BRIDGEPLAY_ mapping in $SRC"; exit 1 ;;
esac
client=$(sed -n '/^  native_client="\$STEAM_COMPAT_CLIENT_INSTALL_PATH"$/,/^  link_legacy_steam_dll$/p' "$SRC")
[ -n "$client" ] || { echo "FAIL: the Steam client lookup not found in $SRC"; exit 1; }
legacy=$(sed -n '/^install_legacycompat() {/,/^}/p' "$SRC")
link=$(sed -n '/^link_legacy_steam_dll() {/,/^}/p' "$SRC")
[ -n "$legacy" ] && [ -n "$link" ] || { echo "FAIL: install_legacycompat or link_legacy_steam_dll not found in $SRC"; exit 1; }
body="$top
$legacy
$link
$client"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n         want [%s]\n         got  [%s]\n' "$1" "$2" "$3"; fails=$((fails + 1)); }
is() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }

# A Steam client where the run script looks for one, a bridge with a legacycompat file, and a
# game folder inside a library folder.
steam="$work/home/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS"
mkdir -p "$steam/legacycompat" "$work/bridge/legacycompat" "$work/library/Game"
printf 'client Steam.dll\n' > "$steam/legacycompat/Steam.dll"
printf 'bridge evaluator\n' > "$work/bridge/legacycompat/evaluator"

# Prints the client path the launch ends with, then whether it touched Steam's folders.
launch() {
	rm -f "$steam/legacycompat/evaluator" "$work/library/Steam.dll"
	: > "$work/log"
	env -i HOME="$work/home" PATH="$PATH" bridge_src="$work/bridge" log="$work/log" \
		STEAM_COMPAT_INSTALL_PATH="$work/library/Game" body="$body" "$@" \
		sh -ec 'eval "$body"; printf "client=%s overlay=%s\n" "$STEAM_COMPAT_CLIENT_INSTALL_PATH" "$STEAM_DYLD_INSERT_LIBRARIES"' \
		> "$work/out" 2>&1 || true
	[ -f "$steam/legacycompat/evaluator" ] && echo "copied into Steam" >> "$work/out"
	[ -L "$work/library/Steam.dll" ] && echo "linked beside the game" >> "$work/out"
	cat "$work/out"
}

echo "== a Steam launch finds the client and keeps its legacy files"
is "the client is looked up, the evaluator copied and Steam.dll linked" \
	"client=$steam overlay=
copied into Steam
linked beside the game" "$(launch)"

echo "== a standalone launch leaves Steam alone"
is "BRIDGEPLAY_STANDALONE=1 looks up nothing and touches nothing" "client= overlay=" \
	"$(launch BRIDGEPLAY_STANDALONE=1)"
is "a client path and overlay passed in are dropped" "client= overlay=" \
	"$(launch BRIDGEPLAY_STANDALONE=1 STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam" STEAM_DYLD_INSERT_LIBRARIES=/x/overlay.dylib)"
is "the NOTPROTON_ spelling works too" "client= overlay=" "$(launch NOTPROTON_STANDALONE=1)"
is "BRIDGEPLAY_STANDALONE=0 is a Steam launch" \
	"client=$steam overlay=
copied into Steam
linked beside the game" "$(launch BRIDGEPLAY_STANDALONE=0)"

echo "== a standalone prefix gets steam.exe and no steamclient"
# The bridge staging block, as bridgecheck runs it.
stage_block=$(sed -n '/^bridge_files="steamclient64/,/^  verify_runner$/p' "$SRC" | sed '$d')
trigger=$(sed -n '/^install_lsteamclient_trigger() {/,/^}/p' "$SRC")
legacy_dll=$(sed -n '/^install_legacy_steam_dll() {/,/^}/p' "$SRC")
[ -n "$stage_block" ] && [ -n "$trigger" ] && [ -n "$legacy_dll" ] || { echo "FAIL: the bridge staging not found in $SRC"; exit 1; }
stage_body='same_volume() { :; }
volume_clones() { :; }
show_alert() { printf "alert: %s\n" "$1" >> "$log"; }
'"$stage_block
fi
$trigger
$legacy_dll
install_lsteamclient_trigger
install_legacy_steam_dll"
files="steamclient64.dll steamclient.dll tier0_s64.dll vstdlib_s64.dll tier0_s.dll vstdlib_s.dll lsteamclient.dll steam.exe"
mkdir -p "$work/bridge/i386-windows" "$work/bridge/x86_64-unix"
for f in $files; do printf 'bridge %s\n' "$f" > "$work/bridge/$f"; done
printf 'unix bridge\n' > "$work/bridge/x86_64-unix/lsteamclient.so"
printf 'trigger\n' > "$work/bridge/i386-windows/lsteamclient.dll"
printf 'legacy\n' > "$work/bridge/legacycompat/Steam.dll"
prefix="$work/pfx"
pfx_steam="$prefix/drive_c/Program Files (x86)/Steam"
mkdir -p "$prefix/drive_c/windows/syswow64"
# Each name in a folder, in byte order.
names() { for f in "$1"/*; do [ -e "$f" ] && printf '%s\n' "${f##*/}"; done | LC_ALL=C sort | tr '\n' ' '; }
stage() {
	: > "$work/log"
	env bridge_src="$work/bridge" WINEPREFIX="$prefix" prefix_steam="$pfx_steam" log="$work/log" \
		wine_unix="$work/runner/x86_64-unix" STEAM_COMPAT_DATA_PATH="" np_standalone="$1" body="$stage_body" \
		sh -ec 'eval "$body"; echo reached' > "$work/out" 2>&1 || true
	names "$pfx_steam"
	names "$prefix/drive_c/windows/syswow64"
}
is "a Steam launch stages the whole bridge, the trigger and Steam.dll" \
	"lsteamclient.dll lsteamclient.so steam.exe steamclient.dll steamclient64.dll tier0_s.dll tier0_s64.dll vstdlib_s.dll vstdlib_s64.dll Steam.dll lsteamclient.dll " \
	"$(stage 0)"
rm -f "$prefix/drive_c/windows/syswow64/"*
is "a standalone launch on the same prefix keeps only steam.exe" "steam.exe " "$(stage 1)"
is "the launch goes on" reached "$(cat "$work/out")"

echo "== the launch still goes through steam.exe"
# steam.exe waits for every process the game starts, so a launcher that hands over to its
# client and exits does not end the session.
is "the game is started through the shim in either mode" 1 "$(grep -c '^set -- --args "\$shim_exe" "\$@"$' "$SRC")"
is "the log names who keeps the input permission" 1 \
	"$(grep -c 'input permission stays with the app that started it' "$SRC")"

[ "$fails" -eq 0 ] || { echo "==> standalonecheck: $fails failure(s)"; exit 1; }
echo "==> standalonecheck: a standalone launch reads and writes nothing of Steam's"
