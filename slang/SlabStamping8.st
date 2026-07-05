'Slab stamping v8 for VectorEnginePlugin (whole pixel family). Applies on top of v7.
DIRTY-SPAN JOURNAL, bit-identical output: two plugin-internal per-row arrays
(dirtyLeftJ, dirtyRightJ, allocated at set-target) record the x-extent every WP
stamper touches on each row. The WP blend passes then clamp their per-row sweep to
the dirty span and reset it, instead of scanning the whole span bounding box:
- pixels outside the dirty span hold no stamps, so stroke alpha is zero there and
  fill winding cannot change there (edges ARE stamps, and a closed path''s crossings
  balance to zero after the rightmost one), so skipping them is bit-identical;
- the journal is an over-approximation (stampers record the examined, clip-clamped
  range; conditional writes may not all land): a dirty row with clean bytes is swept
  cheaply by the existing segment machinery, never incorrectly;
- a window-chrome stroke blend used to sweep its whole 4.2 Mpx bounding box for a
  ring that touches ~2% of it; now each row costs two loads outside the ring rows.
ML 7/4/2026'!

SmartSyntaxInterpreterPlugin subclass: #VectorEnginePlugin
	instanceVariableNames: 'targetBits morphIds edgeCounts edgeCountsWP alphaMask alphaMaskWP affectedBits contour targetWidth targetHeight targetAssumedOpaque antiAliasingWidth subPixelDelta hop strokeWidth strokeR strokeG strokeB strokeA dashedStrokeBits dashBitCount dashBitLength dashBitOffset fillR fillG fillB fillA txA11 txA12 txA13 txA21 txA22 txA23 currentMorphId clipLeft clipTop clipRight clipBottom clippingSpec auxAntiAliasingWidthScaledInverse auxStrokeWidthDilatedHalf auxStrokeWidthDilatedHalfSquared auxStrokeWidthErodedHalfSquared spanLeft spanTop spanRight spanBottom prevYTruncated prevYRounded leftAtThisY rightAtThisY trajectoryLength needsFullAlphaCircle dirtyLeftJ dirtyRightJ dirtyRowsAllocated dirtyMinY dirtyMaxY'
	classVariableNames: ''
	poolDictionaries: ''
	category: 'VectorEnginePlugin'!

!VectorEnginePlugin class methodsFor: 'translation' stamp: 'ML 7/4/2026 20:00'!
declareCVarsIn: aCCodeGenerator


	aCCodeGenerator addHeaderFile: '<stdint.h>'.
	aCCodeGenerator addHeaderFile: '<stdlib.h>'.
	aCCodeGenerator var: 'targetBits' type: 'uint32_t *'.
	aCCodeGenerator var: 'morphIds' type: 'uint32_t *'.
	aCCodeGenerator var: 'edgeCounts' type: 'uint32_t *'.
	aCCodeGenerator var: 'edgeCountsWP' type: 'uint8_t *'.
	aCCodeGenerator var: 'alphaMask' type: 'uint32_t *'.
	aCCodeGenerator var: 'alphaMaskWP' type: 'uint8_t *'.
	aCCodeGenerator var: 'affectedBits' type: 'uint8_t *'.
	aCCodeGenerator var: 'contour' type: 'float *'.
	aCCodeGenerator var: 'currentMorphId' type: 'uint32_t'.
	aCCodeGenerator var: 'clippingSpec' type: 'int *'.
	"Dirty-span journal: per-row stamped x-extent, plugin-internal (see class comment
	of the v8 change set). Static NULL/0 initialization is correct: the set-target
	primitive allocates and initializes before any stamper can run."
	aCCodeGenerator var: 'dirtyLeftJ' type: 'int *'.
	aCCodeGenerator var: 'dirtyRightJ' type: 'int *'.
	aCCodeGenerator var: 'dirtyRowsAllocated' type: 'int'.
	aCCodeGenerator var: 'dirtyMinY' type: 'int'.
	aCCodeGenerator var: 'dirtyMaxY' type: 'int'.
	#(antiAliasingWidth subPixelDelta hop strokeWidth strokeR strokeG strokeB strokeA dashBitLength fillR fillG fillB fillA txA11 txA12 txA13 txA21 txA22 txA23 auxAntiAliasingWidthScaledInverse auxStrokeWidthDilatedHalf auxStrokeWidthDilatedHalfSquared auxStrokeWidthErodedHalfSquared spanLeft spanTop spanRight spanBottom leftAtThisY rightAtThisY trajectoryLength) do: [ :varName |
		aCCodeGenerator var: varName type: 'float' ].! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - setup' stamp: 'ML 7/4/2026 20:00'!
targetBits: aBitmap morphIds: aWordArray edgeCountsWP: otherByteArray alphaMaskWP: anotherByteArray affectedBits: affectedBitsBA contour: aFloat32Array targetWidth: aNumber targetHeight: otherNumber

	self
		primitive: 'primSetTargetWP'
		parameters: #(WordArray WordArray ByteArray ByteArray ByteArray Float32Array SmallInteger SmallInteger).

	targetBits := aBitmap.
	morphIds := aWordArray.
	edgeCountsWP := otherByteArray.
	alphaMaskWP := anotherByteArray.
	affectedBits := affectedBitsBA.
	contour := aFloat32Array.
	targetWidth := aNumber.
	targetHeight := otherNumber.
	clippingSpec := nil.
	"Ensure the dirty-span journal covers this target. Rows initialize to the empty
	sentinel (left = targetWidth, right = -1); afterwards stampers widen rows and
	blends consume-and-reset them, so no per-path reset is needed."
	self cCode: 'if (dirtyRowsAllocated < targetHeight) {
			int i;
			free(dirtyLeftJ);
			free(dirtyRightJ);
			dirtyLeftJ = (int *)malloc(targetHeight * sizeof(int));
			dirtyRightJ = (int *)malloc(targetHeight * sizeof(int));
			dirtyRowsAllocated = targetHeight;
			for (i = 0; i < targetHeight; i += 1) {
				dirtyLeftJ[i] = targetWidth;
				dirtyRightJ[i] = -1; } }' inSmalltalk: [].
	dirtyMinY := targetHeight.
	dirtyMaxY := -1.! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - path algorithms' stamp: 'ML 7/4/2026 20:00'!
journalDirtyRow: displayY from: xLeft to: xRight
	"Record that a stamper touched row displayY between xLeft and xRight (inclusive),
	widening the row's dirty span. Over-approximation is safe (blends sweep clean
	bytes cheaply); inverted inputs from empty runs only ever widen, never corrupt."
	<inline: true>
	xLeft < (dirtyLeftJ at: displayY) ifTrue: [ dirtyLeftJ at: displayY put: xLeft ].
	xRight > (dirtyRightJ at: displayY) ifTrue: [ dirtyRightJ at: displayY put: xRight ].
	displayY < dirtyMinY ifTrue: [ dirtyMinY := displayY ].
	displayY > dirtyMaxY ifTrue: [ dirtyMaxY := displayY ]! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - path algorithms' stamp: 'ML 7/4/2026 21:30'!
initializePath
	self
		primitive: 'primInitializePath'
		parameters: #().

	spanLeft := targetWidth.						"drawable right. Will later be refined."
	spanTop := targetHeight.						"drawable bottom. Will later be refined."
	spanRight := 0.						"drawable left. Will later be refined."
	spanBottom := 0.						"drawable top. Will later be refined."
	prevYRounded := 16r7FFFFFFF.
	"Reset the dirty-span journal for the new path -- only the rows the previous
	path touched (dirtyMinY..dirtyMaxY). Blends read the journal but never reset
	it: the engine may blend the same stamped data more than once (second-pass /
	contour draws), so the journal must survive until the next path begins."
	(dirtyRowsAllocated > 0 and: [dirtyMinY <= dirtyMaxY]) ifTrue: [
		"dirtyRowsAllocated guards the whole-pixel journal: this primitive is
		shared with the subpixel engine, which never allocates it."
		dirtyMinY to: dirtyMaxY do: [ :i |
			dirtyLeftJ at: i put: targetWidth.
			dirtyRightJ at: i put: -1 ].
		dirtyMinY := targetHeight.
		dirtyMaxY := -1 ].! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - stamping alpha values' stamp: 'ML 7/4/2026 20:00'!
