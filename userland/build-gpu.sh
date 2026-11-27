#!/bin/bash
# GPU user space for the ginkgo port (iOS 16.7.16, arm64), built on macOS with Xcode:
#   libOSMesa.8.dylib   Mesa 25.0.7, gallium freedreno (+softpipe) behind OSMesa, talking to the
#                       kernel's RedwoodGPU service through mesa/redwood-drm (patches from topaz)
#   libtopaz-gl.dylib   OpenGL ES behind EAGLContext for CoreAnimation's window server
#                       (gpu/eagl.c + gpu/gl_osmesa.c; table made by tools/mkeagl.py)
#   libtopaz-inject.dylib  loaded into backboardd; loads libtopaz-gl when the kernel has a GPU
#   backboardd-wrap     /usr/libexec/backboardd stand-in that sets DYLD_INSERT_LIBRARIES
# Sources: MakrSas/ios-topaz userland/ (from HakiOS, MIT) and HakiOS userland/mkeagl.py,
# src/eagl_slots.txt (MIT). See CREDITS.md. Output: userland/out/.
set -euo pipefail
U=$(cd "$(dirname "$0")" && pwd)
OUT=$U/out
B=$U/build-mesa
mkdir -p "$OUT" "$B"

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
MSDK=$(xcrun --sdk macosx --show-sdk-path)
CLANG=$(xcrun --sdk iphoneos -f clang)
TARGET=(-target arm64-apple-ios16.0 -isysroot "$SDK")
echo "iPhoneOS SDK: $SDK"

# ---- Mesa (as topaz's mk-mesa-mac.sh, with this tree's paths) ----
VERSION=25.0.7
SHA256=592272df3cf01e85e7db300c449df5061092574d099da275d19e97ef0510f8a6
cd "$B"
[ -f mesa-$VERSION.tar.xz ] || curl -sL --fail -o mesa-$VERSION.tar.xz https://archive.mesa3d.org/mesa-$VERSION.tar.xz
echo "$SHA256  mesa-$VERSION.tar.xz" | shasum -a 256 -c --quiet
rm -rf mesa-$VERSION build
tar xJf mesa-$VERSION.tar.xz
for p in "$U"/mesa/*.patch; do
	echo "mesa patch: $(basename "$p")"
	patch -s --no-backup-if-mismatch -d mesa-$VERSION -p1 < "$p"
done
cp -r "$U/mesa/redwood-drm" mesa-$VERSION/src/redwood-drm
python3 -m venv venv
venv/bin/pip -q install mako pyyaml packaging
export PATH=$B/venv/bin:$(brew --prefix bison)/bin:$PATH
cat > cross.ini <<INI
[binaries]
c = ['$CLANG', '-target', 'arm64-apple-ios16.0', '-isysroot', '$SDK']
cpp = ['$CLANG++', '-target', 'arm64-apple-ios16.0', '-isysroot', '$SDK', '-fuse-cxa-atexit']
objc = ['$CLANG', '-target', 'arm64-apple-ios16.0', '-isysroot', '$SDK']
ar = '$(xcrun -f ar)'
ranlib = '$(xcrun -f ranlib)'
strip = '$(xcrun -f strip)'
pkg-config = 'false'

[host_machine]
system = 'darwin'
subsystem = 'ios'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'

[properties]
needs_exe_wrapper = true
INI
meson setup build mesa-$VERSION --cross-file cross.ini --wrap-mode=nofallback \
	--prefix=/topaz --libdir=lib --buildtype=release -Db_ndebug=true \
	-Dplatforms= -Dgallium-drivers=softpipe,freedreno -Dfreedreno-kmds=msm -Dvulkan-drivers= -Dglx=disabled \
	-Degl=disabled -Dgbm=disabled -Dosmesa=true -Dllvm=disabled -Dshared-glapi=enabled -Dgles1=disabled \
	-Dgles2=enabled -Dopengl=true -Dzstd=disabled -Dxmlconfig=disabled -Dexpat=disabled -Dshader-cache=disabled \
	-Dvalgrind=disabled -Dlibunwind=disabled -Dglvnd=disabled -Dvideo-codecs= -Dtools= -Dgallium-vdpau=disabled \
	-Dgallium-va=disabled -Dgallium-xa=disabled -Dlmsensors=disabled -Dbuild-tests=false
ninja -C build
$(xcrun -f strip) -x -o "$OUT/libOSMesa.8.dylib" build/src/gallium/targets/osmesa/libOSMesa.8.dylib
install_name_tool -id /topaz/lib/libOSMesa.8.dylib "$OUT/libOSMesa.8.dylib"
# every non-system library libOSMesa needs goes beside it (shared glapi, ...)
for dep in $(otool -L "$OUT/libOSMesa.8.dylib" | awk 'NR>2 {print $1}' | grep -v -E '^/(usr/lib|System)/'); do
	name=$(basename "$dep")
	src=$(find build -name "$name" -type f | head -1)
	[ -n "$src" ] || { echo "missing dependency $dep"; exit 1; }
	$(xcrun -f strip) -x -o "$OUT/$name" "$src"
	install_name_tool -id "/topaz/lib/$name" "$OUT/$name"
	install_name_tool -change "$dep" "/topaz/lib/$name" "$OUT/libOSMesa.8.dylib"
	echo "dependency $name -> /topaz/lib/$name"
done
nm -gU "$OUT/libOSMesa.8.dylib" | awk '$3 ~ /^_gl/ { print substr($3, 2) }' > "$B/exported-gl.txt"
GLXML=mesa-$VERSION/src/mapi/glapi/registry/gl.xml

# ---- our libraries ----
# The iOS SDK has IOKit's link stub but not its headers: take the headers from the macOS SDK.
INC=$B/inc; rm -rf "$INC"; mkdir -p "$INC"
cp -R "$MSDK/System/Library/Frameworks/IOKit.framework/Headers" "$INC/IOKit"
python3 "$U/tools/mkeagl.py" "$U/tools/eagl_slots.txt" "$GLXML" "$B/exported-gl.txt" "$U/gpu/eagl.c" > "$B/eagl_gen.h"
CC=("$CLANG" "${TARGET[@]}" -O1 -Wall -Wno-unused -I"$B" -I"$U/gpu" -I"$INC")
"${CC[@]}" -dynamiclib -install_name /topaz/lib/libtopaz-gl.dylib \
	-framework CoreFoundation -framework IOKit -framework IOSurface -lobjc "$OUT/libOSMesa.8.dylib" \
	-o "$OUT/libtopaz-gl.dylib" "$U/gpu/eagl.c" "$U/gpu/gl_osmesa.c"
"${CC[@]}" -dynamiclib -install_name /topaz/lib/libtopaz-inject.dylib \
	-framework CoreFoundation -framework IOKit -lobjc -o "$OUT/libtopaz-inject.dylib" "$U/gpu/topaz_inject.c"
"${CC[@]}" -o "$OUT/backboardd-wrap" "$U/gpu/bbd_wrap.c"
for f in "$OUT"/*; do codesign -f -s - "$f"; done
cd "$OUT"
for f in *; do echo "== $f"; file "$f"; otool -L "$f" | tail -n +2; done
shasum -a 256 * > SHA256SUMS
ls -la
