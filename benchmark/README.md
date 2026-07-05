# Benchmarks

Two offscreen `VectorCanvas` benchmarks — no window, no compositor, just the rasterizer.

- **`VEBenchmark.st`** — the suite: strokes, wide strokes, quadratic/cubic beziers,
  opaque + translucent fills, filled polygons, and two text workloads. Reports, per
  workload, the **mean / standard deviation / coefficient of variation over 20 timed
  samples** plus a total. Run it from a Workspace ("print it"), or headless in the UI
  process (the plugin isn't reentrant — see the header comment).
- **`StrokeStorm.st`** — a stroke-only throughput loop (fps over a fixed wall-clock
  window); good for a quick feel of stroke-heavy performance.

## Results

Same machine (M1), macOS; OpenSmalltalk Cog/Spur VM `7.20260609.1739`
(VMMaker.oscog-eem.3764), image Cuis7.9-7983. All three builds measured back-to-back in one
session — **mean of 20 timed samples ± σ (standard deviation)** per workload. **Only
`RemoteControl` (the bench bridge) is loaded — no application packages** (see the
methodology note below; this matters). Three builds:

- **shipped stock** — the bundle Cuis actually ships, no published source, universal
  (x86_64 + arm64), `__TEXT` 49 KB. This is what you run today.
- **pristine (Slang -O3)** — the base `VectorEnginePlugin-jmv.26` recompiled from Slang
  with the repo's `build.sh` at `-O3`, no `VectorEngineOpt`. Same algorithm as shipped
  stock, matched to this build's compiler/flags — the *isolate-the-algorithm* baseline.
- **this build** — the augmented plugin (`-O3`) + the `VectorEngineOpt` package.

| workload | shipped stock | pristine (Slang -O3) | this build | vs stock |
|---|--:|--:|--:|--:|
| hairlines (1px polylines) | 541.0 ± 4.5 | 481.0 ± 5.7 | 189.5 ± 4.4 | **2.9×** |
| wideStrokes (6px) | 57.8 ± 0.7 | 48.8 ± 0.5 | 39.6 ± 0.5 | 1.5× |
| quadratics | 13.2 ± 0.4 | 12.4 ± 0.5 | 13.4 ± 0.5 | ~1× |
| cubics | 13.6 ± 0.5 | 12.9 ± 0.5 | 13.4 ± 0.5 | ~1× |
| fillsOpaque | 27.1 ± 0.3 | 22.8 ± 0.4 | 14.4 ± 0.5 | 1.9× |
| fillsTrans (blended) | 43.3 ± 0.5 | 34.3 ± 0.5 | 19.3 ± 0.5 | 2.2× |
| polygons (stroke+fill) | 21.8 ± 0.5 | 19.0 ± 0.2 | 11.2 ± 0.4 | 1.9× |
| **textPlain** | 50.8 ± 1.4 | 46.4 ± 2.2 | 4.8 ± 0.5 | **10.6×** |
| **textDense** | 60.1 ± 0.7 | 56.2 ± 0.8 | 8.4 ± 0.5 | **7.2×** |
| **TOTAL** | **828.6 ± 4.9** | **733.8 ± 6.2** | **314.2 ± 4.6** | **2.6×** |

All coefficients of variation are ≤ ~5% (the tiny textPlain workload at 4.8 ms is the only
one near 10%, being closest to the millisecond clock's resolution). ms are milliseconds for
the workload's fixed iteration count, not per-primitive.

Reading it:

- **vs the shipped bundle** (the honest headline, since it's what people run): **2.6×**
  overall, ~2.9× on strokes, ~7–11× on text.
- **Shipped stock is ~13% *slower* than pristine-from-Slang at `-O3`** (829 vs 734) despite
  its smaller `__TEXT` — it's evidently built size-optimized (`-Os`-like), which trades a
  little speed for size. So recompiling from Slang already edges out what ships *before* any
  algorithm change; the algorithm then does the rest. (This is why the pristine column
  exists — it isolates algorithm from compiler.)
- **Strokes** carry the plugin win — slab stamping is ~2.9× on hairlines (worst case for
  the old per-hop stamper, since thin strokes never saturate the mask).
- **Fills** gain ~1.9–2.2× from bulk interior runs and the opaque-target fast path.
- **Beziers** are ~flat: these curves are short, so flattening dominates and the
  per-segment slab win is small (absolute times are near the noise floor — the 13.4 vs 12.4
  is within σ, not a regression).
- **Text** is the standout — ~**7–11×** — but that is the `VectorEngineOpt` glyph-tile
  cache (bake each glyph once, composite cached tiles), not the plugin alone. With just
  the plugin bundle and no package, text uses the base outline path (and is bit-identical
  to stock — see [`../validate/`](../validate/#text)).

### Methodology: measure the rasterizer alone

These numbers load **only `RemoteControl`**. An earlier run also loaded an application
package (Blueprint) that extends `VectorEngineWithPlugin>>finishPath:` — a method *every*
stroke, fill, and glyph passes through — which nearly **doubled** the outline-text baseline
(textDense ~56 → ~110 ms) while barely touching this build (its cached text path bypasses
`finishPath:`). That inflated the apparent text speedup. Lesson: any package that patches a
hot rasterizer method contaminates the comparison. Benchmark with nothing but the bridge
loaded, and the numbers above are what you get.

Numbers are indicative — run the suite on your own hardware, idle, for a clean read.
