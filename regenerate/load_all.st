| log installer |
Utilities setAuthorInitials: 'ML'.
log := FileStream forceNewFileNamed: 'load-all.txt'.
[[[
log nextPutAll: 'compiler version: ', (SystemVersion current version); cr; flush.
log nextPutAll: 'LiteralNode has is:? ', (LiteralNode canUnderstand: #is:) printString; cr; flush.
log nextPutAll: 'CompiledMethod has pragmasDo:? ', (CompiledMethod canUnderstand: #pragmasDo:) printString; cr; flush.
log nextPutAll: 'loading VMMaker group...'; cr; flush.
installer := Installer squeak.
installer project: 'VMMaker'.
installer packages addAll: #('CogPools-ISAs' 'BytecodeSets.spur' 'VMMaker.oscog-eem.3767' 'Cog' 'ImageFormat').
installer installQuietly.
log nextPutAll: 'loading VectorEnginePlugin-jmv.26...'; cr; flush.
installer := Installer squeaksource.
installer project: 'VectorEnginePlugin'.
installer packages addAll: #('VectorEnginePlugin-jmv.26').
installer installQuietly.
log nextPutAll: 'loaded. VEP: ', (Smalltalk includesKey: #VectorEnginePlugin) printString.
log nextPutAll: ' VMMaker: ', (Smalltalk includesKey: #VMMaker) printString; cr; flush]
	on: Warning do: [:w | log nextPutAll: 'WARN: ', w messageText; cr; flush. w resume: true]]
	on: Error do: [:e | log nextPutAll: 'ERROR: ', e class name, ' -- ', e messageText asString; cr; flush]] valueSupplyingAnswer: true.
log close.
Smalltalk snapshot: true andQuit: true.
