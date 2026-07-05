'From Cuis7.9 [latest update: #7983] on 5 July 2026 at 3:54:24 pm'!
'Description '!
!provides: 'VectorEngineOpt' 1 3!
SystemOrganization addCategory: #VectorEngineOpt!


!classDefinition: #GlyphTileCache category: #VectorEngineOpt!
Object subclass: #GlyphTileCache
	instanceVariableNames: ''
	classVariableNames: 'Sheet SheetUsed Tiles'
	poolDictionaries: ''
	category: 'VectorEngineOpt'!
!classDefinition: 'GlyphTileCache class' category: #VectorEngineOpt!
GlyphTileCache class
	instanceVariableNames: ''!


!GlyphTileCache commentStamp: 'ML 7/4/2026' prior: 0!
Class-side cache of glyph coverage tiles for VectorEngineWithPluginWholePixel.
Tiles maps font -> sizeKey -> (utf32 * 8 + phase) -> tile record
{w. h. dx. dy. sheetOffset}, where sheetOffset is a 0-based offset into Sheet, a
single append-only ByteArray holding all tile bytes (row major, pitch = w).
Coverage is 0..127, extracted via primExtractCoverageWP after stamping a glyph
through the regular outline path, so tiles inherit the rasterizer''s exact output.!

!GlyphTileCache class methodsFor: 'accessing' stamp: 'ML 4/Jul/2026 00:00:00'!
append: aByteArray
	"Append tile bytes to the sheet, growing it as needed. Answer the 0-based offset."
	| offset needed grown |
	Sheet ifNil: [self reset].
	needed := SheetUsed + aByteArray size.
	needed > Sheet size ifTrue: [
		grown := ByteArray new: (Sheet size * 2 max: needed).
		grown replaceFrom: 1 to: SheetUsed with: Sheet startingAt: 1.
		Sheet := grown].
	offset := SheetUsed.
	Sheet replaceFrom: SheetUsed + 1 to: needed with: aByteArray startingAt: 1.
	SheetUsed := needed.
	^ offset! !

!GlyphTileCache class methodsFor: 'accessing' stamp: 'ML 4/Jul/2026 00:00:00'!
reset
	Tiles := IdentityDictionary new.
	Sheet := ByteArray new: 262144.
	SheetUsed := 0! !

!GlyphTileCache class methodsFor: 'accessing' stamp: 'ML 4/Jul/2026 00:00:00'!
sheet
	Sheet ifNil: [self reset].
	^ Sheet! !

!GlyphTileCache class methodsFor: 'accessing' stamp: 'ML 4/Jul/2026 00:00:00'!
tilesFor: aFontDescription sizeKey: sizeKey
	"Answer the (utf32 * 8 + phase) -> tile Dictionary for this font at this size."
	Tiles ifNil: [self reset].
	^ (Tiles at: aFontDescription ifAbsentPut: [Dictionary new])
		at: sizeKey ifAbsentPut: [Dictionary new]! !

!HybridCanvas methodsFor: '*VectorEngineOpt' stamp: 'ML 5/Jul/2026 15:54:24'!
opaqueImage: aForm at: aPoint
	"Fully opaque Form: plain store (Form over) instead of per-pixel alpha blending --
	7x faster for display-sized wallpaper repair. The morph-ids branch clears the ids
	of covered pixels to 0 (the world id) -- via a rule-3 store of a zero pixel, NOT
	rule 0: rule-0 clear falls off BitBlt's fast path and runs ~11x slower than the
	identical store (measured 5.8ms vs 0.5ms at 1.6Mpx). Bit-identical (both write 0)."
	| p e |
	e := aForm extent.
	e > `0@0` ifFalse: [^ self].
	p := (currentTransformation transform: aPoint) roundedHAFZ.
	drawingOnMorphIDs ifTrue: [
		engine sourceForm: nil; fillColor: Color transparent; combinationRule: Form over.
		engine fillRect: (p extent: e).
		^ self].
	engine colorMap: (aForm colormapIfNeededFor: form); fillColor: nil.
	engine image: aForm at: p sourceRect: aForm boundingBox rule: Form over! !

!VectorEngineWithPlugin methodsFor: '*VectorEngineOpt' stamp: 'ML 4/Jul/2026 00:46:54'!
primBlendCoverageRun: sheet meta: metaWords count: n
	<primitive: 'primBlendCoverageRunWP' module: 'VectorEnginePlugin'>
	self primitiveFailed! !

