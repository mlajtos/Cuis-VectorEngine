'Slab stamping v2 for VectorEnginePlugin (whole pixel family).
Adds to v1 (slab-stamped solid+dashed line strokes):
- quadratic + cubic beziers stamp their pen trace as ~2px chord slabs (glyphs, squircles)
- blendFillOnlyWP / blendStrokeAndFillWP blast clean interior segments as bulk runs:
  opaque fills as plain overwrites, translucent fills with the per-pixel constants
  (and divides) hoisted -- both bit-identical to the per-pixel path.
ML 7/3/2026'!

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - path algorithms' stamp: 'ML 7/3/2026 12:00'!
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

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - path algorithms' stamp: 'ML 7/3/2026 12:00'!
pvt_lineWPFromX: xFrom y: yFrom toX: xTo y: yTo

	<var: 'xFrom' type: #float>
	<var: 'yFrom' type: #float>
	<var: 'xTo' type: #float>
	<var: 'yTo' type: #float>
	| txFrom tyFrom txTo tyTo dx dy hops t oneLessT increment x y runStartK kEnd bit isOn tR0 tR1 |
	<var: 'txFrom' type: #float>
	<var: 'tyFrom' type: #float>
	<var: 'txTo' type: #float>
	<var: 'tyTo' type: #float>
	<var: 'dx' type: #float>
	<var: 'dy' type: #float>
	<var: 'hops' type: #int>
	<var: 't' type: #float>
	<var: 'oneLessT' type: #float>
	<var: 'increment' type: #float>
	<var: 'x' type: #float>
	<var: 'y' type: #float>
	<var: 'runStartK' type: #int>
	<var: 'kEnd' type: #int>
	<var: 'tR0' type: #float>
	<var: 'tR1' type: #float>

	trajectoryLength := 0.0.
	needsFullAlphaCircle := true.
	txFrom := (xFrom * txA11) + (yFrom * txA12) + txA13.
	tyFrom := (xFrom * txA21) + (yFrom * txA22) + txA23.
	txTo := (xTo * txA11) + (yTo * txA12) + txA13.
	tyTo := (xTo * txA21) + (yTo * txA22) + txA23.
	dx := txTo-txFrom.
	dy := tyTo-tyFrom.
	dx := dx abs.
	dy := dy abs.
	hops := ((dx max: dy) / hop) asInteger + 1.

	spanLeft := spanLeft min: (txFrom min: txTo).
	spanRight := spanRight max: (txFrom max: txTo).
	spanTop := spanTop min: (tyFrom min: tyTo).
	spanBottom := spanBottom max: (tyFrom max: tyTo).

	t := 0.0.
	increment := 1.0 / hops.
	dashBitLength = 0.0
		ifTrue: [
			"Solid stroke: one slab pass stamps the whole segment, each pixel visited once."
			self slabStampSegmentWPFromX: txFrom y: tyFrom toX: txTo y: tyTo ]
		ifFalse: [
			"Dashed: classify each sample on/off with the SAME trajectoryLength accumulator
			the disk stamper uses, then stamp each run of consecutive 'on' samples as one
			slab sub-segment. Round caps at dash ends fall out of the distance math."
			runStartK := -1.
			1 to: hops + 1 do: [ :k |
				trajectoryLength := trajectoryLength + hop.
				"Note: dashBitOffset must be positive."
				bit := ((trajectoryLength / dashBitLength) asInteger + dashBitOffset) \\ dashBitCount.
				isOn := (dashedStrokeBits bitAnd: 1 << (dashBitCount-bit-1)) ~= 0.
				(isOn and: [runStartK < 0]) ifTrue: [ runStartK := k ].
				(runStartK >= 0 and: [isOn not or: [k = (hops + 1)]]) ifTrue: [
					kEnd := isOn ifTrue: [k] ifFalse: [k - 1].
					tR0 := (runStartK - 1) * increment.
					tR0 > 1.0 ifTrue: [ tR0 := 1.0 ].
					tR1 := (kEnd - 1) * increment.
					tR1 > 1.0 ifTrue: [ tR1 := 1.0 ].
					self
						slabStampSegmentWPFromX: ((1.0-tR0) * txFrom) + (tR0 * txTo)
						y: ((1.0-tR0) * tyFrom) + (tR0 * tyTo)
						toX: ((1.0-tR1) * txFrom) + (tR1 * txTo)
						y: ((1.0-tR1) * tyFrom) + (tR1 * tyTo).
					runStartK := -1 ]]].

	"Edge counts and contour keep the original sampled walk (identical output to the
	sampled stamper; correct fill edge counts require visiting every y at least once)."
	[ t < 1.0 ] whileTrue: [
		oneLessT := 1.0 - t.
		x := (oneLessT * txFrom) + (t * txTo).
		y := (oneLessT * tyFrom) + (t * tyTo).
		fillA = 0.0 ifFalse: [
			self updateEdgeCountWPAtX: x y: y ].
		self updateContourForX: x y: y.
		t := t + increment. ].
	fillA = 0.0 ifFalse: [
		self updateEdgeCountWPAtX: txTo y: tyTo ].
	self updateContourForX: txTo y: tyTo.! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - path algorithms' stamp: 'ML 7/3/2026 21:00'!
