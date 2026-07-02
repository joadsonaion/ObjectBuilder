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
*  OUT OF OR IN CONNECTION WITH THE SOFTWARE.
*/

package otlib.utils
{
    import flash.events.EventDispatcher;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.utils.ByteArray;
    import flash.utils.Dictionary;
    import flash.utils.Endian;

    import nail.errors.NullArgumentError;

    import ob.commands.ProgressBarID;

    import otlib.animation.FrameDuration;
    import otlib.animation.FrameGroup;
    import otlib.core.ClientFeatures;
    import otlib.core.Version;
    import otlib.events.ProgressEvent;
    import otlib.items.ItemsXmlWriter;
    import otlib.items.OtbReader;
    import otlib.items.OtbWriter;
    import otlib.items.ServerItem;
    import otlib.items.ServerItemList;
    import otlib.items.ServerItemStorage;
    import otlib.items.ServerItemType;
    import otlib.sprites.Sprite;
    import otlib.sprites.SpriteStorage;
    import otlib.things.FrameGroupType;
    import otlib.things.ThingCategory;
    import otlib.things.ThingType;
    import otlib.things.ThingTypeStorage;

    [Event(name="progress", type="otlib.events.ProgressEvent")]

    public class MapUsedAssetsBuilder extends EventDispatcher
    {
        private static const NODE_START:uint = 0xFE;
        private static const NODE_END:uint = 0xFF;
        private static const ESCAPE_CHAR:uint = 0xFD;

        private static const OTBM_ITEM:uint = 6;
        private static const OTBM_TILE:uint = 5;
        private static const OTBM_HOUSETILE:uint = 14;
        private static const OTBM_ATTR_TILE_FLAGS:uint = 3;
        private static const OTBM_ATTR_ITEM:uint = 9;

        private var m_objects:ThingTypeStorage;
        private var m_sprites:SpriteStorage;
        private var m_serverItems:ServerItemStorage;

        private var m_mapPrefix:ByteArray;
        private var m_mapRoot:Object;
        private var m_usedServerIds:Dictionary;
        private var m_oldServerToNewServer:Dictionary;
        private var m_newServerToClient:Dictionary;
        private var m_oldClientToNewClient:Dictionary;
        private var m_thingKeyToNewClient:Dictionary;
        private var m_newItems:Dictionary;
        private var m_newServerItems:ServerItemList;
        private var m_mappingRows:Array;
        private var m_oldOutfitToNewOutfit:Dictionary;
        private var m_oldEffectToNewEffect:Dictionary;
        private var m_oldMissileToNewMissile:Dictionary;

        private var m_spriteHashes:Dictionary;
        private var m_oldToNewSpriteId:Dictionary;
        private var m_hashToNewSpriteId:Dictionary;
        private var m_newSprites:Dictionary;
        private var m_nextSpriteId:uint;
        private var m_nextClientItemId:uint;
        private var m_nextServerItemId:uint;
        private var m_dedupeClientItems:Boolean;
        private var m_preserveClientItemIds:Boolean;
        private var m_thingHashToClientId:Dictionary;
        private var m_thingHashCache:Dictionary;
        private var m_visualSignature:AssetVisualSignature;

        public var mapItemNodesCount:uint;
        public var mapCompactItemsCount:uint;
        public var rewrittenMapItemsCount:uint;
        public var mapUsedOnlyServerItemsCount:uint;
        public var extraDefinitionServerItemsCount:uint;
        public var usedServerItemsCount:uint;
        public var oldUsedClientItemsCount:uint;
        public var newClientItemsCount:uint;
        public var newServerItemsCount:uint;
        public var oldSpriteCount:uint;
        public var newSpriteCount:uint;
        public var reusedSpritesCount:uint;
        public var removedSpritesCount:uint;
        public var skippedInvalidServerItemsCount:uint;
        public var oldOutfitsCount:uint;
        public var oldEffectsCount:uint;
        public var oldMissilesCount:uint;
        public var outfitsCount:uint;
        public var effectsCount:uint;
        public var missilesCount:uint;
        public var removedOutfits:uint;
        public var removedEffects:uint;
        public var removedMissiles:uint;

        public function MapUsedAssetsBuilder(objects:ThingTypeStorage,
                sprites:SpriteStorage,
                serverItems:ServerItemStorage)
        {
            if (!objects)
                throw new NullArgumentError("objects");
            if (!sprites)
                throw new NullArgumentError("sprites");
            if (!serverItems)
                throw new NullArgumentError("serverItems");

            m_objects = objects;
            m_sprites = sprites;
            m_serverItems = serverItems;
        }

        public function export(mapInFile:File,
                mapOutFile:File,
                datFile:File,
                sprFile:File,
                otbFile:File,
                usedIdsFile:File,
                csvFile:File,
                version:Version,
                features:ClientFeatures,
                extraServerIds:Dictionary = null,
                dedupeClientItems:Boolean = true,
                preserveClientItemIds:Boolean = false):Boolean
        {
            if (!mapInFile)
                throw new NullArgumentError("mapInFile");
            if (!mapOutFile)
                throw new NullArgumentError("mapOutFile");
            if (!datFile)
                throw new NullArgumentError("datFile");
            if (!sprFile)
                throw new NullArgumentError("sprFile");
            if (!otbFile)
                throw new NullArgumentError("otbFile");
            if (!usedIdsFile)
                throw new NullArgumentError("usedIdsFile");
            if (!csvFile)
                throw new NullArgumentError("csvFile");
            if (!version)
                throw new NullArgumentError("version");
            if (!features)
                throw new NullArgumentError("features");
            if (!m_serverItems.loaded || !m_serverItems.items)
                throw new Error("Load items.otb before building map-used assets.");

            initialize();
            m_dedupeClientItems = dedupeClientItems;
            m_preserveClientItemIds = preserveClientItemIds;

            dispatchProgress(0, 10, "Scanning OTBM item IDs");
            scanMapUsedItemIds(mapInFile);
            mapUsedOnlyServerItemsCount = countDictionary(m_usedServerIds);
            mergeExtraServerIds(extraServerIds);
            usedServerItemsCount = countDictionary(m_usedServerIds);
            extraDefinitionServerItemsCount = usedServerItemsCount > mapUsedOnlyServerItemsCount ?
                    usedServerItemsCount - mapUsedOnlyServerItemsCount : 0;
            if (usedServerItemsCount == 0)
                throw new Error("No items were found in the selected OTBM map.");

            dispatchProgress(1, 10, "Writing used server ID list");
            writeUsedServerIds(usedIdsFile);

            dispatchProgress(2, 10, "Building fast map item map");
            buildItemMaps();
            validateCompactItemMaps();

            dispatchProgress(3, 10, "Rewriting OTBM map IDs");
            rewriteMapFile(mapInFile, mapOutFile);

            dispatchProgress(4, 10, "Compacting duplicate outfits, effects and missiles");
            var outfitResult:Object = compactDuplicateCategory(ThingCategory.OUTFIT,
                    m_objects.outfits,
                    ThingTypeStorage.MIN_OUTFIT_ID,
                    m_objects.outfitsCount);
            var outfitList:Dictionary = outfitResult.list;
            outfitsCount = outfitResult.count;
            removedOutfits = outfitResult.removed;

            var effectResult:Object = compactDuplicateCategory(ThingCategory.EFFECT,
                    m_objects.effects,
                    ThingTypeStorage.MIN_EFFECT_ID,
                    m_objects.effectsCount);
            var effectList:Dictionary = effectResult.list;
            effectsCount = effectResult.count;
            removedEffects = effectResult.removed;

            var missileResult:Object = compactDuplicateCategory(ThingCategory.MISSILE,
                    m_objects.missiles,
                    ThingTypeStorage.MIN_MISSILE_ID,
                    m_objects.missilesCount);
            var missileList:Dictionary = missileResult.list;
            missilesCount = missileResult.count;
            removedMissiles = missileResult.removed;

            newSpriteCount = m_nextSpriteId > 1 ? m_nextSpriteId - 1 : 1;
            removedSpritesCount = oldSpriteCount > newSpriteCount ? oldSpriteCount - newSpriteCount : 0;

            var compileFeatures:ClientFeatures = features.clone();
            compileFeatures.applyVersionDefaults(version.value);
            if (!compileFeatures.extended && version.value < 960 && newSpriteCount >= 0xFFFF)
                throw new Error("Generated SPR still has " + newSpriteCount + " sprites. Enable Extended or use a 9.60+ client version.");

            dispatchProgress(5, 10, "Writing compact DAT");
            if (!m_objects.compileCustom(datFile,
                        version,
                        features,
                        m_newItems,
                        newClientItemsCount,
                        outfitList,
                        outfitsCount,
                        effectList,
                        effectsCount,
                        missileList,
                        missilesCount))
            {
                return false;
            }

            dispatchProgress(6, 10, "Writing compact SPR");
            if (!m_sprites.compileRemapped(sprFile, version, features, m_oldToNewSpriteId, newSpriteCount))
                return false;

            dispatchProgress(7, 10, "Writing compact items.otb");
            var writer:OtbWriter = new OtbWriter(m_newServerItems);
            if (!writer.write(otbFile))
                return false;
            validateWrittenOtb(otbFile);

            dispatchProgress(8, 10, "Rewritten OTBM map ready");

            dispatchProgress(9, 10, "Writing map item remap CSV");
            writeMapping(csvFile);

            dispatchProgress(10, 10, "Map-used assets complete");
            return true;
        }

        private function initialize():void
        {
            m_mapPrefix = null;
            m_mapRoot = null;
            m_usedServerIds = new Dictionary();
            m_oldServerToNewServer = new Dictionary();
            m_newServerToClient = new Dictionary();
            m_oldClientToNewClient = new Dictionary();
            m_oldOutfitToNewOutfit = new Dictionary();
            m_oldEffectToNewEffect = new Dictionary();
            m_oldMissileToNewMissile = new Dictionary();
            m_thingKeyToNewClient = new Dictionary();
            m_newItems = new Dictionary();
            m_newServerItems = new ServerItemList();
            m_mappingRows = [];

            var source:ServerItemList = m_serverItems.items;
            m_newServerItems.majorVersion = source.majorVersion;
            m_newServerItems.minorVersion = source.minorVersion;
            m_newServerItems.buildNumber = source.buildNumber;
            m_newServerItems.clientVersion = source.clientVersion;

            m_spriteHashes = new Dictionary();
            m_oldToNewSpriteId = new Dictionary();
            m_hashToNewSpriteId = new Dictionary();
            m_newSprites = new Dictionary();
            m_thingHashToClientId = new Dictionary();
            m_thingHashCache = new Dictionary();
            m_visualSignature = new AssetVisualSignature(m_sprites);
            m_nextSpriteId = 1;
            m_nextClientItemId = ThingTypeStorage.MIN_ITEM_ID;
            m_nextServerItemId = 100;
            m_dedupeClientItems = true;
            m_preserveClientItemIds = false;

            mapItemNodesCount = 0;
            mapCompactItemsCount = 0;
            rewrittenMapItemsCount = 0;
            mapUsedOnlyServerItemsCount = 0;
            extraDefinitionServerItemsCount = 0;
            usedServerItemsCount = 0;
            oldUsedClientItemsCount = 0;
            newClientItemsCount = ThingTypeStorage.MIN_ITEM_ID;
            newServerItemsCount = 0;
            oldSpriteCount = m_sprites.spritesCount;
            newSpriteCount = 0;
            reusedSpritesCount = 0;
            removedSpritesCount = 0;
            skippedInvalidServerItemsCount = 0;
            oldOutfitsCount = m_objects.outfitsCount;
            oldEffectsCount = m_objects.effectsCount;
            oldMissilesCount = m_objects.missilesCount;
            outfitsCount = 0;
            effectsCount = 0;
            missilesCount = 0;
            removedOutfits = 0;
            removedEffects = 0;
            removedMissiles = 0;
        }

        public function writeItemsXml(file:File):Boolean
        {
            if (!file)
                throw new NullArgumentError("file");
            if (!m_newServerItems)
                return false;

            var writer:ItemsXmlWriter = new ItemsXmlWriter();
            return writer.write(file.nativePath, m_newServerItems);
        }

        public function getServerIdRemap():Dictionary
        {
            var result:Dictionary = new Dictionary();
            if (!m_oldServerToNewServer)
                return result;

            for (var key:* in m_oldServerToNewServer)
                result[uint(key)] = uint(m_oldServerToNewServer[key]);
            return result;
        }

        public function getOutfitIdRemap():Dictionary
        {
            return copyRemap(m_oldOutfitToNewOutfit);
        }

        public function getEffectIdRemap():Dictionary
        {
            return copyRemap(m_oldEffectToNewEffect);
        }

        public function getMissileIdRemap():Dictionary
        {
            return copyRemap(m_oldMissileToNewMissile);
        }

        public function getRmeItemRows():Array
        {
            var result:Array = [];
            if (!m_newServerItems || !m_newItems)
                return result;

            for each (var item:ServerItem in m_newServerItems.toArray())
            {
                if (!item)
                    continue;

                var thing:ThingType = m_newItems[item.clientId] as ThingType;
                result.push({
                    serverId: item.id,
                    clientId: item.clientId,
                    name: getServerItemName(item),
                    ground: thing ? thing.isGround || thing.isFullGround || item.fullGround || item.groundSpeed > 0 : item.groundSpeed > 0,
                    border: thing ? thing.isGroundBorder : false,
                    wall: thing ? thing.isVertical || thing.isHorizontal || thing.hangable : item.hangable,
                    liquid: thing ? thing.isFluid || thing.isFluidContainer : item.type == ServerItemType.FLUID || item.type == ServerItemType.SPLASH,
                    pickup: thing ? thing.pickupable : item.pickupable,
                    top: thing ? thing.isOnTop : false,
                    bottom: thing ? thing.isOnBottom : false,
                    unpassable: thing ? thing.isUnpassable : item.unpassable
                });
            }
            return result;
        }

        private function copyRemap(source:Dictionary):Dictionary
        {
            var result:Dictionary = new Dictionary();
            if (!source)
                return result;

            for (var key:* in source)
                result[uint(key)] = uint(source[key]);
            return result;
        }

        private function scanMapUsedItemIds(file:File):void
        {
            if (!file.exists)
                throw new Error("Map file not found: " + file.nativePath);

            var stream:FileStream = new FileStream();
            var bytes:ByteArray = new ByteArray();
            bytes.endian = Endian.LITTLE_ENDIAN;
            stream.open(file, FileMode.READ);
            stream.readBytes(bytes, 0, stream.bytesAvailable);
            stream.close();

            var rootOffset:uint = findRootOffset(bytes);
            bytes.position = rootOffset;
            scanNodeForUsedIds(bytes);
        }

        private function rewriteMapFile(input:File, output:File):void
        {
            if (!input.exists)
                throw new Error("Map file not found: " + input.nativePath);

            var source:ByteArray = new ByteArray();
            source.endian = Endian.LITTLE_ENDIAN;
            var stream:FileStream = new FileStream();
            stream.open(input, FileMode.READ);
            stream.readBytes(source, 0, stream.bytesAvailable);
            stream.close();

            var rootOffset:uint = findRootOffset(source);
            var target:ByteArray = new ByteArray();
            target.endian = Endian.LITTLE_ENDIAN;
            if (rootOffset > 0)
                target.writeBytes(source, 0, rootOffset);

            source.position = rootOffset;
            rewriteNodeTo(source, target);

            stream = new FileStream();
            stream.open(output, FileMode.WRITE);
            stream.writeBytes(target);
            stream.close();
        }

        private function findRootOffset(bytes:ByteArray):uint
        {
            var limit:uint = Math.min(64, bytes.length);
            var oldPosition:uint = bytes.position;
            for (var i:uint = 0; i < limit; i++)
            {
                bytes.position = i;
                if (bytes.readUnsignedByte() == NODE_START)
                {
                    bytes.position = oldPosition;
                    return i;
                }
            }
            bytes.position = oldPosition;
            throw new Error("Invalid OTBM map: root node marker was not found.");
        }

        private function scanNodeForUsedIds(bytes:ByteArray):void
        {
            if (bytes.bytesAvailable < 2)
                throw new Error("Invalid OTBM map: unexpected end of node stream.");

            var marker:uint = bytes.readUnsignedByte();
            if (marker != NODE_START)
                throw new Error("Invalid OTBM map: expected node start marker.");

            var type:uint = bytes.readUnsignedByte();
            var props:ByteArray = new ByteArray();
            props.endian = Endian.LITTLE_ENDIAN;
            var propsScanned:Boolean = false;

            while (bytes.bytesAvailable > 0)
            {
                var value:uint = bytes.readUnsignedByte();
                if (value == ESCAPE_CHAR)
                {
                    if (bytes.bytesAvailable == 0)
                        throw new Error("Invalid OTBM map: dangling escape byte.");
                    props.writeByte(bytes.readUnsignedByte());
                }
                else if (value == NODE_START)
                {
                    if (!propsScanned)
                    {
                        scanNodePropsForUsedIds(type, props);
                        propsScanned = true;
                    }
                    bytes.position--;
                    scanNodeForUsedIds(bytes);
                }
                else if (value == NODE_END)
                {
                    if (!propsScanned)
                        scanNodePropsForUsedIds(type, props);
                    return;
                }
                else
                {
                    props.writeByte(value);
                }
            }

            throw new Error("Invalid OTBM map: node was not closed.");
        }

        private function rewriteNodeTo(source:ByteArray, target:ByteArray):void
        {
            if (source.bytesAvailable < 2)
                throw new Error("Invalid OTBM map: unexpected end of node stream.");

            var marker:uint = source.readUnsignedByte();
            if (marker != NODE_START)
                throw new Error("Invalid OTBM map: expected node start marker.");

            var type:uint = source.readUnsignedByte();
            target.writeByte(NODE_START);
            target.writeByte(type);

            var props:ByteArray = new ByteArray();
            props.endian = Endian.LITTLE_ENDIAN;
            var propsWritten:Boolean = false;

            while (source.bytesAvailable > 0)
            {
                var value:uint = source.readUnsignedByte();
                if (value == ESCAPE_CHAR)
                {
                    if (source.bytesAvailable == 0)
                        throw new Error("Invalid OTBM map: dangling escape byte.");
                    props.writeByte(source.readUnsignedByte());
                }
                else if (value == NODE_START)
                {
                    if (!propsWritten)
                    {
                        rewriteNodeProps(type, props);
                        writeEscaped(target, props);
                        propsWritten = true;
                    }
                    source.position--;
                    rewriteNodeTo(source, target);
                }
                else if (value == NODE_END)
                {
                    if (!propsWritten)
                    {
                        rewriteNodeProps(type, props);
                        writeEscaped(target, props);
                    }
                    target.writeByte(NODE_END);
                    return;
                }
                else
                {
                    props.writeByte(value);
                }
            }

            throw new Error("Invalid OTBM map: node was not closed.");
        }

        private function writeEscaped(bytes:ByteArray, props:ByteArray):void
        {
            if (!props)
                return;
            var oldPosition:uint = props.position;
            props.position = 0;
            while (props.bytesAvailable > 0)
            {
                var value:uint = props.readUnsignedByte();
                if (value == NODE_START || value == NODE_END || value == ESCAPE_CHAR)
                    bytes.writeByte(ESCAPE_CHAR);
                bytes.writeByte(value);
            }
            props.position = oldPosition;
        }

        private function scanNodePropsForUsedIds(type:uint, props:ByteArray):void
        {
            props.position = 0;
            if (type == OTBM_ITEM && props.length >= 2)
            {
                mapItemNodesCount++;
                addUsedServerId(readU16(props, 0));
            }
            else if (type == OTBM_TILE || type == OTBM_HOUSETILE)
            {
                scanTileCompactItems(type, props, false);
            }
        }

        private function rewriteNodeProps(type:uint, props:ByteArray):void
        {
            props.position = 0;
            if (type == OTBM_ITEM && props.length >= 2)
            {
                rewriteItemIdAt(props, 0);
            }
            else if (type == OTBM_TILE || type == OTBM_HOUSETILE)
            {
                scanTileCompactItems(type, props, true);
            }
        }

        private function scanTileCompactItems(type:uint, props:ByteArray, rewrite:Boolean):void
        {
            var offset:uint = type == OTBM_HOUSETILE ? 6 : 2;
            if (props.length <= offset)
                return;

            while (offset < props.length)
            {
                var attribute:uint = readU8(props, offset);
                offset++;
                switch (attribute)
                {
                    case OTBM_ATTR_TILE_FLAGS:
                        offset += 4;
                        break;

                    case OTBM_ATTR_ITEM:
                        if (offset + 1 >= props.length)
                            return;
                        if (!rewrite)
                            mapCompactItemsCount++;
                        if (rewrite)
                            rewriteItemIdAt(props, offset);
                        else
                            addUsedServerId(readU16(props, offset));
                        offset += 2;
                        break;

                    default:
                        return;
                }
            }
        }

        private function addUsedServerId(serverId:uint):void
        {
            if (serverId < ThingTypeStorage.MIN_ITEM_ID)
                return;
            m_usedServerIds[serverId] = true;
        }

        private function mergeExtraServerIds(extraServerIds:Dictionary):void
        {
            if (!extraServerIds)
                return;

            for (var key:* in extraServerIds)
                addUsedServerId(uint(key));
        }

        private function rewriteItemIdAt(props:ByteArray, offset:uint):void
        {
            var oldId:uint = readU16(props, offset);
            if (m_oldServerToNewServer[oldId] === undefined)
                return;

            var newId:uint = uint(m_oldServerToNewServer[oldId]);
            if (newId != oldId)
                rewrittenMapItemsCount++;
            writeU16(props, offset, newId);
        }

        private function buildItemMaps():void
        {
            var ids:Array = [];
            for (var key:* in m_usedServerIds)
                ids.push(uint(key));
            ids.sort(Array.NUMERIC);

            var source:ServerItemList = m_serverItems.items;
            var usedClientIds:Dictionary = new Dictionary();

            var total:uint = ids.length;
            var processed:uint = 0;
            for each (var oldServerId:uint in ids)
            {
                processed++;
                if (processed == 1 || processed % 2000 == 0)
                    dispatchProgress(2, 10, "Mapping map item IDs " + processed + "/" + total);

                var serverItem:ServerItem = source.getItemById(oldServerId);
                if (!serverItem)
                {
                    skippedInvalidServerItemsCount++;
                    continue;
                }

                var oldClientId:uint = serverItem.clientId;
                if (oldClientId < ThingTypeStorage.MIN_ITEM_ID)
                {
                    skippedInvalidServerItemsCount++;
                    continue;
                }

                var resolved:Object = resolveThingForServerItem(serverItem);
                if (!resolved || !resolved.thing)
                {
                    skippedInvalidServerItemsCount++;
                    continue;
                }

                var thing:ThingType = resolved.thing as ThingType;
                oldClientId = uint(resolved.clientId);

                usedClientIds[oldClientId] = true;

                var newClientId:uint = getOrCreateClientItem(thing, oldClientId);
                var newServerId:uint = m_nextServerItemId++;
                if (newServerId > 0xFFFF)
                    throw new Error("The map uses more than 65436 server items. Tibia 8.60 OTBM/OTB item IDs cannot exceed 65535.");
                m_oldServerToNewServer[oldServerId] = newServerId;
                m_newServerToClient[newServerId] = newClientId;

                var clone:ServerItem = serverItem.clone();
                clone.id = newServerId;
                clone.previousClientId = oldClientId;
                clone.clientId = newClientId;
                ensureXmlData(clone, serverItem, thing, oldServerId, newServerId);
                m_newServerItems.add(clone);

                m_mappingRows.push({
                            oldServerId: oldServerId,
                            newServerId: newServerId,
                            oldClientId: oldClientId,
                            newClientId: newClientId,
                            name: getServerItemName(serverItem)
                        });
            }

            oldUsedClientItemsCount = countDictionary(usedClientIds);
            newServerItemsCount = m_newServerItems.count;
            remapXmlServerIdReferences();
            dispatchProgress(2, 10, "Mapped " + newServerItemsCount + " server items");
        }

        private function validateCompactItemMaps():void
        {
            if (!m_preserveClientItemIds)
            {
                for (var clientId:uint = ThingTypeStorage.MIN_ITEM_ID;
                        clientId <= newClientItemsCount;
                        clientId++)
                {
                    if (!m_newItems[clientId])
                        throw new Error("Compact DAT validation failed: missing client ID " + clientId + ".");
                }
            }

            for (var key:* in m_newServerToClient)
            {
                var serverId:uint = uint(key);
                var mappedClientId:uint = uint(m_newServerToClient[key]);
                if (!m_newItems[mappedClientId])
                    throw new Error("Compact mapping validation failed: server ID " + serverId +
                            " points to missing client ID " + mappedClientId + ".");
            }
        }

        private function remapXmlServerIdReferences():void
        {
            for each (var item:ServerItem in m_newServerItems.toArray())
            {
                if (!item)
                    continue;
                remapXmlDictionary(item.getXmlAttributes());
            }
        }

        private function ensureXmlData(clone:ServerItem,
                source:ServerItem,
                thing:ThingType,
                oldServerId:uint,
                newServerId:uint):void
        {
            var hadXmlName:Boolean = clone.nameXml && clone.nameXml.length > 0;
            if (!hadXmlName)
            {
                var generatedName:String = getServerItemName(source);
                if (!generatedName || generatedName.length == 0)
                    generatedName = buildGeneratedItemName(thing, oldServerId, newServerId);
                clone.nameXml = generatedName;
            }

            if (!clone.article || clone.article.length == 0)
                clone.article = "a";

            if (!hadXmlName && !clone.hasXmlAttribute("description"))
            {
                clone.setXmlAttribute("description",
                        "Generated by Map Used ID Generator from original server ID " +
                        oldServerId + " and client ID " + clone.previousClientId + ".");
            }
        }

        private function buildGeneratedItemName(thing:ThingType, oldServerId:uint, newServerId:uint):String
        {
            var prefix:String = "generated item";
            if (thing)
            {
                if (thing.isGround || thing.isFullGround)
                    prefix = "generated ground";
                else if (thing.isVertical || thing.isHorizontal || thing.hangable)
                    prefix = "generated wall";
                else if (thing.isFluid || thing.isFluidContainer)
                    prefix = "generated liquid";
                else if (thing.pickupable)
                    prefix = "generated pickup";
                else if (thing.isOnTop || thing.isOnBottom || thing.isUnpassable)
                    prefix = "generated map object";
            }
            return prefix + " " + newServerId + " (old " + oldServerId + ")";
        }

        private function remapXmlDictionary(attributes:Dictionary):void
        {
            if (!attributes)
                return;

            for (var key:* in attributes)
            {
                var value:Object = attributes[key];
                if (value is Dictionary)
                {
                    remapXmlDictionary(value as Dictionary);
                    continue;
                }

                if (!isServerItemReferenceKey(String(key)))
                    continue;

                var oldId:uint = uint(String(value));
                if (oldId > 0 && m_oldServerToNewServer[oldId] !== undefined)
                    attributes[key] = String(uint(m_oldServerToNewServer[oldId]));
            }
        }

        private function isServerItemReferenceKey(key:String):Boolean
        {
            switch (key.toLowerCase())
            {
                case "writeonceitemid":
                case "decayto":
                case "destroyto":
                case "transformequipto":
                case "transformdeequipto":
                case "maletransformto":
                case "femaletransformto":
                case "transformto":
                case "malesleeper":
                case "femalesleeper":
                    return true;
            }
            return false;
        }

        private function validateWrittenOtb(file:File):void
        {
            var reader:OtbReader = new OtbReader();
            if (!reader.read(file))
                throw new Error("Generated items.otb could not be read back for validation.");

            for (var key:* in m_newServerToClient)
            {
                var serverId:uint = uint(key);
                var expectedClientId:uint = uint(m_newServerToClient[key]);
                var item:ServerItem = reader.items.getItemById(serverId);
                if (!item)
                    throw new Error("Generated items.otb validation failed: missing server ID " + serverId + ".");
                if (item.clientId != expectedClientId)
                    throw new Error("Generated items.otb validation failed: server ID " + serverId +
                            " points to client ID " + item.clientId + " instead of " + expectedClientId + ".");
            }
        }

        private function getOrCreateClientItem(thing:ThingType, oldClientId:uint):uint
        {
            if (m_preserveClientItemIds)
                return preserveClientItem(thing, oldClientId);

            if (m_dedupeClientItems && m_oldClientToNewClient[oldClientId] !== undefined)
                return uint(m_oldClientToNewClient[oldClientId]);

            thing.category = ThingCategory.ITEM;
            var key:String = m_dedupeClientItems ? getThingKey(thing) : null;
            if (m_dedupeClientItems && m_thingKeyToNewClient[key] !== undefined)
            {
                var duplicateClientId:uint = uint(m_thingKeyToNewClient[key]);
                m_oldClientToNewClient[oldClientId] = duplicateClientId;
                return duplicateClientId;
            }

            var newClientId:uint = m_nextClientItemId++;
            if (newClientId > 0xFFFF)
                throw new Error("The map needs more than 65436 client items. Tibia 8.60 DAT item IDs cannot exceed 65535.");
            var clone:ThingType = cloneThingWithRemappedSprites(thing);
            clone.id = newClientId;
            clone.category = ThingCategory.ITEM;
            m_newItems[newClientId] = clone;

            if (m_dedupeClientItems)
                m_thingKeyToNewClient[key] = newClientId;
            m_oldClientToNewClient[oldClientId] = newClientId;
            newClientItemsCount = newClientId;
            return newClientId;
        }

        private function preserveClientItem(thing:ThingType, oldClientId:uint):uint
        {
            if (oldClientId < ThingTypeStorage.MIN_ITEM_ID || oldClientId > 0xFFFF)
                throw new Error("Cannot preserve invalid client item ID " + oldClientId + ".");

            if (m_oldClientToNewClient[oldClientId] !== undefined)
                return uint(m_oldClientToNewClient[oldClientId]);

            var clone:ThingType = cloneThingWithRemappedSprites(thing);
            clone.id = oldClientId;
            clone.category = ThingCategory.ITEM;
            m_newItems[oldClientId] = clone;
            m_oldClientToNewClient[oldClientId] = oldClientId;
            if (oldClientId > newClientItemsCount)
                newClientItemsCount = oldClientId;
            return oldClientId;
        }

        private function resolveThingForServerItem(serverItem:ServerItem):Object
        {
            var thing:ThingType = getUsableItemThing(serverItem.clientId);
            if (thing)
                return {thing: thing, clientId: serverItem.clientId};

            if (serverItem.previousClientId > 0)
            {
                thing = getUsableItemThing(serverItem.previousClientId);
                if (thing)
                    return {thing: thing, clientId: serverItem.previousClientId};
            }

            var hashKey:String = getServerItemSpriteHashKey(serverItem);
            if (hashKey && hashKey.length > 0)
            {
                var nearbyId:uint = findClientItemByHashNear(serverItem.clientId, hashKey, 96);
                if (nearbyId > 0)
                    return {thing: m_objects.items[nearbyId] as ThingType, clientId: nearbyId};

                var globalId:uint = findClientItemByHashGlobal(hashKey);
                if (globalId > 0)
                    return {thing: m_objects.items[globalId] as ThingType, clientId: globalId};
            }

            return null;
        }

        private function getUsableItemThing(clientId:uint):ThingType
        {
            if (clientId < ThingTypeStorage.MIN_ITEM_ID || clientId > m_objects.itemsCount)
                return null;

            var thing:ThingType = m_objects.items[clientId] as ThingType;
            if (!ThingUtils.isValid(thing) || ThingUtils.isEmpty(thing))
                return null;

            return thing;
        }

        private function getServerItemSpriteHashKey(serverItem:ServerItem):String
        {
            if (!serverItem || !serverItem.spriteHash || serverItem.spriteHash.length == 0)
                return null;

            var previous:uint = serverItem.spriteHash.position;
            serverItem.spriteHash.position = 0;
            var parts:Array = [];
            while (serverItem.spriteHash.bytesAvailable > 0)
            {
                var value:uint = serverItem.spriteHash.readUnsignedByte();
                var hex:String = value.toString(16).toUpperCase();
                if (hex.length < 2)
                    hex = "0" + hex;
                parts.push(hex);
            }
            serverItem.spriteHash.position = previous;
            return parts.join("");
        }

        private function getThingHashKey(clientId:uint):String
        {
            if (m_thingHashCache[clientId] !== undefined)
                return String(m_thingHashCache[clientId]);

            var thing:ThingType = getUsableItemThing(clientId);
            if (!thing)
            {
                m_thingHashCache[clientId] = "";
                return "";
            }

            var bytes:ByteArray = m_sprites.getSpriteHash(thing);
            if (!bytes || bytes.length == 0)
            {
                m_thingHashCache[clientId] = "";
                return "";
            }

            var previous:uint = bytes.position;
            bytes.position = 0;
            var parts:Array = [];
            while (bytes.bytesAvailable > 0)
            {
                var value:uint = bytes.readUnsignedByte();
                var hex:String = value.toString(16).toUpperCase();
                if (hex.length < 2)
                    hex = "0" + hex;
                parts.push(hex);
            }
            bytes.position = previous;

            var key:String = parts.join("");
            m_thingHashCache[clientId] = key;
            return key;
        }

        private function findClientItemByHashNear(centerId:uint, hashKey:String, radius:uint):uint
        {
            if (!hashKey || hashKey.length == 0)
                return 0;

            for (var delta:uint = 0; delta <= radius; delta++)
            {
                var low:int = int(centerId) - int(delta);
                var high:uint = centerId + delta;

                if (low >= ThingTypeStorage.MIN_ITEM_ID)
                {
                    var lowId:uint = uint(low);
                    if (getThingHashKey(lowId) == hashKey)
                        return lowId;
                }

                if (delta == 0)
                    continue;

                if (high <= m_objects.itemsCount && getThingHashKey(high) == hashKey)
                    return high;
            }

            return 0;
        }

        private function findClientItemByHashGlobal(hashKey:String):uint
        {
            if (!hashKey || hashKey.length == 0)
                return 0;

            if (m_thingHashToClientId[hashKey] !== undefined)
                return uint(m_thingHashToClientId[hashKey]);

            for (var clientId:uint = ThingTypeStorage.MIN_ITEM_ID; clientId <= m_objects.itemsCount; clientId++)
            {
                if (getThingHashKey(clientId) == hashKey)
                {
                    m_thingHashToClientId[hashKey] = clientId;
                    return clientId;
                }
            }

            m_thingHashToClientId[hashKey] = 0;
            return 0;
        }

        private function compactDuplicateCategory(category:String,
                list:Dictionary,
                minId:uint,
                maxId:uint):Object
        {
            var output:Dictionary = new Dictionary();
            var oldToNew:Dictionary = getCategoryRemap(category);
            var groups:Dictionary = new Dictionary();
            var entries:Array = [];
            var removed:uint = 0;

            for (var id:uint = minId; id <= maxId; id++)
            {
                var thing:ThingType = list[id] as ThingType;
                if (!ThingUtils.isValid(thing) || ThingUtils.isEmpty(thing))
                    continue;

                thing.category = category;
                var key:String = getDuplicateThingKey(thing);
                var entry:Object = {
                    oldId: id,
                    thing: thing,
                    key: key,
                    quality: m_visualSignature.getThingQualityScore(thing),
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

            for each (group in groups)
            {
                if (group.length < 2)
                    continue;

                var canonical:Object = chooseBestVisualEntry(group);
                for each (entry in group)
                {
                    if (entry === canonical)
                        continue;

                    entry.removed = true;
                    entry.canonicalOldId = canonical.oldId;
                    removed++;
                }
            }

            var nextId:uint = minId;
            for each (entry in entries)
            {
                if (entry.removed)
                    continue;

                var clone:ThingType = cloneThingWithRemappedSprites(entry.thing as ThingType);
                clone.id = nextId;
                clone.category = category;
                output[nextId] = clone;
                entry.newId = nextId;
                oldToNew[uint(entry.oldId)] = nextId;
                nextId++;
            }

            for each (entry in entries)
            {
                if (!entry.removed)
                    continue;

                entry.newId = oldToNew[uint(entry.canonicalOldId)];
                oldToNew[uint(entry.oldId)] = uint(entry.newId);
            }

            return {
                list: output,
                count: nextId > minId ? nextId - 1 : minId,
                removed: removed
            };
        }

        private function getDuplicateThingKey(thing:ThingType):String
        {
            return m_visualSignature ? m_visualSignature.getThingVisualKey(thing) : getThingKey(thing);
        }

        private function chooseBestVisualEntry(group:Array):Object
        {
            var best:Object = group[0];
            for each (var entry:Object in group)
            {
                if (Number(entry.quality) > Number(best.quality) + 0.001)
                {
                    best = entry;
                    continue;
                }

                if (Math.abs(Number(entry.quality) - Number(best.quality)) <= 0.001 &&
                        uint(entry.oldId) > uint(best.oldId))
                {
                    best = entry;
                }
            }
            return best;
        }

        private function getCategoryRemap(category:String):Dictionary
        {
            switch (category)
            {
                case ThingCategory.OUTFIT:
                    return m_oldOutfitToNewOutfit;
                case ThingCategory.EFFECT:
                    return m_oldEffectToNewEffect;
                case ThingCategory.MISSILE:
                    return m_oldMissileToNewMissile;
            }
            return new Dictionary();
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
            if (oldId > oldSpriteCount)
                return 0;
            if (m_oldToNewSpriteId[oldId] !== undefined)
            {
                reusedSpritesCount++;
                return uint(m_oldToNewSpriteId[oldId]);
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
            m_oldToNewSpriteId[oldId] = newId;
            m_hashToNewSpriteId[hash] = newId;
            return newId;
        }

        private function getSpriteHash(spriteId:uint):String
        {
            if (spriteId == 0 || spriteId == uint.MAX_VALUE)
                return "0";
            if (m_spriteHashes[spriteId] !== undefined)
                return String(m_spriteHashes[spriteId]);

            var hash:String = m_sprites.getStorageHashFast(spriteId);
            if (!hash)
                hash = "missing:" + spriteId;
            m_spriteHashes[spriteId] = hash;
            return hash;
        }

        private function getThingKey(thing:ThingType):String
        {
            var parts:Array = [thing.category, "properties"];
            appendThingProperties(parts, thing);
            parts.push("visual");
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

        private function readU8(bytes:ByteArray, offset:uint):uint
        {
            var position:uint = bytes.position;
            bytes.position = offset;
            var value:uint = bytes.readUnsignedByte();
            bytes.position = position;
            return value;
        }

        private function readU16(bytes:ByteArray, offset:uint):uint
        {
            var position:uint = bytes.position;
            bytes.endian = Endian.LITTLE_ENDIAN;
            bytes.position = offset;
            var value:uint = bytes.readUnsignedShort();
            bytes.position = position;
            return value;
        }

        private function writeU16(bytes:ByteArray, offset:uint, value:uint):void
        {
            var position:uint = bytes.position;
            bytes.position = offset;
            bytes.writeByte(value & 0xFF);
            bytes.writeByte((value >> 8) & 0xFF);
            bytes.position = position;
        }

        private function writeMapping(file:File):void
        {
            var stream:FileStream = new FileStream();
            stream.open(file, FileMode.WRITE);
            stream.writeUTFBytes("old_server_id,new_server_id,old_client_id,new_client_id,name" + File.lineEnding);
            for each (var row:Object in m_mappingRows)
            {
                stream.writeUTFBytes(row.oldServerId + "," +
                        row.newServerId + "," +
                        row.oldClientId + "," +
                        row.newClientId + "," +
                        csv(row.name) + File.lineEnding);
            }
            stream.close();
        }

        private function writeUsedServerIds(file:File):void
        {
            var ids:Array = [];
            for (var key:* in m_usedServerIds)
                ids.push(uint(key));
            ids.sort(Array.NUMERIC);

            var stream:FileStream = new FileStream();
            stream.open(file, FileMode.WRITE);
            stream.writeUTFBytes("server_id,client_id,name" + File.lineEnding);

            var source:ServerItemList = m_serverItems.items;
            for each (var serverId:uint in ids)
            {
                var item:ServerItem = source.getItemById(serverId);
                stream.writeUTFBytes(serverId + "," +
                        (item ? item.clientId : "") + "," +
                        (item ? csv(getServerItemName(item)) : "") +
                        File.lineEnding);
            }

            stream.close();
        }

        private function getServerItemName(item:ServerItem):String
        {
            if (item.nameXml && item.nameXml.length > 0)
                return item.nameXml;
            if (item.name && item.name.length > 0)
                return item.name;
            return "";
        }

        private function countDictionary(dict:Dictionary):uint
        {
            var total:uint = 0;
            for (var key:* in dict)
                total++;
            return total;
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
