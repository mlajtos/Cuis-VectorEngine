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
so background load raises times but rarely touches the minimum). **Only `RemoteControl`
(the bench bridge) is loaded — no application packages** (see the methodology note below;
this matters). Three builds:

- **shipped stock** — the bundle Cuis actually ships, no published source, universal
  (x86_64 + arm64), `__TEXT` 49 KB. This is what you run today.
- **pristine (Slang -O2)** — the base `VectorEnginePlugin-jmv.26` recompiled from Slang
  with the repo's `build.sh` at `-O2`, no `VectorEngineOpt`. Same algorithm as shipped
  stock, matched to this build's compiler/flags — the *isolate-the-algorithm* baseline.
- **this build** — the augmented plugin (`-O2`) + the `VectorEngineOpt` package.

| workload | shipped stock | pristine (Slang -O2) | this build | vs stock |
|---|--:|--:|--:|--:|
| hairlines (1px polylines) | 540 ms | 509 ms | 207 ms | **2.6×** |
| wideStrokes (6px) | 58 ms | 52 ms | 42 ms | 1.4× |
| quadratics | 14 ms | 13 ms | 14 ms | ~1× |
| cubics | 14 ms | 13 ms | 14 ms | ~1× |
| fillsOpaque | 28 ms | 23 ms | 16 ms | 1.8× |
| fillsTrans (blended) | 44 ms | 35 ms | 22 ms | 2.0× |
| polygons (stroke+fill) | 22 ms | 19 ms | 11 ms | 2.0× |
| **textPlain** | 52 ms | 49 ms | 5 ms | **10×** |
| **textDense** | 60 ms | 57 ms | 9 ms | **6.7×** |
| **TOTAL** | **832 ms** | **770 ms** | **340 ms** | **2.4×** |

Reading it:

- **vs the shipped bundle** (the honest headline, since it's what people run): **2.4×**
  overall, ~2.6× on strokes, ~7–10× on text.
- **Shipped stock is ~8% *slower* than pristine-from-Slang at `-O2`** (832 vs 770) despite
  its smaller `__TEXT` — it's evidently built size-optimized (`-Os`-like), which trades a
  little speed for size. So `-O2` from Slang already edges out what ships *before* any
  algorithm change; the algorithm then does the rest. (This is why `build.sh` uses `-O2`,
  and why the pristine column exists — it isolates algorithm from compiler.)
- **Strokes** carry the plugin win — slab stamping is ~2.6× on hairlines (worst case for
  the old per-hop stamper, since thin strokes never saturate the mask).
- **Fills** gain ~1.8–2× from bulk interior runs and the opaque-target fast path.
- **Beziers** are ~flat: these curves are short, so flattening dominates and the
  per-segment slab win is small (absolute times are near the noise floor — the 14 vs 13 is
  noise, not a regression).
- **Text** is the standout — ~**7–10×** — but that is the `VectorEngineOpt` glyph-tile
  cache (bake each glyph once, composite cached tiles), not the plugin alone. With just
  the plugin bundle and no package, text uses the base outline path (and is bit-identical
  to stock — see [`../validate/`](../validate/#text)).

### Methodology: measure the rasterizer alone

These numbers load **only `RemoteControl`**. An earlier run also loaded an application
package (Blueprint) that extends `VectorEngineWithPlugin>>finishPath:` — a method *every*
stroke, fill, and glyph passes through — which nearly **doubled** the outline-text baseline
(textDense 57 → 110 ms) while barely touching this build (its cached text path bypasses
`finishPath:`). That inflated the apparent text speedup to ~11×. Lesson: any package that
patches a hot rasterizer method contaminates the comparison. Benchmark with nothing but the
bridge loaded, and the numbers above are what you get.

Numbers are indicative — run the suite on your own hardware, idle, for a clean read.
