package mapused
{
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.utils.ByteArray;
    import flash.utils.Dictionary;

    public class XmlItemReferenceRemapper
    {
        private static const MIN_SERVER_ITEM_ID:uint = 100;

        private static const SERVER_DATA_FOLDERS:Object = {
                "XML": true,
                "actions": true,
                "creaturescripts": true,
                "globalevents": true,
                "lib": true,
                "monster": true,
                "movements": true,
                "npc": true,
                "raids": true,
                "spells": true,
                "talkactions": true,
                "weapons": true
            };

        public var filesCount:uint;
        public var copiedFilesCount:uint;
        public var remappedValuesCount:uint;
        public var referencedItemsCount:uint;
        public var unresolvedItemIdsCount:uint;

        private var m_referencedIds:Dictionary;
        private var m_unresolvedIds:Dictionary;

        public function XmlItemReferenceRemapper()
        {
            resetStats();
        }

        public function collectReferencedItemIds(root:File):Dictionary
        {
            resetStats();
            if (!root || !root.exists)
                return new Dictionary();

            scanForReferences(root);
            return copyDictionary(m_referencedIds);
        }

        public function copyRemappedFolder(source:File,
                target:File,
                remap:Dictionary,
                outfitRemap:Dictionary = null,
                effectRemap:Dictionary = null,
                missileRemap:Dictionary = null):Boolean
        {
            if (!source || !source.exists || !target)
                return false;

            filesCount = 0;
            copiedFilesCount = 0;
            remappedValuesCount = 0;
            unresolvedItemIdsCount = 0;
            m_unresolvedIds = new Dictionary();

            if (target.exists)
                target.deleteDirectory(true);
            target.createDirectory();

            copyFolderInternal(source, target, remap, outfitRemap, effectRemap, missileRemap);
            return true;
        }

        private function resetStats():void
        {
            filesCount = 0;
            copiedFilesCount = 0;
            remappedValuesCount = 0;
            referencedItemsCount = 0;
            unresolvedItemIdsCount = 0;
            m_referencedIds = new Dictionary();
            m_unresolvedIds = new Dictionary();
        }

        private function scanForReferences(file:File):void
        {
            if (file.isDirectory)
            {
                var children:Array = file.getDirectoryListing();
                for each (var child:File in children)
                {
                    if (isServerDataRoot(file) && !isAllowedServerDataFolder(child))
                        continue;
                    scanForReferences(child);
                }
                return;
            }

            if (!isRemappableTextFile(file))
                return;

            filesCount++;
            processFileText(file, readText(file).text, null, m_referencedIds, null, null, null);
        }

        private function copyFolderInternal(source:File,
                target:File,
                remap:Dictionary,
                outfitRemap:Dictionary,
                effectRemap:Dictionary,
                missileRemap:Dictionary):void
        {
            if (source.isDirectory)
            {
                if (!target.exists)
                    target.createDirectory();

                var children:Array = source.getDirectoryListing();
                for each (var child:File in children)
                {
                    if (isServerDataRoot(source) && !isAllowedServerDataFolder(child))
                        continue;
                    copyFolderInternal(child,
                            target.resolvePath(child.name),
                            remap,
                            outfitRemap,
                            effectRemap,
                            missileRemap);
                }
                return;
            }

            copiedFilesCount++;
            if (!isRemappableTextFile(source))
            {
                source.copyTo(target, true);
                return;
            }

            filesCount++;
            var loaded:Object = readText(source);
            var remapped:String = processFileText(source,
                    String(loaded.text),
                    remap,
                    null,
                    outfitRemap,
                    effectRemap,
                    missileRemap);
            writeText(target, remapped, String(loaded.encoding));
        }

        private function processFileText(file:File,
                text:String,
                remap:Dictionary,
                collect:Dictionary,
                outfitRemap:Dictionary,
                effectRemap:Dictionary,
                missileRemap:Dictionary):String
        {
            if (isXmlFile(file))
                return processXmlText(text, remap, collect, outfitRemap, effectRemap, missileRemap);
            if (isLuaFile(file))
                return processLuaText(text, remap, collect, outfitRemap, effectRemap, missileRemap);
            return text;
        }

        private function processXmlText(text:String,
                remap:Dictionary,
                collect:Dictionary,
                outfitRemap:Dictionary,
                effectRemap:Dictionary,
                missileRemap:Dictionary):String
        {
            if (!text || text.length == 0)
                return text;

            var tagPattern:RegExp = /<\s*([A-Za-z_][A-Za-z0-9_:\.-]*)([^<>]*)>/g;
            var result:String = "";
            var lastIndex:int = 0;
            var match:Object;

            while ((match = tagPattern.exec(text)) != null)
            {
                result += text.substring(lastIndex, int(match.index));
                result += processTag(String(match[0]),
                        String(match[1]),
                        remap,
                        collect,
                        outfitRemap,
                        effectRemap,
                        missileRemap);
                lastIndex = tagPattern.lastIndex;
            }

            result += text.substr(lastIndex);
            return result;
        }

        private function processTag(tagText:String,
                tagName:String,
                remap:Dictionary,
                collect:Dictionary,
                outfitRemap:Dictionary,
                effectRemap:Dictionary,
                missileRemap:Dictionary):String
        {
            var normalizedTag:String = normalizeName(tagName);
            var attrPattern:RegExp = /([A-Za-z_][A-Za-z0-9_:\.-]*)(\s*=\s*)(["'])([^"']*)\3/g;
            var result:String = "";
            var lastIndex:int = 0;
            var match:Object;

            while ((match = attrPattern.exec(tagText)) != null)
            {
                result += tagText.substring(lastIndex, int(match.index));

                var attrName:String = String(match[1]);
                var separator:String = String(match[2]);
                var quote:String = String(match[3]);
                var value:String = String(match[4]);
                var normalizedAttr:String = normalizeName(attrName);

                if (isItemListAttribute(normalizedAttr) ||
                        isListLikeSingleItemAttribute(normalizedTag, normalizedAttr, value))
                {
                    value = remapItemList(value, remap, collect);
                }
                else if (isSingleItemAttribute(normalizedAttr) ||
                        isItemIdAttributeForTag(normalizedTag, normalizedAttr))
                {
                    value = remapSingleItemValue(value, remap, collect);
                }
                else if (outfitRemap && isOutfitAttribute(normalizedAttr))
                {
                    value = remapAssetValue(value, outfitRemap);
                }
                else if (effectRemap && isEffectAttribute(normalizedAttr))
                {
                    value = remapAssetValue(value, effectRemap);
                }
                else if (missileRemap && isMissileAttribute(normalizedAttr))
                {
                    value = remapAssetValue(value, missileRemap);
                }

                result += attrName + separator + quote + value + quote;
                lastIndex = attrPattern.lastIndex;
            }

            result += tagText.substr(lastIndex);
            return result;
        }

        private function remapSingleItemValue(value:String, remap:Dictionary, collect:Dictionary):String
        {
            var trimmed:String = trim(value);
            if (!isUnsignedInteger(trimmed))
                return value;

            var oldId:uint = uint(trimmed);
            return preserveOuterWhitespace(value, remapItemNumber(oldId, trimmed, remap, collect));
        }

        private function remapItemList(value:String, remap:Dictionary, collect:Dictionary):String
        {
            var tokenPattern:RegExp = /(\d+)\s*-\s*(\d+)|(\d+)/g;
            var result:String = "";
            var lastIndex:int = 0;
            var match:Object;

            while ((match = tokenPattern.exec(value)) != null)
            {
                result += value.substring(lastIndex, int(match.index));

                var original:String = String(match[0]);
                if (isCountSideOfPair(value, int(match.index)))
                {
                    result += original;
                    lastIndex = tokenPattern.lastIndex;
                    continue;
                }

                if (match[1] !== undefined && String(match[1]).length > 0)
                {
                    result += remapItemRange(String(match[1]), String(match[2]), original, remap, collect);
                }
                else
                {
                    result += remapItemNumber(uint(match[3]), String(match[3]), remap, collect);
                }

                lastIndex = tokenPattern.lastIndex;
            }

            result += value.substr(lastIndex);
            return result;
        }

        private function remapItemRange(startText:String,
                endText:String,
                original:String,
                remap:Dictionary,
                collect:Dictionary):String
        {
            if (!isUnsignedInteger(startText) || !isUnsignedInteger(endText))
                return original;

            var start:uint = uint(startText);
            var end:uint = uint(endText);
            if (end < start || end - start > 10000)
                return original;

            var values:Array = [];
            for (var id:uint = start; id <= end; id++)
                values.push(remapItemNumber(id, String(id), remap, collect));
            return values.join(";");
        }

        private function remapItemNumber(oldId:uint,
                original:String,
                remap:Dictionary,
                collect:Dictionary):String
        {
            if (!isServerItemId(oldId))
                return original;

            rememberReferenced(oldId, collect);

            if (!remap)
                return original;

            if (remap[oldId] === undefined)
            {
                rememberUnresolved(oldId);
                return original;
            }

            var newId:uint = uint(remap[oldId]);
            if (newId == oldId)
                return original;

            remappedValuesCount++;
            return String(newId);
        }

        private function processLuaText(text:String,
                remap:Dictionary,
                collect:Dictionary,
                outfitRemap:Dictionary,
                effectRemap:Dictionary,
                missileRemap:Dictionary):String
        {
            if (!text || text.length == 0)
                return text;

            text = remapLuaPattern(text,
                    /(\b(?:itemid|itemId|itemID|item_id|itemtype|itemType|itemTypeId|itemtypeid|rewardItemId|rewarditemid|requiredItemId|requireditemid|consumeItemId|consumeitemid|currencyItemId|currencyitemid|priceItemId|priceitemid|paymentItemId|paymentitemid|bagId|bagid|containerId|containerid|backpackId|backpackid|empty|vial|to|from|transformTo|transformto|decayTo|decayto|rewardId|rewardid|reward)\b\s*=\s*)(\d+)/g,
                    remap,
                    collect);

            text = remapLuaPattern(text,
                    /(\[\s*)(\d+)(\s*\]\s*=)/g,
                    remap,
                    collect);

            text = remapLuaPattern(text,
                    /(\b(?:doCreateItemEx|doCreateItem|getItemInfo|getItemNameById|getItemWeightById|getItemDescriptionsById)\s*\(\s*)(\d+)/g,
                    remap,
                    collect);

            text = remapLuaPattern(text,
                    /(\b(?:doPlayerAddItem|doPlayerRemoveItem|getPlayerItemCount|doAddContainerItem|doTransformItem|getTileItemById|getTileItemByType)\s*\([^()\r\n]*?,\s*)(\d+)/g,
                    remap,
                    collect);

            text = remapLuaPattern(text,
                    /(\b[A-Za-z_][A-Za-z0-9_]*\.itemid\s*(?:==|~=)\s*)(\d+)/g,
                    remap,
                    collect);

            text = remapLuaPattern(text,
                    /(\{[^\r\n{}]*\bid\s*=\s*)(\d+)(?=[^\r\n{}]*(?:count|chance|reward|amount|mincount|maxcount|item))/g,
                    remap,
                    collect);

            text = remapLuaPattern(text,
                    /(\b(?:[A-Z0-9_]*ITEM[A-Z0-9_]*|[A-Z0-9_]*COIN[A-Z0-9_]*|TILE_[A-Z0-9_]+)\s*=\s*)(\d+)/g,
                    remap,
                    collect);

            if (outfitRemap)
            {
                text = remapLuaAssetPattern(text,
                        /(\b(?:looktype|lookType|look_type|lookTypeId|looktypeid|outfitId|outfitid|outfitType|outfittype)\b\s*=\s*)(\d+)/g,
                        outfitRemap);
            }

            if (effectRemap)
            {
                text = remapLuaAssetPattern(text,
                        /(\b(?:effect|effectId|effectid|magicEffect|magiceffect|magicEffectId|magiceffectid|effectType|effecttype)\b\s*=\s*)(\d+)/g,
                        effectRemap);
                text = remapLuaAssetPattern(text,
                        /(\b(?:doSendMagicEffect|sendMagicEffect)\s*\([^\r\n]*,\s*)(\d+)/g,
                        effectRemap);
            }

            if (missileRemap)
            {
                text = remapLuaAssetPattern(text,
                        /(\b(?:missile|missileId|missileid|distanceEffect|distanceeffect|distanceEffectId|distanceeffectid|shootEffect|shooteffect|shootEffectId|shooteffectid)\b\s*=\s*)(\d+)/g,
                        missileRemap);
                text = remapLuaAssetPattern(text,
                        /(\b(?:doSendDistanceShoot|sendDistanceShoot)\s*\([^\r\n]*,\s*[^\r\n]*,\s*)(\d+)/g,
                        missileRemap);
            }

            return text;
        }

        private function remapLuaPattern(text:String,
                pattern:RegExp,
                remap:Dictionary,
                collect:Dictionary):String
        {
            var result:String = "";
            var lastIndex:int = 0;
            var match:Object;

            while ((match = pattern.exec(text)) != null)
            {
                result += text.substring(lastIndex, int(match.index));
                result += String(match[1]) + remapNumericToken(String(match[2]), remap, collect);
                if (match.length > 3)
                    result += String(match[3]);
                lastIndex = pattern.lastIndex;
            }

            result += text.substr(lastIndex);
            return result;
        }

        private function remapLuaAssetPattern(text:String,
                pattern:RegExp,
                remap:Dictionary):String
        {
            var result:String = "";
            var lastIndex:int = 0;
            var match:Object;

            while ((match = pattern.exec(text)) != null)
            {
                result += text.substring(lastIndex, int(match.index));
                result += String(match[1]) + remapAssetNumber(uint(match[2]), String(match[2]), remap);
                if (match.length > 3)
                    result += String(match[3]);
                lastIndex = pattern.lastIndex;
            }

            result += text.substr(lastIndex);
            return result;
        }

        private function remapAssetValue(value:String, remap:Dictionary):String
        {
            var trimmed:String = trim(value);
            if (!trimmed || !/^\d+(\s*[-,;|]\s*\d+)*$/.test(trimmed))
                return value;
            return preserveOuterWhitespace(value, remapAssetList(trimmed, remap));
        }

        private function remapAssetList(value:String, remap:Dictionary):String
        {
            var tokenPattern:RegExp = /(\d+)\s*-\s*(\d+)|(\d+)/g;
            var result:String = "";
            var lastIndex:int = 0;
            var match:Object;

            while ((match = tokenPattern.exec(value)) != null)
            {
                result += value.substring(lastIndex, int(match.index));
                if (match[1] !== undefined && String(match[1]).length > 0)
                    result += remapAssetRange(String(match[1]), String(match[2]), String(match[0]), remap);
                else
                    result += remapAssetNumber(uint(match[3]), String(match[3]), remap);
                lastIndex = tokenPattern.lastIndex;
            }

            result += value.substr(lastIndex);
            return result;
        }

        private function remapAssetRange(startText:String,
                endText:String,
                original:String,
                remap:Dictionary):String
        {
            if (!isUnsignedInteger(startText) || !isUnsignedInteger(endText))
                return original;

            var start:uint = uint(startText);
            var end:uint = uint(endText);
            if (end < start || end - start > 10000)
                return original;

            var values:Array = [];
            for (var id:uint = start; id <= end; id++)
                values.push(remapAssetNumber(id, String(id), remap));
            return values.join(";");
        }

        private function remapAssetNumber(oldId:uint,
                original:String,
                remap:Dictionary):String
        {
            if (oldId == 0 || !remap || remap[oldId] === undefined)
                return original;

            var newId:uint = uint(remap[oldId]);
            if (newId == oldId)
                return original;

            remappedValuesCount++;
            return String(newId);
        }

        private function remapNumericToken(value:String, remap:Dictionary, collect:Dictionary):String
        {
            if (!isUnsignedInteger(value))
                return value;

            return remapItemNumber(uint(value), value, remap, collect);
        }

        private function rememberReferenced(id:uint, collect:Dictionary):void
        {
            if (!collect || !isServerItemId(id))
                return;
            if (collect[id] !== undefined)
                return;
            collect[id] = true;
            referencedItemsCount++;
        }

        private function rememberUnresolved(id:uint):void
        {
            if (!isServerItemId(id) || m_unresolvedIds[id] !== undefined)
                return;
            m_unresolvedIds[id] = true;
            unresolvedItemIdsCount++;
        }

        private function isSingleItemAttribute(name:String):Boolean
        {
            if (name == "clientid" || name == "looktype" || name == "looktypeex" ||
                    name == "outfitstorage" || name == "storage" || name == "uniqueid" ||
                    name == "actionid" || name == "questid")
            {
                return false;
            }

            if (name == "item" || name == "itemid" || name == "itemtype" ||
                    name == "itemtypeid" || name == "bagid" || name == "containerid" ||
                    name == "backpackid" || name == "rewarditemid" || name == "requireditemid" ||
                    name == "consumeitemid" || name == "currencyitemid" || name == "priceitemid" ||
                    name == "paymentitemid" || name == "removeitemid" || name == "additemid")
            {
                return true;
            }

            return name.indexOf("itemid") >= 0;
        }

        private function isItemListAttribute(name:String):Boolean
        {
            return name == "items" || name == "itemids" || name == "rewards" ||
                    name == "rewarditems" || name == "costitems" || name == "requireditems" ||
                    name == "consumeitems" || name == "paymentitems" || name == "lootitems";
        }

        private function isListLikeSingleItemAttribute(tag:String, attr:String, value:String):Boolean
        {
            if (!(isSingleItemAttribute(attr) || isItemIdAttributeForTag(tag, attr)))
                return false;
            return value && /[,;\|\-]/.test(value);
        }

        private function isItemIdAttributeForTag(tag:String, attr:String):Boolean
        {
            if (attr != "id" && attr != "fromid" && attr != "toid")
                return false;

            switch (tag)
            {
                case "item":
                case "reward":
                case "loot":
                case "rune":
                case "melee":
                case "distance":
                case "wand":
                case "weapon":
                case "ammo":
                case "ingredient":
                case "material":
                case "cost":
                case "currency":
                case "consume":
                case "require":
                case "requireditem":
                case "giveitem":
                case "createitem":
                    return true;
            }
            return false;
        }

        private function isOutfitAttribute(name:String):Boolean
        {
            return name == "looktype" || name == "looktypeid" ||
                    name == "outfitid" || name == "outfittype";
        }

        private function isEffectAttribute(name:String):Boolean
        {
            return name == "effect" || name == "effectid" ||
                    name == "magiceffect" || name == "magiceffectid";
        }

        private function isMissileAttribute(name:String):Boolean
        {
            return name == "missile" || name == "missileid" ||
                    name == "distanceeffect" || name == "distanceeffectid" ||
                    name == "shooteffect" || name == "shooteffectid";
        }

        private function isAllowedServerDataFolder(file:File):Boolean
        {
            return file && file.isDirectory && SERVER_DATA_FOLDERS[file.name] === true;
        }

        private function isServerDataRoot(file:File):Boolean
        {
            if (!file || !file.isDirectory)
                return false;
            return file.resolvePath("items").exists &&
                    file.resolvePath("world").exists &&
                    (file.resolvePath("actions").exists || file.resolvePath("XML").exists);
        }

        private function isRemappableTextFile(file:File):Boolean
        {
            return isXmlFile(file) || isLuaFile(file);
        }

        private function isXmlFile(file:File):Boolean
        {
            return file && file.extension && file.extension.toLowerCase() == "xml";
        }

        private function isLuaFile(file:File):Boolean
        {
            return file && file.extension && file.extension.toLowerCase() == "lua";
        }

        private function readText(file:File):Object
        {
            var stream:FileStream = new FileStream();
            var bytes:ByteArray = new ByteArray();
            stream.open(file, FileMode.READ);
            stream.readBytes(bytes, 0, stream.bytesAvailable);
            stream.close();

            bytes.position = 0;
            var header:String = bytes.readUTFBytes(Math.min(bytes.length, 256));
            var encoding:String = detectEncoding(header, isXmlFile(file));
            bytes.position = 0;

            var text:String;
            if (encoding.toLowerCase() == "utf-8" || encoding.toLowerCase() == "utf8")
                text = bytes.readUTFBytes(bytes.length);
            else
                text = bytes.readMultiByte(bytes.length, encoding);

            return { text: text, encoding: encoding };
        }

        private function writeText(file:File, text:String, encoding:String):void
        {
            if (file.parent && !file.parent.exists)
                file.parent.createDirectory();

            var stream:FileStream = new FileStream();
            stream.open(file, FileMode.WRITE);
            if (!encoding || encoding.toLowerCase() == "utf-8" || encoding.toLowerCase() == "utf8")
                stream.writeUTFBytes(text);
            else
                stream.writeMultiByte(text, encoding);
            stream.close();
        }

        private function detectEncoding(header:String, xml:Boolean):String
        {
            if (!xml)
                return "iso-8859-1";

            if (!header)
                return "utf-8";

            var match:Object = /encoding\s*=\s*["']([^"']+)["']/i.exec(header);
            if (match && match.length > 1)
                return String(match[1]);

            return "utf-8";
        }

        private function normalizeName(value:String):String
        {
            if (!value)
                return "";
            return value.toLowerCase().replace(/[_\-:\.]/g, "");
        }

        private function trim(value:String):String
        {
            return value ? value.replace(/^\s+|\s+$/g, "") : "";
        }

        private function isUnsignedInteger(value:String):Boolean
        {
            return value && /^\d+$/.test(value);
        }

        private function isCountSideOfPair(value:String, tokenIndex:int):Boolean
        {
            var index:int = tokenIndex - 1;
            while (index >= 0 && /\s/.test(value.charAt(index)))
                index--;
            return index >= 0 && value.charAt(index) == ":";
        }

        private function isServerItemId(id:uint):Boolean
        {
            return id >= MIN_SERVER_ITEM_ID && id <= 0xFFFF;
        }

        private function preserveOuterWhitespace(original:String, replacement:String):String
        {
            var leading:Object = /^\s*/.exec(original);
            var trailing:Object = /\s*$/.exec(original);
            return String(leading ? leading[0] : "") + replacement + String(trailing ? trailing[0] : "");
        }

        private function copyDictionary(source:Dictionary):Dictionary
        {
            var result:Dictionary = new Dictionary();
            for (var key:* in source)
                result[uint(key)] = true;
            return result;
        }
    }
}