!VectorEngineWithPlugin methodsFor: '*VectorEngineOpt' stamp: 'ML 4/Jul/2026 22:42:05'!
primBlendStampedCoverageRun: sheet meta: metaWords count: n
	"Fused stamp+blend for a run of non-overlapping glyph tiles (see the plugin's
	blendStampedCoverageRunWP:meta:count:). On an older plugin without the
	primitive, degrade gracefully to the two-pass stamp path."
	<primitive: 'primBlendStampedCoverageRunWP' module: 'VectorEnginePlugin'>
	^ self primStampCoverageRun: sheet meta: metaWords count: n! !

!VectorEngineWithPlugin methodsFor: '*VectorEngineOpt' stamp: 'ML 4/Jul/2026 14:38:17'!
primClearMaskLeft: l top: t right: r bottom: b
	<primitive: 'primClearMaskWP' module: 'VectorEnginePlugin'>
	self primitiveFailed! !

!VectorEngineWithPlugin methodsFor: '*VectorEngineOpt' stamp: 'ML 4/Jul/2026 00:46:54'!
primExtractCoverageLeft: l top: t right: r bottom: b into: aByteArray pitch: p
	<primitive: 'primExtractCoverageWP' module: 'VectorEnginePlugin'>
	self primitiveFailed! !

!VectorEngineWithPlugin methodsFor: '*VectorEngineOpt' stamp: 'ML 4/Jul/2026 00:46:54'!
primStampCoverageRun: sheet meta: metaWords count: n
	<primitive: 'primStampCoverageRunWP' module: 'VectorEnginePlugin'>
	self primitiveFailed! !

!VectorEngineWithPluginWholePixel methodsFor: '*VectorEngineOpt' stamp: 'ML 4/Jul/2026 00:00:00'!
drawUtf8String: aByteArray fromByte: byteStartIndex toByte: byteStopIndex at: aPoint trueTypeFont: aTTFontDescription color: aColor scale: scale preventMirroring: doPreventMirroring
	"Cached-tile fast path: each (font, effective size, glyph, subpixel phase) rasterizes
	once; runs then composite cached coverage tiles in one plugin call. Falls back to the
	outline path for anything unusual (rotated/mirrored transforms, stroked fonts,
	multi-byte utf8, runs crossing the clip, oversize glyphs)."
	| tx indexes i |
	tx := geometryTransformation.
	(aTTFontDescription minimumStrokeWidth = 0.0
		and: [doPreventMirroring
		and: [tx a12 = 0.0 and: [tx a21 = 0.0 and: [tx a11 > 0.0 and: [tx a22 > 0.0]]]]])
		ifFalse: [
			^ super drawUtf8String: aByteArray fromByte: byteStartIndex toByte: byteStopIndex
				at: aPoint trueTypeFont: aTTFontDescription color: aColor
				scale: scale preventMirroring: doPreventMirroring].
	"multi-byte utf8 in the run? fall back."
	indexes := aTTFontDescription contourDataIndexesByUtf8.
	byteStartIndex to: byteStopIndex do: [:k |
		i := indexes at: (aByteArray at: k) + 1.
		i < 0 ifTrue: [
			^ super drawUtf8String: aByteArray fromByte: byteStartIndex toByte: byteStopIndex
				at: aPoint trueTypeFont: aTTFontDescription color: aColor
				scale: scale preventMirroring: doPreventMirroring]].
	^ self pvtDrawTiledUtf8: aByteArray fromByte: byteStartIndex toByte: byteStopIndex
		at: aPoint trueTypeFont: aTTFontDescription color: aColor
		scale: scale
		orFallBack: [
			super drawUtf8String: aByteArray fromByte: byteStartIndex toByte: byteStopIndex
				at: aPoint trueTypeFont: aTTFontDescription color: aColor
				scale: scale preventMirroring: doPreventMirroring]! !

