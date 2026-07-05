"Regenerate generated/VectorEnginePlugin.c from the Slang sources in slang/.
 Run inside the VMMaker image built by load_all.st (see regenerate/README.md).
 Invoke headless with this file as the -s script, from the regenerate/ directory:

   Squeak VMMaker.image generate.st

 The output lands in ./gen/VectorEnginePlugin.c; diff it against
 ../generated/VectorEnginePlugin.c to confirm, then move it into place."
| dir log ctx base |
Utilities setAuthorInitials: 'ML'.
base := '../slang/'.
log := FileStream forceNewFileNamed: 'generate-log.txt'.
"VMMaker.oscog-eem.3767's code generator can leave a boolean in its logger ivar;
 the warning path then crashes on Transcript protocol. Fall back to Transcript."
CCodeGenerator compile: 'logger
	^ (logger isNil or: [logger == true or: [logger == false]])
		ifTrue: [Transcript]
		ifFalse: [logger]' classified: '*vmmaker-compatibility'.
[[[[
	#('SlabStamping5.st' 'SlabStamping6.st' 'SlabStamping7.st' 'SlabStamping8.st' 'SlabStamping9.st')
		do: [:f | (FileStream readOnlyFileNamed: base, f) fileIn].
	log nextPutAll: 'slang filed in'; cr; flush.
	dir := FileDirectory default directoryNamed: 'gen'.
	dir assureExistence.
	VectorEnginePlugin translateInDirectory: dir doInlining: true.
	log nextPutAll: 'translated -> gen/VectorEnginePlugin.c'; cr; flush]
	on: ProgressInitiationException
	do: [:e | e sendNotificationsTo: [:min :max :current | ]]]
	on: Warning do: [:w | log nextPutAll: 'WARN: ', w messageText; cr; flush. w resume: true]]
	on: Error do: [:e |
		log nextPutAll: 'ERROR: ', e class name, ' -- ', e messageText asString; cr.
		ctx := e signalerContext.
		1 to: 14 do: [:i | ctx ifNotNil: [log nextPutAll: '  ', ctx printString; cr. ctx := ctx sender]].
		log flush]] valueSupplyingAnswer: true.
log nextPutAll: 'done'; cr.
log close.
Smalltalk quitPrimitive.
