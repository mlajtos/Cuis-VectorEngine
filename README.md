# Cuis-VectorEngine

A faster drop-in build of Cuis Smalltalk's **VectorEnginePlugin** (the whole-pixel,
anti-aliased vector rasterizer behind `VectorCanvas`), plus a small image-side package
(`VectorEngineOpt`) that adds a glyph-tile cache and a few rendering fast paths.

It is **visually equivalent** to the stock rasterizer, **not bit-identical**: solid fill
interiors and the plugin's outline text are pixel-for-pixel identical, while anti-aliased
*edges* differ slightly — the stroke/curve rasterizer computes exact analytic per-pixel
distance where stock hop-samples, and the optional cached-text path (`VectorEngineOpt`)
snaps glyphs to a ⅛-pixel grid. Differences are confined to edge pixels and bounded
(Δ41/255 worst case on primitives, ~72% ≤ Δ6/255; glyph edges up to Δ111 but same
letterforms), imperceptible in normal use — and if anything the exact-distance stroke
edges are marginally *smoother*. See [`validate/`](validate/) for measured per-primitive
and text pixel-diffs, rendered A/B comparisons, and zoomed crops. The *other*
optimizations layered on top of the rasterizer (opaque-target fast path, bulk runs,
gang-skip, dirty-span journal) **are** provably bit-identical (render oracles; and for the
one shortcut that leans on an IEEE identity, exhaustive proof — `check_alpha_identity.c`).
The non-bit-identity comes from exactly two things: exact-distance slab stamping replacing
hop-sampling, and the glyph cache's sub-pixel snapping.

The plugin is generated from Slang (the restricted Smalltalk that VMMaker translates to
C), exactly like the upstream plugin — `slang/SlabStamping.st` is the source of truth,
`generated/VectorEnginePlugin.c` is its committed translation.

## What you get

The [`benchmark/`](benchmark/) suite — strokes, beziers, fills, text — mean of 20 runs
(±σ) on an idle M1, all three builds measured back-to-back with **only the bench bridge
loaded** (no application packages — a package that patches a hot rasterizer method skews
the baseline; see the benchmark README). **shipped stock** is the bundle Cuis actually
ships (no source); **pristine** is the same base plugin recompiled from Slang at `-O3`
(isolates algorithm from compiler); **this build** is the augmented plugin + `VectorEngineOpt`:

| | shipped stock | pristine (Slang -O3) | this build | vs stock |
|---|--:|--:|--:|--:|
| strokes (hairlines) | 541 ms | 481 ms | 190 ms | **2.9×** |
| fills | 27–43 ms | 23–34 ms | 14–19 ms | ~2× |
| **text** | 51–60 ms | 46–56 ms | 5–8 ms | **7–11×** |
| **whole suite** | **829 ms** | **734 ms** | **314 ms** | **2.6×** |

