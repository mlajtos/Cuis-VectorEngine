"Text quality scene. Draws several strings at a range of point sizes offscreen through
VectorCanvas and writes /tmp/text_out.png (plus a raw RGBA dump to /tmp/text_dump.bin).

Render it under two configurations to A/B the text path:
  - stock plugin, no VectorEngineOpt   -> the outline text path
  - this build + VectorEngineOpt loaded -> the cached fused-tile text path
The committed text-stock.png / text-this.png were made this way.

The plugin is not reentrant -- headless/bridge runs must go through the UI process:
  UISupervisor whenUIinSafeState: [ <this expression> ]"

| f c mk bits ws |
f := Form extent: 640@300 depth: 32.
f fillColor: (Color r: 0.13 g: 0.15 b: 0.19).
c := VectorCanvas onForm: f.
mk := [:pts | FontFamily familyName: 'DejaVu Sans' pointSize: pts].
c drawString: 'The quick brown fox jumps over the lazy dog' at: 16@20 font: (mk value: 12) color: (Color r: 0.9 g: 0.9 b: 0.6).
c drawString: 'ABCDEFG abcdefg 0123456789 !?@#&' at: 16@60 font: (mk value: 16) color: (Color r: 0.6 g: 0.85 b: 1.0).
c drawString: 'Kerning pairs: AVA WoW To Ty. Yo!' at: 16@110 font: (mk value: 22) color: (Color r: 0.7 g: 1.0 b: 0.75).
c drawString: 'Hamburgefonstiv' at: 16@175 font: (mk value: 30) color: (Color r: 1.0 g: 0.8 b: 0.7).
c drawString: 'the the the the aaaa oooo mmmm' at: 16@245 font: (mk value: 20) color: (Color r: 0.85 g: 0.8 b: 1.0).
f writePNGfileNamed: '/tmp/text_out.png'.
bits := f bits.
ws := WriteStream on: (ByteArray new: bits size * 4).
1 to: bits size do: [:i | | w | w := bits at: i.
	ws nextPut: ((w bitShift: -24) bitAnd: 255); nextPut: ((w bitShift: -16) bitAnd: 255);
	   nextPut: ((w bitShift: -8) bitAnd: 255); nextPut: (w bitAnd: 255)].
'/tmp/text_dump.bin' asFileEntry forceWriteStreamDo: [:s | s binary; nextPutAll: ws contents].
'wrote /tmp/text_out.png'
