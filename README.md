# Cuis-VectorEngine

A faster drop-in build of Cuis Smalltalk's **VectorEnginePlugin** (the whole-pixel,
anti-aliased vector rasterizer behind `VectorCanvas`), plus a small image-side package
(`VectorEngineOpt`) that adds a glyph-tile cache and a few rendering fast paths.

Every change here is **bit-identical** to the stock rasterizer's output — verified by
render oracles (per-pixel checksums of the same scene through both builds) and, where a
shortcut relies on a floating-point identity, by exhaustive proof (see
`check_alpha_identity.c`). It is faster, not different.

The plugin is generated from Slang (the restricted Smalltalk that VMMaker translates to
C), exactly like the upstream plugin — the sources in `slang/` are the source of truth,
`generated/VectorEnginePlugin.c` is their committed output.

## What you get

On the working benchmark — a clean fullscreen VM with the Blueprint desktop, a System
Browser maximized to 2880×1800, timed as full-repaint frames — the frame cost went from
**~55 ms to ~33 ms** over this work. Two independent multipliers stack:

- **~3.5× from compiling at `-O2`** alone. The stock VM builds internal plugins at `-O0`;
  see the note below.
- **up to ~2.5× more from the algorithmic changes** in `slang/` (raster-microbenchmark
  total, measured within `-O2`), and separately a **2× cut in text-draw cost** from the
  fused glyph path.

---

## Compiling

The plugin is one C file plus the VM's proxy/config headers. You need those headers from
OpenSmalltalk (compile-time only, never shipped):

```sh
# 1. VM headers (Cog branch)
git clone --depth 1 --branch Cog \
  https://github.com/OpenSmalltalk/opensmalltalk-vm.git osvm

# 2. compile the committed C into an -O2 bundle
./build.sh
# -> ./VectorEnginePlugin   (arm64, -O2)
```

`build.sh` invokes:

```sh
clang -arch arm64 -O2 -g -bundle -undefined dynamic_lookup \
  -DHAVE_CONFIG_H=1 -DNDEBUG=1 -DDEBUGVM=0 -DBUILD_FOR_OSX=1 \
  -I osvm/platforms/iOS/vm/OSX -I osvm/platforms/Cross/vm -I osvm/src/spur64.cog \
  -o VectorEnginePlugin generated/VectorEnginePlugin.c
```

On Intel: `ARCH=x86_64 ./build.sh`. Point at a different headers checkout with
`OSVM=/path ./build.sh`.

### ⚠️ Keep `-O2` — it is half the speedup

The Cuis VM ships the VectorEnginePlugin **compiled into the VM at `-O0`** (no
optimization). This rasterizer is a tight per-pixel loop, so `-O0` leaves ~3.5× on the
floor before any algorithm changes:

| raster microbenchmark total | `-O0` (as shipped) | `-O2` |
|---|---|---|
| stock plugin | 2483 ms | 714 ms |

Building this plugin as an **external `-O2` bundle** captures that immediately, and the
`slang/` changes compound on top. Do not build it at `-O0`.

## Using it

### 1. Install the plugin bundle

Overwrite the plugin binary inside your VM app and re-sign (macOS):

```sh
APP=/path/to/YourCuisVM.app
cp VectorEnginePlugin "$APP/Contents/Resources/VectorEnginePlugin.bundle/Contents/MacOS/VectorEnginePlugin"
codesign --force --deep -s - "$APP"
```

With just the bundle installed, all existing `VectorCanvas` drawing is faster and
pixel-for-pixel identical — no image changes required.

### 2. (Optional) Load the `VectorEngineOpt` package

`VectorEngineOpt.pck.st` adds the image-side pieces that need the augmented plugin:

- a **glyph-tile cache** and a **fused text path** (`drawUtf8String:…`,
  `pvtDrawTiledUtf8:…`, `GlyphTileCache`) — each `(font, size, glyph, sub-pixel phase)`
  rasterizes once, then whole runs composite as cached coverage tiles. ~2× on text draw.
- a **rule-3 morph-ids clear** override of `HybridCanvas>>opaqueImage:at:`.

Notes on dependencies:
- The glyph-tile / fused-text methods require **this** plugin build (they call prims it
  adds: `primStampCoverageRunWP`, `primBlendStampedCoverageRunWP`, `primClearMaskWP`,
  `primExtractCoverageWP`). They work with or without Blueprint.
