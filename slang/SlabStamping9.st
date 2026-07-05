'Slab stamping v9 for VectorEnginePlugin (whole pixel family). Applies on top of v8.
FUSED STAMP+BLEND for glyph tile runs: blendStampedCoverageRunWP:meta:count:
composites cached coverage tiles directly with the current fill color instead of
stamping them into alphaMaskWP and blending in a second pass. The mask round trip
(write coverage, re-scan the span, blend, clear) measured as ~72% of text raster
cost (39ms -> 11ms on a 210-line offscreen micro).
Bit-identical by construction:
- per covered pixel it applies EXACTLY blendFillOnlyWPLeft:''s outside-the-shape
  treatment: the clippingSpec window, the four anti-aliased clip columns (0.25 /
  0.75 fillA modulation), and blendFillOnlyWPAt:antiAliasAlphaByte: math;
- the anti-aliased clip columns are derived from the run''s clipped bounding box,
  exactly the l..r the two-pass blend would have received from finishPath:;
- it updates spanLeft/Top/Right/Bottom exactly like stampCoverageRunWP: (spans
  feed morph damage -- skipping them corrupts redraws, measured the hard way);
- pixels are independent, so blend ORDER differences cannot change results;
- the image side calls it only for runs whose tiles do NOT overlap; kerned
  overlaps fall back to the stamp path, where the mask max-combines them.
