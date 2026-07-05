"StrokeStorm — feel the rasterizer.
Paste into a Workspace and DoIt (Cmd-D selects nothing needed: select all, Cmd-d).
Renders an animated stroke-heavy scene (1,440 hairline segments + 1,250 w4 segments
per frame) offscreen through the VectorEngine and blits each frame to the top-left
of the Display for ~5 seconds, then answers the average fps.

Run it twice on the SAME image:
  1. under the stock  CuisVM.app            -> ~21 fps  (visible chug)
  2. under ~/Work/Blueprint/CuisVM-SLAB.app -> ~48 fps  (smooth)

Casual desktop use won't feel different: small damage-rect redraws finish far
under the 16ms frame budget on both VMs. The slab pays off when frames are
raster-BOUND: stroke-dense scenes, hairlines (which never saturate the alpha
mask, so every sample pays full price on the old stamper), charts, full-frame
animation."

| f c phase t0 frames x0 |
f := Form extent: 600@600 depth: 32.
c := VectorCanvas onForm: f.
phase := 0.0. frames := 0. t0 := Time localMillisecondClock.
[Time localMillisecondClock - t0 < 5000] whileTrue: [
	f fillColor: (Color r: 0.08 g: 0.08 b: 0.1).
	phase := phase + 0.013.
	1 to: 90 do: [:z |
		x0 := z * 6.6 + ((phase * 15 + z) sin * 5).
		c strokeWidth: 1 color: (Color h: z * 4 s: 0.6 v: 0.9) do: [
			c moveTo: x0 @ 2.
			1 to: 16 do: [:k |
				c lineTo: (x0 + (k * 34 * ((k odd ifTrue: [1] ifFalse: [-1]))) + 250) @ (k * 37)]]].
	1 to: 50 do: [:z |
		x0 := (z \\ 25) * 24 + 5 + ((z // 25) * 3).
		c strokeWidth: 4 color: (Color h: z * 7.2 s: 0.7 v: 1.0) do: [
			c moveTo: x0 @ 5.
			1 to: 25 do: [:k |
				c lineTo: (x0 + (k odd ifTrue: [11] ifFalse: [0]) + ((phase + (k * 0.7)) sin * 5)) @ (5 + (k * 23))]]].
	f displayAt: 0@0.
	frames := frames + 1].
UISupervisor ui ifNotNil: [:w | w fullRepaintNeeded].
'average fps: ', (frames / 5.0) printString