updateAlphasWPForX: x y: y
	
	"In a basic implementation, this method computes anti aliasing translucency for all possibly affected pixels as determined by
	the outer radius of the pen nib: auxStrokeWidthDilatedHalf.
	But usually the next point visited is very close to the last, and there's no real need to fill the inner part of the pen nib as opaque,
	as it was already set. So, unless needsFullAlphaCircle, only the outer ring is computed and stored.
	The inner radius of this ring is auxStrokeWidthErodedHalfSquared"

	<var: 'x' type: #float>
	<var: 'y' type: #float>
	| t b l r pixelIndex candidateAlpha alphaByte distanceToAxisSquared dy dySquared dx bit lastUpdated affectedBitsIndex aux1 |
	<var: 'candidateAlpha' type: #'uint8_t'>
	<var: 'alphaByte' type: #'uint8_t'>
	<var: 'distanceToAxisSquared' type: #float>
	<var: 'dy' type: #float>
	<var: 'dySquared' type: #float>
	<var: 'dx' type: #float>
	<var: 'aux1' type: #float>
	
	"Use this optimized varsion if possible."	
	(strokeWidth = 0.0 and: [(antiAliasingWidth - 1.6) abs < 1e-6]) ifTrue: [
		^self updateAlphasWPZeroStrokeForX: x y: y ].

	"If dashed strokes, only draw if in a dash, not in a gap."
	dashBitLength = 0.0 ifFalse: [
		"Compute trajectory length. This is not precise. In many cases the actual hop used is smaller than this."
		trajectoryLength := trajectoryLength + hop.
		"Note: dashBitOffset must be positive."
		bit := ((trajectoryLength / dashBitLength) asInteger + dashBitOffset) \\ dashBitCount.
		(dashedStrokeBits bitAnd: 1 << (dashBitCount-bit-1)) = 0 ifTrue: [
			needsFullAlphaCircle := true.
			^self ]].
	
	"Compute affected rect. Honor clipRect"
	t := (y - auxStrokeWidthDilatedHalf + 1) asInteger.				"(int(z+1)) works equally well than the more intuitive but slower (int(ceil(z))"
	t < clipTop ifTrue: [ t := clipTop ].
	b := (y + auxStrokeWidthDilatedHalf) asInteger.
	b > clipBottom ifTrue: [ b := clipBottom ].
	l := (x - auxStrokeWidthDilatedHalf + 1) asInteger.				"(int(z+1)) works equally well than the more intuitive but slower (int(ceil(z))"
	l < clipLeft ifTrue: [ l := clipLeft ].
	r := (x + auxStrokeWidthDilatedHalf) asInteger.
	r > clipRight ifTrue: [ r := clipRight ].

	lastUpdated := -1.
	t to: b do: [ :displayY |
		self journalDirtyRow: displayY from: l to: r.
		pixelIndex := displayY * targetWidth + l -1.
		dy := displayY - y.
		dySquared := dy * dy.
		l to: r do: [ :displayX |
			pixelIndex := pixelIndex + 1.
			dx := displayX - x.
			distanceToAxisSquared := dx*dx + dySquared.
			distanceToAxisSquared < auxStrokeWidthDilatedHalfSquared
				ifTrue: [
					(needsFullAlphaCircle or: [distanceToAxisSquared > auxStrokeWidthErodedHalfSquared]) ifTrue: [
						alphaByte := alphaMaskWP at: pixelIndex.
						alphaByte = 16r7F ifFalse: [
							aux1 := auxStrokeWidthDilatedHalf - distanceToAxisSquared sqrt.
							candidateAlpha := ((aux1 min: antiAliasingWidth) * auxAntiAliasingWidthScaledInverse) asInteger.
							candidateAlpha > alphaByte ifTrue: [
								affectedBitsIndex := pixelIndex>>4.
								lastUpdated = affectedBitsIndex ifFalse: [ "Slight optimization"
									(affectedBits at: affectedBitsIndex) = 1 ifFalse: [
										affectedBits at: affectedBitsIndex put: 1.
										lastUpdated := affectedBitsIndex ]].
								alphaMaskWP at: pixelIndex put: candidateAlpha ]]]]]].
	needsFullAlphaCircle := false.! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - stamping alpha values' stamp: 'ML 7/4/2026 20:00'!
updateAlphasWPZeroStrokeForX: x y: y
	"Optimization.
	Assumptions:
		- strokeWidth = 0.0
		- antiAliasingWidth = 1.6 (Default for whole pixel anti aliasing)
	Therefore:
		- swDilatedHalf = 0.8
		- swDilatedHalfSquared = 0.64
		- aawScaledInverse = 79.375
		- No use for needsFullAlphaCircle, swErodedHalfSquared
		- No support for dashedStrokes
		"

	<var: 'x' type: #float>
	<var: 'y' type: #float>
	| t b l r pixelIndex candidateAlpha alphaByte distanceToAxisSquared dy dySquared dy2 dy2Squared dx dxSquared dx2 dx2Squared affectedBitsIndex1 affectedBitsIndex2 |
	<var: 'candidateAlpha' type: #'uint8_t'>
	<var: 'alphaByte' type: #'uint8_t'>
	<var: 'distanceToAxisSquared' type: #float>
	<var: 'dy' type: #float>
	<var: 'dySquared' type: #float>
	<var: 'dy2' type: #float>
	<var: 'dy2Squared' type: #float>
	<var: 'dx' type: #float>
	<var: 'dxSquared' type: #float>
	<var: 'dx2' type: #float>
	<var: 'dx2Squared' type: #float>
	
	"Compute affected rect. Honor clipRect"
	t := y asInteger.
	b := t + 1.
	l := x asInteger.
	r := l + 1.
	t < clipTop ifTrue: [ t := clipTop ].
	b > clipBottom ifTrue: [ b := clipBottom ].
	l < clipLeft ifTrue: [ l := clipLeft ].
	r > clipRight ifTrue: [ r := clipRight ].
	t> b ifTrue: [ ^self ].
	l > r ifTrue: [ ^self ].
	self journalDirtyRow: t from: l to: r.

	pixelIndex := t * targetWidth + l.
	affectedBitsIndex1 := -1.
	dy := t - y.
	dySquared := dy * dy.
	dx := l - x.
	dxSquared := dx * dx.
	distanceToAxisSquared := dxSquared + dySquared.
	distanceToAxisSquared < 0.64 ifTrue: [
		alphaByte := alphaMaskWP at: pixelIndex.
		alphaByte = 16r7F ifFalse: [
			candidateAlpha := ((0.8 - distanceToAxisSquared sqrt) * 79.375) asInteger.
			candidateAlpha > alphaByte ifTrue: [
				affectedBitsIndex1 := pixelIndex>>4.
				(affectedBits at: affectedBitsIndex1) = 0 ifTrue: [
					affectedBits at: affectedBitsIndex1 put: 1 ].
				alphaMaskWP at: pixelIndex put: candidateAlpha ]].
		distanceToAxisSquared < 0.36 ifTrue: [ ^self ]].

	r = l ifFalse: [
		dx2 := dx + 1.
		dx2Squared := dx2 * dx2.
		distanceToAxisSquared := dx2Squared + dySquared.
		distanceToAxisSquared < 0.64 ifTrue: [
			alphaByte := alphaMaskWP at: pixelIndex+1.
			alphaByte = 16r7F ifFalse: [
				candidateAlpha := ((0.8 - distanceToAxisSquared sqrt) * 79.375) asInteger.
				candidateAlpha > alphaByte ifTrue: [
					affectedBitsIndex2 := (pixelIndex+1)>>4.
					affectedBitsIndex2 = affectedBitsIndex1 ifFalse: [
						(affectedBits at: affectedBitsIndex2) = 0 ifTrue: [
							affectedBits at: affectedBitsIndex2 put: 1 ]].
					alphaMaskWP at: pixelIndex+1 put: candidateAlpha ]].
			distanceToAxisSquared < 0.36 ifTrue: [ ^self ]]].

	t = b ifTrue: [ ^self ].
	self journalDirtyRow: b from: l to: r.

	pixelIndex := b * targetWidth + l.
	affectedBitsIndex1 := -1.
	dy2 := dy + 1.
	dy2Squared := dy2 * dy2.
	distanceToAxisSquared := dxSquared + dy2Squared.
	distanceToAxisSquared < 0.64 ifTrue: [
		alphaByte := alphaMaskWP at: pixelIndex.
		alphaByte = 16r7F ifFalse: [
			candidateAlpha := ((0.8 - distanceToAxisSquared sqrt) * 79.375) asInteger.
			candidateAlpha > alphaByte ifTrue: [
				affectedBitsIndex1 := pixelIndex>>4.
				(affectedBits at: affectedBitsIndex1) = 0 ifTrue: [
					affectedBits at: affectedBitsIndex1 put: 1 ].
				alphaMaskWP at: pixelIndex put: candidateAlpha ]].
		distanceToAxisSquared < 0.36 ifTrue: [ ^self ]].

	r = l ifFalse: [
		distanceToAxisSquared := dx2Squared + dy2Squared.
		distanceToAxisSquared < 0.64 ifTrue: [
			alphaByte := alphaMaskWP at: pixelIndex+1.
			alphaByte = 16r7F ifFalse: [
				candidateAlpha := ((0.8 - distanceToAxisSquared sqrt) * 79.375) asInteger.
				candidateAlpha > alphaByte ifTrue: [
					affectedBitsIndex2 := (pixelIndex+1)>>4.
					affectedBitsIndex2 = affectedBitsIndex1 ifFalse: [
						(affectedBits at: affectedBitsIndex2) = 0 ifTrue: [
							affectedBits at: affectedBitsIndex2 put: 1 ]].
					alphaMaskWP at: pixelIndex+1 put: candidateAlpha ]]]].! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - stamping alpha values' stamp: 'ML 7/4/2026 20:00'!
