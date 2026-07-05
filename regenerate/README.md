# Regenerating the C from Slang

`generated/VectorEnginePlugin.c` is committed, so **you only need this if you change
the Slang sources in `../slang/`.** The C is produced by VMMaker's Slang→C translator
from the plugin methods; this directory holds the scripts to run it headless.

## 1. Build a VMMaker image (once)

Use a **Squeak trunk** image (6.1alpha or newer) — the release 6.0 image is missing
methods VMMaker.oscog needs (`CompiledMethod>>pragmasDo:`, `ParseNode>>is:`,
`Compiler-ct`). Download one from <https://files.squeak.org/trunk/> and load VMMaker
plus the base VE plugin into it:

```
Squeak Squeak6.1alpha-XXXXX-64bit.image load_all.st
```

`load_all.st` Installer-loads `VMMaker.oscog-eem.3767` (+ CogPools/BytecodeSets/Cog/
ImageFormat) from source.squeak.org and `VectorEnginePlugin-jmv.26` from squeaksource,
then saves the image. That saved image is your reusable generator.

## 2. Generate

From this directory, run `generate.st` in the VMMaker image:

```
Squeak <the-saved-VMMaker>.image generate.st
```

It files in `../slang/SlabStamping.st`, runs
`VectorEnginePlugin translateInDirectory:doInlining:`, and writes
`gen/VectorEnginePlugin.c`. Diff it against `../generated/VectorEnginePlugin.c`
(they should match modulo the VMMaker/compiler version banner), then promote it.

## Headless gotchas (each hangs as an invisible modal otherwise)

- Set `Utilities setAuthorInitials:` first — any compile otherwise pops an author prompt.
- Wrap in `valueSupplyingAnswer: true` **and** catch `ProgressInitiationException`
  (`sendNotificationsTo: [:a :b :c|]`) — both scripts already do.
- `translateInDirectory:` silently **skips** if the output `.c` is newer than the
  code — delete `gen/` first for a clean run.
- End scripts with `Smalltalk quitPrimitive` (a normal `snapshot:andQuit:` can hang
  headless).
- Slang 64-bit locals must be typed `#'usqLong'`, **not** `uint64_t` (the generator's
  `sizeOfIntegralCType:` rejects the latter). The `slang/` sources already do this.
