# win32u-patch

`app/Sources/BridgeplayApp/Resources/win32u-winecx-11.17.so` is winecx `e0aa380`'s
`win32u.so` with two changes, made in this order.

## Legacy GL extensions: `winecx-legacy-gl-extensions.patch`

`parse_current_extensions()` in `dlls/win32u/opengl.c` parsed a legacy (< 3.0) context's
`GL_EXTENSIONS` into a local array that shadowed its argument, then set `extensions[i] = TRUE`
on that local copy. A legacy context therefore had no GL extensions at all: `glGetString(GL_EXTENSIONS)`
returned only `WGL_EXT_extensions_string WGL_EXT_swap_control`. libGDX/LWJGL games, which ask
for a plain `wglCreateContext` context, then stop with "OpenGL 2.0 or higher with the FBO
extension is required" (DW3 Online, Java 17). Core and 3.x contexts (wined3d) were not affected.

The patch is Wine commit `1c2d909829c757fdf70c8d863642cd0ae9b81e59` by Rémi Bernon ("win32u:
Parse extensions directly into the BOOLEAN set.", in Wine 11.19 and later), re-diffed against
winecx `e0aa380`. With it, the default context on an M5 reports `2.1 Metal - 91.7` with 132
extensions, `GL_EXT_framebuffer_object` and `GL_ARB_framebuffer_object` among them.

Build the unix objects of `dlls/win32u/win32u.so` in the tree configured as in
`winemac-patch/README.md`, with the libraries the runtime's CI configured (freetype and
MoltenVK, which that configure does not find) given as defines and the configured `CFLAGS`
kept:

```sh
git -C winecx apply ../win32u-patch/winecx-legacy-gl-extensions.patch
cd build
MACOSX_DEPLOYMENT_TARGET=26.0 make CFLAGS="-O2 -Wno-error=implicit-function-declaration \
  -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -I$(brew --prefix freetype)/include/freetype2 \
  -DHAVE_FT2BUILD_H=1 -DSONAME_LIBFREETYPE=\\\"libfreetype.6.dylib\\\" \
  -DSONAME_LIBMOLTENVK=\\\"libMoltenVK.dylib\\\" -DSONAME_LIBVULKAN=\\\"libMoltenVK.dylib\\\"" \
  dlls/win32u/<each object of win32u.so>        # the .o list of its Makefile rule
clang -arch x86_64 -m64 -o win32u.so -dynamiclib -install_name @rpath/win32u.so \
  -Wl,-rpath,@loader_path/ dlls/win32u/*.o dlls/win32u/dibdrv/*.o <runtime>/ntdll.so \
  -framework CoreText -framework AppKit -lm
codesign -fs - -i win32u-5555494472d344e534d53608b2b5d84e28c14c6d win32u.so
install_name_tool -add_rpath @loader_path/../../ win32u.so
codesign -fs - -i win32u-5555494472d344e534d53608b2b5d84e28c14c6d win32u.so
```

`<runtime>` is runtime 4.7.3's `lib/wine/x86_64-unix`. Built this way without the patch, the
result matches the runtime's `win32u.so` (sha256
`5ea985227c89b57e5f48d7422059db933d32a213e172577d68e4415d6f7c2a71`) in every section, all
4217 symbols and their addresses, and every load command; only the linker's version,
`__LINKEDIT` and the signature differ. With the patch, sha256
`6b6cd9c69f6c0c07e6c52e5ac20c98df9107ca49dbb07304e2522153d9859c3c` (Xcode 27 ld 27106.1).

## Driver version: `patch-driver-version.sh`

A binary edit of that build, not a source patch: `driver_vendor_to_version()` reports NVIDIA
as `35.0.15.6094` (560.94) in the display class key's `DriverVersion`, which games that read it
(Deadlock) call out of date, hiding DLSS. The script replaces that string and the DirectX
key's QWORD `DriverVersion` (`35.0.15.8180`) with `35.0.15.9541` (595.41), the version
`nvapi-shim` reports, and signs the file ad hoc with its original identifier. Keep it in step
with `wined3d-patch` and `nvapi-shim`.

```sh
win32u-patch/patch-driver-version.sh <the win32u.so built above>
```

The script refuses any input other than the build above (sha256 `6b6cd9c6…`). Output sha256
`30dfff79def32f1b238e45f09d293c6da5e7f00619ae7f61784546755a772889`, pinned in
`FreeEngineWinecx.swift` (`v1117.nvidia`) and `SignedPin.swift`.