ML 7/4/2026'!

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - text and multi paths' stamp: 'ML 7/4/2026 22:30'!
blendStampedCoverageRunWP: sheet meta: metaArray count: n
	"Fused stamp+blend for n cached coverage tiles (glyphs). See the change set
	comment: bit-identical to stampCoverageRunWP: followed by finishPath''s
	blendFillOnlyWPLeft: for runs of non-overlapping tiles.
	metaArray holds 5 words per tile: destX destY w h sheetOffset."

	| l r base dx dy w h off rowStart rowEnd colStart colEnd pixelIndex sIndex cov clippingSpecL clippingSpecR antiAliasedClippedLeftPixel antiAliasedClippedRightPixel mustResetColor realFillAlpha displayX opaqueFillColorWord auxR auxG auxB rowSafe covAlpha covUnAlpha covR covG covB targetWord |
	<var: 'cov' type: #'uint8_t'>
	<var: 'realFillAlpha' type: #float>
	<var: 'opaqueFillColorWord' type: #'uint32_t'>
	<var: 'covAlpha' type: #float>
	<var: 'covUnAlpha' type: #float>
	<var: 'covR' type: #float>
	<var: 'covG' type: #float>
	<var: 'covB' type: #float>
	<var: 'targetWord' type: #'uint32_t'>
	<var: 'auxR' type: #'uint32_t'>
	<var: 'auxG' type: #'uint32_t'>
	<var: 'auxB' type: #'uint32_t'>
	self
		primitive: 'primBlendStampedCoverageRunWP'
		parameters: #(ByteArray WordArray SmallInteger).

	"Clipped bounding box of the whole run: the anti-aliased clip columns must be
	judged against the same l..r the two-pass blend would have used."
	l := targetWidth.
	r := 0.
	1 to: n do: [ :g |
		base := g - 1 * 5.
		dx := metaArray at: base.
		w := metaArray at: base + 2.
		dx < l ifTrue: [ l := dx ].
		dx + w - 1 > r ifTrue: [ r := dx + w - 1 ]].
	l < clipLeft ifTrue: [ l := clipLeft ].
	r > clipRight ifTrue: [ r := clipRight ].

	mustResetColor := false.
	realFillAlpha := fillA.
	"Same opaque shortcut recipe as the blends. For cov = 127 with an opaque fill
	over an opaque target, blendFillOnlyWPAt: computes alpha = 127 * (1/127) * 1.0
	which rounds to exactly 1.0 (double math assigned to float), unAlpha = 0.0, and
	the result word equals this opaqueFillColorWord bit for bit -- so the direct
	overwrite below is an exact shortcut, not an approximation."
	opaqueFillColorWord := 0.
	targetAssumedOpaque ifTrue: [
		fillA = 1.0 ifTrue: [
			auxR := (fillR + 0.5) asInteger bitShift: 16.
			auxG := (fillG + 0.5) asInteger bitShift: 8.
			auxB := (fillB + 0.5) asInteger.
			opaqueFillColorWord := ((16rFF000000 bitOr: auxR) bitOr: auxG) bitOr: auxB ]].
	1 to: n do: [ :g |
		base := g - 1 * 5.
		dx := metaArray at: base.
		dy := metaArray at: base + 1.
		w := metaArray at: base + 2.
		h := metaArray at: base + 3.
		off := metaArray at: base + 4.
		"honor the clip rect: composite only the visible part of the tile"
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
				clippingSpecL := 0.
				clippingSpecR := targetWidth - 1.
				antiAliasedClippedLeftPixel := targetWidth."targetWidth means effectively no AA for clipping"
				antiAliasedClippedRightPixel := targetWidth."targetWidth means effectively no AA for clipping"
				clippingSpec ifNotNil: [
					clippingSpecL := clippingSpec at: rowY * 2.
					clippingSpecR := clippingSpec at: rowY * 2 + 1.
					antiAliasedClippedLeftPixel := clippingSpecL >= l ifTrue: [clippingSpecL] ifFalse: [targetWidth].
					antiAliasedClippedRightPixel := clippingSpecR <= r ifTrue: [clippingSpecR] ifFalse: [targetWidth]].
				pixelIndex := rowY * targetWidth + colStart.
				sIndex := off + ((rowY - dy) * w) + (colStart - dx).
				displayX := colStart.
				"Fast row: whole tile row inside the clip window and clear of the four
				anti-aliased clip columns (the usual case for text inside a pane) --
				no per-pixel window checks, and cov = 127 with an opaque fill takes
				the exact overwrite shortcut justified above."
				rowSafe := (colStart >= clippingSpecL and: [colEnd <= clippingSpecR])
					and: [(antiAliasedClippedLeftPixel + 1 < colStart or: [antiAliasedClippedLeftPixel > (colEnd + 1)])
					and: [(antiAliasedClippedRightPixel + 1 < colStart or: [antiAliasedClippedRightPixel > (colEnd + 1)])]].
				rowSafe
					ifTrue: [
						[ displayX <= colEnd ] whileTrue: [
							cov := sheet at: sIndex.
							cov = 0 ifFalse: [
								(cov = 16r7F and: [opaqueFillColorWord ~= 0])
									ifTrue: [
										targetBits at: pixelIndex put: opaqueFillColorWord.
										morphIds at: pixelIndex put: currentMorphId ]
									ifFalse: [
										targetWord := targetBits at: pixelIndex.
										(targetWord bitAnd: 16rFF000000) = 16rFF000000
											ifTrue: [
												"blendFillOnlyWPAt:antiAliasAlphaByte:''s opaque-target
												branch, inlined expression for expression"
												covAlpha := cov * (1.0 / 127.0).
												covAlpha := covAlpha * fillA.
												covUnAlpha := 1.0 - covAlpha.
												covR := covAlpha * fillR + (covUnAlpha * ((targetWord bitAnd: 16rFF0000) bitShift: -16)).
												covG := covAlpha * fillG + (covUnAlpha * ((targetWord bitAnd: 16rFF00) bitShift: -8)).
												covB := covAlpha * fillB + (covUnAlpha * (targetWord bitAnd: 16rFF)).
												targetWord := ((16rFF000000 bitOr: ((covR + 0.5) asInteger bitShift: 16)) bitOr: ((covG + 0.5) asInteger bitShift: 8)) bitOr: (covB + 0.5) asInteger.
												targetBits at: pixelIndex put: targetWord.
												morphIds at: pixelIndex put: currentMorphId ]
											ifFalse: [
												self blendFillOnlyWPAt: pixelIndex antiAliasAlphaByte: cov ]]].
							displayX := displayX + 1.
							pixelIndex := pixelIndex + 1.
							sIndex := sIndex + 1 ]]
					ifFalse: [
						[ displayX <= colEnd ] whileTrue: [
							cov := sheet at: sIndex.
							cov = 0 ifFalse: [
								(displayX >= clippingSpecL and: [ displayX <= clippingSpecR ]) ifTrue: [
									(displayX = antiAliasedClippedLeftPixel or: [ displayX = antiAliasedClippedRightPixel ])
										ifTrue: [
											fillA := fillA * 0.25. mustResetColor := true ]
										ifFalse: [
											(displayX - 1 = antiAliasedClippedLeftPixel or: [ displayX + 1 = antiAliasedClippedRightPixel ]) ifTrue: [
												fillA := fillA * 0.75. mustResetColor := true ]].
									self blendFillOnlyWPAt: pixelIndex antiAliasAlphaByte: cov.
									mustResetColor ifTrue: [
										fillA := realFillAlpha. mustResetColor := false ]]].
							displayX := displayX + 1.
							pixelIndex := pixelIndex + 1.
							sIndex := sIndex + 1 ]]]]]! !
