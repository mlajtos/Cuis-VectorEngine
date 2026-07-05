'Slab stamping v6 for VectorEnginePlugin (whole pixel family). Applies on top of v5.
Blend-pass optimizations, all bit-identical to v5 output (validated by render oracle):
- blendFillOnlyWPAt:/blendStrokeOnlyWPAt: skip their three divides (and three
  multiplies) when the target pixel is opaque: targetAlpha computes to exactly 1.0
  and alpha + (unAlpha * 1.0) rounds to exactly 1.0 for EVERY float alpha in [0..1]
  (verified exhaustively over all 2^30 such floats), so the skipped operations are
  IEEE identities. Opaque targets are the universal case for live Morphic.
- The WP blend sweeps hop over runs of clear 16-pixel segments eight flags per
  compare (clearAffectedSpanFrom:max:, one uint64 load) instead of one segment at
  a time. A window-chrome stroke sweeps its whole bounding box -- 4.2 Mpx at
  retina fullscreen -- of which the stroke ring is ~2%.
- Pure-alpha full segments (stamped glyph coverage: no edge counts, outside any
  fill winding) take a tight loop: gang-load 16 edge counts and 16 coverage bytes
  as uint64 pairs, bulk-clear the mask, and blend only covered pixels.
- The clean-interior bulk loops write targetBits and morphIds in SEPARATE loops:
  single-array constant-store loops vectorize; the interleaved form cannot (the
  compiler must assume the two pointers alias).
- New prim clearMaskWPLeft:top:right:bottom: clears stamped coverage state over a
  rect without a blend pass, so glyph-tile BAKING (rasterize once, read coverage
  back, cache) can happen at any in-clip position and leave no residue. The image
  side uses it to bake tiles for runs that cross the clip rect.
ML 7/4/2026'!

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - blending' stamp: 'ML 7/4/2026 15:00'!
blendFillOnlyWPAt: pixelIndex antiAliasAlphaByte: antiAliasAlphaBits
	"Blends fill color over background.
	WP: Whole pixel anti aliasing.
	Target translucency is computed correctly.
	For blending, alphas are in [0 .. 1.0] and R, G, B color components are in [0 .. 255]"
	<var: 'antiAliasAlphaBits' type: #'uint8_t'>
	| targetWord resultR resultG resultB resultRBits resultGBits resultBBits alpha unAlpha targetAlphaBits targetAlpha resultAlpha resultAlphaBits |
	<var: 'targetWord' type: #'uint32_t'>
	<var: 'targetAlphaBits' type: #'uint32_t'>
	<var: 'targetAlpha' type: #float>
	<var: 'resultRBits' type: #'uint32_t'>
	<var: 'resultGBits' type: #'uint32_t'>
	<var: 'resultBBits' type: #'uint32_t'>
	<var: 'resultAlpha' type: #float>
	<var: 'resultR' type: #float>
	<var: 'resultG' type: #float>
	<var: 'resultB' type: #float>
	<var: 'alpha' type: #float>
	<var: 'unAlpha' type: #float>
	<var: 'resultAlphaBits' type: #'uint32_t'>
	alpha := antiAliasAlphaBits * (1.0 / 127.0).
	alpha := alpha * fillA.
	unAlpha := 1.0 - alpha.
	targetWord := targetBits at: pixelIndex.
	targetAlphaBits := targetWord bitAnd: 16rFF000000.
	resultRBits := targetWord bitAnd: 16rFF0000.
	resultGBits := targetWord bitAnd: 16rFF00.
	resultBBits := targetWord bitAnd: 16rFF.
	targetAlphaBits = 16rFF000000 ifTrue: [
		"Opaque target pixel: targetAlpha computes to exactly 1.0, and
		alpha + (unAlpha * 1.0) rounds to exactly 1.0 for every float alpha
		in [0..1] (verified exhaustively over all 2^30 such floats). The
		three divides and three multiplies by these values are IEEE
		identities, so skipping them is bit-identical to the general path.
		This is the universal case when drawing to the live Display."
		resultR := alpha * fillR + (unAlpha * (resultRBits bitShift: -16)).
		resultG := alpha * fillG + (unAlpha * (resultGBits bitShift: -8)).
		resultB := alpha * fillB + (unAlpha * resultBBits).
		resultRBits := (resultR + 0.5) asInteger bitShift: 16.
		resultGBits := (resultG + 0.5) asInteger bitShift: 8.
		resultBBits := (resultB + 0.5) asInteger.
		targetWord := ((16rFF000000 bitOr: resultRBits) bitOr: resultGBits) bitOr: resultBBits.
		targetBits at: pixelIndex put: targetWord.
		morphIds at: pixelIndex put: currentMorphId.
		^ 0 ].
	targetAlpha := targetAlphaBits * ( 1.0 / (255.0 * 256 * 256 * 256)).
	resultAlpha := alpha + (unAlpha * targetAlpha).
	resultR := alpha * fillR + (unAlpha * (resultRBits bitShift: -16) * targetAlpha).
	resultG := alpha * fillG + (unAlpha * (resultGBits bitShift: -8) * targetAlpha).
	resultB := alpha * fillB + (unAlpha * resultBBits * targetAlpha).
	resultAlphaBits := (resultAlpha * 255 + 0.5) asInteger bitShift: 24.
	resultRBits := (resultR / resultAlpha + 0.5) asInteger bitShift: 16.
	resultGBits := (resultG / resultAlpha + 0.5) asInteger bitShift: 8.
	resultBBits := (resultB / resultAlpha + 0.5) asInteger.
	targetWord := ((resultAlphaBits bitOr: resultRBits) bitOr: resultGBits) bitOr: resultBBits.
	targetBits at: pixelIndex put: targetWord.
	morphIds at: pixelIndex put: currentMorphId.! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - blending' stamp: 'ML 7/4/2026 15:00'!