!VectorEngineWithPluginWholePixel methodsFor: '*VectorEngineOpt' stamp: 'ML 4/Jul/2026 22:42:05'!
pvtBakeGlyphTile: aByteArray byteAt: k phaseX: phaseIx phaseY: phaseIy sx: sx sy: sy contourData: contourData indexes: indexes tx: tx
	"Rasterize the single glyph at byte k through the regular outline path at a
	SYNTHETIC position at the centre of the clip rect -- a tile depends only on
	(glyph, size, subpixel phase), not on where it bakes -- then extract its
	coverage, clear the mask residue with primClearMask, and reset the path so
	neither coverage nor span leaks into the caller's blend.
	Tile = {w. h. dx. dy. sheetOffset. leftInk. rightInk}: dx/dy relative to the
	integer pen position; leftInk/rightInk are the first and last columns with any
	coverage (tile-relative). Two tiles whose INK extents do not overlap compose
	identically whether max-combined in the mask or blended independently, so the
	fused prim only needs ink disjointness, not box disjointness.
	Answers nil when the glyph cannot be baked here."
	| bakeDevX bakeDevY localX localY l t r b w h bytes offset leftInk rightInk idx |
	bakeDevX := ((clipLeft + clipRight) // 2) + (phaseIx * 0.25).
	bakeDevY := ((clipTop + clipBottom) // 2) + (phaseIy * 0.5).
	localX := (bakeDevX - tx a13) / tx a11.
	localY := (bakeDevY - tx a23) / tx a22.
	self initializePath.
	self displayUtf8: aByteArray fromByte: k toByte: k
		atx: localX y: localY scalex: sx y: sy
		contourData: contourData contourDataIndexes: indexes.
	self primUpdateContourLastLine.
	l := self primSpanLeft.
	t := self primSpanTop.
	r := self primSpanRight.
	b := self primSpanBottom + 1.
	(r < l or: [b < t]) ifTrue: [
		"empty glyph (e.g. space): cache as zero-size tile"
		self initializePath.
		^ {0. 0. 0. 0. 0. 0. 0}].
	(l < clipLeft or: [t < clipTop or: [r > clipRight or: [b > clipBottom]]]) ifTrue: [
		"glyph does not fit inside the hosting clip even at its centre: it baked
		cropped, so refuse it and let the caller fall back"
		self primClearMaskLeft: (l max: clipLeft) top: (t max: clipTop) right: (r min: clipRight) bottom: (b min: clipBottom).
		self initializePath.
		^ nil].
	w := r - l + 1.
	h := b - t + 1.
	w * h > 16384 ifTrue: [
		self primClearMaskLeft: l top: t right: r bottom: b.
		self initializePath.
		^ nil].
	bytes := ByteArray new: w * h.
	self primExtractCoverageLeft: l top: t right: r bottom: b into: bytes pitch: w.
	self primClearMaskLeft: l top: t right: r bottom: b.
	self initializePath.
	leftInk := w - 1.
	rightInk := 0.
	1 to: bytes size do: [:i |
		(bytes at: i) = 0 ifFalse: [
			idx := (i - 1) \\ w.
			idx < leftInk ifTrue: [leftInk := idx].
			idx > rightInk ifTrue: [rightInk := idx]]].
	offset := GlyphTileCache append: bytes.
	^ {w. h. l - bakeDevX floor. t - bakeDevY floor. offset. leftInk. rightInk}! !

!VectorEngineWithPluginWholePixel methodsFor: '*VectorEngineOpt' stamp: 'ML 4/Jul/2026 22:42:05'!
pvtDrawTiledUtf8: aByteArray fromByte: byteStartIndex toByte: byteStopIndex at: aPoint trueTypeFont: aTTFontDescription color: aColor scale: scale orFallBack: fallBackBlock
	| tx trueTypeScale sx sy contourData indexes sizeKey tiles n meta destY devY yFrac phaseIy wantDevY count localPen adv devX xFrac phaseIx tile key glyphIndex ok dx dy inkS inkE prefMaxE overlaps stampMeta stampCount fusedMeta fusedCount i |
	tx := geometryTransformation.
	trueTypeScale := 1.0 / aTTFontDescription letterMTopSideBearing.
	sx := scale * trueTypeScale.
	sy := (scale * trueTypeScale) negated.
	contourData := aTTFontDescription contourDataForUtf8.
	indexes := aTTFontDescription contourDataIndexesByUtf8.
	"sx is pointSize/letterMTopSideBearing, i.e. ~0.02: quantize FINELY -- coarse
	quantization collapses different point sizes into one bucket and glyphs render
	at the wrong size (1/16384 in sx-space is ~1/15 of a point step)."
	sizeKey := (sx * tx a11 * 16384.0) rounded.
	tiles := GlyphTileCache tilesFor: aTTFontDescription sizeKey: sizeKey.
	"Both stamping AND baking are clip-independent: the prims clip tiles to the
	clip rect, and pvtBakeGlyphTile bakes at a synthetic in-clip position and
	cleans up after itself. So cached runs draw (and bake) regardless of clipping."
	destY := aPoint y asFloat.
	devY := (destY * tx a22) + tx a23.
	yFrac := (devY * 2.0) rounded.
	phaseIy := yFrac \\ 2.
	wantDevY := (yFrac // 2) + (phaseIy * 0.5).
	n := byteStopIndex - byteStartIndex + 1.
	meta := WordArray new: n * 5.
	inkS := Array new: n.
	inkE := Array new: n.
	prefMaxE := Array new: n.
	overlaps := Array new: n.
	ok := true.
	self fillColor: aColor do: [
		"fillColor:do: may evaluate this block more than once (see super): reset run state each time"
		count := 0.
		localPen := aPoint x asFloat.
		byteStartIndex to: byteStopIndex do: [:k |
			glyphIndex := indexes at: (aByteArray at: k) + 1.
			adv := contourData at: glyphIndex.
			devX := (localPen * tx a11) + tx a13.
			xFrac := (devX * 4.0) rounded.
			phaseIx := xFrac \\ 4.
			devX := xFrac // 4.
			key := glyphIndex * 8 + (phaseIx * 2) + phaseIy.
			tile := tiles at: key ifAbsent: [nil].
			tile ifNil: [
				tile := self pvtBakeGlyphTile: aByteArray byteAt: k
					phaseX: phaseIx phaseY: phaseIy
					sx: sx sy: sy contourData: contourData indexes: indexes tx: tx.
				tile ifNil: [ok := false] ifNotNil: [tiles at: key put: tile]].
			(ok and: [tile notNil and: [(tile at: 1) > 0]]) ifTrue: [
				dx := devX + (tile at: 3).
				dy := wantDevY floor + (tile at: 4).
				(dx < 0 or: [dy < 0])
					ifTrue: [
						"meta is a WordArray (unsigned): a tile that starts left of or
						above the target cannot be encoded -- outline-draw this run"
						ok := false]
					ifFalse: [
						meta at: count * 5 + 1 put: dx.
						meta at: count * 5 + 2 put: dy.
						meta at: count * 5 + 3 put: (tile at: 1).
						meta at: count * 5 + 4 put: (tile at: 2).
						meta at: count * 5 + 5 put: (tile at: 5).
						count := count + 1.
						inkS at: count put: dx + (tile at: 6).
						inkE at: count put: dx + (tile at: 7).
						prefMaxE at: count put: (count = 1
							ifTrue: [inkE at: 1]
							ifFalse: [(prefMaxE at: count - 1) max: (inkE at: count)]).
						overlaps at: count put: false]].
			localPen := localPen + (adv * sx)].
		(ok and: [count > 0]) ifTrue: [
			"Partition: tiles whose ink overlaps a neighbour must max-combine in the
			mask (stamp path); every other tile composites directly (fused prim).
			The two pixel sets are disjoint, so mixing the paths stays bit-identical
			to stamping everything."
			2 to: count do: [:j | | back |
				"scan back over every earlier tile whose ink could still reach this
				one (prefix-max of ink ends bounds the walk); mark both sides of
				each genuine ink overlap for the mask path"
				back := j - 1.
				[back >= 1 and: [(prefMaxE at: back) >= (inkS at: j)]] whileTrue: [
					(inkE at: back) >= (inkS at: j) ifTrue: [
						overlaps at: j put: true.
						overlaps at: back put: true].
					back := back - 1]].
			stampCount := 0.
			1 to: count do: [:j | (overlaps at: j) ifTrue: [stampCount := stampCount + 1]].
			stampCount = 0
				ifTrue: [self primBlendStampedCoverageRun: GlyphTileCache sheet meta: meta count: count]
				ifFalse: [
					stampMeta := WordArray new: stampCount * 5.
					fusedMeta := WordArray new: (count - stampCount) * 5.
					stampCount := 0.
					fusedCount := 0.
					1 to: count do: [:j |
						(overlaps at: j)
							ifTrue: [
								1 to: 5 do: [:f | stampMeta at: stampCount * 5 + f put: (meta at: j - 1 * 5 + f)].
								stampCount := stampCount + 1]
							ifFalse: [
								1 to: 5 do: [:f | fusedMeta at: fusedCount * 5 + f put: (meta at: j - 1 * 5 + f)].
								fusedCount := fusedCount + 1]].
					fusedCount > 0 ifTrue: [
						self primBlendStampedCoverageRun: GlyphTileCache sheet meta: fusedMeta count: fusedCount].
					stampCount > 0 ifTrue: [
						self primStampCoverageRun: GlyphTileCache sheet meta: stampMeta count: stampCount]]]].
	ok ifFalse: [^ fallBackBlock value].
	^ localPen @ destY! !
