# Cuis-VectorEngine

A faster drop-in build of Cuis Smalltalk's **VectorEnginePlugin** (the whole-pixel,
anti-aliased vector rasterizer behind `VectorCanvas`), plus a small image-side package
(`VectorEngineOpt`) that adds a glyph-tile cache and a few rendering fast paths.

Every change here is **bit-identical** to the stock rasterizer's output — verified by
render oracles (per-pixel checksums of the same scene through both builds) and, where a
shortcut relies on a floating-point identity, by exhaustive proof (see
`check_alpha_identity.c`). It is faster, not different.

The plugin is generated from Slang (the restricted Smalltalk that VMMaker translates to
C), exactly like the upstream plugin — `slang/SlabStamping.st` is the source of truth,
`generated/VectorEnginePlugin.c` is its committed translation.

## What you get

Directly measured against the plugin Cuis ships, same VM, same image, on a stroke-heavy
offscreen benchmark (`StrokeStorm`):

| VectorEnginePlugin | strokes/s |
|---|---|
| stock (Cuis 7.x) | 22 fps |
| this build | **58 fps** — ~2.6× |

The gain is algorithmic (see [techniques](#what-makes-it-faster)), not a compiler flag:
**Cuis already ships the plugin as an optimized external bundle**, so this is 2.6× over
an already-optimized baseline. With the optional `VectorEngineOpt` package, text drawing
is a further ~2× from a fused glyph-tile path.

---

## Building

Two stages. You normally only run **stage 2** — the translated C is committed.

### Stage 1 — translate Slang → C (only if you edit `slang/`)

`generated/VectorEnginePlugin.c` is VMMaker's C translation of the plugin methods in
`slang/SlabStamping.st`. If you change the Slang, regenerate it in a VMMaker image:

```sh
# build a VMMaker image once (Squeak trunk + VMMaker.oscog + the base VE plugin)
Squeak Squeak6.1alpha-XXXXX-64bit.image regenerate/load_all.st

# translate slang/SlabStamping.st -> regenerate/gen/VectorEnginePlugin.c
cd regenerate && Squeak <the-saved-VMMaker>.image generate.st
```

Then promote `regenerate/gen/VectorEnginePlugin.c` to `generated/`. Full details and the
headless gotchas are in [`regenerate/README.md`](regenerate/README.md).

### Stage 2 — compile C → loadable bundle

The C needs the VM's proxy/config headers from OpenSmalltalk (compile-time only, never
shipped):

```sh
# VM headers (Cog branch)
git clone --depth 1 --branch Cog \
  https://github.com/OpenSmalltalk/opensmalltalk-vm.git osvm

# compile the committed C into a bundle
./build.sh
# -> ./VectorEnginePlugin   (arm64, -O2)
```

`build.sh` runs:

```sh
clang -arch arm64 -O2 -g -bundle -undefined dynamic_lookup \
  -DHAVE_CONFIG_H=1 -DNDEBUG=1 -DDEBUGVM=0 -DBUILD_FOR_OSX=1 \
  -I osvm/platforms/iOS/vm/OSX -I osvm/platforms/Cross/vm -I osvm/src/spur64.cog \
  -o VectorEnginePlugin generated/VectorEnginePlugin.c
```

On Intel: `ARCH=x86_64 ./build.sh`. Different headers checkout: `OSVM=/path ./build.sh`.

### A note on `-O2`

Cuis ships this plugin as an **external bundle compiled with optimization** (roughly
`-O2`/`-Os` — its `__TEXT` is *smaller* than an unoptimized build). So `-O2` here is not
a speedup over stock; it is the level you must match. **Do not build at `-O0`** — the
rasterizer is a tight per-pixel loop and an `-O0` build is markedly *slower* than the
stock plugin, erasing the algorithmic gains. `build.sh` uses `-O2`; keep it there.

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

`VectorEngineOpt.pck.st` adds the image-side pieces that build on this plugin:

- a **glyph-tile cache** and a **fused text path** — each `(font, size, glyph,
  sub-pixel phase)` rasterizes once, then whole runs composite as cached coverage tiles.
  ~2× on text drawing. These call prims this build adds (`primStampCoverageRunWP`,
  `primBlendStampedCoverageRunWP`, `primClearMaskWP`, `primExtractCoverageWP`), so they
  need **this** plugin, not the stock one.
- a **fast `opaqueImage:at:`** — a rule-3 morph-ids clear (11× faster than the rule-0
  clear it replaces; see the techniques).

---

## What makes it faster

All techniques are in `slang/SlabStamping.st` (plugin) or `VectorEngineOpt.pck.st`
(image side). Each is bit-identical to the stock output.

**Strokes — slab stamping.**
The stock stroke rasterizer walks a pen along the segment and stamps a distance-disk at
every hop, so each pixel is visited ~`penWidth·2/hop` times. Instead, for a whole
transformed segment, compute the **exact distance from each affected pixel to the
segment in one pass** (`slabStampSegmentWP…`) — per-scanline x-interval, analytic
point-to-segment distance, round caps falling out of the endpoint branches. Same alpha
function, a fraction of the work. This is most of the 2.6×.

**Fills — bulk interior runs.**
A shape's interior is long runs of fully-covered pixels between anti-aliased edges. The
blend passes detect a clean interior run and blast it as a **bulk overwrite** (opaque
fill) or a hoisted-constant blend (translucent), skipping per-pixel edge/clip
bookkeeping — bit-identical because the hoisted divisors are exactly 1.0.

**Opaque-target fast path** (the `…WPAt:` blend helpers).
Over an opaque target — the universal case when drawing to the live Display — the alpha
composite's three divides and three multiplies are IEEE **identities**: `targetAlpha`
is exactly 1.0, and `alpha + (1−alpha)` rounds to exactly 1.0 for *every* float in
`[0,1]` (proved by brute force over all 2³⁰ such floats — `check_alpha_identity.c`). The
helper skips them.

**Gang-skip empty space.**
The blend sweep hops over runs of clear 16-pixel segments **eight segment-flags per
`uint64` compare** instead of one at a time — a chrome stroke sweeps its whole bounding
box for a ring that covers ~2% of it.

**Vectorizable stores.** The clean-run loops write the color buffer and the morph-id
buffer in **separate** loops; a single-array constant-store loop vectorizes, the
interleaved form can't (the compiler must assume the two pointers alias).

**Extend bulk runs across clear segments.** A full-width interior row becomes **one** run
instead of ~170 segment-sized ones — the per-segment re-establishment cost is amortized.

**Dirty-span journal.** The stampers record, per row, the `[minX, maxX]` of pixels they
touched; the blend passes clamp their sweep to that dirty span instead of the full shape
bounding box. A plugin-internal per-target array; bit-identical by construction (pixels
outside the dirty span carry no stamps, so neither stroke alpha nor fill winding can
change there).

**Fused stamp + blend for glyph runs** (plugin + `VectorEngineOpt`).
Cached glyph coverage tiles normally stamp into an alpha mask that is then re-scanned and
blended — three memory passes. The fused path (`blendStampedCoverageRunWP…`) composites
the tiles **directly** with the fill color, applying the exact per-pixel treatment (clip
window, anti-aliased clip columns, span updates) the two-pass path would. Kerned glyphs
whose *ink* overlaps fall back to the mask path (which max-combines them), so a run is
partitioned and the result stays bit-identical. ~2× on text.

**Glyph-tile cache** (`VectorEngineOpt`, image side).
`GlyphTileCache` bakes each `(font, effective size, glyph, sub-pixel phase)` once through
the normal outline pipeline and extracts its coverage; runs then composite cached tiles.
Scale-free (tiles bake on demand at the drawn size), so they inherit the rasterizer's
exact anti-aliasing.

**Faster morph-ids clear** (`VectorEngineOpt`, image side).
Clearing the morph-ids buffer used BitBlt `combinationRule: 0`, which falls off BitBlt's
fast path and runs **~11× slower** than the identical store (5.8 ms vs 0.5 ms per
1.6 Mpx). A rule-3 store of a zero pixel writes exactly the same 0 at full speed.

---

## Layout

```
slang/SlabStamping.st    Slang source of truth (translates to the plugin C)
generated/VectorEnginePlugin.c   committed translation of slang/SlabStamping.st
VectorEngineOpt.pck.st   image-side package (glyph-tile cache, fused text, ids-clear)
build.sh                 compile the generated C -> loadable -O2 bundle
regenerate/              scripts + notes to re-run the Slang->C translation
check_alpha_identity.c   brute-force proof behind the opaque-target fast path
```

## Correctness

The rule for the whole project: **an optimization must produce bit-identical output, or
it does not ship.** Validation used offscreen `VectorCanvas` renders and live window
captures checksummed pixel-for-pixel against the stock build, plus the exhaustive float
proof for the one shortcut that leans on an IEEE identity. When a change traded
correctness for speed (an early "consume the dirty journal in the blend" variant), a
deterministic window-flight replay caught it and it was fixed, not shipped.

## Provenance & license

Derived from Cuis's `VectorEnginePlugin-jmv.26` (by Juan Vuletich) and translated with
`VMMaker.oscog-eem.3767`. MIT-licensed (see `LICENSE`); the upstream VectorEnginePlugin
and the OpenSmalltalk VM carry their own licenses.