pvt_quadraticBezierWPFromX: xFrom y: yFrom toX: xTo y: yTo controlX: xControl y: yControl

	<var: 'xFrom' type: #float>
	<var: 'yFrom' type: #float>
	<var: 'xTo' type: #float>
	<var: 'yTo' type: #float>
	<var: 'xControl' type: #float>
	<var: 'yControl' type: #float>
	| txFrom tyFrom txTo tyTo txControl tyControl dx dy dx2 dy2 length xMinEnd xMaxEnd yMinEnd yMaxEnd t0 x0 y0 t oneLessT increment f1 f2 f3 x y correction chordX chordY cdx cdy |
	<var: 'chordX' type: #float>
	<var: 'chordY' type: #float>
	<var: 'cdx' type: #float>
	<var: 'cdy' type: #float>
	<var: 'txFrom' type: #float>
	<var: 'tyFrom' type: #float>
	<var: 'txTo' type: #float>
	<var: 'tyTo' type: #float>
	<var: 'txControl' type: #float>
	<var: 'tyControl' type: #float>
	<var: 'dx' type: #float>
	<var: 'dy' type: #float>
	<var: 'dx2' type: #float>
	<var: 'dy2' type: #float>
	<var: 'length' type: #float>
	<var: 'correction' type: #float>
	<var: 't0' type: #float>
	<var: 'x0' type: #float>
	<var: 'y0' type: #float>
	<var: 't' type: #float>
	<var: 'oneLessT' type: #float>
	<var: 'increment' type: #float>
	<var: 'f1' type: #float>
	<var: 'f2' type: #float>
	<var: 'f3' type: #float>
	<var: 'x' type: #float>
	<var: 'y' type: #float>
	<var: 'xMinEnd' type: #float>
	<var: 'xMaxEnd' type: #float>
	<var: 'yMinEnd' type: #float>
	<var: 'yMaxEnd' type: #float>
	

	"If control point is bogus, just draw a line"
	(xControl = xTo and: [ yControl = yTo ]) ifTrue: [
		^self pvt_lineWPFromX: xFrom y: yFrom toX: xTo y: yTo ].
	(xControl = xFrom and: [ yControl = yFrom ]) ifTrue: [
		^self pvt_lineWPFromX: xFrom y: yFrom toX: xTo y: yTo ].

	trajectoryLength := 0.0.
	needsFullAlphaCircle := true.
	txFrom := (xFrom * txA11) + (yFrom * txA12) + txA13.
	tyFrom := (xFrom * txA21) + (yFrom * txA22) + txA23.
	txTo := (xTo * txA11) + (yTo * txA12) + txA13.
	tyTo := (xTo * txA21) + (yTo * txA22) + txA23.
	txControl := (xControl * txA11) + (yControl * txA12) + txA13.
	tyControl := (xControl * txA21) + (yControl * txA22) + txA23.
	dx := (txTo-txFrom) abs.
	dx2 := (txControl-txFrom) abs.
	dy := (tyTo-tyFrom) abs.
	dy2 := (tyControl-tyFrom) abs.

	"If almost a vertical line, just draw a line. (Ignoring control point)"
	(dx < 1.0 and: [dx2 < 1.0]) ifTrue: [
		^self pvt_lineWPFromX: xFrom y: yFrom toX: xTo y: yTo ].

	"If almost an horizontal line, just draw a line. (Ignoring control point)"
	(dy < 1.0 and: [dy2 < 1.0]) ifTrue: [
		^self pvt_lineWPFromX: xFrom y: yFrom toX: xTo y: yTo ].

	"This computed span of the Bezier curve is a bit pessimistic (larger than strict bounds), but safe."
	xMinEnd := txFrom min: txTo.
	xMaxEnd := txFrom max: txTo.
	yMinEnd := tyFrom min: tyTo.
	yMaxEnd := tyFrom max: tyTo.
	spanLeft := spanLeft min: (xMinEnd min: (xMinEnd+txControl) / 2.0).
	spanRight := spanRight max: (xMaxEnd max: (xMaxEnd+txControl) / 2.0).
	spanTop := spanTop min: (yMinEnd min: (yMinEnd+tyControl) / 2.0).
	spanBottom := spanBottom max: (yMaxEnd max: (yMaxEnd+tyControl) / 2.0).

	"Case t = 0.0"
	x := txFrom.
	y := tyFrom.
	dashBitLength = 0.0
		ifTrue: [ chordX := x. chordY := y ]
		ifFalse: [ self updateAlphasWPForX: x y: y ].
	fillA = 0.0 ifFalse: [
		self updateEdgeCountWPAtX: x y: y ].
	self updateContourForX: x y: y.

	"Will be corrected for each hop. This, being close to pointFrom, is a good initial guess for first correction."
	increment := 0.5 / (dx max: dy) min: 0.5.
	t := 0.0.
	[
		t0 := t. x0 := x. y0 := y.
		"Compute next point"
		t := t0 + increment. oneLessT := 1.0 - t.
		f1 := oneLessT * oneLessT. f2 := 2.0 * oneLessT * t. f3 := t * t.
		x := (f1 * txFrom) + (f2 * txControl) + (f3 * txTo).
		y := (f1 * tyFrom) + (f2 * tyControl) + (f3 * tyTo).
		"Now adjust the increment to aim at the required hop length, and recompute next point."
		dx := x-x0. dy := y-y0.
		length := ((dx*dx) + (dy*dy)) sqrt.
		correction := hop / (length max: 0.1). "Don't grow increment too much in one step. More importantly, don't divide by zero under any circumstances."
		[
			increment := increment * correction.
			t := t0 + increment. oneLessT := 1.0 - t.
			f1 := oneLessT * oneLessT. f2 := 2.0 * oneLessT * t. f3 := t * t.
			x := (f1 * txFrom) + (f2 * txControl) + (f3 * txTo).
			y := (f1 * tyFrom) + (f2 * tyControl) + (f3 * tyTo).
			dx := x-x0. dy := y-y0.
			length := ((dx*dx) + (dy*dy)) sqrt.
			correction := hop / (length max: 0.1). "Don't grow increment too much in one step. More importantly, don't divide by zero under any circumstances."
			correction < 0.99]  whileTrue.		   "Keep adjusting if actual hop would be too big"
		t < 1.0 ]
	whileTrue: [
		dashBitLength = 0.0
			ifTrue: [
				"Chord accumulation: stamp the pen trace as ~2px straight sub-segments,
				each pixel visited once (see slabStampSegmentWPFromX:y:toX:y:).
				Dashed strokes keep the sampled stamper, which drives the dash pattern."
				cdx := x - chordX. cdy := y - chordY.
				(cdx * cdx) + (cdy * cdy) >= 4.0 ifTrue: [
					self slabStampSegmentWPFromX: chordX y: chordY toX: x y: y.
					chordX := x. chordY := y ]]
			ifFalse: [ self updateAlphasWPForX: x y: y ].
		fillA = 0.0 ifFalse: [
			self updateEdgeCountWPAtX: x y: y ].
		self updateContourForX: x y: y ].

	"Case t= 1.0"
	dashBitLength = 0.0
		ifTrue: [ self slabStampSegmentWPFromX: chordX y: chordY toX: txTo y: tyTo ]
		ifFalse: [ self updateAlphasWPForX: txTo y: tyTo ].
	fillA = 0.0 ifFalse: [
		self updateEdgeCountWPAtX: txTo y: tyTo ].
	self updateContourForX: txTo y: tyTo.! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - path algorithms' stamp: 'ML 7/3/2026 21:00'!
