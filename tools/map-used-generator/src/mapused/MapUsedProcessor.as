package mapused
{
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.utils.ByteArray;
    import flash.utils.Dictionary;
    import flash.utils.Endian;

    import otlib.items.OtbReader;
    import otlib.items.ServerItem;
    import otlib.items.ServerItemList;
    import otlib.items.ServerItemStorage;
    import otlib.core.ClientFeatures;
    import otlib.core.Version;
    import otlib.events.ProgressEvent;
    import otlib.sprites.SpriteStorage;
    import otlib.things.ThingTypeStorage;
    import otlib.utils.MapUsedAssetsBuilder;
    import otlib.utils.MergedClientCleaner;
    import otlib.utils.OTFI;
    import otlib.utils.SpriteExtent;


    public class MapUsedProcessor
    {
        private static const NODE_START:uint = 0xFE;
        private static const NODE_END:uint = 0xFF;
        private static const ESCAPE_CHAR:uint = 0xFD;

        private static const OTBM_ITEM:uint = 6;
        private static const OTBM_TILE:uint = 5;
        private static const OTBM_HOUSETILE:uint = 14;
        private static const OTBM_ATTR_TILE_FLAGS:uint = 3;
        private static const OTBM_ATTR_ITEM:uint = 9;

        private var m_usedServerIds:Dictionary;
        private var m_occurrences:Dictionary;
        private var m_oldToNew:Dictionary;
        private var m_items:ServerItemList;

        public var mapItemNodesCount:uint;
        public var mapCompactItemsCount:uint;
        public var usedServerItemsCount:uint;
        public var rewrittenMapItemsCount:uint;

        public function run(mapFile:File,
                otbFile:File,
                outputDir:File,
                startServerId:uint,
                rewriteMap:Boolean):Object
        {
            if (!mapFile || !mapFile.exists)
                throw new Error("Selecione um mapa .otbm valido.");

            if (!outputDir)
                outputDir = mapFile.parent.resolvePath("map_used_generator");
            if (!outputDir.exists)
                outputDir.createDirectory();

            initialize();
            if (otbFile && otbFile.exists)
                loadOtb(otbFile);

            scanMapUsedItemIds(mapFile);
            var ids:Array = sortedUsedIds();
            usedServerItemsCount = ids.length;
            if (usedServerItemsCount == 0)
                throw new Error("Nenhum item foi encontrado no mapa.");

            buildRemap(ids, startServerId);

            var baseName:String = fileBaseName(mapFile);
            var usedCsv:File = outputDir.resolvePath(baseName + "_map_used_server_ids.csv");
            var remapCsv:File = outputDir.resolvePath(baseName + "_map_item_remap.csv");
            var remappedMap:File = outputDir.resolvePath(baseName + "_remapped.otbm");

            writeUsedCsv(usedCsv, ids);
            writeRemapCsv(remapCsv, ids);

            if (rewriteMap)
                rewriteMapFile(mapFile, remappedMap);

            return {
                usedCsv: usedCsv.nativePath,
                remapCsv: remapCsv.nativePath,
                remappedMap: rewriteMap ? remappedMap.nativePath : "",
                usedServerItemsCount: usedServerItemsCount,
                mapItemNodesCount: mapItemNodesCount,
                mapCompactItemsCount: mapCompactItemsCount,
                rewrittenMapItemsCount: rewrittenMapItemsCount,
                otbLoaded: m_items != null
            };
        }

        public function runCompact(mapFile:File,
                datFile:File,
                sprFile:File,
                otbFile:File,
                outputDir:File,
                versionValue:uint,
                features:ClientFeatures,
                includeXmlDefinitions:Boolean = false,
                progress:Function = null):Object
        {
            if (!mapFile || !mapFile.exists)
                throw new Error("Selecione um mapa .otbm valido.");
            if (!datFile || !datFile.exists)
                throw new Error("Selecione Tibia.dat valido.");
            if (!sprFile || !sprFile.exists)
                throw new Error("Selecione Tibia.spr valido.");
            if (!otbFile || !otbFile.exists)
                throw new Error("Selecione items.otb valido.");

            if (!outputDir)
                outputDir = mapFile.parent.resolvePath("map_used_compact_client");
            if (!outputDir.exists)
                outputDir.createDirectory();

            if (!features)
                features = new ClientFeatures(true, true, true, true, "default", "tfs0.5");

            var version:Version = new Version();
            version.value = versionValue > 0 ? versionValue : 860;
            version.valueStr = String(version.value);

            if (progress != null)
                progress("Carregando DAT...");
            var objects:ThingTypeStorage = new ThingTypeStorage();
            objects.load(datFile, version, features);

            if (progress != null)
                progress("Carregando SPR...");
            var sprites:SpriteStorage = new SpriteStorage();
            sprites.load(sprFile, version, features);

            version.datSignature = objects.signature;
            version.sprSignature = sprites.signature;

            if (progress != null)
                progress("Carregando items.otb...");
            var serverItems:ServerItemStorage = new ServerItemStorage();
            if (!serverItems.load(otbFile))
                throw new Error("Nao foi possivel carregar items.otb.");

            var baseName:String = fileBaseName(mapFile);
            var mapOut:File = outputDir.resolvePath(baseName + "_remapped.otbm");
            var datOut:File = outputDir.resolvePath("Tibia.dat");
            var sprOut:File = outputDir.resolvePath("Tibia.spr");
            var otbOut:File = outputDir.resolvePath("items.otb");
            var xmlOut:File = outputDir.resolvePath("items.xml");
            var usedIdsFile:File = outputDir.resolvePath(baseName + "_map_used_server_ids.csv");
            var remapCsv:File = outputDir.resolvePath(baseName + "_map_item_remap.csv");
            var extraServerIds:Dictionary = includeXmlDefinitions ? buildXmlDefinedServerIds(serverItems) : null;

            var builder:MapUsedAssetsBuilder = new MapUsedAssetsBuilder(objects, sprites, serverItems);
            if (progress != null)
                builder.addEventListener(ProgressEvent.PROGRESS, function(event:ProgressEvent):void
                {
                    progress(event.label);
                });

            if (!builder.export(mapFile,
                    mapOut,
                    datOut,
                    sprOut,
                    otbOut,
                    usedIdsFile,
                    remapCsv,
                    version,
                    features,
                    extraServerIds,
                    !includeXmlDefinitions))
            {
                throw new Error("Falha ao gerar cliente compacto.");
            }

            if (!builder.writeItemsXml(xmlOut))
                throw new Error("Falha ao gerar items.xml do cliente compacto.");

            var otfi:OTFI = new OTFI(features, datOut.name, sprOut.name, SpriteExtent.DEFAULT_SIZE, SpriteExtent.DEFAULT_DATA_SIZE);
            otfi.save(outputDir.resolvePath("Tibia.otfi"));
            var serverItemsDir:File = writeGeneratedServerItemsFolder(outputDir, otbOut, xmlOut);
            var readmeFile:File = writeCompactReadme(outputDir, datOut, sprOut, otbOut, xmlOut, serverItemsDir, mapOut);

            return {
                dat: datOut.nativePath,
                spr: sprOut.nativePath,
                otb: otbOut.nativePath,
                xml: xmlOut.nativePath,
                serverItemsDir: serverItemsDir.nativePath,
                map: mapOut.nativePath,
                otfi: outputDir.resolvePath("Tibia.otfi").nativePath,
                readme: readmeFile.nativePath,
                usedCsv: usedIdsFile.nativePath,
                remapCsv: remapCsv.nativePath,
                usedServerItemsCount: builder.usedServerItemsCount,
                mapUsedOnlyServerItemsCount: builder.mapUsedOnlyServerItemsCount,
                extraDefinitionServerItemsCount: builder.extraDefinitionServerItemsCount,
                oldUsedClientItemsCount: builder.oldUsedClientItemsCount,
                newClientItemsCount: builder.newClientItemsCount,
                newServerItemsCount: builder.newServerItemsCount,
                oldSpriteCount: builder.oldSpriteCount,
                newSpriteCount: builder.newSpriteCount,
                reusedSpritesCount: builder.reusedSpritesCount,
                removedSpritesCount: builder.removedSpritesCount,
                rewrittenMapItemsCount: builder.rewrittenMapItemsCount
            };
        }

        private function writeGeneratedServerItemsFolder(outputDir:File, otbOut:File, xmlOut:File):File
        {
            var serverItemsDir:File = outputDir.resolvePath("server_items_use_this");
            if (!serverItemsDir.exists)
                serverItemsDir.createDirectory();

            otbOut.copyTo(serverItemsDir.resolvePath("items.otb"), true);
            xmlOut.copyTo(serverItemsDir.resolvePath("items.xml"), true);
            return serverItemsDir;
        }

        private function writeCompactReadme(outputDir:File,
                datOut:File,
                sprOut:File,
                otbOut:File,
                xmlOut:File,
                serverItemsDir:File,
                mapOut:File):File
        {
            var readme:File = outputDir.resolvePath("LEIA_ANTES.txt");
            var stream:FileStream = new FileStream();
            stream.open(readme, FileMode.WRITE);
            stream.writeUTFBytes("CLIENTE COMPACTO GERADO PELO Map Used ID Generator" + File.lineEnding);
            stream.writeUTFBytes(File.lineEnding);
            stream.writeUTFBytes("Use estes arquivos juntos. Nao misture Tibia.dat/Tibia.spr compactos com o data/items antigo." + File.lineEnding);
            stream.writeUTFBytes("Se misturar, o ObjectBuilder/RME mostra server IDs e visuais trocados." + File.lineEnding);
            stream.writeUTFBytes(File.lineEnding);
            stream.writeUTFBytes("ObjectBuilder:" + File.lineEnding);
            stream.writeUTFBytes("  Pasta do Cliente: " + outputDir.nativePath + File.lineEnding);
            stream.writeUTFBytes("  Server Items Folder: " + serverItemsDir.nativePath + File.lineEnding);
            stream.writeUTFBytes(File.lineEnding);
            stream.writeUTFBytes("RME/servidor:" + File.lineEnding);
            stream.writeUTFBytes("  Copie/aponte Tibia.dat: " + datOut.nativePath + File.lineEnding);
            stream.writeUTFBytes("  Copie/aponte Tibia.spr: " + sprOut.nativePath + File.lineEnding);
            stream.writeUTFBytes("  Copie/aponte items.otb: " + otbOut.nativePath + File.lineEnding);
            stream.writeUTFBytes("  Copie/aponte items.xml: " + xmlOut.nativePath + File.lineEnding);
            stream.writeUTFBytes("  Mapa remapeado: " + mapOut.nativePath + File.lineEnding);
            stream.close();
            return readme;
        }

        public function runMergedCleanupCompact(mapFile:File,
                datFile:File,
                sprFile:File,
                otbFile:File,
                outputDir:File,
                versionValue:uint,
                features:ClientFeatures,
                removalCutoff:uint,
                progress:Function = null):Object
        {
            if (!mapFile || !mapFile.exists)
                throw new Error("Selecione um mapa .otbm valido.");
            if (!datFile || !datFile.exists)
                throw new Error("Selecione Tibia.dat valido.");
            if (!sprFile || !sprFile.exists)
                throw new Error("Selecione Tibia.spr valido.");
            if (!otbFile || !otbFile.exists)
                throw new Error("Selecione items.otb valido.");

            if (!outputDir)
                outputDir = mapFile.parent.resolvePath("merged_cleanup_client");
            if (!outputDir.exists)
                outputDir.createDirectory();

            if (!features)
                features = new ClientFeatures(true, true, true, true, "default", "tfs0.5");

            var version:Version = new Version();
            version.value = versionValue > 0 ? versionValue : 860;
            version.valueStr = String(version.value);

            if (progress != null)
                progress("Carregando DAT...");
            var objects:ThingTypeStorage = new ThingTypeStorage();
            objects.load(datFile, version, features);

            if (progress != null)
                progress("Carregando SPR...");
            var sprites:SpriteStorage = new SpriteStorage();
            sprites.load(sprFile, version, features);

            version.datSignature = objects.signature;
            version.sprSignature = sprites.signature;

            if (progress != null)
                progress("Carregando items.otb...");
            var serverItems:ServerItemStorage = new ServerItemStorage();
            if (!serverItems.load(otbFile))
                throw new Error("Nao foi possivel carregar items.otb.");

            var mapBaseName:String = fileBaseName(mapFile);
            var datOut:File = outputDir.resolvePath("Tibia.dat");
            var sprOut:File = outputDir.resolvePath("Tibia.spr");
            var otbOut:File = outputDir.resolvePath("items.otb");
            var csvOut:File = outputDir.resolvePath(mapBaseName + "_cleanup_id_map.csv");
            var copiedMap:File = outputDir.resolvePath(mapFile.name);
            if (copiedMap.nativePath == mapFile.nativePath)
                copiedMap = outputDir.resolvePath(mapBaseName + "_compatible.otbm");

            var cleaner:MergedClientCleaner = new MergedClientCleaner(objects, sprites, serverItems);
            if (progress != null)
                cleaner.addEventListener(ProgressEvent.PROGRESS, function(event:ProgressEvent):void
                {
                    progress(event.label);
                });

            if (!cleaner.export(datOut,
                    sprOut,
                    csvOut,
                    otbOut,
                    version,
                    features,
                    removalCutoff,
                    true))
            {
                throw new Error("Falha ao gerar cleanup compacto.");
            }

            if (progress != null)
                progress("Copiando mapa compativel");
            if (copiedMap.exists)
                copiedMap.deleteFile();
            mapFile.copyTo(copiedMap, true);

            var otfi:OTFI = new OTFI(features, datOut.name, sprOut.name, SpriteExtent.DEFAULT_SIZE, SpriteExtent.DEFAULT_DATA_SIZE);
            otfi.save(outputDir.resolvePath("Tibia.otfi"));

            return {
                dat: datOut.nativePath,
                spr: sprOut.nativePath,
                otb: otbOut.nativePath,
                otfi: outputDir.resolvePath("Tibia.otfi").nativePath,
                map: copiedMap.nativePath,
                csv: csvOut.nativePath,
                oldItemsCount: cleaner.oldItemsCount,
                itemsCount: cleaner.itemsCount,
                oldOutfitsCount: cleaner.oldOutfitsCount,
                outfitsCount: cleaner.outfitsCount,
                oldEffectsCount: cleaner.oldEffectsCount,
                effectsCount: cleaner.effectsCount,
                oldMissilesCount: cleaner.oldMissilesCount,
                missilesCount: cleaner.missilesCount,
                oldSpriteCount: cleaner.oldSpriteCount,
                newSpriteCount: cleaner.newSpriteCount,
                removedItems: cleaner.removedItems,
                removedOutfits: cleaner.removedOutfits,
                removedEffects: cleaner.removedEffects,
                removedMissiles: cleaner.removedMissiles,
                reusedSpritesCount: cleaner.reusedSpritesCount,
                removedSpritesCount: cleaner.removedSpritesCount,
                remappedServerItems: cleaner.remappedServerItems,
                unresolvedServerItems: cleaner.unresolvedServerItems
            };
        }

        private function initialize():void
        {
            m_usedServerIds = new Dictionary();
            m_occurrences = new Dictionary();
            m_oldToNew = new Dictionary();
            m_items = null;

            mapItemNodesCount = 0;
            mapCompactItemsCount = 0;
            usedServerItemsCount = 0;
            rewrittenMapItemsCount = 0;
        }

        private function loadOtb(file:File):void
        {
            var reader:OtbReader = new OtbReader();
            if (!reader.read(file))
                throw new Error("Nao foi possivel ler items.otb: " + file.nativePath);
            m_items = reader.items;
        }

        private function scanMapUsedItemIds(file:File):void
        {
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
            throw new Error("Mapa OTBM invalido: marcador root nao encontrado.");
        }

        private function scanNodeForUsedIds(bytes:ByteArray):void
        {
            if (bytes.bytesAvailable < 2)
                throw new Error("Mapa OTBM invalido: fim inesperado.");

            var marker:uint = bytes.readUnsignedByte();
            if (marker != NODE_START)
                throw new Error("Mapa OTBM invalido: node start esperado.");

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
                        throw new Error("Mapa OTBM invalido: escape pendente.");
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

            throw new Error("Mapa OTBM invalido: node nao fechado.");
        }

        private function rewriteNodeTo(source:ByteArray, target:ByteArray):void
        {
            if (source.bytesAvailable < 2)
                throw new Error("Mapa OTBM invalido: fim inesperado.");

            var marker:uint = source.readUnsignedByte();
            if (marker != NODE_START)
                throw new Error("Mapa OTBM invalido: node start esperado.");

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
                        throw new Error("Mapa OTBM invalido: escape pendente.");
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

            throw new Error("Mapa OTBM invalido: node nao fechado.");
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
                        if (rewrite)
                            rewriteItemIdAt(props, offset);
                        else
                        {
                            mapCompactItemsCount++;
                            addUsedServerId(readU16(props, offset));
                        }
                        offset += 2;
                        break;

                    default:
                        return;
                }
            }
        }

        private function addUsedServerId(serverId:uint):void
        {
            if (serverId == 0)
                return;
            m_usedServerIds[serverId] = true;
            m_occurrences[serverId] = uint(m_occurrences[serverId]) + 1;
        }

        private function buildRemap(ids:Array, startServerId:uint):void
        {
            var nextId:uint = startServerId > 0 ? startServerId : 100;
            for each (var oldServerId:uint in ids)
            {
                if (nextId > 0xFFFF)
                    throw new Error("Novo server ID passou de 65535. Use menos itens ou outro formato.");
                m_oldToNew[oldServerId] = nextId++;
            }
        }

        private function buildXmlDefinedServerIds(serverItems:ServerItemStorage):Dictionary
        {
            var result:Dictionary = new Dictionary();
            if (!serverItems || !serverItems.loaded || !serverItems.items)
                return result;

            for each (var item:ServerItem in serverItems.items.toArray())
            {
                if (!item || item.id == 0)
                    continue;
                if (hasXmlDefinition(item))
                    result[item.id] = true;
            }

            return result;
        }

        private function hasXmlDefinition(item:ServerItem):Boolean
        {
            if (!item)
                return false;
            if (item.nameXml && item.nameXml.length > 0)
                return true;

            var attrs:Dictionary = item.getXmlAttributes();
            if (!attrs)
                return false;

            for (var key:* in attrs)
                return true;

            return false;
        }

        private function sortedUsedIds():Array
        {
            var ids:Array = [];
            for (var key:* in m_usedServerIds)
                ids.push(uint(key));
            ids.sort(Array.NUMERIC);
            return ids;
        }

        private function rewriteItemIdAt(props:ByteArray, offset:uint):void
        {
            var oldId:uint = readU16(props, offset);
            if (m_oldToNew[oldId] === undefined)
                return;

            var newId:uint = uint(m_oldToNew[oldId]);
            if (newId != oldId)
                rewrittenMapItemsCount++;
            writeU16(props, offset, newId);
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

        private function writeUsedCsv(file:File, ids:Array):void
        {
            var stream:FileStream = new FileStream();
            stream.open(file, FileMode.WRITE);
            stream.writeUTFBytes("server_id,client_id,occurrences,name" + File.lineEnding);
            for each (var serverId:uint in ids)
            {
                var item:ServerItem = getServerItem(serverId);
                stream.writeUTFBytes(serverId + "," +
                        (item ? item.clientId : "") + "," +
                        uint(m_occurrences[serverId]) + "," +
                        (item ? csv(getServerItemName(item)) : "") +
                        File.lineEnding);
            }
            stream.close();
        }

        private function writeRemapCsv(file:File, ids:Array):void
        {
            var stream:FileStream = new FileStream();
            stream.open(file, FileMode.WRITE);
            stream.writeUTFBytes("old_server_id,new_server_id,client_id,occurrences,name" + File.lineEnding);
            for each (var oldServerId:uint in ids)
            {
                var item:ServerItem = getServerItem(oldServerId);
                stream.writeUTFBytes(oldServerId + "," +
                        uint(m_oldToNew[oldServerId]) + "," +
                        (item ? item.clientId : "") + "," +
                        uint(m_occurrences[oldServerId]) + "," +
                        (item ? csv(getServerItemName(item)) : "") +
                        File.lineEnding);
            }
            stream.close();
        }

        private function getServerItem(serverId:uint):ServerItem
        {
            return m_items ? m_items.getItemById(serverId) : null;
        }

        private function getServerItemName(item:ServerItem):String
        {
            if (item.nameXml && item.nameXml.length > 0)
                return item.nameXml;
            if (item.name && item.name.length > 0)
                return item.name;
            return "";
        }

        private function csv(value:String):String
        {
            if (!value)
                return "";
            if (value.indexOf("\"") >= 0)
                value = value.replace(/"/g, "\"\"");
            if (value.indexOf(",") >= 0 || value.indexOf("\"") >= 0 ||
                    value.indexOf("\r") >= 0 || value.indexOf("\n") >= 0)
                return "\"" + value + "\"";
            return value;
        }

        private function fileBaseName(file:File):String
        {
            var name:String = file.name;
            var dot:int = name.lastIndexOf(".");
            return dot > 0 ? name.substr(0, dot) : name;
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
    }
}