The gain is algorithmic (see [techniques](#what-makes-it-faster)), **not** a compiler
flag. Note the shipped bundle is actually ~13% *slower* than pristine-from-Slang at `-O3`
(it's built size-optimized), so recompiling alone already edges it out before any algorithm
change — this build is **2.6× over what ships**, 2.3× over the same-flags baseline. The
outsized text win is the `VectorEngineOpt` glyph-tile cache. Full per-workload table,
standard deviations, and methodology in [`benchmark/README.md`](benchmark/README.md).

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
# -> ./VectorEnginePlugin   (arm64, -O3)
```

`build.sh` runs:

```sh
clang -arch arm64 -O3 -g -bundle -undefined dynamic_lookup \
  -DHAVE_CONFIG_H=1 -DNDEBUG=1 -DDEBUGVM=0 -DBUILD_FOR_OSX=1 \
  -I osvm/platforms/iOS/vm/OSX -I osvm/platforms/Cross/vm -I osvm/src/spur64.cog \
  -o VectorEnginePlugin generated/VectorEnginePlugin.c
```

On Intel: `ARCH=x86_64 ./build.sh`. Different headers checkout: `OSVM=/path ./build.sh`.

### A note on the optimization level

Cuis ships this plugin as an **external bundle compiled size-optimized** (`-Os`-like — its
`__TEXT` is *smaller* than an `-O2` build, and it benchmarks ~13% slower than the same
source at `-O3`). `build.sh` uses **`-O3`**, chosen empirically: over `-O2` it is a further
~9% and is **bit-identical** (conforming optimization never reassociates floats — verified
same-checksum output). **Do not** use `-ffast-math` (it relaxes IEEE, breaking the
opaque-fast-path identity the correctness proof depends on) or `-O0` (markedly *slower*
than even the shipped bundle). `-flto`/`-march=native` add nothing here (single
translation unit). Keep `-O3`.

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
  ~7–11× on text drawing. These call prims this build adds (`primStampCoverageRunWP`,
  `primBlendStampedCoverageRunWP`, `primClearMaskWP`, `primExtractCoverageWP`), so they
  need **this** plugin, not the stock one.
- a **fast `opaqueImage:at:`** — a rule-3 morph-ids clear (11× faster than the rule-0
  clear it replaces; see the techniques).

---

## What makes it faster

All techniques are in `slang/SlabStamping.st` (plugin) or `VectorEngineOpt.pck.st`
(image side). Every one is bit-identical to stock **except slab stamping**, which is
visually equivalent (exact-distance vs hop-sampled anti-aliased edges — see
[`validate/`](validate/)).

**Strokes — slab stamping.**
The stock stroke rasterizer walks a pen along the segment and stamps a distance-disk at
every hop, so each pixel is visited ~`penWidth·2/hop` times. Instead, for a whole
transformed segment, compute the **exact distance from each affected pixel to the
segment in one pass** (`slabStampSegmentWP…`) — per-scanline x-interval, analytic
point-to-segment distance, round caps falling out of the endpoint branches. Same
distance→alpha curve, but evaluated *exactly* per pixel rather than accumulated from
overlapping hops — so edge coverage is slightly different (and marginally smoother) than
stock, at a fraction of the work. This carries the ~2.9× on stroke-heavy scenes.

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
partitioned. The fused compositing is bit-identical to the two-pass path; the *cache* it
draws from is what makes cached text visually-equivalent-not-identical to stock (next
item). With the tile cache this is ~7–11× on text.

**Glyph-tile cache** (`VectorEngineOpt`, image side).
`GlyphTileCache` bakes each `(font, effective size, glyph, sub-pixel phase)` once through
the normal outline pipeline and extracts its coverage; runs then composite cached tiles.
Scale-free (tiles bake on demand at the drawn size), so each phase inherits the
rasterizer's exact anti-aliasing. The cache keeps **8 phases per glyph** — quarter-pixel
horizontal, half-pixel vertical — and snaps each placement to the nearest, so a glyph
rasterizes at most 8 times however often it appears. That ≤⅛px snap makes cached text
*visually equivalent but not bit-identical* to stock's exact continuous placement — see
[`validate/`](validate/#text) for the measured text diff and A/B renders.

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
build.sh                 compile the generated C -> loadable -O3 bundle
regenerate/              scripts + notes to re-run the Slang->C translation
check_alpha_identity.c   brute-force proof behind the opaque-target fast path
```

## Correctness

Two classes of change, held to two different standards:

1. **The arithmetic optimizations** (opaque-target fast path, bulk interior runs,
   gang-skip, vectorizable stores, dirty-span journal) must be **bit-identical**, or they
   do not ship. They were validated with offscreen `VectorCanvas` renders and live window
   captures checksummed pixel-for-pixel against the stock build, plus an exhaustive float
   proof for the one shortcut that leans on an IEEE identity (`check_alpha_identity.c`).
   When an early "consume the dirty journal in the blend" variant traded correctness for
   speed, a deterministic window-flight replay caught it and it was fixed, not shipped.

2. **Slab stamping** (the exact-distance stroke/curve rasterizer) is **visually
   equivalent but not bit-identical** — it computes analytic per-pixel distance where
   stock hop-samples, so anti-aliased *edges* differ by a small, bounded amount. Interiors
   and plugin outline text stay identical. The full measured per-primitive pixel-diff,
   rendered A/B images, zoomed crops, and a three-way binary comparison (including Cuis's
   shipped no-source bundle) are in [`validate/`](validate/).

## Provenance & license

Derived from the base **`VectorEnginePlugin-jmv.26`** (by Juan Vuletich), obtained from its
SqueakSource project:

- Plugin source: **http://www.squeaksource.com/VectorEnginePlugin** (package
  `VectorEnginePlugin-jmv.26`)
- Translated to C with `VMMaker.oscog-eem.3767` (VMMaker from
  http://source.squeak.org/VMMaker)

Developed and benchmarked against the **OpenSmalltalk Cog/Spur VM `7.20260609.1739`**
(`VMMaker.oscog-eem.3764`) running **Cuis 7.9 (image update 7983)** on macOS/arm64. The
generated C is ABI-compatible with any current Cog/Spur VM, not just this build.

MIT-licensed (see `LICENSE`); the upstream VectorEnginePlugin and the OpenSmalltalk VM
carry their own licenses.