pvt_cubicBezierWPFromX: xFrom y: yFrom toX: xTo y: yTo control1X: xControl1 y: yControl1 control2X: xControl2 y: yControl2

	<var: 'xFrom' type: #float>
	<var: 'yFrom' type: #float>
	<var: 'xTo' type: #float>
	<var: 'yTo' type: #float>
	<var: 'xControl1' type: #float>
	<var: 'yControl1' type: #float>
	<var: 'xControl2' type: #float>
	<var: 'yControl2' type: #float>
	| txFrom tyFrom txTo tyTo txControl1 tyControl1 txControl2 tyControl2 dx dy xMinEnd xMaxEnd yMinEnd yMaxEnd t oneLessT increment f1 f23 f2 f3 f4 x y t0 x0 y0 length correction chordX chordY cdx cdy |
	<var: 'chordX' type: #float>
	<var: 'chordY' type: #float>
	<var: 'cdx' type: #float>
	<var: 'cdy' type: #float>
	<var: 'txFrom' type: #float>
	<var: 'tyFrom' type: #float>
	<var: 'txTo' type: #float>
	<var: 'tyTo' type: #float>
	<var: 'txControl1' type: #float>
	<var: 'tyControl1' type: #float>
	<var: 'txControl2' type: #float>
	<var: 'tyControl2' type: #float>
	<var: 'dx' type: #float>
	<var: 'dy' type: #float>
	<var: 't' type: #float>
	<var: 'oneLessT' type: #float>
	<var: 'increment' type: #float>
	<var: 'f1' type: #float>
	<var: 'f23' type: #float>
	<var: 'f2' type: #float>
	<var: 'f3' type: #float>
	<var: 'f4' type: #float>
	<var: 'x' type: #float>
	<var: 'y' type: #float>
	<var: 'xMinEnd' type: #float>
	<var: 'xMaxEnd' type: #float>
	<var: 'yMinEnd' type: #float>
	<var: 'yMaxEnd' type: #float>
	<var: 'length' type: #float>
	<var: 'correction' type: #float>
	<var: 't0' type: #float>
	<var: 'x0' type: #float>
	<var: 'y0' type: #float>
	
	trajectoryLength := 0.0.
	needsFullAlphaCircle := true.
	txFrom := (xFrom * txA11) + (yFrom * txA12) + txA13.
	tyFrom := (xFrom * txA21) + (yFrom * txA22) + txA23.
	txTo := (xTo * txA11) + (yTo * txA12) + txA13.
	tyTo := (xTo * txA21) + (yTo * txA22) + txA23.
	txControl1 := (xControl1 * txA11) + (yControl1 * txA12) + txA13.
	tyControl1 := (xControl1 * txA21) + (yControl1 * txA22) + txA23.
	txControl2 := (xControl2 * txA11) + (yControl2 * txA12) + txA13.
	tyControl2 := (xControl2 * txA21) + (yControl2 * txA22) + txA23.

	"This computed span of the Bezier curve is a bit pessimistic (larger than strict bounds), but safe."
	xMinEnd := txFrom min: txTo.
	xMaxEnd := txFrom max: txTo.
	yMinEnd := tyFrom min: tyTo.
	yMaxEnd := tyFrom max: tyTo.
	spanLeft := spanLeft min: (xMinEnd min: xMinEnd*0.25 + ((txControl1 min: txControl2)*0.75)).
	spanRight := spanRight max: (xMaxEnd max: xMaxEnd*0.25 + ((txControl1 max: txControl2)*0.75)).
	spanTop := spanTop min: (yMinEnd min: yMinEnd*0.25 + ((tyControl1 min: tyControl2)*0.75)).
	spanBottom := spanBottom max: (yMaxEnd max: yMaxEnd*0.25 + ((tyControl1 max: tyControl2)*0.75)).

	"Case t = 0.0"
	x := txFrom.
	y := tyFrom.
	dashBitLength = 0.0
		ifTrue: [ chordX := x. chordY := y ]
		ifFalse: [ self updateAlphasWPForX: x y: y ].
	fillA = 0.0 ifFalse: [
		self updateEdgeCountWPAtX: x y: y ].
	self updateContourForX: x y: y.

	dx := (txTo-txFrom) abs.
	dy := (tyTo-tyFrom) abs.
	
	"Will be corrected for each hop. This, being close to pointFrom, is a good initial guess for first correction."
	increment := 0.5 / (dx max: dy) min: 0.5.
	t := 0.0.
	[
		t0 := t. x0 := x. y0 := y.
		"Compute next point"
		t := t0 + increment. oneLessT := 1.0 - t.
		f1 := oneLessT * oneLessT * oneLessT. f23 := 3.0 * oneLessT * t. f2 := f23 * oneLessT. f3 := f23 * t. f4 := t * t * t.
		x := (f1 * txFrom) + (f2 * txControl1) + (f3 * txControl2) + (f4 * txTo).
		y := (f1 * tyFrom) + (f2 * tyControl1) + (f3 * tyControl2) + (f4 * tyTo).
		"Now adjust the increment to aim at the required hop length, and recompute next point."
		dx := x-x0. dy := y-y0.
		length := ((dx*dx) + (dy*dy)) sqrt.
		correction := hop / (length max: 0.1). "Don't grow increment too much in one step. More importantly, don't divide by zero under any circumstances."
		[
			increment := increment * correction.
			t := t0 + increment. oneLessT := 1.0 - t.
			f1 := oneLessT * oneLessT * oneLessT. f23 := 3.0 * oneLessT * t. f2 := f23 * oneLessT. f3 := f23 * t. f4 := t * t * t.
			x := (f1 * txFrom) + (f2 * txControl1) + (f3 * txControl2) + (f4 * txTo).
			y := (f1 * tyFrom) + (f2 * tyControl1) + (f3 * tyControl2) + (f4 * tyTo).
			dx := x-x0. dy := y-y0.
			length := ((dx*dx) + (dy*dy)) sqrt.
			correction := hop / (length max: 0.1). "Don't grow increment too much in one step. More importantly, don't divide by zero under any circumstances."
			correction < 0.99]  whileTrue.		   "Keep adjusting if actual hop would be too big"
		t < 1.0 ]
	whileTrue: [
		dashBitLength = 0.0
			ifTrue: [
				"Chord accumulation: stamp the pen trace as ~2px straight sub-segments,
				each pixel visited once (see slabStampSegmentWPFromX:y:toX:y:).
				Dashed strokes keep the sampled stamper, which drives the dash pattern."
				cdx := x - chordX. cdy := y - chordY.
				(cdx * cdx) + (cdy * cdy) >= 4.0 ifTrue: [
					self slabStampSegmentWPFromX: chordX y: chordY toX: x y: y.
					chordX := x. chordY := y ]]
			ifFalse: [ self updateAlphasWPForX: x y: y ].
		fillA = 0.0 ifFalse: [
			self updateEdgeCountWPAtX: x y: y ].
		self updateContourForX: x y: y ].

	"Case t= 1.0"
	dashBitLength = 0.0
		ifTrue: [ self slabStampSegmentWPFromX: chordX y: chordY toX: txTo y: tyTo ]
		ifFalse: [ self updateAlphasWPForX: txTo y: tyTo ].
	fillA = 0.0 ifFalse: [
		self updateEdgeCountWPAtX: txTo y: tyTo ].
	self updateContourForX: txTo y: tyTo.! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - blend stroke and fill' stamp: 'ML 7/3/2026 21:00'!
