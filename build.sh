#!/bin/zsh
# Compile the (VMMaker-generated) VectorEnginePlugin C into a loadable, -O3 bundle.
#
#   ./build.sh [source.c] [output.bundle]
#
# Defaults: generated/VectorEnginePlugin.c  ->  VectorEnginePlugin
#
# Optimization level: -O3. The shipped Cuis bundle is size-optimized (-Os-like: smaller
# __TEXT, and ~8% slower than the same source at -O2), so -O2 already matches it before any
# algorithm change; -O3 is a further ~9% and is bit-identical to -O2 (conforming
# optimization never reassociates floats -- verified same-checksum output). Do NOT use
# -ffast-math (relaxes IEEE, breaking the opaque-fast-path identity) or -O0 (markedly
# slower than even the shipped bundle). Keep -O3.
#
# Header dependency: the VM proxy/config headers from OpenSmalltalk. Point OSVM at a
# checkout (Cog branch); it is only needed at compile time, never shipped:
#   git clone --depth 1 --branch Cog https://github.com/OpenSmalltalk/opensmalltalk-vm.git osvm
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-$HERE/generated/VectorEnginePlugin.c}"
OUT="${2:-$HERE/VectorEnginePlugin}"
OSVM="${OSVM:-$HERE/osvm}"

if [ ! -f "$OSVM/platforms/Cross/vm/sqVirtualMachine.h" ]; then
  echo "OpenSmalltalk headers not found under OSVM=$OSVM" >&2
  echo "  git clone --depth 1 --branch Cog https://github.com/OpenSmalltalk/opensmalltalk-vm.git \"$OSVM\"" >&2
  exit 1
fi

# arch: arm64 by default; override with ARCH=x86_64 on Intel.
ARCH="${ARCH:-arm64}"

clang -arch "$ARCH" -O3 -g -bundle -undefined dynamic_lookup \
  -DHAVE_CONFIG_H=1 -DNDEBUG=1 -DDEBUGVM=0 -DBUILD_FOR_OSX=1 \
  -I "$OSVM/platforms/iOS/vm/OSX" \
  -I "$OSVM/platforms/Cross/vm" \
  -I "$OSVM/src/spur64.cog" \
  -o "$OUT" "$SRC"

echo "built $OUT ($(wc -c < "$OUT") bytes, $ARCH -O3)"
echo "install: copy over <YourVM>.app/Contents/Resources/VectorEnginePlugin.bundle/Contents/MacOS/VectorEnginePlugin"
echo "then re-sign: codesign --force --deep -s - <YourVM>.app"
