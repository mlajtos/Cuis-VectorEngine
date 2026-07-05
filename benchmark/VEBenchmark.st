"VectorEngine benchmark suite.
Renders a set of workloads offscreen through VectorCanvas and reports the best-of-3
milliseconds for each, plus a total. Every workload is deterministic, so the number is
comparable across plugin builds.

Run it from a Workspace (select all, 'print it') -- it answers a report String.
Headless / over a bridge, run it inside the UI process (the VectorEnginePlugin is not
reentrant, so driving it from another process while the UI also draws will deadlock):

    UISupervisor whenUIinSafeState: [ Smalltalk at: #VEBench put: <this expression> ]

Workloads:
  hairlines   1px anti-aliased polylines (never saturate the mask -- worst case for the
              old per-hop stamper)
  wideStrokes 6px strokes
  quadratics  quadratic bezier fans
  cubics      cubic bezier fans (glyph-shaped)
  fillsOpaque opaque rounded-rect fills
  fillsTrans  translucent rounded-rect fills (per-pixel blend)
  polygons    many-sided filled polygons (stroke + fill)
  textPlain   a paragraph drawn many times (glyph rasterization / tile cache)
  textDense   small text, many short runs (layout + rasterization pressure)
"
| form canvas bench report font para total run |
form := Form extent: 900@700 depth: 32.
canvas := VectorCanvas onForm: form.
font := FontFamily defaultFamilyAndPointSize.
para := 'The quick brown fox jumps over the lazy dog. 0123456789 !!@#$%^&*() {[<>]}'.
report := OrderedCollection new.

bench := [:name :reps :block |
	| t best |
	block value.                              "warm (bakes glyph tiles, warms caches)"
	best := 1000000.
	3 timesRepeat: [
		t := Time localMillisecondClock.
		reps timesRepeat: block.
		t := Time localMillisecondClock - t.
		best := best min: t].
	report add: { name. best } ].

"--- strokes ---"
bench value: 'hairlines' value: 12 value: [
	| x0 |
	1 to: 90 do: [:z |
		x0 := z * 8 + 5.
		canvas strokeWidth: 1 color: (Color h: z * 4 s: 0.6 v: 0.9) do: [
			canvas moveTo: x0 @ 4.
			1 to: 16 do: [:k |
				canvas lineTo: (x0 + (k * 30 * (k odd ifTrue: [1] ifFalse: [-1])) + 300) @ (k * 42)]]]].

bench value: 'wideStrokes' value: 12 value: [
	| x0 |
	1 to: 60 do: [:z |
		x0 := (z \\ 30) * 28 + 6.
		canvas strokeWidth: 6 color: (Color h: z * 6 s: 0.7 v: 1.0) do: [
			canvas moveTo: x0 @ 6.
			1 to: 20 do: [:k |
				canvas lineTo: (x0 + (k odd ifTrue: [14] ifFalse: [0])) @ (6 + (k * 33))]]]].

"--- beziers ---"
bench value: 'quadratics' value: 10 value: [
	1 to: 120 do: [:z | | x y |
		x := (z \\ 12) * 70 + 20. y := (z // 12) * 60 + 20.
		canvas strokeWidth: 2 color: (Color h: z * 3 s: 0.7 v: 0.9) do: [
			canvas moveTo: x @ y.
			canvas quadraticBezierTo: (x + 60) @ (y + 40) control: (x + 30) @ (y - 30)]]].

bench value: 'cubics' value: 10 value: [
	1 to: 120 do: [:z | | x y |
		x := (z \\ 12) * 70 + 20. y := (z // 12) * 60 + 20.
		canvas strokeWidth: 2 color: (Color h: z * 3 s: 0.6 v: 0.9) do: [
			canvas moveTo: x @ y.
			canvas cubicBezierTo: (x + 55) @ (y + 45) control1: (x + 15) @ (y - 25) control2: (x + 45) @ (y + 60)]]].

"--- fills ---"
bench value: 'fillsOpaque' value: 12 value: [
	1 to: 80 do: [:z | | x y |
		x := (z \\ 10) * 88 + 10. y := (z // 10) * 84 + 10.
		canvas roundRect: (x @ y extent: 78@74) color: (Color h: z * 4.5 s: 0.5 v: 0.85) radius: 12]].

bench value: 'fillsTrans' value: 12 value: [
	1 to: 80 do: [:z | | x y |
		x := (z \\ 10) * 88 + 10. y := (z // 10) * 84 + 10.
		canvas roundRect: (x @ y extent: 78@74) color: (Color h: z * 4.5 s: 0.5 v: 0.85 alpha: 0.5) radius: 12]].

bench value: 'polygons' value: 10 value: [
	1 to: 60 do: [:z | | cx cy r |
		cx := (z \\ 10) * 88 + 50. cy := (z // 10) * 110 + 60. r := 40.
		canvas strokeWidth: 2 color: Color black fillColor: (Color h: z * 6 s: 0.6 v: 0.9) do: [
			canvas moveTo: (cx + r) @ cy.
			1 to: 7 do: [:k | | a |
				a := k * 2 * Float pi / 7.
				canvas lineTo: (cx + (r * a cos)) @ (cy + (r * a sin))].
			canvas lineTo: (cx + r) @ cy]]].

"--- text ---"
bench value: 'textPlain' value: 8 value: [
	0 to: 14 do: [:row |
		canvas drawString: para at: 12 @ (row * 46 + 20) font: font color: Color black]].

bench value: 'textDense' value: 8 value: [
	0 to: 22 do: [:row |
		0 to: 3 do: [:col |
			canvas drawString: 'item ', (row * 4 + col) printString, ' -- lorem ipsum'
				at: (col * 220 + 8) @ (row * 30 + 14) font: font color: (Color gray: 0.15)]]].

total := (report inject: 0 into: [:acc :each | acc + (each at: 2)]).
run := String streamContents: [:s |
	s nextPutAll: 'VectorEngine benchmark (best-of-3 ms, lower is better)'; newLine.
	s nextPutAll: '------------------------------------------------------'; newLine.
	report do: [:each | | pad |
		pad := (14 - (each at: 1) size) max: 1.
		s nextPutAll: (each at: 1); nextPutAll: (String new: pad withAll: Character space).
		s nextPutAll: (each at: 2) printString; nextPutAll: ' ms'; newLine].
	s nextPutAll: '------------------------------------------------------'; newLine.
	s nextPutAll: ('TOTAL', (String new: 9 withAll: Character space)), total printString, ' ms'].
run
