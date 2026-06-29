package mapused
{
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.utils.ByteArray;
    import flash.utils.Dictionary;

    public class XmlItemReferenceRemapper
    {
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

        public function copyRemappedFolder(source:File, target:File, remap:Dictionary):Boolean
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

            copyFolderInternal(source, target, remap);
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
                    scanForReferences(child);
                return;
            }

            if (!isXmlFile(file))
                return;

            filesCount++;
            processXmlText(readText(file).text, null, m_referencedIds);
        }

        private function copyFolderInternal(source:File, target:File, remap:Dictionary):void
        {
            if (source.isDirectory)
            {
                if (!target.exists)
                    target.createDirectory();

                var children:Array = source.getDirectoryListing();
                for each (var child:File in children)
                    copyFolderInternal(child, target.resolvePath(child.name), remap);
                return;
            }

            copiedFilesCount++;
            if (!isXmlFile(source))
            {
                source.copyTo(target, true);
                return;
            }

            filesCount++;
            var loaded:Object = readText(source);
            var remapped:String = processXmlText(String(loaded.text), remap, null);
            writeText(target, remapped, String(loaded.encoding));
        }

        private function processXmlText(text:String, remap:Dictionary, collect:Dictionary):String
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
                result += processTag(String(match[0]), String(match[1]), remap, collect);
                lastIndex = tagPattern.lastIndex;
            }

            result += text.substr(lastIndex);
            return result;
        }

        private function processTag(tagText:String, tagName:String, remap:Dictionary, collect:Dictionary):String
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

                if (isItemListAttribute(normalizedAttr))
                    value = remapItemList(value, remap, collect);
                else if (isSingleItemAttribute(normalizedAttr) ||
                        isItemIdAttributeForTag(normalizedTag, normalizedAttr))
                    value = remapSingleItemValue(value, remap, collect);

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
            rememberReferenced(oldId, collect);

            if (!remap)
                return value;

            if (remap[oldId] === undefined)
            {
                rememberUnresolved(oldId);
                return value;
            }

            var newId:uint = uint(remap[oldId]);
            if (newId == oldId)
                return value;

            remappedValuesCount++;
            return preserveOuterWhitespace(value, String(newId));
        }

        private function remapItemList(value:String, remap:Dictionary, collect:Dictionary):String
        {
            var tokenPattern:RegExp = /(^|[,\s;\|])(\d+)(?=\s*(:|[,;\|\s]|$))/g;
            var result:String = "";
            var lastIndex:int = 0;
            var match:Object;

            while ((match = tokenPattern.exec(value)) != null)
            {
                result += value.substring(lastIndex, int(match.index));

                var prefix:String = String(match[1]);
                var oldText:String = String(match[2]);
                var oldId:uint = uint(oldText);
                var replacement:String = oldText;

                rememberReferenced(oldId, collect);
                if (remap)
                {
                    if (remap[oldId] !== undefined)
                    {
                        var newId:uint = uint(remap[oldId]);
                        if (newId != oldId)
                        {
                            replacement = String(newId);
                            remappedValuesCount++;
                        }
                    }
                    else
                    {
                        rememberUnresolved(oldId);
                    }
                }

                result += prefix + replacement;
                lastIndex = tokenPattern.lastIndex;
            }

            result += value.substr(lastIndex);
            return result;
        }

        private function rememberReferenced(id:uint, collect:Dictionary):void
        {
            if (!collect || id == 0)
                return;
            if (collect[id] !== undefined)
                return;
            collect[id] = true;
            referencedItemsCount++;
        }

        private function rememberUnresolved(id:uint):void
        {
            if (id == 0 || m_unresolvedIds[id] !== undefined)
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

        private function isItemIdAttributeForTag(tag:String, attr:String):Boolean
        {
            if (attr != "id" && attr != "fromid" && attr != "toid")
                return false;

            switch (tag)
            {
                case "item":
                case "reward":
                case "loot":
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

        private function isXmlFile(file:File):Boolean
        {
            return file && file.extension && file.extension.toLowerCase() == "xml";
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
            var encoding:String = detectEncoding(header);
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

        private function detectEncoding(header:String):String
        {
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
