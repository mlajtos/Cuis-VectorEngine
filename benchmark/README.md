# Benchmarks

Two offscreen `VectorCanvas` benchmarks — no window, no compositor, just the rasterizer.

- **`VEBenchmark.st`** — the suite: strokes, wide strokes, quadratic/cubic beziers,
  opaque + translucent fills, filled polygons, and two text workloads. Answers a
  best-of-3 report. Run it from a Workspace ("print it"), or headless in the UI process
  (the plugin isn't reentrant — see the header comment).
- **`StrokeStorm.st`** — a stroke-only throughput loop (fps over a fixed wall-clock
  window); good for a quick feel of stroke-heavy performance.

## Results

Same machine (M1), same VM and image, **both plugins compiled from Slang with the repo's
`build.sh` at `-O2`** so the comparison isolates the algorithm, not the compiler:

- **pristine** — the base `VectorEnginePlugin-jmv.26`, no `VectorEngineOpt`.
- **this build** — the augmented plugin + the `VectorEngineOpt` package.

Measured as VM **CPU-time**, on an idle system (wall-clock on a laptop is dominated by
background load and thermal state — an indexing daemon at 99% inflated an early run 6×;
CPU-time is immune):

| workload | pristine | this build | speedup |
|---|--:|--:|--:|
| hairlines (1px polylines) | 509 ms | 208 ms | 2.4× |
| wideStrokes (6px) | 52 ms | 43 ms | 1.2× |
| quadratics | 13 ms | 14 ms | ~1× |
| cubics | 13 ms | 14 ms | ~1× |
| fillsOpaque | 23 ms | 16 ms | 1.4× |
| fillsTrans (blended) | 35 ms | 22 ms | 1.6× |
| polygons (stroke+fill) | 19 ms | 11 ms | 1.7× |
| **textPlain** | 69 ms | 6 ms | **11×** |
| **textDense** | 110 ms | 12 ms | **9×** |
| **TOTAL (wall)** | **843 ms** | **346 ms** | **2.4×** |
| TOTAL (VM CPU-time) | 2.65 s | 1.13 s | 2.3× |

Reading it:

- **Strokes** carry the plugin win — slab stamping is ~2.4× on hairlines (the worst case
  for the old per-hop stamper, since thin strokes never saturate the mask).
- **Fills** gain ~1.4–1.7× from bulk interior runs and the opaque-target fast path.
- **Beziers** are ~flat here: these curves are short, so flattening dominates and the
  per-segment slab win is small (and the absolute times are near the noise floor).
- **Text** is the standout — ~**9–11×** — but that is the `VectorEngineOpt` glyph-tile
  cache (bake each glyph once, composite cached tiles), not the plugin alone. With just
  the plugin bundle and no package, text uses the base outline path.

Numbers are indicative — run the suite on your own hardware, idle, for a clean read.