updateEdgeCountWPAtX: x y: y
	"Compute edges intersecting with this horizontal line, for fills."

	<var: 'x' type: #float>
	<var: 'y' type: #float>
	| thisYTruncated pixelY pixelIndex increment count pixelOffset affectedBitsIndex |

	<var: 'count' type: #'uint8_t'>
	<var: 'increment' type: #'uint8_t'>
	

	thisYTruncated := y asInteger.	"truncated, both in C and Smalltalk"
	thisYTruncated = prevYTruncated ifTrue: [
		^ 0].
	(thisYTruncated between: clipTop-1 and: clipBottom) ifFalse: [
		^ 0 ].
	prevYTruncated = 16r7FFFFFFF ifTrue: [ 
		prevYTruncated := thisYTruncated.
		^ 0 ].

	thisYTruncated > prevYTruncated
		ifTrue: [
			pixelY := thisYTruncated.
			increment := 16r01 ]
		ifFalse: [
			pixelY := prevYTruncated.
			increment := 16rFF ].
	prevYTruncated := thisYTruncated.

	"All edge count at the left of the clipRect are added there (at the left of the clipRect).
	The effect is the same, and we need to clean up less stuff afterwards.
	More important, it avoids trying to acess pixels outside our form, i.e. invalid array acesses."
	pixelOffset := (x+1) asInteger max: clipLeft.		"take the next pixel center to the right of x"

	pixelOffset <= clipRight ifTrue: [
		self journalDirtyRow: pixelY from: pixelOffset to: pixelOffset.
		pixelIndex := pixelY * targetWidth + pixelOffset.
		count := edgeCountsWP at: pixelIndex.
		count := count + increment.
		edgeCountsWP at: pixelIndex put: count.
		affectedBitsIndex := pixelIndex>>4.
		(affectedBits at: affectedBitsIndex) = 1 ifFalse: [
			affectedBits at: affectedBitsIndex put: 1 ]].! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - path algorithms' stamp: 'ML 7/4/2026 20:00'!
slabStampSegmentWPFromX: x0 y: y0 toX: x1 y: y1
	"Stamp stroke coverage for a whole (already transformed) segment in ONE pass, computing
	the exact distance from each affected pixel to the segment, instead of stamping a distance
	disk at every hop along the trajectory (which visits each pixel about
	auxStrokeWidthDilatedHalf * 2 / hop times).
	Same alpha function as updateAlphasWPForX:y:. Interior pixels (distance <= erodedHalf)
	get full alpha directly: auxStrokeWidthDilatedHalf - erodedHalf = antiAliasingWidth, so the
	(aux1 min: antiAliasingWidth) clamp yields 127 for them; we shortcut with the eroded test.
	Round caps at both segment ends fall out of the distance-to-endpoint branches.
	Callers handle dashes by stamping each dash run as a separate sub-segment."

	<var: 'x0' type: #float>
	<var: 'y0' type: #float>
	<var: 'x1' type: #float>
	<var: 'y1' type: #float>
	| dh dx dy len2 invLen2 t b l r pixelIndex candidateAlpha alphaByte lastUpdated affectedBitsIndex aux1 d2 qx qy tt tA tB tmp xA xB xlo xhi c rx ry rowHasSlab |
	<var: 'dh' type: #float>
	<var: 'dx' type: #float>
	<var: 'dy' type: #float>
	<var: 'len2' type: #float>
	<var: 'invLen2' type: #float>
	<var: 'candidateAlpha' type: #'uint8_t'>
	<var: 'alphaByte' type: #'uint8_t'>
	<var: 'aux1' type: #float>
	<var: 'd2' type: #float>
	<var: 'qx' type: #float>
	<var: 'qy' type: #float>
	<var: 'tt' type: #float>
	<var: 'tA' type: #float>
	<var: 'tB' type: #float>
	<var: 'tmp' type: #float>
	<var: 'xA' type: #float>
	<var: 'xB' type: #float>
	<var: 'xlo' type: #float>
	<var: 'xhi' type: #float>
	<var: 'c' type: #float>
	<var: 'rx' type: #float>
	<var: 'ry' type: #float>

	dh := auxStrokeWidthDilatedHalf.
	dx := x1 - x0.
	dy := y1 - y0.
	len2 := (dx * dx) + (dy * dy).
	len2 = 0.0 ifTrue: [
		"Degenerate segment: nudge it into a tiny one. The endpoint-distance branches below
		then compute plain point distance, i.e. a single disk stamp."
		dx := 1e-6.
		len2 := 1e-12 ].
	invLen2 := 1.0 / len2.
	t := ((y0 min: y1) - dh + 1) asInteger.				"(int(z+1)) works equally well than the more intuitive but slower (int(ceil(z))"
	t < clipTop ifTrue: [ t := clipTop ].
	b := ((y0 max: y1) + dh) asInteger.
	b > clipBottom ifTrue: [ b := clipBottom ].

	lastUpdated := -1.
	t to: b do: [ :displayY |
		"x interval covered by the slab on this scanline: the segment's x extent over the
		t-range whose y is within dh of the row, dilated by dh."
		rowHasSlab := true.
		dy abs > 1e-6
			ifTrue: [
				tA := (displayY - dh - y0) / dy.
				tB := (displayY + dh - y0) / dy.
				tA > tB ifTrue: [ tmp := tA. tA := tB. tB := tmp ].
				(tB < 0.0 or: [tA > 1.0])
					ifTrue: [ rowHasSlab := false ]
					ifFalse: [
						tA < 0.0 ifTrue: [ tA := 0.0 ].
						tB > 1.0 ifTrue: [ tB := 1.0 ].
						xA := x0 + (tA * dx).
						xB := x0 + (tB * dx).
						xlo := (xA min: xB) - dh.
						xhi := (xA max: xB) + dh ]]
			ifFalse: [
				xlo := (x0 min: x1) - dh.
				xhi := (x0 max: x1) + dh ].
		rowHasSlab ifTrue: [
			l := (xlo + 1) asInteger.				"(int(z+1)) works equally well than the more intuitive but slower (int(ceil(z))"
			l < clipLeft ifTrue: [ l := clipLeft ].
			r := xhi asInteger.
			r > clipRight ifTrue: [ r := clipRight ].
			l <= r ifTrue: [ self journalDirtyRow: displayY from: l to: r ].
			pixelIndex := displayY * targetWidth + l - 1.
			qy := displayY - y0.
			l to: r do: [ :displayX |
				pixelIndex := pixelIndex + 1.
				alphaByte := alphaMaskWP at: pixelIndex.
				alphaByte = 16r7F ifFalse: [
					qx := displayX - x0.
					tt := (qx * dx) + (qy * dy).
					tt <= 0.0
						ifTrue: [ d2 := (qx * qx) + (qy * qy) ]
						ifFalse: [
							tt >= len2
								ifTrue: [
									rx := qx - dx.
									ry := qy - dy.
									d2 := (rx * rx) + (ry * ry) ]
								ifFalse: [
									c := (qx * dy) - (qy * dx).
									d2 := c * c * invLen2 ]].
					d2 < auxStrokeWidthDilatedHalfSquared ifTrue: [
						d2 <= auxStrokeWidthErodedHalfSquared
							ifTrue: [ candidateAlpha := 16r7F ]
							ifFalse: [
								aux1 := dh - d2 sqrt.
								candidateAlpha := ((aux1 min: antiAliasingWidth) * auxAntiAliasingWidthScaledInverse) asInteger ].
						candidateAlpha > alphaByte ifTrue: [
							affectedBitsIndex := pixelIndex>>4.
							lastUpdated = affectedBitsIndex ifFalse: [ "Slight optimization"
								(affectedBits at: affectedBitsIndex) = 1 ifFalse: [
									affectedBits at: affectedBitsIndex put: 1.
									lastUpdated := affectedBitsIndex ]].
							alphaMaskWP at: pixelIndex put: candidateAlpha ]]]]]].
	needsFullAlphaCircle := false.! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - text and multi paths' stamp: 'ML 7/4/2026 20:00'!
