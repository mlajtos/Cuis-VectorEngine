"Anti-aliasing quality scene. Renders a set of AA-revealing primitives (shallow
hairlines, a 2px diagonal, a thin cubic bezier, a stroked circle and a filled disc)
offscreen through VectorCanvas and writes /tmp/quality_out.png.

Render it once under each plugin build to get a visual A/B (the committed
quality-stock.png / quality-this.png were made this way). The plugin is not
reentrant, so headless/bridge runs must go through the UI process:
  UISupervisor whenUIinSafeState: [ <this expression> ]"

| f c |
f := Form extent: 420@320 depth: 32.
f fillColor: (Color r: 0.13 g: 0.15 b: 0.19).
c := VectorCanvas onForm: f.

"shallow-angle hairlines -- AA is most visible here"
0 to: 7 do: [:k |
	c strokeWidth: 1 color: Color white do: [
		c moveTo: 20 @ (30 + (k * 12)). c lineTo: 200 @ (34 + (k * 12) + (k * 3))]].

"a diagonal 2px line and a thin cubic curve"
c strokeWidth: 2 color: (Color r: 1 g: 0.8 b: 0.2) do: [ c moveTo: 20@300. c lineTo: 200@140 ].
c strokeWidth: 1.5 color: (Color r: 0.4 g: 0.9 b: 1.0) do: [
	c moveTo: 230@40. c cubicBezierTo: 400@120 control1: 230@180 control2: 410@40 ].

"a circle outline (stroke edge) and a filled disc (fill edge)"
c ellipseCenter: 300@210 radius: 60@60 borderWidth: 2 borderColor: (Color r: 0.5 g: 1 b: 0.6) fillColor: nil.
c ellipseCenter: 300@210 radius: 30@30 borderWidth: 0 borderColor: nil fillColor: (Color r: 0.9 g: 0.4 b: 0.5).

f writePNGfileNamed: '/tmp/quality_out.png'.
'wrote /tmp/quality_out.png'