blendStrokeOnlyWPAt: pixelIndex antiAliasAlphaByte: strokeAntiAliasAlphaBits
	"Blends stroke color over background.
	WP: Whole pixel anti aliasing.
	Target translucency is computed correctly.
	For blending, alphas are in [0 .. 1.0] and R, G, B color components are in [0 .. 255]"
	<var: 'strokeAntiAliasAlphaBits' type: #'uint8_t'>
	| targetWord resultR resultG resultB resultRBits resultGBits resultBBits alpha unAlpha targetAlphaBits targetAlpha resultAlpha resultAlphaBits |
	<var: 'targetWord' type: #'uint32_t'>
	<var: 'targetAlphaBits' type: #'uint32_t'>
	<var: 'targetAlpha' type: #float>
	<var: 'resultRBits' type: #'uint32_t'>
	<var: 'resultGBits' type: #'uint32_t'>
	<var: 'resultBBits' type: #'uint32_t'>
	<var: 'resultAlpha' type: #float>
	<var: 'resultR' type: #float>
	<var: 'resultG' type: #float>
	<var: 'resultB' type: #float>
	<var: 'alpha' type: #float>
	<var: 'unAlpha' type: #float>
	<var: 'resultAlphaBits' type: #'uint32_t'>
	alpha := strokeAntiAliasAlphaBits * (1.0 / 127.0).
	alpha := alpha * strokeA.
	unAlpha := 1.0 - alpha.
	targetWord := targetBits at: pixelIndex.
	targetAlphaBits := targetWord bitAnd: 16rFF000000.
	resultRBits := targetWord bitAnd: 16rFF0000.
	resultGBits := targetWord bitAnd: 16rFF00.
	resultBBits := targetWord bitAnd: 16rFF.
	targetAlphaBits = 16rFF000000 ifTrue: [
		"Opaque target pixel: see blendFillOnlyWPAt:antiAliasAlphaByte: --
		the skipped divides and multiplies are IEEE identities here."
		resultR := alpha * strokeR + (unAlpha * (resultRBits bitShift: -16)).
		resultG := alpha * strokeG + (unAlpha * (resultGBits bitShift: -8)).
		resultB := alpha * strokeB + (unAlpha * resultBBits).
		resultRBits := (resultR + 0.5) asInteger bitShift: 16.
		resultGBits := (resultG + 0.5) asInteger bitShift: 8.
		resultBBits := (resultB + 0.5) asInteger.
		targetWord := ((16rFF000000 bitOr: resultRBits) bitOr: resultGBits) bitOr: resultBBits.
		targetBits at: pixelIndex put: targetWord.
		morphIds at: pixelIndex put: currentMorphId.
		^ 0 ].
	targetAlpha := targetAlphaBits * ( 1.0 / (255.0 * 256 * 256 * 256)).
	resultAlpha := alpha + (unAlpha * targetAlpha).
	resultR := alpha * strokeR + (unAlpha * (resultRBits bitShift: -16) * targetAlpha).
	resultG := alpha * strokeG + (unAlpha * (resultGBits bitShift: -8) * targetAlpha).
	resultB := alpha * strokeB + (unAlpha * resultBBits * targetAlpha).
	resultAlphaBits := (resultAlpha * 255 + 0.5) asInteger bitShift: 24.
	resultRBits := (resultR / resultAlpha + 0.5) asInteger bitShift: 16.
	resultGBits := (resultG / resultAlpha + 0.5) asInteger bitShift: 8.
	resultBBits := (resultB / resultAlpha + 0.5) asInteger.
	targetWord := ((resultAlphaBits bitOr: resultRBits) bitOr: resultGBits) bitOr: resultBBits.
	targetBits at: pixelIndex put: targetWord.
	morphIds at: pixelIndex put: currentMorphId.! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - blending' stamp: 'ML 7/4/2026 15:00'!