stampCoverageRunWP: sheet meta: metaArray count: n
	"Stamp n cached coverage tiles (glyphs) into alphaMaskWP (max-combine, like the
	regular stampers) instead of compositing directly, so the caller's normal blend
	does the single compositing pass. Idempotent under repeated draws of the same
	frame region, exactly like outline stamping. Updates affectedBits and the span.
	metaArray holds 5 words per tile: destX destY w h sheetOffset."

	| base dx dy w h off pixelIndex sIndex cov old lastUpdated affectedBitsIndex rowStart rowEnd colStart colEnd |
	<var: 'cov' type: #'uint8_t'>
	<var: 'old' type: #'uint8_t'>
	self
		primitive: 'primStampCoverageRunWP'
		parameters: #(ByteArray WordArray SmallInteger).

	lastUpdated := -1.
	1 to: n do: [ :g |
		base := g - 1 * 5.
		dx := metaArray at: base.
		dy := metaArray at: base + 1.
		w := metaArray at: base + 2.
		h := metaArray at: base + 3.
		off := metaArray at: base + 4.
		"honor the clip rect: stamp only the visible part of the tile"
		rowStart := dy max: clipTop.
		rowEnd := dy + h - 1 min: clipBottom.
		colStart := dx max: clipLeft.
		colEnd := dx + w - 1 min: clipRight.
		(rowEnd >= rowStart and: [colEnd >= colStart]) ifTrue: [
		colStart < spanLeft ifTrue: [ spanLeft := colStart ].
		rowStart < spanTop ifTrue: [ spanTop := rowStart ].
		colEnd + 1 > spanRight ifTrue: [ spanRight := colEnd + 1 ].
		rowEnd + 1 > spanBottom ifTrue: [ spanBottom := rowEnd + 1 ].
		rowStart to: rowEnd do: [ :rowY |
			self journalDirtyRow: rowY from: colStart to: colEnd.
			pixelIndex := rowY * targetWidth + colStart.
			sIndex := off + ((rowY - dy) * w) + (colStart - dx).
			0 to: colEnd - colStart do: [ :col |
				cov := sheet at: sIndex + col.
				cov = 0 ifFalse: [
					old := alphaMaskWP at: pixelIndex.
					cov > old ifTrue: [
						affectedBitsIndex := pixelIndex >> 4.
						lastUpdated = affectedBitsIndex ifFalse: [
							(affectedBits at: affectedBitsIndex) = 1 ifFalse: [
								affectedBits at: affectedBitsIndex put: 1 ].
							lastUpdated := affectedBitsIndex ].
						alphaMaskWP at: pixelIndex put: cov ]].
				pixelIndex := pixelIndex + 1 ]]]]! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - blend stroke and fill' stamp: 'ML 7/4/2026 20:00'!