blendFillOnlyWPLeft: l top: t right: r bottom: b
	"Blends fill color over background.
	WP: Whole pixel anti aliasing.
	If targetAssumedOpaque is false, target translucency is computed correctly.
	If targetAssumedOpaque is true (and target translucency is actually 255 on input), an optimization is made and target translucency is set to 255.
	For blending, alphas are in [0 .. 1.0] and R, G, B color components are in [0 .. 255]"
	| pixelIndex edgesUpToThisPixel edgesThisPixel strokeAntiAliasAlphaBits clippingSpecL clippingSpecR clippingSpecIndex antiAliasedClippedLeftPixel antiAliasedClippedRightPixel mustResetColor realFillAlpha opaqueFillColorWord realOpaqueFillColorWord auxR auxG auxB displayX affectedBitsIndex segmentLength alphasOrEdgeCountsInThisSegment lastSegmentIndex aux1 runLen runSafe targetWord2 bulkAlpha bulkUnAlpha bulkTargetAlpha bulkResultAlpha bulkFR bulkFG bulkFB bulkR bulkG bulkB |
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
				no clipping effects. No per-pixel byte checks are needed at all."
				opaqueFillColorWord ~= 0
					ifTrue: [
						1 to: runLen do: [ :idx2 |
							targetBits at: pixelIndex put: opaqueFillColorWord.
							morphIds at: pixelIndex put: currentMorphId.
							pixelIndex := pixelIndex + 1 ]]
					ifFalse: [
						"Same math as blendFillOnlyWPAt: with alpha byte 127 over an opaque
						target, constants hoisted. Only taken when the hoisted divisors are
						exactly 1.0, so results stay bit-identical without the divides."
						1 to: runLen do: [ :idx2 |
							targetWord2 := targetBits at: pixelIndex.
							bulkR := bulkFR + (bulkUnAlpha * ((targetWord2 bitAnd: 16rFF0000) bitShift: -16)).
							bulkG := bulkFG + (bulkUnAlpha * ((targetWord2 bitAnd: 16rFF00) bitShift: -8)).
							bulkB := bulkFB + (bulkUnAlpha * (targetWord2 bitAnd: 16rFF)).
							targetWord2 := ((16rFF000000 bitOr: ((bulkR + 0.5) asInteger bitShift: 16)) bitOr: ((bulkG + 0.5) asInteger bitShift: 8)) bitOr: (bulkB + 0.5) asInteger.
							targetBits at: pixelIndex put: targetWord2.
							morphIds at: pixelIndex put: currentMorphId.
							pixelIndex := pixelIndex + 1 ]].
				displayX := displayX + runLen ]
			ifFalse: [
			alphasOrEdgeCountsInThisSegment  | (edgesUpToThisPixel ~= 0) ifTrue: [
				aux1 := r-displayX+1.
				1 to: (segmentLength min: aux1) do: [ :idx |
					
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
					pixelIndex := pixelIndex + 1 ]]
			ifFalse: [				"All alphas and edgeCounts are zero in this segment of length delta"
				displayX := displayX + segmentLength.
				pixelIndex := pixelIndex + segmentLength ] ] ].
		
		clippingSpecIndex := clippingSpecIndex + 2 ].! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - blend stroke and fill' stamp: 'ML 7/3/2026 21:00'!
