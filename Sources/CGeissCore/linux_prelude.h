// Linux build only (force-included by the Linux manifest). Two clashes macOS's libc++ never hits:
//  - win_compat.h defines MSVC's min/max macros, and libstdc++ does not shield its headers from
//    them, so every C/C++ header the core uses is read first;
//  - glibc still declares BSD's legacy gamma(), which Geiss names a setting after.
#define gamma glibc_legacy_gamma
#include <cmath>
#include <math.h>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <new>
#undef gamma