blendFillOnlyWPLeft: l top: t right: r bottom: b
	"Blends fill color over background.
	WP: Whole pixel anti aliasing.
	If targetAssumedOpaque is false, target translucency is computed correctly.
	If targetAssumedOpaque is true (and target translucency is actually 255 on input), an optimization is made and target translucency is set to 255.
	For blending, alphas are in [0 .. 1.0] and R, G, B color components are in [0 .. 255]"
	| pixelIndex edgesUpToThisPixel edgesThisPixel strokeAntiAliasAlphaBits clippingSpecL clippingSpecR clippingSpecIndex antiAliasedClippedLeftPixel antiAliasedClippedRightPixel mustResetColor realFillAlpha opaqueFillColorWord realOpaqueFillColorWord auxR auxG auxB displayX affectedBitsIndex segmentLength alphasOrEdgeCountsInThisSegment lastSegmentIndex aux1 toDoLimit tightDone runLen runSafe maxRun targetWord2 bulkAlpha bulkUnAlpha bulkTargetAlpha bulkResultAlpha bulkFR bulkFG bulkFB bulkR bulkG bulkB vEdges0 vEdges1 vAlpha0 vAlpha1 rowL rowR |
	<var: 'targetWord2' type: #'uint32_t'>
	<var: 'bulkAlpha' type: #float>
	<var: 'bulkUnAlpha' type: #float>
	<var: 'bulkTargetAlpha' type: #float>
	<var: 'bulkResultAlpha' type: #float>
	<var: 'bulkFR' type: #float>
	<var: 'bulkFG' type: #float>
	<var: 'bulkFB' type: #float>
	<var: 'bulkR' type: #float>
	<var: 'bulkG' type: #float>
	<var: 'bulkB' type: #float>
	<var: 'edgesThisPixel' type: #'uint8_t'>
	<var: 'edgesUpToThisPixel' type: #'uint8_t'>
	<var: 'strokeAntiAliasAlphaBits' type: #'uint8_t'>
	<var: 'opaqueFillColorWord' type: #'uint32_t'>
	<var: 'realOpaqueFillColorWord' type: #'uint32_t'>
	<var: 'auxR' type: #'uint32_t'>
	<var: 'auxG' type: #'uint32_t'>
	<var: 'auxB' type: #'uint32_t'>
	<var: 'vEdges0' type: #'usqLong'>
	<var: 'vEdges1' type: #'usqLong'>
	<var: 'vAlpha0' type: #'usqLong'>
	<var: 'vAlpha1' type: #'usqLong'>
	self
		primitive: 'primBlendFillOnlyWP'
		parameters: #(SmallInteger SmallInteger SmallInteger SmallInteger).

	clippingSpecL := 0.
	clippingSpecR := targetWidth-1.
	antiAliasedClippedLeftPixel := targetWidth."targetWidth means effectively no AA for clipping"
	antiAliasedClippedRightPixel := targetWidth."targetWidth means effectively no AA for clipping"
	clippingSpecIndex := t * 2 + 1 - 1.
	mustResetColor := false.
	opaqueFillColorWord := 0.
	targetAssumedOpaque ifTrue: [
		fillA = 1.0 ifTrue: [
			auxR := (fillR + 0.5) asInteger bitShift: 16.
			auxG := (fillG + 0.5) asInteger bitShift: 8.
			auxB := (fillB + 0.5) asInteger.
			opaqueFillColorWord := ((16rFF000000 bitOr: auxR) bitOr: auxG) bitOr: auxB ]].
	lastSegmentIndex := -1.
	"Constants for the bulk interior blend below, hoisted out of the per-pixel loops.
	They mirror blendFillOnlyWPAt: called with antiAliasAlphaByte 127 on an opaque
	target word (the targetAssumedOpaque contract)."
	bulkAlpha := 16r7F * (1.0 / 127.0).
	bulkAlpha := bulkAlpha * fillA.
	bulkUnAlpha := 1.0 - bulkAlpha.
	bulkTargetAlpha := 16rFF000000 * ( 1.0 / (255.0 * 256 * 256 * 256)).
	bulkResultAlpha := bulkAlpha + (bulkUnAlpha * bulkTargetAlpha).
	bulkFR := bulkAlpha * fillR.
	bulkFG := bulkAlpha * fillG.
	bulkFB := bulkAlpha * fillB.

	t to: b do: [ :displayY |
		clippingSpec ifNotNil: [
			clippingSpecL := clippingSpec at: clippingSpecIndex.
			clippingSpecR := clippingSpec at: clippingSpecIndex+1.
			antiAliasedClippedLeftPixel := clippingSpecL >= l ifTrue: [clippingSpecL] ifFalse: [targetWidth].
			antiAliasedClippedRightPixel := clippingSpecR <= r ifTrue: [clippingSpecR] ifFalse:  [targetWidth]].
		edgesUpToThisPixel := 0.
		"Dirty-span journal, WINDING-SAFE form (read-only: initializePath resets it;
		the engine may blend the same stamped data more than once). A row with no
		stamps has no edges, so winding stays zero: skip it. A stamped row may only
		clamp its LEFT side (no edges left of the leftmost stamp, and edges left of
		the clip are stamped AT clipLeft) -- the right side must sweep to r: when
		the path is clipped, edges beyond clipRight are never stamped, so the fill's
		winding stays open past the rightmost stamp and the region up to the clip
		edge is inside the fill with no stamps at all. Clamping it away was the
		flight-corruption bug of 2026-07-05."
		rowL := dirtyLeftJ at: displayY.
		rowR := dirtyRightJ at: displayY.
		rowR >= 0 ifTrue: [ rowR := r ].
		rowL < l ifTrue: [ rowL := l ].
		pixelIndex := displayY * targetWidth + rowL.
		displayX := rowL.
		[ displayX <= rowR ] whileTrue: [

			affectedBitsIndex := pixelIndex>>4.
			lastSegmentIndex = affectedBitsIndex ifFalse: [
				alphasOrEdgeCountsInThisSegment := (affectedBits at: affectedBitsIndex) = 1.
				lastSegmentIndex := affectedBitsIndex.
				alphasOrEdgeCountsInThisSegment ifTrue: [
					affectedBits at: affectedBitsIndex put: 0 ]].
			segmentLength := affectedBitsIndex+1 << 4 - pixelIndex.
						runSafe := false.
			(alphasOrEdgeCountsInThisSegment not and: [edgesUpToThisPixel ~= 0]) ifTrue: [
				(targetAssumedOpaque and: [opaqueFillColorWord ~= 0 or: [bulkResultAlpha = 1.0 and: [bulkTargetAlpha = 1.0]]]) ifTrue: [
					runLen := segmentLength min: rowR - displayX + 1.
					(displayX >= clippingSpecL and: [displayX + runLen - 1 <= clippingSpecR]) ifTrue: [
						((displayX + runLen < antiAliasedClippedLeftPixel or: [displayX > (antiAliasedClippedLeftPixel + 1)]) and: [
						  displayX + runLen < antiAliasedClippedRightPixel or: [displayX > (antiAliasedClippedRightPixel + 1)]]) ifTrue: [
							runSafe := true ]]]].
			runSafe ifTrue: [
				"V7: extend the run across following clear segments, bounded by the
				same clip / AA-window constraints that licensed the run start (see the
				runSafe test above; the bounds below are that predicate solved for
				runLen). Longer runs amortize the per-segment re-establishment and let
				the store loops below run at full vector throughput. Extension is only
				possible when runLen filled its whole segment, so pixelIndex + runLen
				is 16-aligned; clearAffectedSpanFrom:max: answers whole clear segments
				only, so runLen never exceeds maxRun."
				maxRun := rowR - displayX + 1.
				clippingSpecR - displayX + 1 < maxRun ifTrue: [ maxRun := clippingSpecR - displayX + 1 ].
				displayX <= (antiAliasedClippedLeftPixel + 1) ifTrue: [
					aux1 := antiAliasedClippedLeftPixel - displayX - 1.
					aux1 < maxRun ifTrue: [ maxRun := aux1 ]].
				displayX <= (antiAliasedClippedRightPixel + 1) ifTrue: [
					aux1 := antiAliasedClippedRightPixel - displayX - 1.
					aux1 < maxRun ifTrue: [ maxRun := aux1 ]].
				runLen < maxRun ifTrue: [
					aux1 := self clearAffectedSpanFrom: (pixelIndex + runLen) >> 4 max: maxRun - runLen >> 4.
					runLen := runLen + (aux1 << 4) ].
				"Clean interior run: no stamps in this segment, strictly inside the shape,
				no clipping effects. No per-pixel byte checks are needed at all.
				targetBits and morphIds are written in separate loops: single-array
				constant-store loops vectorize; the interleaved form cannot (the
				compiler must assume the two pointers alias)."
				opaqueFillColorWord ~= 0
					ifTrue: [
						0 to: runLen - 1 do: [ :idx2 |
							targetBits at: pixelIndex + idx2 put: opaqueFillColorWord ].
						0 to: runLen - 1 do: [ :idx2 |
							morphIds at: pixelIndex + idx2 put: currentMorphId ].
						pixelIndex := pixelIndex + runLen ]
					ifFalse: [
						"Same math as blendFillOnlyWPAt: with alpha byte 127 over an opaque
						target, constants hoisted. Only taken when the hoisted divisors are
						exactly 1.0, so results stay bit-identical without the divides."
						0 to: runLen - 1 do: [ :idx2 |
							targetWord2 := targetBits at: pixelIndex + idx2.
							bulkR := bulkFR + (bulkUnAlpha * ((targetWord2 bitAnd: 16rFF0000) bitShift: -16)).
							bulkG := bulkFG + (bulkUnAlpha * ((targetWord2 bitAnd: 16rFF00) bitShift: -8)).
							bulkB := bulkFB + (bulkUnAlpha * (targetWord2 bitAnd: 16rFF)).
							targetWord2 := ((16rFF000000 bitOr: ((bulkR + 0.5) asInteger bitShift: 16)) bitOr: ((bulkG + 0.5) asInteger bitShift: 8)) bitOr: (bulkB + 0.5) asInteger.
							targetBits at: pixelIndex + idx2 put: targetWord2 ].
						0 to: runLen - 1 do: [ :idx2 |
							morphIds at: pixelIndex + idx2 put: currentMorphId ].
						pixelIndex := pixelIndex + runLen ].
				displayX := displayX + runLen ]
			ifFalse: [
			alphasOrEdgeCountsInThisSegment  | (edgesUpToThisPixel ~= 0) ifTrue: [
				aux1 := rowR-displayX+1.
				toDoLimit := segmentLength min: aux1.
				tightDone := false.
				"Pure-alpha full segment (the text/coverage case): no edge counts,
				so the winding state cannot change; outside the shape; whole segment
				inside the clip window and clear of the four anti-aliased clip
				columns. Gang-load the sixteen edge counts and coverage bytes, bulk
				clear the mask, and blend only the covered pixels -- same pixels,
				same order, same math as the general loop below: bit-identical."
				(alphasOrEdgeCountsInThisSegment
				 and: [edgesUpToThisPixel = 0
				 and: [toDoLimit = 16
				 and: [displayX >= clippingSpecL
				 and: [displayX + 15 <= clippingSpecR
				 and: [(antiAliasedClippedLeftPixel + 1 < displayX or: [antiAliasedClippedLeftPixel > (displayX + 15)])
				 and: [antiAliasedClippedRightPixel < displayX or: [antiAliasedClippedRightPixel - 1 > (displayX + 15)]]]]]]]) ifTrue: [
					self cCode: 'memcpy(&vEdges0, edgeCountsWP + pixelIndex, 8)' inSmalltalk: [vEdges0 := 1].
					self cCode: 'memcpy(&vEdges1, edgeCountsWP + pixelIndex + 8, 8)' inSmalltalk: [vEdges1 := 1].
					(vEdges0 bitOr: vEdges1) = 0 ifTrue: [
						self cCode: 'memcpy(&vAlpha0, alphaMaskWP + pixelIndex, 8)' inSmalltalk: [vAlpha0 := 0].
						self cCode: 'memcpy(&vAlpha1, alphaMaskWP + pixelIndex + 8, 8)' inSmalltalk: [vAlpha1 := 0].
						(vAlpha0 bitOr: vAlpha1) = 0 ifFalse: [
							self cCode: 'memset(alphaMaskWP + pixelIndex, 0, 16)' inSmalltalk: [].
							0 to: 7 do: [ :lane |
								strokeAntiAliasAlphaBits := (vAlpha0 >> (lane * 8)) bitAnd: 16rFF.
								strokeAntiAliasAlphaBits = 0 ifFalse: [
									self blendFillOnlyWPAt: pixelIndex + lane antiAliasAlphaByte: strokeAntiAliasAlphaBits ]].
							0 to: 7 do: [ :lane |
								strokeAntiAliasAlphaBits := (vAlpha1 >> (lane * 8)) bitAnd: 16rFF.
								strokeAntiAliasAlphaBits = 0 ifFalse: [
									self blendFillOnlyWPAt: pixelIndex + 8 + lane antiAliasAlphaByte: strokeAntiAliasAlphaBits ]]].
						displayX := displayX + 16.
						pixelIndex := pixelIndex + 16.
						tightDone := true ]].
				tightDone ifFalse: [
				1 to: toDoLimit do: [ :idx |

					strokeAntiAliasAlphaBits := 0.
					alphasOrEdgeCountsInThisSegment ifTrue: [
						edgesThisPixel := edgeCountsWP at: pixelIndex.
						edgesThisPixel = 0 ifFalse: [
							edgeCountsWP at: pixelIndex put: 0.
							self cCode: nil inSmalltalk: [
								"Not needed in C or OpenCL, just use a wraparound 8 bit type, such uint8_t"
								edgesThisPixel > 127 ifTrue: [ edgesThisPixel := edgesThisPixel - 256 ]].
							edgesUpToThisPixel := edgesUpToThisPixel + edgesThisPixel ].
							strokeAntiAliasAlphaBits := alphaMaskWP at: pixelIndex.
							strokeAntiAliasAlphaBits = 16r00 ifFalse: [ alphaMaskWP at: pixelIndex put: 0 ]].

					(displayX >= clippingSpecL and: [ displayX <= clippingSpecR ]) ifTrue: [
						(displayX = antiAliasedClippedLeftPixel or: [ displayX = antiAliasedClippedRightPixel])
							ifTrue: [
								realFillAlpha := fillA. fillA := fillA * 0.25.
								realOpaqueFillColorWord := opaqueFillColorWord. opaqueFillColorWord := 0. mustResetColor := true ]
							ifFalse: [
								(displayX-1 = antiAliasedClippedLeftPixel or: [ displayX+1 = antiAliasedClippedRightPixel]) ifTrue: [
									realFillAlpha := fillA. fillA := fillA * 0.75.
									realOpaqueFillColorWord := opaqueFillColorWord. opaqueFillColorWord:= 0. mustResetColor := true ]].

						edgesUpToThisPixel = 0
							ifFalse: [			"Inside the shape"
								(opaqueFillColorWord ~= 0 and: [strokeAntiAliasAlphaBits = 16r00])
									ifTrue: [	"Optimize common case: opaque fill, inside fill area, no anti aliasing, no clipping at this point."
										targetBits at: pixelIndex put: opaqueFillColorWord.
										morphIds at: pixelIndex put: currentMorphId ]
									ifFalse: [	"Inside the shape. Turn stroke anti aliasing into fill anti aliasing."
										self blendFillOnlyWPAt: pixelIndex antiAliasAlphaByte: 16r7F - strokeAntiAliasAlphaBits ]]
							ifTrue: [			"Still in the anti aliasing area, but outside the shape, strictly speaking."
								strokeAntiAliasAlphaBits = 16r00 ifFalse: [
									self blendFillOnlyWPAt: pixelIndex antiAliasAlphaByte: strokeAntiAliasAlphaBits ]].

							mustResetColor ifTrue: [
								fillA := realFillAlpha. opaqueFillColorWord := realOpaqueFillColorWord. mustResetColor := false ]].
					displayX := displayX + 1.
					pixelIndex := pixelIndex + 1 ]]]
			ifFalse: [				"All alphas and edgeCounts are zero in this segment of length delta"
				displayX := displayX + segmentLength.
				pixelIndex := pixelIndex + segmentLength.
				"Hop over any following clear segments, eight segment flags per
				compare. Only taken outside the shape: clear segments carry no
				edges, so the winding state cannot change across them."
				displayX <= rowR ifTrue: [
					aux1 := self clearAffectedSpanFrom: pixelIndex >> 4 max: (rowR - displayX >> 4) + 1.
					aux1 > 0 ifTrue: [
						aux1 := aux1 << 4.
						aux1 > (rowR - displayX + 1) ifTrue: [ aux1 := rowR - displayX + 1 ].
						displayX := displayX + aux1.
						pixelIndex := pixelIndex + aux1 ]]] ] ].

		clippingSpecIndex := clippingSpecIndex + 2 ].! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - blend stroke and fill' stamp: 'ML 7/4/2026 20:00'!