clearAffectedSpanFrom: firstSegment max: maxSegments
	"Count how many consecutive 16-pixel segments starting at firstSegment are
	completely clear (affectedBits zero), up to maxSegments. Gang-checks eight
	segment flags per uint64 load so blend passes can hop empty space at
	~128 px per compare instead of 16."
	| n chunk |
	<var: 'chunk' type: #'usqLong'>
	<inline: false>
	n := 0.
	chunk := 0.
	[n + 8 <= maxSegments
	 and: [self cCode: '(memcpy(&chunk, affectedBits + firstSegment + n, 8), chunk == 0)'
			inSmalltalk: [chunk = 0]]]
		whileTrue: [ n := n + 8 ].
	[n < maxSegments and: [(affectedBits at: firstSegment + n) = 0]]
		whileTrue: [ n := n + 1 ].
	^ n! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - text and multi paths' stamp: 'ML 7/4/2026 15:00'!
clearMaskWPLeft: l top: t right: r bottom: b
	"Clear stamped coverage state (alphaMaskWP, edgeCountsWP, affectedBits) over
	a pixel rect, so a caller that only rasterized to read coverage back (glyph
	tile baking) leaves no residue for the next blend. affectedBits flags are
	cleared only for segments FULLY inside the rect: an edge segment may still
	carry data from neighbouring stamps, so its flag must survive (a set flag
	over clean bytes is harmless; a cleared flag over live bytes loses them)."
	| lc tc rc bc w pixelIndex firstSeg lastSeg |
	self
		primitive: 'primClearMaskWP'
		parameters: #(SmallInteger SmallInteger SmallInteger SmallInteger).
	lc := l max: 0.
	tc := t max: 0.
	rc := r min: targetWidth - 1.
	bc := b min: targetHeight - 1.
	(rc >= lc and: [bc >= tc]) ifTrue: [
		w := rc - lc + 1.
		tc to: bc do: [ :displayY |
			pixelIndex := displayY * targetWidth + lc.
			self cCode: 'memset(alphaMaskWP + pixelIndex, 0, w)'
				inSmalltalk: [ pixelIndex to: pixelIndex + w - 1 do: [ :i | alphaMaskWP at: i put: 0 ]].
			self cCode: 'memset(edgeCountsWP + pixelIndex, 0, w)'
				inSmalltalk: [ pixelIndex to: pixelIndex + w - 1 do: [ :i | edgeCountsWP at: i put: 0 ]].
			firstSeg := pixelIndex + 15 >> 4.
			lastSeg := (pixelIndex + w >> 4) - 1.
			firstSeg to: lastSeg do: [ :seg |
				affectedBits at: seg put: 0 ]]]! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - blend stroke and fill' stamp: 'ML 7/4/2026 15:00'!
