package ob.utils
{
    import flash.display.BitmapData;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.geom.Point;
    import flash.geom.Rectangle;
    import flash.utils.ByteArray;
    import flash.utils.CompressionAlgorithm;
    import flash.utils.Dictionary;
    import flash.utils.Endian;

    import otlib.animation.FrameDuration;
    import otlib.animation.FrameGroup;
    import otlib.obd.OBDVersions;
    import otlib.sprites.SpriteData;
    import otlib.things.FrameGroupType;
    import otlib.things.ThingCategory;
    import otlib.things.ThingData;
    import otlib.things.ThingType;

    public final class ModernAssetsImporter
    {
        public static function importRange(directory:File,
                category:String,
                fromId:uint,
                toId:uint,
                clientVersion:uint):Vector.<ThingData>
        {
            if (!directory || !directory.exists || !directory.isDirectory)
                throw new Error("Invalid modern assets directory.");

            var catalogFile:File = directory.resolvePath("catalog-content.json");
            if (!catalogFile.exists)
                throw new Error("catalog-content.json was not found.");

            var catalog:Array = JSON.parse(readText(catalogFile)) as Array;
            if (!catalog)
                throw new Error("Invalid catalog-content.json.");

            var appearancesFile:File;
            var sheets:Array = [];
            for each (var entry:Object in catalog)
            {
                if (entry.type == "appearances")
                    appearancesFile = directory.resolvePath(String(entry.file));
                else if (entry.type == "sprite")
                    sheets.push(new ModernSheet(directory,
                            String(entry.file),
                            uint(entry.firstspriteid),
                            uint(entry.lastspriteid),
                            uint(entry.spritetype)));
            }

            if (!appearancesFile || !appearancesFile.exists)
                throw new Error("The appearances file declared by the catalog was not found.");
            if (sheets.length == 0)
                throw new Error("No sprite sheets were declared by the catalog.");

            sheets.sortOn("firstId", Array.NUMERIC);
            var bytes:ByteArray = readBytes(appearancesFile);
            var reader:ProtoReader = new ProtoReader(bytes);
            var categoryField:uint = categoryToField(category);
            var result:Vector.<ThingData> = new Vector.<ThingData>();

            while (!reader.end)
            {
                var tag:Object = reader.readTag();
                if (tag.wire == 2 && tag.field >= 1 && tag.field <= 4)
                {
                    var appearanceBytes:ByteArray = reader.readLengthBytes();
                    if (tag.field == categoryField)
                    {
                        var appearance:Object = parseAppearance(appearanceBytes);
                        if (appearance && appearance.id >= fromId && appearance.id <= toId)
                        {
                            var thingData:ThingData = buildThingData(appearance, category, sheets, clientVersion);
                            if (thingData)
                                result.push(thingData);
                        }
                    }
                }
                else
                {
                    reader.skip(tag.wire);
                }
            }

            for each (var sheet:ModernSheet in sheets)
                sheet.dispose();
            return result;
        }

        private static function parseAppearance(bytes:ByteArray):Object
        {
            var reader:ProtoReader = new ProtoReader(bytes);
            var result:Object = {id: 0, name: null, groups: []};
            while (!reader.end)
            {
                var tag:Object = reader.readTag();
                if (tag.field == 1 && tag.wire == 0)
                    result.id = reader.readVarint();
                else if (tag.field == 2 && tag.wire == 2)
                {
                    var group:Object = parseFrameGroup(reader.readLengthBytes());
                    if (group)
                        result.groups.push(group);
                }
                else if (tag.field == 4 && tag.wire == 2)
                    result.name = bytesToString(reader.readLengthBytes());
                else
                    reader.skip(tag.wire);
            }
            return result.id && result.groups.length ? result : null;
        }

        private static function parseFrameGroup(bytes:ByteArray):Object
        {
            var reader:ProtoReader = new ProtoReader(bytes);
            var fixed:uint = 0;
            var spriteInfo:Object;
            while (!reader.end)
            {
                var tag:Object = reader.readTag();
                if (tag.field == 1 && tag.wire == 0)
                    fixed = reader.readVarint();
                else if (tag.field == 3 && tag.wire == 2)
                    spriteInfo = parseSpriteInfo(reader.readLengthBytes());
                else
                    reader.skip(tag.wire);
            }
            return spriteInfo ? {fixed: fixed, info: spriteInfo} : null;
        }

        private static function parseSpriteInfo(bytes:ByteArray):Object
        {
            var reader:ProtoReader = new ProtoReader(bytes);
            var result:Object = {patternX: 1, patternY: 1, patternZ: 1, layers: 1,
                    sprites: [], frames: 1, durations: []};
            while (!reader.end)
            {
                var tag:Object = reader.readTag();
                if (tag.field >= 1 && tag.field <= 4 && tag.wire == 0)
                {
                    var value:uint = reader.readVarint();
                    if (tag.field == 1) result.patternX = value;
                    else if (tag.field == 2) result.patternY = value;
                    else if (tag.field == 3) result.patternZ = value;
                    else result.layers = value;
                }
                else if (tag.field == 5)
                {
                    if (tag.wire == 2)
                    {
                        var packed:ProtoReader = new ProtoReader(reader.readLengthBytes());
                        while (!packed.end)
                            result.sprites.push(packed.readVarint());
                    }
                    else if (tag.wire == 0)
                    {
                        result.sprites.push(reader.readVarint());
                    }
                    else
                    {
                        reader.skip(tag.wire);
                    }
                }
                else if (tag.field == 6 && tag.wire == 2)
                {
                    var animation:Object = parseAnimation(reader.readLengthBytes());
                    result.frames = animation.frames;
                    result.durations = animation.durations;
                }
                else
                    reader.skip(tag.wire);
            }
            return result;
        }

        private static function parseAnimation(bytes:ByteArray):Object
        {
            var reader:ProtoReader = new ProtoReader(bytes);
            var durations:Array = [];
            while (!reader.end)
            {
                var tag:Object = reader.readTag();
                if ((tag.field == 5 || tag.field == 6) && tag.wire == 2)
                {
                    durations.push(parsePhase(reader.readLengthBytes()));
                }
                else
                    reader.skip(tag.wire);
            }
            if (durations.length == 0)
                durations.push({minimum: 100, maximum: 100});
            return {frames: durations.length, durations: durations};
        }

        private static function parsePhase(bytes:ByteArray):Object
        {
            var reader:ProtoReader = new ProtoReader(bytes);
            var values:Array = [];
            while (!reader.end)
            {
                var tag:Object = reader.readTag();
                if (tag.wire == 0)
                    values.push(reader.readVarint());
                else
                    reader.skip(tag.wire);
            }
            var minimum:uint = values.length > 0 && values[0] > 0 ? uint(values[0]) : 100;
            var maximum:uint = values.length > 1 && values[1] >= minimum ? uint(values[1]) : minimum;
            return {minimum: minimum, maximum: maximum};
        }

        private static function buildThingData(appearance:Object,
                category:String,
                sheets:Array,
                clientVersion:uint):ThingData
        {
            var thing:ThingType = new ThingType();
            thing.id = appearance.id;
            thing.category = category;
            thing.name = appearance.name;
            var spriteGroups:Dictionary = new Dictionary();

            for each (var modernGroup:Object in appearance.groups)
            {
                var info:Object = modernGroup.info;
                if (!info.sprites || info.sprites.length == 0)
                    continue;

                var firstSheet:ModernSheet = findSheet(sheets, uint(info.sprites[0]));
                if (!firstSheet)
                    continue;

                var groupType:uint = category == ThingCategory.OUTFIT && modernGroup.fixed == 1 ?
                        FrameGroupType.WALKING : FrameGroupType.DEFAULT;
                var group:FrameGroup = new FrameGroup();
                group.width = firstSheet.spriteWidth / 32;
                group.height = firstSheet.spriteHeight / 32;
                group.exactSize = Math.max(firstSheet.spriteWidth, firstSheet.spriteHeight);
                group.layers = info.layers;
                group.patternX = info.patternX;
                group.patternY = info.patternY;
                group.patternZ = info.patternZ;
                group.frames = info.frames;
                group.isAnimation = group.frames > 1;
                group.spriteIndex = new Vector.<uint>(group.getTotalSprites(), true);
                group.frameDurations = new Vector.<FrameDuration>(group.frames, true);
                for (var durationIndex:uint = 0; durationIndex < group.frames; durationIndex++)
                {
                    var duration:Object = durationIndex < info.durations.length ? info.durations[durationIndex] : null;
                    group.frameDurations[durationIndex] = new FrameDuration(duration ? duration.minimum : 100,
                            duration ? duration.maximum : 100);
                }

                var sprites:Vector.<SpriteData> = new Vector.<SpriteData>(group.getTotalSprites(), true);
                var modernIndex:uint = 0;
                for (var frame:uint = 0; frame < group.frames; frame++)
                for (var z:uint = 0; z < group.patternZ; z++)
                for (var y:uint = 0; y < group.patternY; y++)
                for (var x:uint = 0; x < group.patternX; x++)
                for (var layer:uint = 0; layer < group.layers; layer++)
                {
                    var realSpriteId:uint = modernIndex < info.sprites.length ? uint(info.sprites[modernIndex]) : 0;
                    modernIndex++;
                    var full:BitmapData = loadModernSprite(sheets, realSpriteId);
                    for (var h:uint = 0; h < group.height; h++)
                    for (var w:uint = 0; w < group.width; w++)
                    {
                        var legacyIndex:uint = group.getSpriteIndex(w, h, layer, x, y, z, frame);
                        var tile:BitmapData = new BitmapData(32, 32, true, 0);
                        if (full)
                        {
                            var sourceRect:Rectangle = new Rectangle((group.width - 1 - w) * 32,
                                    (group.height - 1 - h) * 32, 32, 32);
                            tile.copyPixels(full, sourceRect, new Point());
                        }
                        var spriteData:SpriteData = SpriteData.createSpriteData(uint.MAX_VALUE, tile.getPixels(tile.rect));
                        sprites[legacyIndex] = spriteData;
                        group.spriteIndex[legacyIndex] = uint.MAX_VALUE;
                        tile.dispose();
                    }
                    if (full)
                        full.dispose();
                }
                thing.setFrameGroup(groupType, group);
                spriteGroups[groupType] = sprites;
            }

            return thing.getFrameGroup(FrameGroupType.DEFAULT) ?
                    ThingData.create(OBDVersions.OBD_VERSION_3, clientVersion, thing, spriteGroups) : null;
        }

        private static function loadModernSprite(sheets:Array, id:uint):BitmapData
        {
            if (id == 0)
                return null;
            var sheet:ModernSheet = findSheet(sheets, id);
            return sheet ? sheet.getSprite(id) : null;
        }

        private static function findSheet(sheets:Array, id:uint):ModernSheet
        {
            var low:int = 0;
            var high:int = sheets.length - 1;
            while (low <= high)
            {
                var middle:int = (low + high) >> 1;
                var sheet:ModernSheet = sheets[middle];
                if (id < sheet.firstId) high = middle - 1;
                else if (id > sheet.lastId) low = middle + 1;
                else return sheet;
            }
            return null;
        }

        private static function categoryToField(category:String):uint
        {
            if (category == ThingCategory.ITEM) return 1;
            if (category == ThingCategory.OUTFIT) return 2;
            if (category == ThingCategory.EFFECT) return 3;
            if (category == ThingCategory.MISSILE) return 4;
            throw new Error("Unsupported category.");
        }

        private static function bytesToString(bytes:ByteArray):String
        {
            bytes.position = 0;
            return bytes.readUTFBytes(bytes.length);
        }

        private static function readText(file:File):String
        {
            var bytes:ByteArray = readBytes(file);
            return bytesToString(bytes);
        }

        private static function readBytes(file:File):ByteArray
        {
            var stream:FileStream = new FileStream();
            var bytes:ByteArray = new ByteArray();
            stream.open(file, FileMode.READ);
            stream.readBytes(bytes);
            stream.close();
            bytes.position = 0;
            bytes.endian = Endian.LITTLE_ENDIAN;
            return bytes;
        }
    }
}
