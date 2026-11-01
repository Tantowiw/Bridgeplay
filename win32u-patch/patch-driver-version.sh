#!/bin/sh
# Rebuilds app/Sources/BridgeplayApp/Resources/win32u-winecx-11.17.so from the win32u.so
# built from winecx e0aa380 with winecx-legacy-gl-extensions.patch (README.md). Its
# driver_vendor_to_version() reports NVIDIA as "35.0.15.6094" (560.94) in the display
# class key's DriverVersion; games that read it
# (Source 2 / Deadlock) call that out of date and hide DLSS behind the NVIDIA identity
# D3DMetal is given. The one copy of the string becomes "35.0.15.9541" (595.41, the
# version nvapi-shim reports), same length, and so does the DirectX key's QWORD
# DriverVersion (35.0.15.8180), then the file is signed ad hoc with its original identifier.
set -eu
src=${1:?usage: patch-driver-version.sh <win32u.so built with winecx-legacy-gl-extensions.patch>}
out="$(cd "$(dirname "$0")/.." && pwd)/app/Sources/BridgeplayApp/Resources/win32u-winecx-11.17.so"
want=6b6cd9c69f6c0c07e6c52e5ac20c98df9107ca49dbb07304e2522153d9859c3c
[ "$(shasum -a 256 "$src" | cut -d' ' -f1)" = "$want" ] || { echo "not the win32u.so built with winecx-legacy-gl-extensions.patch" >&2; exit 1; }
ident=$(codesign -dv "$src" 2>&1 | sed -n 's/^Identifier=//p')
python3 - "$src" "$out" <<'PY'
import sys
data = open(sys.argv[1], 'rb').read()
import struct
old, new = b'35.0.15.6094\x00', b'35.0.15.9541\x00'
assert data.count(old) == 1
data = data.replace(old, new)
# HKLM\Software\Microsoft\DirectX\<luid>\DriverVersion, a QWORD immediate: 35.0.15.8180
# (581.80) becomes 35.0.15.9541 too, so every place a game reads the version agrees.
old, new = struct.pack('<Q', 0x230000000f1ff4), struct.pack('<Q', 0x230000000f2545)
assert data.count(old) == 1
open(sys.argv[2], 'wb').write(data.replace(old, new))
PY
codesign -fs - -i "$ident" "$out"
shasum -a 256 "$out"
