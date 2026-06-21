/*
*  Copyright (c) 2014-2023 Object Builder <https://github.com/ottools/ObjectBuilder>
*
*  Permission is hereby granted, free of charge, to any person obtaining a copy
*  of this software and associated documentation files (the "Software"), to deal
*  in the Software without restriction, including without limitation the rights
*  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
*  copies of the Software, and to permit persons to whom the Software is
*  furnished to do so, subject to the following conditions:
*
*  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
*  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
*  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
*  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
*  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
*  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
*  THE SOFTWARE.
*/

package otlib.utils
{
    import flash.events.EventDispatcher;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.utils.Dictionary;

    import nail.errors.NullArgumentError;

    import ob.commands.ProgressBarID;

    import otlib.animation.FrameDuration;
    import otlib.animation.FrameGroup;
    import otlib.core.ClientFeatures;
    import otlib.core.Version;
    import otlib.events.ProgressEvent;
    import otlib.items.OtbWriter;
    import otlib.items.ServerItem;
    import otlib.items.ServerItemList;
    import otlib.items.ServerItemStorage;
    import otlib.sprites.Sprite;
    import otlib.sprites.SpriteStorage;
    import otlib.things.FrameGroupType;
    import otlib.things.ThingCategory;
    import otlib.things.ThingType;
    import otlib.things.ThingTypeStorage;

    [Event(name="progress", type="otlib.events.ProgressEvent")]

    public class MergedClientCleaner extends EventDispatcher
    {
        private var m_objects:ThingTypeStorage;
        private var m_sprites:SpriteStorage;
        private var m_serverItems:ServerItemStorage;

        private var m_spriteHashes:Dictionary;
        private var m_oldToNewSpriteId:Dictionary;
        private var m_hashToNewSpriteId:Dictionary;
        private var m_newSprites:Dictionary;
        private var m_nextSpriteId:uint;
        private var m_categoryMaps:Dictionary;
        private var m_mappingRows:Array;

        public var oldItemsCount:uint;
        public var oldOutfitsCount:uint;
        public var oldEffectsCount:uint;
        public var oldMissilesCount:uint;
        public var oldSpriteCount:uint;

        public var itemsCount:uint;
        public var outfitsCount:uint;
        public var effectsCount:uint;
        public var missilesCount:uint;
        public var newSpriteCount:uint;

        public var removedItems:uint;
        public var removedOutfits:uint;
        public var removedEffects:uint;
        public var removedMissiles:uint;
        public var duplicateItemsBelowCutoff:uint;
        public var duplicateOutfitsBelowCutoff:uint;
        public var duplicateEffectsBelowCutoff:uint;
        public var duplicateMissilesBelowCutoff:uint;
        public var reusedSpritesCount:uint;
        public var removedSpritesCount:uint;
        public var remappedServerItems:uint;
        public var unresolvedServerItems:uint;

        public function MergedClientCleaner(objects:ThingTypeStorage,
                sprites:SpriteStorage,
                serverItems:ServerItemStorage = null)
        {
            if (!objects)
                throw new NullArgumentError("objects");
            if (!sprites)
                throw new NullArgumentError("sprites");

            m_objects = objects;
            m_sprites = sprites;
            m_serverItems = serverItems;
        }

        public function export(datFile:File,
                sprFile:File,
                mapFile:File,
                otbFile:File,
                version:Version,
                features:ClientFeatures,
                removalCutoff:uint):Boolean
        {
            if (!datFile)
                throw new NullArgumentError("datFile");
            if (!sprFile)
                throw new NullArgumentError("sprFile");
            if (!mapFile)
                throw new NullArgumentError("mapFile");
            if (!version)
                throw new NullArgumentError("version");
            if (!features)
                throw new NullArgumentError("features");
            if (removalCutoff <= ThingTypeStorage.MIN_ITEM_ID)
                throw new ArgumentError("Removal cutoff must be greater than " + ThingTypeStorage.MIN_ITEM_ID + ".");

            initialize();

            dispatchProgress(0, 9, "Indexing merged client objects");
            var itemResult:Object = cleanCategory(m_objects.items,
                    ThingCategory.ITEM,
                    ThingTypeStorage.MIN_ITEM_ID,
                    m_objects.itemsCount,
                    removalCutoff);
            itemsCount = itemResult.count;
            removedItems = itemResult.removed;

            dispatchProgress(1, 9, "Cleaning duplicate outfits");
            var outfitResult:Object = cleanCategory(m_objects.outfits,
                    ThingCategory.OUTFIT,
                    1,
                    m_objects.outfitsCount,
                    removalCutoff);
            outfitsCount = outfitResult.count;
            removedOutfits = outfitResult.removed;

            dispatchProgress(2, 9, "Cleaning duplicate effects");
            var effectResult:Object = cleanCategory(m_objects.effects,
                    ThingCategory.EFFECT,
                    1,
                    m_objects.effectsCount,
                    removalCutoff);
            effectsCount = effectResult.count;
            removedEffects = effectResult.removed;

            dispatchProgress(3, 9, "Cleaning duplicate missiles");
            var missileResult:Object = cleanCategory(m_objects.missiles,
                    ThingCategory.MISSILE,
                    1,
                    m_objects.missilesCount,
                    removalCutoff);
            missilesCount = missileResult.count;
            removedMissiles = missileResult.removed;

            newSpriteCount = m_nextSpriteId > 1 ? m_nextSpriteId - 1 : 1;
            removedSpritesCount = oldSpriteCount > newSpriteCount ? oldSpriteCount - newSpriteCount : 0;

            var compileFeatures:ClientFeatures = features.clone();
            compileFeatures.applyVersionDefaults(version.value);
            if (!compileFeatures.extended && version.value < 960 && newSpriteCount >= 0xFFFF)
                throw new Error("Cleaned SPR still has " + newSpriteCount + " sprites. Enable Extended or use a 9.60+ client version.");

            dispatchProgress(4, 9, "Writing cleaned DAT");
            if (!m_objects.compileCustom(datFile,
                        version,
                        features,
                        itemResult.list,
                        itemsCount,
                        outfitResult.list,
                        outfitsCount,
                        effectResult.list,
                        effectsCount,
                        missileResult.list,
                        missilesCount))
            {
                return false;
            }

            dispatchProgress(5, 9, "Writing cleaned SPR");
            if (!m_sprites.compileCustom(sprFile, version, features, m_newSprites, newSpriteCount))
                return false;

            dispatchProgress(6, 9, "Writing client ID map");
            writeMapping(mapFile);

            if (otbFile && m_serverItems && m_serverItems.loaded)
            {
                dispatchProgress(7, 9, "Writing remapped items.otb");
                if (!writeRemappedOtb(otbFile))
                    return false;
            }
            else
            {
                dispatchProgress(7, 9, "No items.otb loaded; CSV map only");
            }

            dispatchProgress(8, 9, "Merged client cleanup complete");
            return true;
        }

        private function initialize():void
        {
            oldItemsCount = m_objects.itemsCount;
            oldOutfitsCount = m_objects.outfitsCount;
            oldEffectsCount = m_objects.effectsCount;
            oldMissilesCount = m_objects.missilesCount;
            oldSpriteCount = m_sprites.spritesCount;

            removedItems = 0;
            removedOutfits = 0;
            removedEffects = 0;
            removedMissiles = 0;
            duplicateItemsBelowCutoff = 0;
            duplicateOutfitsBelowCutoff = 0;
            duplicateEffectsBelowCutoff = 0;
            duplicateMissilesBelowCutoff = 0;
            reusedSpritesCount = 0;
            removedSpritesCount = 0;
            remappedServerItems = 0;
            unresolvedServerItems = 0;

            m_spriteHashes = new Dictionary();
            m_oldToNewSpriteId = new Dictionary();
            m_hashToNewSpriteId = new Dictionary();
            m_newSprites = new Dictionary();
            m_nextSpriteId = 1;
            m_categoryMaps = new Dictionary();
            m_mappingRows = [];
        }

        private function cleanCategory(list:Dictionary,
                category:String,
                minId:uint,
                maxId:uint,
                removalCutoff:uint):Object
        {
            var output:Dictionary = new Dictionary();
            var oldToNew:Dictionary = new Dictionary();
            var entries:Array = [];
            var groups:Dictionary = new Dictionary();

            for (var id:uint = minId; id <= maxId; id++)
            {
                var thing:ThingType = list[id] as ThingType;
                if (!ThingUtils.isValid(thing) || ThingUtils.isEmpty(thing))
                    continue;

                thing.category = category;
                var key:String = getThingKey(thing);
                var entry:Object = {
                    oldId: id,
                    thing: thing,
                    key: key,
                    removed: false,
                    canonicalOldId: id,
                    newId: 0
                };
                entries.push(entry);

                var group:Array = groups[key] as Array;
                if (!group)
                {
                    group = [];
                    groups[key] = group;
                }
                group.push(entry);
            }

            var duplicatesBelowCutoff:uint = 0;
            for each (group in groups)
            {
                if (group.length < 2)
                    continue;

                var canonical:Object = null;
                for each (entry in group)
                {
                    if (uint(entry.oldId) >= removalCutoff)
                    {
                        canonical = entry;
                        break;
                    }
                }
                if (!canonical)
                    canonical = group[0];

                for each (entry in group)
                {
                    if (entry === canonical)
                        continue;

                    if (uint(entry.oldId) < removalCutoff)
                    {
                        entry.removed = true;
                        entry.duplicate = true;
                        entry.canonicalOldId = canonical.oldId;
                        duplicatesBelowCutoff++;
                    }
                }
            }

            for each (entry in entries)
            {
                if (entry.removed)
                    continue;

                var clone:ThingType = cloneThingWithRemappedSprites(entry.thing as ThingType);
                clone.id = entry.oldId;
                clone.category = category;
                output[entry.oldId] = clone;
                entry.newId = entry.oldId;
                oldToNew[entry.oldId] = entry.oldId;
            }

            for each (entry in entries)
            {
                if (entry.removed)
                {
                    entry.newId = oldToNew[entry.canonicalOldId];
                    oldToNew[entry.oldId] = entry.newId;
                }
                else
                {
                    entry.newId = entry.oldId;
                }

                var original:ThingType = entry.thing as ThingType;
                m_mappingRows.push({
                            category: category,
                            oldId: entry.oldId,
                            newId: entry.newId,
                            status: entry.removed ? "removed_duplicate" : "kept",
                            canonicalOldId: entry.canonicalOldId,
                            name: getThingName(original)
                        });
            }

            switch (category)
            {
                case ThingCategory.ITEM:
                    duplicateItemsBelowCutoff = duplicatesBelowCutoff;
                    break;
                case ThingCategory.OUTFIT:
                    duplicateOutfitsBelowCutoff = duplicatesBelowCutoff;
                    break;
                case ThingCategory.EFFECT:
                    duplicateEffectsBelowCutoff = duplicatesBelowCutoff;
                    break;
                case ThingCategory.MISSILE:
                    duplicateMissilesBelowCutoff = duplicatesBelowCutoff;
                    break;
            }

            m_categoryMaps[category] = oldToNew;
            var count:uint = maxId;
            while (count > minId && output[count] === undefined)
                count--;

            return {
                list: output,
                count: count,
                removed: duplicatesBelowCutoff,
                duplicates: duplicatesBelowCutoff
            };
        }

        private function cloneThingWithRemappedSprites(thing:ThingType):ThingType
        {
            var clone:ThingType = thing.clone();
            for (var groupType:uint = FrameGroupType.DEFAULT; groupType <= FrameGroupType.WALKING; groupType++)
            {
                var group:FrameGroup = clone.getFrameGroup(groupType);
                if (!group || !group.spriteIndex)
                    continue;

                for (var i:uint = 0; i < group.spriteIndex.length; i++)
                    group.spriteIndex[i] = getRemappedSpriteId(group.spriteIndex[i]);
            }
            return clone;
        }

        private function getRemappedSpriteId(oldId:uint):uint
        {
            if (oldId == 0 || oldId == uint.MAX_VALUE)
                return 0;
            if (m_oldToNewSpriteId[oldId] !== undefined)
                return uint(m_oldToNewSpriteId[oldId]);

            var sprite:Sprite = m_sprites.getSprite(oldId);
            if (!sprite || sprite.isEmpty)
            {
                m_oldToNewSpriteId[oldId] = 0;
                return 0;
            }

            var hash:String = getSpriteHash(oldId);
            if (!hash || hash.indexOf("missing:") == 0)
            {
                m_oldToNewSpriteId[oldId] = 0;
                return 0;
            }

            if (m_hashToNewSpriteId[hash] !== undefined)
            {
                var existingId:uint = uint(m_hashToNewSpriteId[hash]);
                m_oldToNewSpriteId[oldId] = existingId;
                reusedSpritesCount++;
                return existingId;
            }

            var newId:uint = m_nextSpriteId++;
            var clonedSprite:Sprite = sprite.clone();
            clonedSprite.id = newId;
            m_newSprites[newId] = clonedSprite;
            m_hashToNewSpriteId[hash] = newId;
            m_oldToNewSpriteId[oldId] = newId;
            return newId;
        }

        private function getThingKey(thing:ThingType):String
        {
            var parts:Array = [thing.category, "exact"];
            appendThingProperties(parts, thing);
            appendFrameGroups(parts, thing);
            return parts.join("|");
        }

        private function appendFrameGroups(parts:Array, thing:ThingType):void
        {
            for (var groupType:uint = FrameGroupType.DEFAULT; groupType <= FrameGroupType.WALKING; groupType++)
            {
                var frameGroup:FrameGroup = thing.getFrameGroup(groupType);
                if (!frameGroup)
                {
                    parts.push(groupType, "null");
                    continue;
                }

                parts.push(groupType,
                        frameGroup.width,
                        frameGroup.height,
                        frameGroup.exactSize,
                        frameGroup.layers,
                        frameGroup.patternX,
                        frameGroup.patternY,
                        frameGroup.patternZ,
                        frameGroup.frames,
                        frameGroup.isAnimation ? 1 : 0,
                        frameGroup.animationMode,
                        frameGroup.loopCount,
                        frameGroup.startFrame);

                var durations:Vector.<FrameDuration> = frameGroup.frameDurations;
                parts.push(durations ? durations.length : 0);
                if (durations)
                {
                    for each (var duration:FrameDuration in durations)
                    {
                        parts.push(duration ? duration.minimum : 0,
                                duration ? duration.maximum : 0);
                    }
                }

                var spriteIds:Vector.<uint> = frameGroup.spriteIndex;
                parts.push(spriteIds ? spriteIds.length : 0);
                if (spriteIds)
                {
                    for each (var spriteId:uint in spriteIds)
                        parts.push(getSpriteHash(spriteId));
                }
            }
        }

        private function appendThingProperties(parts:Array, thing:ThingType):void
        {
            parts.push(thing.isGround ? 1 : 0, thing.groundSpeed,
                    thing.isGroundBorder ? 1 : 0,
                    thing.isOnBottom ? 1 : 0,
                    thing.isOnTop ? 1 : 0,
                    thing.isContainer ? 1 : 0,
                    thing.stackable ? 1 : 0,
                    thing.forceUse ? 1 : 0,
                    thing.multiUse ? 1 : 0,
                    thing.hasCharges ? 1 : 0,
                    thing.writable ? 1 : 0,
                    thing.writableOnce ? 1 : 0,
                    thing.maxReadWriteChars,
                    thing.maxReadChars,
                    thing.isFluidContainer ? 1 : 0,
                    thing.isFluid ? 1 : 0,
                    thing.isUnpassable ? 1 : 0,
                    thing.isUnmoveable ? 1 : 0,
                    thing.blockMissile ? 1 : 0,
                    thing.blockPathfind ? 1 : 0,
                    thing.noMoveAnimation ? 1 : 0,
                    thing.pickupable ? 1 : 0,
                    thing.hangable ? 1 : 0,
                    thing.isVertical ? 1 : 0,
                    thing.isHorizontal ? 1 : 0,
                    thing.rotatable ? 1 : 0,
                    thing.hasLight ? 1 : 0,
                    thing.lightLevel,
                    thing.lightColor,
                    thing.dontHide ? 1 : 0,
                    thing.isTranslucent ? 1 : 0,
                    thing.floorChange ? 1 : 0,
                    thing.hasOffset ? 1 : 0,
                    thing.offsetX,
                    thing.offsetY,
                    thing.hasBones ? 1 : 0,
                    thing.bonesOffsetX ? thing.bonesOffsetX.join(",") : "",
                    thing.bonesOffsetY ? thing.bonesOffsetY.join(",") : "",
                    thing.hasElevation ? 1 : 0,
                    thing.elevation,
                    thing.isLyingObject ? 1 : 0,
                    thing.animateAlways ? 1 : 0,
                    thing.miniMap ? 1 : 0,
                    thing.miniMapColor,
                    thing.isLensHelp ? 1 : 0,
                    thing.lensHelp,
                    thing.isFullGround ? 1 : 0,
                    thing.ignoreLook ? 1 : 0,
                    thing.cloth ? 1 : 0,
                    thing.clothSlot,
                    thing.isMarketItem ? 1 : 0,
                    thing.marketName ? thing.marketName : "",
                    thing.marketCategory,
                    thing.marketTradeAs,
                    thing.marketShowAs,
                    thing.marketRestrictProfession,
                    thing.marketRestrictLevel,
                    thing.hasDefaultAction ? 1 : 0,
                    thing.defaultAction,
                    thing.wrappable ? 1 : 0,
                    thing.unwrappable ? 1 : 0,
                    thing.topEffect ? 1 : 0,
                    thing.usable ? 1 : 0);
        }

        private function getSpriteHash(spriteId:uint):String
        {
            if (spriteId == 0 || spriteId == uint.MAX_VALUE)
                return "0";
            if (m_spriteHashes[spriteId] !== undefined)
                return String(m_spriteHashes[spriteId]);

            var sprite:Sprite = m_sprites.getSprite(spriteId);
            var hash:String = (!sprite || sprite.isEmpty) ? "missing:" + spriteId : sprite.getHash();
            if (!hash)
                hash = "missing:" + spriteId;
            m_spriteHashes[spriteId] = hash;
            return hash;
        }

        private function getThingName(thing:ThingType):String
        {
            if (thing.name && thing.name.length > 0)
                return thing.name;
            if (thing.marketName && thing.marketName.length > 0)
                return thing.marketName;
            return "";
        }

        private function writeMapping(file:File):void
        {
            var stream:FileStream = new FileStream();
            stream.open(file, FileMode.WRITE);
            stream.writeUTFBytes("category,old_id,new_id,status,canonical_old_id,name" + File.lineEnding);
            for each (var row:Object in m_mappingRows)
            {
                stream.writeUTFBytes(csv(row.category) + "," +
                        row.oldId + "," +
                        row.newId + "," +
                        csv(row.status) + "," +
                        row.canonicalOldId + "," +
                        csv(row.name) + File.lineEnding);
            }
            stream.close();
        }

        private function writeRemappedOtb(file:File):Boolean
        {
            var source:ServerItemList = m_serverItems.items;
            var output:ServerItemList = new ServerItemList();
            output.majorVersion = source.majorVersion;
            output.minorVersion = source.minorVersion;
            output.buildNumber = source.buildNumber;
            output.clientVersion = source.clientVersion;

            var itemMap:Dictionary = m_categoryMaps[ThingCategory.ITEM] as Dictionary;
            for each (var sourceItem:ServerItem in source.toArray())
            {
                var clone:ServerItem = sourceItem.clone();
                if (clone.clientId != 0 && itemMap[clone.clientId] !== undefined)
                {
                    var oldClientId:uint = clone.clientId;
                    clone.previousClientId = oldClientId;
                    clone.clientId = uint(itemMap[oldClientId]);
                    if (clone.clientId != oldClientId)
                        remappedServerItems++;
                }
                else if (clone.clientId != 0)
                {
                    clone.previousClientId = clone.clientId;
                    clone.clientId = 0;
                    unresolvedServerItems++;
                }
                output.add(clone);
            }

            var writer:OtbWriter = new OtbWriter(output);
            return writer.write(file);
        }

        private function csv(value:*):String
        {
            var text:String = value == null ? "" : String(value);
            text = text.replace(/"/g, "\"\"");
            return "\"" + text + "\"";
        }

        private function dispatchProgress(current:uint, total:uint, label:String):void
        {
            dispatchEvent(new ProgressEvent(ProgressEvent.PROGRESS, ProgressBarID.METADATA, current, total, label));
        }
    }
}