blendStrokeAndFillWPLeft: l top: t right: r bottom: b
	"Blends stroke color and fill color over background.
	Do an appropriate (anti aliased) gradient between stoke color and fill color (or pick just stroke or just fill). Blend this over background.
	WP: Whole pixel anti aliasing.
	If targetAssumedOpaque is false, target translucency is computed correctly.
	If targetAssumedOpaque is true (and target translucency is actually 255 on input), an optimization is made and target translucency is set to 255.
	For blending, alphas are in [0 .. 1.0] and R, G, B color components are in [0 .. 255]"
	| pixelIndex edgesUpToThisPixel edgesThisPixel strokeAntiAliasAlphaBits clippingSpecL clippingSpecR clippingSpecIndex antiAliasedClippedLeftPixel antiAliasedClippedRightPixel mustResetColor realStrokeAlpha realFillAlpha opaqueStrokeColorWord opaqueFillColorWord realOpaqueStrokeColorWord realOpaqueFillColorWord auxR auxG auxB displayX affectedBitsIndex segmentLength alphasOrEdgeCountsInThisSegment lastSegmentIndex aux1 runLen runSafe targetWord2 bulkAlpha bulkUnAlpha bulkTargetAlpha bulkResultAlpha bulkFR bulkFG bulkFB bulkR bulkG bulkB |
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
				no clipping effects. No per-pixel byte checks are needed at all."
				opaqueFillColorWord ~= 0
					ifTrue: [
						1 to: runLen do: [ :idx2 |
							targetBits at: pixelIndex put: opaqueFillColorWord.
							morphIds at: pixelIndex put: currentMorphId.
							pixelIndex := pixelIndex + 1 ]]
					ifFalse: [
						"Same math as blendFillOnlyWPAt: with alpha byte 127 over an opaque
						target, constants hoisted. Only taken when the hoisted divisors are
						exactly 1.0, so results stay bit-identical without the divides."
						1 to: runLen do: [ :idx2 |
							targetWord2 := targetBits at: pixelIndex.
							bulkR := bulkFR + (bulkUnAlpha * ((targetWord2 bitAnd: 16rFF0000) bitShift: -16)).
							bulkG := bulkFG + (bulkUnAlpha * ((targetWord2 bitAnd: 16rFF00) bitShift: -8)).
							bulkB := bulkFB + (bulkUnAlpha * (targetWord2 bitAnd: 16rFF)).
							targetWord2 := ((16rFF000000 bitOr: ((bulkR + 0.5) asInteger bitShift: 16)) bitOr: ((bulkG + 0.5) asInteger bitShift: 8)) bitOr: (bulkB + 0.5) asInteger.
							targetBits at: pixelIndex put: targetWord2.
							morphIds at: pixelIndex put: currentMorphId.
							pixelIndex := pixelIndex + 1 ]].
				displayX := displayX + runLen ]
			ifFalse: [
			alphasOrEdgeCountsInThisSegment  | (edgesUpToThisPixel ~= 0) ifTrue: [
				aux1 := r-displayX+1.
				1 to: (segmentLength min: aux1) do: [ :idx |
					
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
					pixelIndex := pixelIndex + 1 ]]
			ifFalse: [				"All alphas and edgeCounts are zero in this segment of length delta"
				displayX := displayX + segmentLength.
				pixelIndex := pixelIndex + segmentLength ] ] ].
		
		clippingSpecIndex := clippingSpecIndex + 2 ].! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - text and multi paths' stamp: 'ML 7/3/2026 23:00'!