blendStrokeOnlyWPLeft: l top: t right: r bottom: b
	"Blends stroke color over background.
	WP: Whole pixel anti aliasing.
	If targetAssumedOpaque is false, target translucency is computed correctly.
	If targetAssumedOpaque is true (and target translucency is actually 255 on input), an optimization is made and target translucency is set to 255.
	For blending, alphas are in [0 .. 1.0] and R, G, B color components are in [0 .. 255]"
	| pixelIndex strokeAntiAliasAlphaBits auxR auxG auxB clippingSpecL clippingSpecR clippingSpecIndex antiAliasedClippedLeftPixel antiAliasedClippedRightPixel mustResetColor realStrokeAlpha opaqueStrokeColorWord realOpaqueStrokeColorWord displayX affectedBitsIndex segmentLength alphasOrEdgeCountsInThisSegment lastSegmentIndex aux1 rowL rowR |
	<var: 'strokeAntiAliasAlphaBits' type: #'uint8_t'>
	<var: 'opaqueStrokeColorWord' type: #'uint32_t'>
	<var: 'realOpaqueStrokeColorWord' type: #'uint32_t'>
	<var: 'auxR' type: #'uint32_t'>
	<var: 'auxG' type: #'uint32_t'>
	<var: 'auxB' type: #'uint32_t'>
	self
		primitive: 'primBlendStrokeOnlyWP'
		parameters: #(SmallInteger SmallInteger SmallInteger SmallInteger).
	clippingSpecL := 0.
	clippingSpecR := targetWidth-1.
	antiAliasedClippedLeftPixel := targetWidth."targetWidth means effectively no AA for clipping"
	antiAliasedClippedRightPixel := targetWidth."targetWidth means effectively no AA for clipping"
	clippingSpecIndex := t * 2 + 1 - 1.
	mustResetColor := false.
	opaqueStrokeColorWord := 0.
	targetAssumedOpaque ifTrue: [
		strokeA = 1.0 ifTrue: [
			auxR := (strokeR + 0.5) asInteger bitShift: 16.
			auxG := (strokeG + 0.5) asInteger bitShift: 8.
			auxB := (strokeB + 0.5) asInteger.
			opaqueStrokeColorWord := ((16rFF000000 bitOr: auxR) bitOr: auxG) bitOr: auxB ]].
	lastSegmentIndex := -1.
	t to: b do: [ :displayY |
		clippingSpec ifNotNil: [
			clippingSpecL := clippingSpec at: clippingSpecIndex.
			clippingSpecR := clippingSpec at: clippingSpecIndex+1.
			antiAliasedClippedLeftPixel := clippingSpecL >= l ifTrue: [clippingSpecL] ifFalse: [targetWidth].
			antiAliasedClippedRightPixel := clippingSpecR <= r ifTrue: [clippingSpecR] ifFalse:  [targetWidth]].
		"Dirty-span journal: clamp the sweep to what the stampers touched on this
		row (read-only: initializePath resets it -- the engine may blend the same
		stamped data more than once). Pixels outside the dirty span hold no stamps, so
		stroke alpha is zero and fill winding cannot change there (edges are
		stamps; a closed path's crossings balance to zero after the last one)."
		rowL := dirtyLeftJ at: displayY.
		rowR := dirtyRightJ at: displayY.
		rowL < l ifTrue: [ rowL := l ].
		rowR > r ifTrue: [ rowR := r ].
		pixelIndex := displayY * targetWidth + rowL.
		displayX := rowL.
		[ displayX <= rowR ] whileTrue: [

			affectedBitsIndex := pixelIndex>>4.
			lastSegmentIndex = affectedBitsIndex ifFalse: [
				alphasOrEdgeCountsInThisSegment := (affectedBits at: affectedBitsIndex) = 1.
				lastSegmentIndex := affectedBitsIndex.
				alphasOrEdgeCountsInThisSegment ifTrue: [
					affectedBits at: affectedBitsIndex put: 0 ]].
			segmentLength := affectedBitsIndex+1 << 4 - pixelIndex.
			alphasOrEdgeCountsInThisSegment ifTrue: [
				aux1 := rowR-displayX+1.
				1 to: (segmentLength min: aux1) do: [ :idx |

					strokeAntiAliasAlphaBits := alphaMaskWP at: pixelIndex.
					strokeAntiAliasAlphaBits = 16r00 ifFalse: [

						"In the stroke"
						alphaMaskWP at: pixelIndex put: 0.

						(displayX >= clippingSpecL and: [ displayX <= clippingSpecR ]) ifTrue: [
							(displayX = antiAliasedClippedLeftPixel or: [ displayX = antiAliasedClippedRightPixel])
								ifTrue: [
									realStrokeAlpha := strokeA. strokeA := strokeA * 0.25.
									realOpaqueStrokeColorWord := opaqueStrokeColorWord. opaqueStrokeColorWord := 0. mustResetColor := true ]
								ifFalse: [
									(displayX-1 = antiAliasedClippedLeftPixel or: [ displayX+1 = antiAliasedClippedRightPixel]) ifTrue: [
										realStrokeAlpha := strokeA. strokeA := strokeA * 0.75.
										realOpaqueStrokeColorWord := opaqueStrokeColorWord. opaqueStrokeColorWord := 0. mustResetColor := true ]].
							(opaqueStrokeColorWord ~=0 and: [strokeAntiAliasAlphaBits = 16r7F])
								ifTrue: [ "Optimize inner part of a wide stroke: Fully opaque stroke (and target), no anti aliasing, no clipping at this point."
									targetBits at: pixelIndex put: opaqueStrokeColorWord.
									morphIds at: pixelIndex put: currentMorphId ]
								ifFalse: [ "General case."
									self blendStrokeOnlyWPAt: pixelIndex antiAliasAlphaByte: strokeAntiAliasAlphaBits ].
								mustResetColor ifTrue: [
									strokeA := realStrokeAlpha. opaqueStrokeColorWord := realOpaqueStrokeColorWord. mustResetColor := false ]]].
					displayX := displayX + 1.
					pixelIndex := pixelIndex + 1 ]]
			ifFalse: [
				"All alphas and edgeCounts are zero in this segment of length delta"
				displayX := displayX + segmentLength.
				pixelIndex := pixelIndex + segmentLength.
				"Hop over any following clear segments, eight segment flags per
				compare. Strokes have no winding state, so this is always safe."
				displayX <= rowR ifTrue: [
					aux1 := self clearAffectedSpanFrom: pixelIndex >> 4 max: (rowR - displayX >> 4) + 1.
					aux1 > 0 ifTrue: [
						aux1 := aux1 << 4.
						aux1 > (rowR - displayX + 1) ifTrue: [ aux1 := rowR - displayX + 1 ].
						displayX := displayX + aux1.
						pixelIndex := pixelIndex + aux1 ]]]].

		clippingSpecIndex := clippingSpecIndex + 2 ].! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - blend stroke and fill' stamp: 'ML 7/4/2026 20:00'!
blendStrokeAndFillWPLeft: l top: t right: r bottom: b
	"Blends stroke color and fill color over background.
	Do an appropriate (anti aliased) gradient between stoke color and fill color (or pick just stroke or just fill). Blend this over background.
	WP: Whole pixel anti aliasing.
	If targetAssumedOpaque is false, target translucency is computed correctly.
	If targetAssumedOpaque is true (and target translucency is actually 255 on input), an optimization is made and target translucency is set to 255.
	For blending, alphas are in [0 .. 1.0] and R, G, B color components are in [0 .. 255]"
	| pixelIndex edgesUpToThisPixel edgesThisPixel strokeAntiAliasAlphaBits clippingSpecL clippingSpecR clippingSpecIndex antiAliasedClippedLeftPixel antiAliasedClippedRightPixel mustResetColor realStrokeAlpha realFillAlpha opaqueStrokeColorWord opaqueFillColorWord realOpaqueStrokeColorWord realOpaqueFillColorWord auxR auxG auxB displayX affectedBitsIndex segmentLength alphasOrEdgeCountsInThisSegment lastSegmentIndex aux1 toDoLimit tightDone runLen runSafe maxRun targetWord2 bulkAlpha bulkUnAlpha bulkTargetAlpha bulkResultAlpha bulkFR bulkFG bulkFB bulkR bulkG bulkB vEdges0 vEdges1 vAlpha0 vAlpha1 rowL rowR |
	<var: 'targetWord2' type: #'uint32_t'>
	<var: 'bulkAlpha' type: #float>
	<var: 'bulkUnAlpha' type: #float>
	<var: 'bulkTargetAlpha' type: #float>
	<var: 'bulkResultAlpha' type: #float>
	<var: 'bulkFR' type: #float>
	<var: 'bulkFG' type: #float>
	<var: 'bulkFB' type: #float>
	<var: 'bulkR' type: #float>
	<var: 'bulkG' type: #float>
	<var: 'bulkB' type: #float>
	<var: 'edgesThisPixel' type: #'uint8_t'>
	<var: 'edgesUpToThisPixel' type: #'uint8_t'>
	<var: 'strokeAntiAliasAlphaBits' type: #'uint8_t'>
	<var: 'opaqueStrokeColorWord' type: #'uint32_t'>
	<var: 'realOpaqueStrokeColorWord' type: #'uint32_t'>
	<var: 'opaqueFillColorWord' type: #'uint32_t'>
	<var: 'realOpaqueFillColorWord' type: #'uint32_t'>
	<var: 'auxR' type: #'uint32_t'>
	<var: 'auxG' type: #'uint32_t'>
	<var: 'auxB' type: #'uint32_t'>
	<var: 'vEdges0' type: #'usqLong'>
	<var: 'vEdges1' type: #'usqLong'>
	<var: 'vAlpha0' type: #'usqLong'>
	<var: 'vAlpha1' type: #'usqLong'>
	self
		primitive: 'primBlendStrokeAndFillWP'
		parameters: #(SmallInteger SmallInteger SmallInteger SmallInteger).

	clippingSpecL := 0.
	clippingSpecR := targetWidth-1.
	antiAliasedClippedLeftPixel := targetWidth."targetWidth means effectively no AA for clipping"
	antiAliasedClippedRightPixel := targetWidth."targetWidth means effectively no AA for clipping"
	clippingSpecIndex := t * 2 + 1 - 1.
	mustResetColor := false.
	opaqueStrokeColorWord := 0.
	opaqueFillColorWord := 0.
	targetAssumedOpaque ifTrue: [
		strokeA * fillA = 1.0 ifTrue: [
			auxR := (strokeR + 0.5) asInteger bitShift: 16.
			auxG := (strokeG + 0.5) asInteger bitShift: 8.
			auxB := (strokeB + 0.5) asInteger.
			opaqueStrokeColorWord := ((16rFF000000 bitOr: auxR) bitOr: auxG) bitOr: auxB.
			auxR := (fillR + 0.5) asInteger bitShift: 16.
			auxG := (fillG + 0.5) asInteger bitShift: 8.
			auxB := (fillB + 0.5) asInteger.
			opaqueFillColorWord := ((16rFF000000 bitOr: auxR) bitOr: auxG) bitOr: auxB ]].
	lastSegmentIndex := -1.
	"Constants for the bulk interior blend below, hoisted out of the per-pixel loops.
	They mirror blendFillOnlyWPAt: called with antiAliasAlphaByte 127 on an opaque
	target word (the targetAssumedOpaque contract)."
	bulkAlpha := 16r7F * (1.0 / 127.0).
	bulkAlpha := bulkAlpha * fillA.
	bulkUnAlpha := 1.0 - bulkAlpha.
	bulkTargetAlpha := 16rFF000000 * ( 1.0 / (255.0 * 256 * 256 * 256)).
	bulkResultAlpha := bulkAlpha + (bulkUnAlpha * bulkTargetAlpha).
	bulkFR := bulkAlpha * fillR.
	bulkFG := bulkAlpha * fillG.
	bulkFB := bulkAlpha * fillB.

	t to: b do: [ :displayY |
		clippingSpec ifNotNil: [
			clippingSpecL := clippingSpec at: clippingSpecIndex.
			clippingSpecR := clippingSpec at: clippingSpecIndex+1.
			antiAliasedClippedLeftPixel := clippingSpecL >= l ifTrue: [clippingSpecL] ifFalse: [targetWidth].
			antiAliasedClippedRightPixel := clippingSpecR <= r ifTrue: [clippingSpecR] ifFalse:  [targetWidth]].
		edgesUpToThisPixel := 0.
		"Dirty-span journal, WINDING-SAFE form (read-only: initializePath resets it;
		the engine may blend the same stamped data more than once). A row with no
		stamps has no edges, so winding stays zero: skip it. A stamped row may only
		clamp its LEFT side (no edges left of the leftmost stamp, and edges left of
		the clip are stamped AT clipLeft) -- the right side must sweep to r: when
		the path is clipped, edges beyond clipRight are never stamped, so the fill's
		winding stays open past the rightmost stamp and the region up to the clip
		edge is inside the fill with no stamps at all. Clamping it away was the
		flight-corruption bug of 2026-07-05."
		rowL := dirtyLeftJ at: displayY.
		rowR := dirtyRightJ at: displayY.
		rowR >= 0 ifTrue: [ rowR := r ].
		rowL < l ifTrue: [ rowL := l ].
		pixelIndex := displayY * targetWidth + rowL.
		displayX := rowL.
		[ displayX <= rowR ] whileTrue: [

			affectedBitsIndex := pixelIndex>>4.
			lastSegmentIndex = affectedBitsIndex ifFalse: [
				alphasOrEdgeCountsInThisSegment := (affectedBits at: affectedBitsIndex) = 1.
				lastSegmentIndex := affectedBitsIndex.
				alphasOrEdgeCountsInThisSegment ifTrue: [
					affectedBits at: affectedBitsIndex put: 0 ]].
			segmentLength := affectedBitsIndex+1 << 4 - pixelIndex.
						runSafe := false.
			(alphasOrEdgeCountsInThisSegment not and: [edgesUpToThisPixel ~= 0]) ifTrue: [
				(targetAssumedOpaque and: [opaqueFillColorWord ~= 0 or: [bulkResultAlpha = 1.0 and: [bulkTargetAlpha = 1.0]]]) ifTrue: [
					runLen := segmentLength min: rowR - displayX + 1.
					(displayX >= clippingSpecL and: [displayX + runLen - 1 <= clippingSpecR]) ifTrue: [
						((displayX + runLen < antiAliasedClippedLeftPixel or: [displayX > (antiAliasedClippedLeftPixel + 1)]) and: [
						  displayX + runLen < antiAliasedClippedRightPixel or: [displayX > (antiAliasedClippedRightPixel + 1)]]) ifTrue: [
							runSafe := true ]]]].
			runSafe ifTrue: [
				"V7: extend the run across following clear segments, bounded by the
				same clip / AA-window constraints that licensed the run start (see the
				runSafe test above; the bounds below are that predicate solved for
				runLen). Longer runs amortize the per-segment re-establishment and let
				the store loops below run at full vector throughput. Extension is only
				possible when runLen filled its whole segment, so pixelIndex + runLen
				is 16-aligned; clearAffectedSpanFrom:max: answers whole clear segments
				only, so runLen never exceeds maxRun."
				maxRun := rowR - displayX + 1.
				clippingSpecR - displayX + 1 < maxRun ifTrue: [ maxRun := clippingSpecR - displayX + 1 ].
				displayX <= (antiAliasedClippedLeftPixel + 1) ifTrue: [
					aux1 := antiAliasedClippedLeftPixel - displayX - 1.
					aux1 < maxRun ifTrue: [ maxRun := aux1 ]].
				displayX <= (antiAliasedClippedRightPixel + 1) ifTrue: [
					aux1 := antiAliasedClippedRightPixel - displayX - 1.
					aux1 < maxRun ifTrue: [ maxRun := aux1 ]].
				runLen < maxRun ifTrue: [
					aux1 := self clearAffectedSpanFrom: (pixelIndex + runLen) >> 4 max: maxRun - runLen >> 4.
					runLen := runLen + (aux1 << 4) ].
				"Clean interior run: no stamps in this segment, strictly inside the shape,
				no clipping effects. No per-pixel byte checks are needed at all.
				targetBits and morphIds are written in separate loops: single-array
				constant-store loops vectorize; the interleaved form cannot (the
				compiler must assume the two pointers alias)."
				opaqueFillColorWord ~= 0
					ifTrue: [
						0 to: runLen - 1 do: [ :idx2 |
							targetBits at: pixelIndex + idx2 put: opaqueFillColorWord ].
						0 to: runLen - 1 do: [ :idx2 |
							morphIds at: pixelIndex + idx2 put: currentMorphId ].
						pixelIndex := pixelIndex + runLen ]
					ifFalse: [
						"Same math as blendFillOnlyWPAt: with alpha byte 127 over an opaque
						target, constants hoisted. Only taken when the hoisted divisors are
						exactly 1.0, so results stay bit-identical without the divides."
						0 to: runLen - 1 do: [ :idx2 |
							targetWord2 := targetBits at: pixelIndex + idx2.
							bulkR := bulkFR + (bulkUnAlpha * ((targetWord2 bitAnd: 16rFF0000) bitShift: -16)).
							bulkG := bulkFG + (bulkUnAlpha * ((targetWord2 bitAnd: 16rFF00) bitShift: -8)).
							bulkB := bulkFB + (bulkUnAlpha * (targetWord2 bitAnd: 16rFF)).
							targetWord2 := ((16rFF000000 bitOr: ((bulkR + 0.5) asInteger bitShift: 16)) bitOr: ((bulkG + 0.5) asInteger bitShift: 8)) bitOr: (bulkB + 0.5) asInteger.
							targetBits at: pixelIndex + idx2 put: targetWord2 ].
						0 to: runLen - 1 do: [ :idx2 |
							morphIds at: pixelIndex + idx2 put: currentMorphId ].
						pixelIndex := pixelIndex + runLen ].
				displayX := displayX + runLen ]
			ifFalse: [
			alphasOrEdgeCountsInThisSegment  | (edgesUpToThisPixel ~= 0) ifTrue: [
				aux1 := rowR-displayX+1.
				toDoLimit := segmentLength min: aux1.
				tightDone := false.
				"Pure-alpha full segment (stamped stroke coverage, e.g. glyph runs in a
				stroke-and-fill path): no edge counts, so the winding state cannot
				change; outside the shape; whole segment inside the clip window and
				clear of the four anti-aliased clip columns. Gang-load the sixteen
				edge counts and coverage bytes, bulk clear the mask, and handle only
				the covered pixels -- same pixels, same order, same decision tree as
				the general loop below: bit-identical."
				(alphasOrEdgeCountsInThisSegment
				 and: [edgesUpToThisPixel = 0
				 and: [toDoLimit = 16
				 and: [displayX >= clippingSpecL
				 and: [displayX + 15 <= clippingSpecR
				 and: [(antiAliasedClippedLeftPixel + 1 < displayX or: [antiAliasedClippedLeftPixel > (displayX + 15)])
				 and: [antiAliasedClippedRightPixel < displayX or: [antiAliasedClippedRightPixel - 1 > (displayX + 15)]]]]]]]) ifTrue: [
					self cCode: 'memcpy(&vEdges0, edgeCountsWP + pixelIndex, 8)' inSmalltalk: [vEdges0 := 1].
					self cCode: 'memcpy(&vEdges1, edgeCountsWP + pixelIndex + 8, 8)' inSmalltalk: [vEdges1 := 1].
					(vEdges0 bitOr: vEdges1) = 0 ifTrue: [
						self cCode: 'memcpy(&vAlpha0, alphaMaskWP + pixelIndex, 8)' inSmalltalk: [vAlpha0 := 0].
						self cCode: 'memcpy(&vAlpha1, alphaMaskWP + pixelIndex + 8, 8)' inSmalltalk: [vAlpha1 := 0].
						(vAlpha0 bitOr: vAlpha1) = 0 ifFalse: [
							self cCode: 'memset(alphaMaskWP + pixelIndex, 0, 16)' inSmalltalk: [].
							0 to: 7 do: [ :lane |
								strokeAntiAliasAlphaBits := (vAlpha0 >> (lane * 8)) bitAnd: 16rFF.
								strokeAntiAliasAlphaBits = 0 ifFalse: [
									(opaqueStrokeColorWord ~= 0 and: [strokeAntiAliasAlphaBits = 16r7F])
										ifTrue: [
											targetBits at: pixelIndex + lane put: opaqueStrokeColorWord.
											morphIds at: pixelIndex + lane put: currentMorphId ]
										ifFalse: [
											self blendStrokeOnlyWPAt: pixelIndex + lane antiAliasAlphaByte: strokeAntiAliasAlphaBits ]]].
							0 to: 7 do: [ :lane |
								strokeAntiAliasAlphaBits := (vAlpha1 >> (lane * 8)) bitAnd: 16rFF.
								strokeAntiAliasAlphaBits = 0 ifFalse: [
									(opaqueStrokeColorWord ~= 0 and: [strokeAntiAliasAlphaBits = 16r7F])
										ifTrue: [
											targetBits at: pixelIndex + 8 + lane put: opaqueStrokeColorWord.
											morphIds at: pixelIndex + 8 + lane put: currentMorphId ]
										ifFalse: [
											self blendStrokeOnlyWPAt: pixelIndex + 8 + lane antiAliasAlphaByte: strokeAntiAliasAlphaBits ]]]].
						displayX := displayX + 16.
						pixelIndex := pixelIndex + 16.
						tightDone := true ]].
				tightDone ifFalse: [
				1 to: toDoLimit do: [ :idx |

					strokeAntiAliasAlphaBits := 0.
					alphasOrEdgeCountsInThisSegment ifTrue: [
						edgesThisPixel := edgeCountsWP at: pixelIndex.
						edgesThisPixel = 0 ifFalse: [
							edgeCountsWP at: pixelIndex put: 0.
							self cCode: nil inSmalltalk: [
								"Not needed in C or OpenCL, just use a wraparound 8 bit type, such uint8_t"
								edgesThisPixel > 127 ifTrue: [ edgesThisPixel := edgesThisPixel - 256 ]].
							edgesUpToThisPixel := edgesUpToThisPixel + edgesThisPixel ].
							strokeAntiAliasAlphaBits := alphaMaskWP at: pixelIndex.
							strokeAntiAliasAlphaBits = 16r00 ifFalse: [ alphaMaskWP at: pixelIndex put: 0 ]].

					(displayX >= clippingSpecL and: [ displayX <= clippingSpecR ]) ifTrue: [
						(displayX = antiAliasedClippedLeftPixel or: [ displayX = antiAliasedClippedRightPixel])
							ifTrue: [
								realStrokeAlpha := strokeA. strokeA := strokeA * 0.25. realFillAlpha := fillA. fillA := fillA * 0.25.
								realOpaqueStrokeColorWord := opaqueStrokeColorWord. opaqueStrokeColorWord := 0.
								realOpaqueFillColorWord := opaqueFillColorWord. opaqueFillColorWord := 0. mustResetColor := true ]
							ifFalse: [
								(displayX-1 = antiAliasedClippedLeftPixel or: [ displayX+1 = antiAliasedClippedRightPixel]) ifTrue: [
									realStrokeAlpha := strokeA. strokeA := strokeA * 0.75. realFillAlpha := fillA. fillA := fillA * 0.75.
									realOpaqueStrokeColorWord := opaqueStrokeColorWord. opaqueStrokeColorWord := 0.
									realOpaqueFillColorWord := opaqueFillColorWord. opaqueFillColorWord := 0. mustResetColor := true ]].

						strokeAntiAliasAlphaBits = 16r00
							ifTrue: [ 		"Not in the stroke at all. Either fully in the fill, or outside the shape (pixel is unaffected)."
								edgesUpToThisPixel ~= 0
									ifTrue: [
										"Fully inside the fill, far from anti aliasing."
										opaqueFillColorWord ~= 0
											ifTrue: [
												"Fill color is opaque. Target is too. Just overwrite with fill color."
												targetBits at: pixelIndex put: opaqueFillColorWord.
												morphIds at: pixelIndex put: currentMorphId ]
											ifFalse: [
												"Translucent color or target. Do proper blend of fill over target."
												self blendFillOnlyWPAt: pixelIndex antiAliasAlphaByte: 127 ]]]
							ifFalse: [		"At least partially in the stroke."
								strokeAntiAliasAlphaBits = 16r7F
									ifTrue: [
										"Fully inside the stroke, far from anti aliasing."
										opaqueStrokeColorWord ~= 0
											ifTrue: [
												"Stroke color is opaque. Target is too. Just overwrite with stroke color."
												targetBits at: pixelIndex put: opaqueStrokeColorWord.
												morphIds at: pixelIndex put: currentMorphId ]
											ifFalse: [
												"Translucent color or target. Do proper blend of stroke over target."
												self blendStrokeOnlyWPAt: pixelIndex antiAliasAlphaByte: 127 ]]
									ifFalse: [
										"In an anti aliased part of the stroke. Either blend stroke over background, or pre-mix stroke and fill."
										edgesUpToThisPixel ~= 0
											ifTrue: [
												"Inside the shape. Blend stroke and fill, blend result over target."
												self blendStrokeAndFillWPAt: pixelIndex antiAliasAlphaByte: strokeAntiAliasAlphaBits ]
											ifFalse: [
												"In the outer anti aliasing area of the stroke. Blend stroke over background."
												self blendStrokeOnlyWPAt: pixelIndex antiAliasAlphaByte: strokeAntiAliasAlphaBits ]]].

							mustResetColor ifTrue: [
								strokeA := realStrokeAlpha. fillA := realFillAlpha.
								opaqueStrokeColorWord := realOpaqueStrokeColorWord. opaqueFillColorWord := realOpaqueFillColorWord.
								mustResetColor := false ]].
					displayX := displayX + 1.
					pixelIndex := pixelIndex + 1 ]]]
			ifFalse: [				"All alphas and edgeCounts are zero in this segment of length delta"
				displayX := displayX + segmentLength.
				pixelIndex := pixelIndex + segmentLength.
				"Hop over any following clear segments, eight segment flags per
				compare. Only taken outside the shape: clear segments carry no
				edges, so the winding state cannot change across them."
				displayX <= rowR ifTrue: [
					aux1 := self clearAffectedSpanFrom: pixelIndex >> 4 max: (rowR - displayX >> 4) + 1.
					aux1 > 0 ifTrue: [
						aux1 := aux1 << 4.
						aux1 > (rowR - displayX + 1) ifTrue: [ aux1 := rowR - displayX + 1 ].
						displayX := displayX + aux1.
						pixelIndex := pixelIndex + aux1 ]]] ] ].

		clippingSpecIndex := clippingSpecIndex + 2 ].! !
