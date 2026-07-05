'Slab stamping v10 for VectorEnginePlugin (whole pixel family). Applies on top of v9.
COVERAGE-RLE for the fused glyph path: blendRleCoverageRunWP:meta:count: consumes
tiles as per-row run streams (skip n / opaque n / literal n) instead of per-pixel
byte scans. Glyph coverage is ~75% zeros and full-alpha: zero runs cost one op
byte, full-alpha runs become plain word stores, and only genuine anti-aliasing
pixels reach the blend math. Encoded at bake time by the image side; the raw bytes
remain in the sheet for the mask (stamp) path and for rows needing the per-pixel
clip treatment, so every path keeps its exact v9 semantics -- bit-identical.
metaArray stride is SIX words per tile: destX destY w h rawOffset rleOffset.
The RLE blob layout: h little-endian uint16 row offsets (relative to the blob
start, table included), then the row streams. Op byte: top two bits 0=skip,
1=opaque(127), 2=literal (followed by len coverage bytes); low six bits = len 1..63.
ML 7/5/2026'!

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - text and multi paths' stamp: 'ML 7/5/2026 00:30'!
blendRleCoverageRunWP: sheet meta: metaArray count: n
	"Fused stamp+blend over RLE-encoded coverage tiles. Bit-identical to
	blendStampedCoverageRunWP:meta:count: (same per-pixel math, same span updates,
	same clip treatment); rows clear of the anti-aliased clip columns decode runs,
	other rows fall back to the raw bytes with the exact per-pixel treatment."

	| l r base dx dy w h off rleOff rowStart rowEnd colStart colEnd pixelIndex sIndex cov clippingSpecL clippingSpecR antiAliasedClippedLeftPixel antiAliasedClippedRightPixel mustResetColor realFillAlpha displayX opaqueFillColorWord auxR auxG auxB rowSafe covAlpha covUnAlpha covR covG covB targetWord rowPos x op len kind lo hi |
	<var: 'cov' type: #'uint8_t'>
	<var: 'realFillAlpha' type: #float>
	<var: 'opaqueFillColorWord' type: #'uint32_t'>
	<var: 'covAlpha' type: #float>
	<var: 'covUnAlpha' type: #float>
	<var: 'covR' type: #float>
	<var: 'covG' type: #float>
	<var: 'covB' type: #float>
	<var: 'targetWord' type: #'uint32_t'>
	self
		primitive: 'primBlendRleCoverageRunWP'
		parameters: #(ByteArray WordArray SmallInteger).

	"Clipped bounding box of the whole run: the anti-aliased clip columns must be
	judged against the same l..r the two-pass blend would have used."
	l := targetWidth.
	r := 0.
	1 to: n do: [ :g |
		base := g - 1 * 6.
		dx := metaArray at: base.
		w := metaArray at: base + 2.
		dx < l ifTrue: [ l := dx ].
		dx + w - 1 > r ifTrue: [ r := dx + w - 1 ]].
	l < clipLeft ifTrue: [ l := clipLeft ].
	r > clipRight ifTrue: [ r := clipRight ].

	mustResetColor := false.
	realFillAlpha := fillA.
	"Same opaque shortcut recipe as the blends: for full coverage with an opaque
	fill over an opaque target the blend math produces exactly this word."
	opaqueFillColorWord := 0.
	targetAssumedOpaque ifTrue: [
		fillA = 1.0 ifTrue: [
			auxR := (fillR + 0.5) asInteger bitShift: 16.
			auxG := (fillG + 0.5) asInteger bitShift: 8.
			auxB := (fillB + 0.5) asInteger.
			opaqueFillColorWord := ((16rFF000000 bitOr: auxR) bitOr: auxG) bitOr: auxB ]].
	1 to: n do: [ :g |
		base := g - 1 * 6.
		dx := metaArray at: base.
		dy := metaArray at: base + 1.
		w := metaArray at: base + 2.
		h := metaArray at: base + 3.
		off := metaArray at: base + 4.
		rleOff := metaArray at: base + 5.
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
				rowSafe := (colStart >= clippingSpecL and: [colEnd <= clippingSpecR])
					and: [(antiAliasedClippedLeftPixel + 1 < colStart or: [antiAliasedClippedLeftPixel > (colEnd + 1)])
					and: [(antiAliasedClippedRightPixel + 1 < colStart or: [antiAliasedClippedRightPixel > (colEnd + 1)])]].
				rowSafe
					ifTrue: [
						"RLE fast row: decode runs; zero runs are one op byte, full-alpha
						runs are plain stores, only true AA pixels blend."
						rowPos := rleOff + (sheet at: rleOff + ((rowY - dy) * 2)) + ((sheet at: rleOff + ((rowY - dy) * 2) + 1) * 256).
						x := dx.
						[ x <= colEnd ] whileTrue: [
							op := sheet at: rowPos.
							rowPos := rowPos + 1.
							len := op bitAnd: 63.
							kind := op >> 6.
							kind = 0
								ifTrue: [ x := x + len ]
								ifFalse: [
									lo := x max: colStart.
									hi := x + len - 1 min: colEnd.
									kind = 1
										ifTrue: [
											lo <= hi ifTrue: [
												pixelIndex := rowY * targetWidth + lo.
												opaqueFillColorWord ~= 0
													ifTrue: [
														lo to: hi do: [ :xx |
															targetBits at: pixelIndex put: opaqueFillColorWord.
															morphIds at: pixelIndex put: currentMorphId.
															pixelIndex := pixelIndex + 1 ]]
													ifFalse: [
														lo to: hi do: [ :xx |
															self blendFillOnlyWPAt: pixelIndex antiAliasAlphaByte: 16r7F.
															pixelIndex := pixelIndex + 1 ]]].
											x := x + len ]
										ifFalse: [
											lo <= hi ifTrue: [
												sIndex := rowPos + (lo - x).
												pixelIndex := rowY * targetWidth + lo.
												lo to: hi do: [ :xx |
													cov := sheet at: sIndex.
													targetWord := targetBits at: pixelIndex.
													(targetWord bitAnd: 16rFF000000) = 16rFF000000
														ifTrue: [
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
															self blendFillOnlyWPAt: pixelIndex antiAliasAlphaByte: cov ].
													sIndex := sIndex + 1.
													pixelIndex := pixelIndex + 1 ]].
											rowPos := rowPos + len.
											x := x + len ]]]]
					ifFalse: [
						"edge row (anti-aliased clip columns in range): raw bytes with the
						exact per-pixel treatment, identical to blendStampedCoverageRunWP:"
						pixelIndex := rowY * targetWidth + colStart.
						sIndex := off + ((rowY - dy) * w) + (colStart - dx).
						displayX := colStart.
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