extractCoverageWPLeft: l top: t right: r bottom: b into: aByteArray pitch: pitch
	"Read back the coverage (0..127) that blendFillOnlyWP would have applied for the
	currently stamped shape into aByteArray (row major, origin at l@t, pitch bytes per
	row), consuming and clearing the scratch buffers exactly like the blend does.
	Used to bake glyph coverage tiles: stamp a glyph as usual, then extract its
	coverage once and composite the cached tile from then on
	(see blendCoverageRunWP:meta:count:)."

	| pixelIndex edgesUpToThisPixel edgesThisPixel strokeAntiAliasAlphaBits outIndex cov affectedBitsIndex |
	<var: 'edgesThisPixel' type: #'uint8_t'>
	<var: 'edgesUpToThisPixel' type: #'uint8_t'>
	<var: 'strokeAntiAliasAlphaBits' type: #'uint8_t'>
	<var: 'cov' type: #'uint8_t'>
	self
		primitive: 'primExtractCoverageWP'
		parameters: #(SmallInteger SmallInteger SmallInteger SmallInteger ByteArray SmallInteger).

	t to: b do: [ :displayY |
		edgesUpToThisPixel := 0.
		pixelIndex := displayY * targetWidth + l.
		outIndex := (displayY - t) * pitch.
		l to: r do: [ :displayX |
			edgesThisPixel := edgeCountsWP at: pixelIndex.
			edgesThisPixel = 0 ifFalse: [
				edgeCountsWP at: pixelIndex put: 0.
				self cCode: nil inSmalltalk: [
					edgesThisPixel > 127 ifTrue: [ edgesThisPixel := edgesThisPixel - 256 ]].
				edgesUpToThisPixel := edgesUpToThisPixel + edgesThisPixel ].
			strokeAntiAliasAlphaBits := alphaMaskWP at: pixelIndex.
			strokeAntiAliasAlphaBits = 16r00 ifFalse: [ alphaMaskWP at: pixelIndex put: 0 ].
			cov := edgesUpToThisPixel = 0
				ifTrue: [ strokeAntiAliasAlphaBits ]
				ifFalse: [ 16r7F - strokeAntiAliasAlphaBits ].
			aByteArray at: outIndex put: cov.
			outIndex := outIndex + 1.
			pixelIndex := pixelIndex + 1 ].
		"Clear the dirty-segment bits this row touched, like the blend would."
		affectedBitsIndex := (displayY * targetWidth + l) >> 4.
		[ affectedBitsIndex <= ((displayY * targetWidth + r) >> 4) ] whileTrue: [
			affectedBits at: affectedBitsIndex put: 0.
			affectedBitsIndex := affectedBitsIndex + 1 ]]! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - text and multi paths' stamp: 'ML 7/3/2026 23:00'!