- The `opaqueImage:at:` override speeds up the *Blueprint* wallpaper's background repair
  and is meant to load **after** the [Blueprint](https://github.com/mlajtos/Cuis-Blueprint)
  package (it overrides a method Blueprint introduces). Without Blueprint it is inert.

---

## What makes it faster

All plugin-side techniques are in `slang/`, layered `SlabStamping5.st` (base) →
`SlabStamping9.st`; the image-side ones are in `VectorEngineOpt.pck.st`.

**Strokes — slab stamping** (`slang/SlabStamping5.st`).
The stock stroke rasterizer walks a pen along the segment and stamps a distance-disk at
every hop, so each pixel is visited ~`penWidth·2/hop` times. Instead, for a whole
transformed segment, compute the **exact distance from each affected pixel to the
segment in one pass** (`slabStampSegmentWP…`) — per-scanline x-interval, analytic
point-to-segment distance, round caps falling out of the endpoint branches. Same alpha
function, a fraction of the work.

**Fills — bulk interior runs** (`blendFillOnlyWP…`, `blendStrokeAndFillWP…`).
A shape's interior is long runs of fully-covered pixels between anti-aliased edges. The
blend passes detect a clean interior run and blast it as a **bulk overwrite** (opaque
fill) or a hoisted-constant blend (translucent), skipping the per-pixel edge/clip
bookkeeping — bit-identical because the hoisted divisors are exactly 1.0.

**Opaque-target fast path** (`slang/SlabStamping6.st`, the `…WPAt:` helpers).
Over an opaque target — the universal case when drawing to the live Display — the alpha
composite's three divides and three multiplies are IEEE **identities**: `targetAlpha`
is exactly 1.0, and `alpha + (1−alpha)` rounds to exactly 1.0 for *every* float in
`[0,1]` (proved by brute force over all 2³⁰ such floats — `check_alpha_identity.c`). The
helper skips them. Measurable, and provably lossless.

**Gang-skip empty space** (`clearAffectedSpanFrom:max:`).
The blend sweep hops over runs of clear 16-pixel segments **eight segment-flags per
`uint64` compare** instead of one at a time — a window-chrome stroke sweeps its whole
bounding box for a ring that covers ~2% of it.

**Vectorizable stores.** The clean-run loops write `targetBits` and `morphIds` in
**separate** loops; a single-array constant-store loop vectorizes, the interleaved form
can't (the compiler must assume the two pointers alias).

**Extend bulk runs across clear segments** (`slang/SlabStamping7.st`).
A full-width interior row becomes **one** run instead of ~170 segment-sized ones — the
per-segment re-establishment cost is amortized away.

**Dirty-span journal** (`slang/SlabStamping8.st`).
The stampers record, per row, the `[minX, maxX]` of pixels they touched. The blend
passes clamp their sweep to that dirty span instead of the full shape bounding box. A
plugin-internal, per-target array; bit-identical by construction (pixels outside the
dirty span carry no stamps, so neither stroke alpha nor fill winding can change there).

**Fused stamp + blend for glyph runs** (`slang/SlabStamping9.st` +
`VectorEngineOpt`).
Cached glyph coverage tiles normally stamp into the alpha mask, which is then re-scanned
and blended — three memory passes. The fused path (`blendStampedCoverageRunWP…`)
composites the tiles **directly** with the fill color, applying the exact per-pixel
treatment (clip window, anti-aliased clip columns, span updates) the two-pass path
would. Kerned glyphs whose *ink* overlaps fall back to the mask path (which max-combines
them), so a run is partitioned and the result stays bit-identical. ~2× on text.

**Glyph-tile cache** (`VectorEngineOpt`, image-side).
`GlyphTileCache` bakes each `(font, effective size, glyph, sub-pixel phase)` once through
the normal outline pipeline and extracts its coverage; runs then composite cached tiles.
Scale-free (tiles bake on demand at the drawn size), so it inherits the rasterizer's
exact anti-aliasing.

**Faster morph-ids clear** (`VectorEngineOpt`, image-side).
Clearing the morph-ids buffer for exposed background used BitBlt `combinationRule: 0`,
which falls off BitBlt's fast path and runs **~11× slower** than the identical store
(5.8 ms vs 0.5 ms per 1.6 Mpx). A rule-3 store of a zero pixel writes exactly the same
0 at full speed.

---

## Layout

```
slang/            Slang source of truth (SlabStamping5..9 build the plugin; 10 = an
                  unwired RLE experiment, no net gain on short glyph runs)
generated/        VectorEnginePlugin.c — committed output of translating slang/
VectorEngineOpt.pck.st   image-side package (glyph-tile cache, fused text, ids-clear)
build.sh          compile generated C -> loadable -O2 bundle
regenerate/       scripts + notes to re-run the Slang->C translation (only if you edit slang/)
check_alpha_identity.c   brute-force proof behind the opaque-target fast path
```

## Correctness

The guiding rule for the whole project: **an optimization must produce bit-identical
output, or it does not ship.** Validation used offscreen `VectorCanvas` renders and live
`SystemWindow` captures checksummed pixel-for-pixel against the stock build, plus the
exhaustive float proof for the one shortcut that leans on an IEEE identity. When a
change traded correctness for speed (an early "consume the dirty journal in the blend"
variant), it was caught by a deterministic window-flight replay and fixed, not shipped.

## Provenance & license

Derived from Cuis's `VectorEnginePlugin-jmv.26` (by Juan Vuletich) and translated with
`VMMaker.oscog-eem.3767`. MIT-licensed (see `LICENSE`); the upstream VectorEnginePlugin
and OpenSmalltalk VM carry their own licenses.
