# Fix: Bulk Replace Objects Unknown Source Client Version

## Problem

`Bulk Replace Objects` could fail when loading a valid external `DAT/SPR` pair with an error like:

```text
Unknown source client version (DAT sig: 2474191948, SPR sig: 2483364428)
```

The files were valid, but the signatures shown in the error were byte-swapped. For example, a valid Tibia 8.60 pair:

```text
DAT: 0x4C2C7993
SPR: 0x4C220594
```

was being read as:

```text
DAT: 0x93792C4C
SPR: 0x9405224C
```

Because those swapped values do not exist in `config/versions.xml`, the source client was rejected as unknown.

## Root Cause

The normal DAT/SPR loaders read file headers using little-endian byte order, but the Bulk Replace source-file header reader did not set the `FileStream` endian value before calling `readUnsignedInt()`.

Adobe AIR `FileStream` defaults to big-endian unless explicitly changed. Tibia DAT/SPR signatures are stored little-endian, so Bulk Replace was reading the correct 4 bytes in the wrong byte order.

## Fix

Set both source file streams to `Endian.LITTLE_ENDIAN` before reading the DAT and SPR signatures.

```actionscript
import flash.utils.Endian;
```

```actionscript
var datStream:FileStream = new FileStream();
datStream.endian = Endian.LITTLE_ENDIAN;
datStream.open(sourceDatFile, FileMode.READ);
datSignature = datStream.readUnsignedInt();
datStream.close();

var sprStream:FileStream = new FileStream();
sprStream.endian = Endian.LITTLE_ENDIAN;
sprStream.open(sourceSprFile, FileMode.READ);
sprSignature = sprStream.readUnsignedInt();
sprStream.close();
```

## Files Changed

- `src/ObjectBuilderWorker.as`

## Verification

After the fix, Bulk Replace reads the same signatures as the regular client loader and can resolve known versions through:

```actionscript
VersionStorage.getInstance().getBySignatures(datSignature, sprSignature);
```

The project was compiled successfully after the change:

```text
workerswfs/ObjectBuilderWorker.swf
bin-debug/ObjectBuilder.swf
bin/ObjectBuilder/ObjectBuilder.exe
```

## Result

Bulk Replace no longer rejects valid source clients because of byte-swapped DAT/SPR signatures.