blendCoverageRunWP: sheet meta: metaArray count: n
	"Composite n cached coverage tiles (glyphs) using the current fill color.
	metaArray holds 5 words per tile: destX destY w h sheetOffset -- destination in
	pixels (already clipped by the caller to lie fully inside the clip rect), tile
	size, and the tile's byte offset into sheet (row major, pitch = w).
	Assumes targetAssumedOpaque (callers fall back to the outline path otherwise).
	Coverage 127 with an opaque fill takes the overwrite fast path; other coverages
	blend exactly like blendFillOnlyWPAt: does over an opaque target."

	| base dx dy w h off pixelIndex sIndex cov opaqueWord auxR auxG auxB covAlpha covUnAlpha covR covG covB targetWord |
	<var: 'cov' type: #'uint8_t'>
	<var: 'opaqueWord' type: #'uint32_t'>
	<var: 'auxR' type: #'uint32_t'>
	<var: 'auxG' type: #'uint32_t'>
	<var: 'auxB' type: #'uint32_t'>
	<var: 'targetWord' type: #'uint32_t'>
	<var: 'covAlpha' type: #float>
	<var: 'covUnAlpha' type: #float>
	<var: 'covR' type: #float>
	<var: 'covG' type: #float>
	<var: 'covB' type: #float>
	self
		primitive: 'primBlendCoverageRunWP'
		parameters: #(ByteArray WordArray SmallInteger).

	opaqueWord := 0.
	fillA = 1.0 ifTrue: [
		auxR := (fillR + 0.5) asInteger bitShift: 16.
		auxG := (fillG + 0.5) asInteger bitShift: 8.
		auxB := (fillB + 0.5) asInteger.
		opaqueWord := ((16rFF000000 bitOr: auxR) bitOr: auxG) bitOr: auxB ].
	1 to: n do: [ :g |
		base := g - 1 * 5.
		dx := metaArray at: base.
		dy := metaArray at: base + 1.
		w := metaArray at: base + 2.
		h := metaArray at: base + 3.
		off := metaArray at: base + 4.
		0 to: h - 1 do: [ :row |
			pixelIndex := (dy + row) * targetWidth + dx.
			sIndex := off + (row * w).
			0 to: w - 1 do: [ :col |
				cov := sheet at: sIndex + col.
				cov = 0 ifFalse: [
					(cov = 16r7F and: [opaqueWord ~= 0])
						ifTrue: [
							targetBits at: pixelIndex put: opaqueWord.
							morphIds at: pixelIndex put: currentMorphId ]
						ifFalse: [
							covAlpha := cov * (1.0 / 127.0).
							covAlpha := covAlpha * fillA.
							covUnAlpha := 1.0 - covAlpha.
							targetWord := targetBits at: pixelIndex.
							covR := covAlpha * fillR + (covUnAlpha * ((targetWord bitAnd: 16rFF0000) bitShift: -16)).
							covG := covAlpha * fillG + (covUnAlpha * ((targetWord bitAnd: 16rFF00) bitShift: -8)).
							covB := covAlpha * fillB + (covUnAlpha * (targetWord bitAnd: 16rFF)).
							targetWord := ((16rFF000000 bitOr: ((covR + 0.5) asInteger bitShift: 16)) bitOr: ((covG + 0.5) asInteger bitShift: 8)) bitOr: (covB + 0.5) asInteger.
							targetBits at: pixelIndex put: targetWord.
							morphIds at: pixelIndex put: currentMorphId ]].
				pixelIndex := pixelIndex + 1 ]]]! !

!VectorEnginePlugin methodsFor: 'whole pixel anti aliased - text and multi paths' stamp: 'ML 7/4/2026 12:00'!
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

