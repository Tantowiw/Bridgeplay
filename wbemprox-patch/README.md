# wbemprox-patch

`winecx-automatic-pagefile.patch` adds `AutomaticManagedPagefile` to `Win32_ComputerSystem` in
`dlls/wbemprox/builtin.c` and sets it to TRUE (`VARIANT_TRUE`), which is Windows' default.
Digimon Story Time Stranger asks for it before it starts. When it is not TRUE and
`Win32_PageFileSetting` has no rows, the game wants `GlobalMemoryStatusEx` to show at least
8 GiB of `ullAvailPageFile`, and otherwise stops with "Insufficient memory or disk space". Wine
had no such property, so `Get` failed with `WBEM_E_NOT_FOUND`. On macOS, Wine's commit limit is
RAM plus the swap in use, so a 16 GB Mac with no swap in use showed about 5 GiB. macOS grows
its swap on demand, which is what a system-managed page file does, so TRUE is accurate.
Wine master has no such change (checked 2026-10-28). Against winecx `e0aa380`; the build and
pin are in `docs/WINECX.md` (Managed page file).
