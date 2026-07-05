"Pixel-level validation. Renders a deterministic scene (strokes, wide strokes,
quadratic + cubic beziers, opaque + translucent fills, a polygon, and text) offscreen
through VectorCanvas, then writes the target Form's raw 32-bit pixels to
/tmp/ve_validate.bin and answers a fold checksum of them.

Run it under two plugin builds (or with/without VectorEngineOpt) and compare:
  - equal checksum  => pixel-for-pixel identical
  - to see WHERE they differ, cmp the two /tmp/ve_validate.bin dumps.

Headless / bridge: run in the UI process (the plugin is not reentrant):
  UISupervisor whenUIinSafeState: [ Smalltalk at: #VESum put: <this expression> ]"
| f c font sum bits ws |
f := Form extent: 700@560 depth: 32.
f fillColor: (Color r: 0.10 g: 0.12 b: 0.16).
c := VectorCanvas onForm: f.
font := FontFamily defaultFamilyAndPointSize.

"strokes"
1 to: 40 do: [:z | | x0 |
	x0 := z * 8 + 4.
	c strokeWidth: 1 color: (Color h: z * 9 s: 0.6 v: 0.9) do: [
		c moveTo: x0 @ 4.
		1 to: 8 do: [:k | c lineTo: (x0 + (k * 20 * (k odd ifTrue: [1] ifFalse: [-1])) + 120) @ (k * 20)]]].
c strokeWidth: 6 color: (Color r: 1 g: 0.7 b: 0.1 alpha: 0.6) do: [
	c moveTo: 20@200. c lineTo: 660@230. c lineTo: 300@120].

"beziers"
c strokeWidth: 2 color: Color white do: [
	c moveTo: 40@300.
	c quadraticBezierTo: 320@360 control: 180@250.
	c cubicBezierTo: 640@420 control1: 400@300 control2: 520@480].

"fills"
c roundRect: (60@360 extent: 240@150) color: (Color r: 0.2 g: 0.6 b: 0.9) radius: 20.
c roundRect: (120@400 extent: 240@130) color: (Color r: 0.9 g: 0.3 b: 0.4 alpha: 0.5) radius: 16.
c strokeWidth: 3 color: Color black fillColor: (Color r: 0.1 g: 0.8 b: 0.3) do: [
	c moveTo: 470@380.
	1 to: 6 do: [:k | | a | a := k * 2 * Float pi / 6. c lineTo: (540 + (60 * a cos)) @ (450 + (60 * a sin))].
	c lineTo: (540 + 60) @ 450].

"text"
c drawString: 'The quick brown fox 0123456789' at: 30@180 font: font color: Color yellow.
c drawString: 'Bit-identical or bust! @#$%^&*()' at: 30@520 font: font color: (Color r: 0.8 g: 0.9 b: 1.0).

"dump raw RGBA and checksum"
bits := f bits.
ws := WriteStream on: (ByteArray new: bits size * 4).
1 to: bits size do: [:i | | w |
	w := bits at: i.
	ws nextPut: ((w bitShift: -24) bitAnd: 255); nextPut: ((w bitShift: -16) bitAnd: 255);
	   nextPut: ((w bitShift: -8) bitAnd: 255); nextPut: (w bitAnd: 255)].
'/tmp/ve_validate.bin' asFileEntry forceWriteStreamDo: [:s | s binary; nextPutAll: ws contents].
sum := 0.
1 to: bits size do: [:i | sum := (sum + (bits at: i) + i) \\ 1073741789].
'checksum ', sum printString, '  (', f extent printString, ', ', bits size printString, ' px, dumped /tmp/ve_validate.bin)'