blendFillOnlyWPLeft: l top: t right: r bottom: b
	"Blends fill color over background.
	WP: Whole pixel anti aliasing.
	If targetAssumedOpaque is false, target translucency is computed correctly.
	If targetAssumedOpaque is true (and target translucency is actually 255 on input), an optimization is made and target translucency is set to 255.
	For blending, alphas are in [0 .. 1.0] and R, G, B color components are in [0 .. 255]"
	| pixelIndex edgesUpToThisPixel edgesThisPixel strokeAntiAliasAlphaBits clippingSpecL clippingSpecR clippingSpecIndex antiAliasedClippedLeftPixel antiAliasedClippedRightPixel mustResetColor realFillAlpha opaqueFillColorWord realOpaqueFillColorWord auxR auxG auxB displayX affectedBitsIndex segmentLength alphasOrEdgeCountsInThisSegment lastSegmentIndex aux1 toDoLimit tightDone runLen runSafe targetWord2 bulkAlpha bulkUnAlpha bulkTargetAlpha bulkResultAlpha bulkFR bulkFG bulkFB bulkR bulkG bulkB vEdges0 vEdges1 vAlpha0 vAlpha1 |
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
		pixelIndex := displayY * targetWidth + l.
		displayX := l.
		[ displayX <= r ] whileTrue: [

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
					runLen := segmentLength min: r - displayX + 1.
					(displayX >= clippingSpecL and: [displayX + runLen - 1 <= clippingSpecR]) ifTrue: [
						((displayX + runLen < antiAliasedClippedLeftPixel or: [displayX > (antiAliasedClippedLeftPixel + 1)]) and: [
						  displayX + runLen < antiAliasedClippedRightPixel or: [displayX > (antiAliasedClippedRightPixel + 1)]]) ifTrue: [
							runSafe := true ]]]].
			runSafe ifTrue: [
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
				aux1 := r-displayX+1.
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
				displayX <= r ifTrue: [
					aux1 := self clearAffectedSpanFrom: pixelIndex >> 4 max: (r - displayX >> 4) + 1.
					aux1 > 0 ifTrue: [
						aux1 := aux1 << 4.
						aux1 > (r - displayX + 1) ifTrue: [ aux1 := r - displayX + 1 ].
						displayX := displayX + aux1.
						pixelIndex := pixelIndex + aux1 ]]] ] ].

		clippingSpecIndex := clippingSpecIndex + 2 ].! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - blend stroke and fill' stamp: 'ML 7/4/2026 15:00'!
