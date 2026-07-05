# Benchmarks

Two offscreen `VectorCanvas` benchmarks — no window, no compositor, just the rasterizer.

- **`VEBenchmark.st`** — the suite: strokes, wide strokes, quadratic/cubic beziers,
  opaque + translucent fills, filled polygons, and two text workloads. Answers a
  best-of-3 report. Run it from a Workspace ("print it"), or headless in the UI process
  (the plugin isn't reentrant — see the header comment).
- **`StrokeStorm.st`** — a stroke-only throughput loop (fps over a fixed wall-clock
  window); good for a quick feel of stroke-heavy performance.

## Results

Same machine (M1), same VM and image, all three measured back-to-back in one session
(best-of-3 ms per workload — the harness takes the fastest of three runs after a warm-up,
so background load raises times but rarely touches the minimum). Three builds:

- **shipped stock** — the bundle Cuis actually ships, no published source, universal
  (x86_64 + arm64), `__TEXT` 49 KB. This is what you run today.
- **pristine (Slang -O2)** — the base `VectorEnginePlugin-jmv.26` recompiled from Slang
  with the repo's `build.sh` at `-O2`, no `VectorEngineOpt`. Same algorithm as shipped
  stock, matched to this build's compiler/flags — the *isolate-the-algorithm* baseline.
- **this build** — the augmented plugin (`-O2`) + the `VectorEngineOpt` package.

| workload | shipped stock | pristine (Slang -O2) | this build | vs stock |
|---|--:|--:|--:|--:|
| hairlines (1px polylines) | 538 ms | 506 ms | 208 ms | **2.6×** |
| wideStrokes (6px) | 57 ms | 52 ms | 43 ms | 1.3× |
| quadratics | 13 ms | 13 ms | 14 ms | ~1× |
| cubics | 13 ms | 13 ms | 14 ms | ~1× |
| fillsOpaque | 27 ms | 23 ms | 16 ms | 1.7× |
| fillsTrans (blended) | 43 ms | 35 ms | 22 ms | 2.0× |
| polygons (stroke+fill) | 21 ms | 19 ms | 11 ms | 1.9× |
| **textPlain** | 75 ms | 69 ms | 6 ms | **12×** |
| **textDense** | 118 ms | 110 ms | 11 ms | **11×** |
| **TOTAL** | **905 ms** | **840 ms** | **345 ms** | **2.6×** |

Reading it:

- **vs the shipped bundle** (the honest headline, since it's what people run): **2.6×**
  overall, ~2.6× on strokes, ~11–12× on text.
- **Shipped stock is ~8% *slower* than pristine-from-Slang at `-O2`** (905 vs 840) despite
  its smaller `__TEXT` — it's evidently built size-optimized (`-Os`-like), which trades a
  little speed for size. So `-O2` from Slang already edges out what ships *before* any
  algorithm change; the algorithm then does the rest. (This is why `build.sh` uses `-O2`,
  and why the pristine column exists — it isolates algorithm from compiler.)
- **Strokes** carry the plugin win — slab stamping is ~2.6× on hairlines (worst case for
  the old per-hop stamper, since thin strokes never saturate the mask).
- **Fills** gain ~1.7–2× from bulk interior runs and the opaque-target fast path.
- **Beziers** are ~flat: these curves are short, so flattening dominates and the
  per-segment slab win is small (absolute times are near the noise floor — the 14 vs 13 is
  noise, not a regression).
- **Text** is the standout — ~**11–12×** — but that is the `VectorEngineOpt` glyph-tile
  cache (bake each glyph once, composite cached tiles), not the plugin alone. With just
  the plugin bundle and no package, text uses the base outline path (and is bit-identical
  to stock — see [`../validate/`](../validate/#text)).

Numbers are indicative — run the suite on your own hardware, idle, for a clean read.