blendStrokeOnlyWPLeft: l top: t right: r bottom: b
	"Blends stroke color over background.
	WP: Whole pixel anti aliasing.
	If targetAssumedOpaque is false, target translucency is computed correctly.
	If targetAssumedOpaque is true (and target translucency is actually 255 on input), an optimization is made and target translucency is set to 255.
	For blending, alphas are in [0 .. 1.0] and R, G, B color components are in [0 .. 255]"
	| pixelIndex strokeAntiAliasAlphaBits auxR auxG auxB clippingSpecL clippingSpecR clippingSpecIndex antiAliasedClippedLeftPixel antiAliasedClippedRightPixel mustResetColor realStrokeAlpha opaqueStrokeColorWord realOpaqueStrokeColorWord displayX affectedBitsIndex segmentLength alphasOrEdgeCountsInThisSegment lastSegmentIndex aux1 |
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
		pixelIndex := displayY * targetWidth + l.
		displayX := l.
		[ displayX <= r ] whileTrue: [

			affectedBitsIndex := pixelIndex>>4.
			lastSegmentIndex = affectedBitsIndex ifFalse: [
				alphasOrEdgeCountsInThisSegment := (affectedBits at: affectedBitsIndex) = 1.
				lastSegmentIndex := affectedBitsIndex.
				alphasOrEdgeCountsInThisSegment ifTrue: [
					affectedBits at: affectedBitsIndex put: 0 ]].
			segmentLength := affectedBitsIndex+1 << 4 - pixelIndex.
			alphasOrEdgeCountsInThisSegment ifTrue: [
				aux1 := r-displayX+1.
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
				displayX <= r ifTrue: [
					aux1 := self clearAffectedSpanFrom: pixelIndex >> 4 max: (r - displayX >> 4) + 1.
					aux1 > 0 ifTrue: [
						aux1 := aux1 << 4.
						aux1 > (r - displayX + 1) ifTrue: [ aux1 := r - displayX + 1 ].
						displayX := displayX + aux1.
						pixelIndex := pixelIndex + aux1 ]]]].

		clippingSpecIndex := clippingSpecIndex + 2 ].! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - blend stroke and fill' stamp: 'ML 7/4/2026 15:00'!
blendStrokeAndFillWPLeft: l top: t right: r bottom: b
	"Blends stroke color and fill color over background.
	Do an appropriate (anti aliased) gradient between stoke color and fill color (or pick just stroke or just fill). Blend this over background.
	WP: Whole pixel anti aliasing.
	If targetAssumedOpaque is false, target translucency is computed correctly.
	If targetAssumedOpaque is true (and target translucency is actually 255 on input), an optimization is made and target translucency is set to 255.
	For blending, alphas are in [0 .. 1.0] and R, G, B color components are in [0 .. 255]"
	| pixelIndex edgesUpToThisPixel edgesThisPixel strokeAntiAliasAlphaBits clippingSpecL clippingSpecR clippingSpecIndex antiAliasedClippedLeftPixel antiAliasedClippedRightPixel mustResetColor realStrokeAlpha realFillAlpha opaqueStrokeColorWord opaqueFillColorWord realOpaqueStrokeColorWord realOpaqueFillColorWord auxR auxG auxB displayX affectedBitsIndex segmentLength alphasOrEdgeCountsInThisSegment lastSegmentIndex aux1 toDoLimit tightDone runLen runSafe targetWord2 bulkAlpha bulkUnAlpha bulkTargetAlpha bulkResultAlpha bulkFR bulkFG bulkFB bulkR bulkG bulkB vEdges0 vEdges1 vAlpha0 vAlpha1 |
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
		pixelIndex := displayY * targetWidth + l.
		displayX := l.
		[ displayX <= r ] whileTrue: [

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
					runLen := segmentLength min: r - displayX + 1.
					(displayX >= clippingSpecL and: [displayX + runLen - 1 <= clippingSpecR]) ifTrue: [
						((displayX + runLen < antiAliasedClippedLeftPixel or: [displayX > (antiAliasedClippedLeftPixel + 1)]) and: [
						  displayX + runLen < antiAliasedClippedRightPixel or: [displayX > (antiAliasedClippedRightPixel + 1)]]) ifTrue: [
							runSafe := true ]]]].
			runSafe ifTrue: [
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
				aux1 := r-displayX+1.
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
				displayX <= r ifTrue: [
					aux1 := self clearAffectedSpanFrom: pixelIndex >> 4 max: (r - displayX >> 4) + 1.
					aux1 > 0 ifTrue: [
						aux1 := aux1 << 4.
						aux1 > (r - displayX + 1) ifTrue: [ aux1 := r - displayX + 1 ].
						displayX := displayX + aux1.
						pixelIndex := pixelIndex + aux1 ]]] ] ].

		clippingSpecIndex := clippingSpecIndex + 2 ].! !
