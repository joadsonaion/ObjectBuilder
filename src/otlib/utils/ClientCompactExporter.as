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
    import nail.utils.StringUtil;

    import ob.commands.ProgressBarID;

    import otlib.animation.FrameGroup;
    import otlib.core.ClientFeatures;
    import otlib.core.Version;
    import otlib.events.ProgressEvent;
    import otlib.sprites.Sprite;
    import otlib.sprites.SpriteStorage;
    import otlib.things.FrameGroupType;
    import otlib.things.ThingCategory;
    import otlib.things.ThingType;
    import otlib.things.ThingTypeStorage;

    [Event(name="progress", type="otlib.events.ProgressEvent")]

    public class ClientCompactExporter extends EventDispatcher
    {
        private var m_objects:ThingTypeStorage;
        private var m_sprites:SpriteStorage;
        private var m_oldToNewSpriteId:Dictionary;
        private var m_hashToNewSpriteId:Dictionary;
        private var m_newSprites:Dictionary;
        private var m_nextSpriteId:uint;
        private var m_mapping:Array;

        public var oldSpriteCount:uint;
        public var newSpriteCount:uint;
        public var reusedSpritesCount:uint;
        public var removedSpritesCount:uint;
        public var itemsCount:uint;
        public var outfitsCount:uint;
        public var effectsCount:uint;
        public var missilesCount:uint;

        public function ClientCompactExporter(objects:ThingTypeStorage, sprites:SpriteStorage)
        {
            if (!objects)
                throw new NullArgumentError("objects");
            if (!sprites)
                throw new NullArgumentError("sprites");

            m_objects = objects;
            m_sprites = sprites;
        }

        public function export(datFile:File,
                sprFile:File,
                mapFile:File,
                version:Version,
                features:ClientFeatures,
                preserveThingIds:Boolean = false):Boolean
        {
            if (!datFile)
                throw new NullArgumentError("datFile");
            if (!sprFile)
                throw new NullArgumentError("sprFile");
            if (!preserveThingIds && !mapFile)
                throw new NullArgumentError("mapFile");
            if (!version)
                throw new NullArgumentError("version");
            if (!features)
                throw new NullArgumentError("features");

            oldSpriteCount = m_sprites.spritesCount;
            reusedSpritesCount = 0;
            m_nextSpriteId = 1;
            m_oldToNewSpriteId = new Dictionary();
            m_hashToNewSpriteId = new Dictionary();
            m_newSprites = new Dictionary();
            m_mapping = [];

            dispatchProgress(0, 8, preserveThingIds ? "Preparing same-ID compact export" : "Preparing grouped compact export");

            var itemList:Dictionary = cloneItems();
            var outfitList:Dictionary;
            var effectList:Dictionary;
            var missileList:Dictionary;

            if (preserveThingIds)
            {
                dispatchProgress(1, 8, "Preserving outfit IDs");
                outfitList = clonePreservedCategory(ThingCategory.OUTFIT);

                dispatchProgress(2, 8, "Preserving effect IDs");
                effectList = clonePreservedCategory(ThingCategory.EFFECT);

                dispatchProgress(3, 8, "Preserving missile IDs");
                missileList = clonePreservedCategory(ThingCategory.MISSILE);
            }
            else
            {
                dispatchProgress(1, 8, "Grouping outfits");
                outfitList = cloneGroupedCategory(ThingCategory.OUTFIT);

                dispatchProgress(2, 8, "Grouping effects");
                effectList = cloneGroupedCategory(ThingCategory.EFFECT);

                dispatchProgress(3, 8, "Grouping missiles");
                missileList = cloneGroupedCategory(ThingCategory.MISSILE);
            }

            newSpriteCount = m_nextSpriteId > 1 ? m_nextSpriteId - 1 : 1;
            removedSpritesCount = oldSpriteCount > newSpriteCount ? oldSpriteCount - newSpriteCount : 0;

            var compileFeatures:ClientFeatures = features.clone();
            compileFeatures.applyVersionDefaults(version.value);
            if (!compileFeatures.extended && version.value < 960 && newSpriteCount >= 0xFFFF)
            {
                throw new Error("Compact SPR still has " + newSpriteCount + " sprites. Enable Extended or use a 9.60+ client version.");
            }

            dispatchProgress(4, 8, "Writing compact DAT");
            if (!m_objects.compileCustom(datFile,
                        version,
                        features,
                        itemList,
                        m_objects.itemsCount,
                        outfitList,
                        outfitsCount,
                        effectList,
                        effectsCount,
                        missileList,
                        missilesCount))
            {
                return false;
            }

            dispatchProgress(5, 8, "Writing compact SPR");
            if (!m_sprites.compileCustom(sprFile,
                        version,
                        features,
                        m_newSprites,
                        newSpriteCount))
            {
                return false;
            }

            if (preserveThingIds)
            {
                dispatchProgress(6, 8, "All client IDs preserved");
            }
            else
            {
                dispatchProgress(6, 8, "Writing ID map");
                writeMapping(mapFile);
            }

            dispatchProgress(7, 8, "Compact export complete");
            return true;
        }

        private function cloneItems():Dictionary
        {
            dispatchProgress(0, 8, "Preserving item IDs");
            var result:Dictionary = new Dictionary();
            itemsCount = m_objects.itemsCount;

            for (var id:uint = ThingTypeStorage.MIN_ITEM_ID; id <= itemsCount; id++)
            {
                var thing:ThingType = m_objects.items[id] as ThingType;
                if (!thing)
                    continue;

                var clone:ThingType = cloneThingWithRemappedSprites(thing);
                clone.id = id;
                clone.category = ThingCategory.ITEM;
                result[id] = clone;
            }
            return result;
        }

        private function clonePreservedCategory(category:String):Dictionary
        {
            var result:Dictionary = new Dictionary();
            var list:Dictionary;
            var maxId:uint;

            switch (category)
            {
                case ThingCategory.OUTFIT:
                    list = m_objects.outfits;
                    maxId = m_objects.outfitsCount;
                    outfitsCount = maxId;
                    break;
                case ThingCategory.EFFECT:
                    list = m_objects.effects;
                    maxId = m_objects.effectsCount;
                    effectsCount = maxId;
                    break;
                case ThingCategory.MISSILE:
                    list = m_objects.missiles;
                    maxId = m_objects.missilesCount;
                    missilesCount = maxId;
                    break;
            }

            for (var id:uint = 1; id <= maxId; id++)
            {
                var thing:ThingType = list[id] as ThingType;
                if (!thing)
                    continue;

                var clone:ThingType = cloneThingWithRemappedSprites(thing);
                clone.id = id;
                clone.category = category;
                result[id] = clone;
            }
            return result;
        }

        private function cloneGroupedCategory(category:String):Dictionary
        {
            var result:Dictionary = new Dictionary();
            var entries:Array = collectEntries(category);
            entries.sort(sortEntries);

            var nextId:uint = 1;
            for each (var entry:Object in entries)
            {
                var clone:ThingType = cloneThingWithRemappedSprites(entry.thing as ThingType);
                clone.id = nextId;
                clone.category = category;
                result[nextId] = clone;
                m_mapping.push({
                            category: category,
                            oldId: entry.id,
                            newId: nextId,
                            group: entry.group,
                            name: entry.name
                        });
                nextId++;
            }

            var count:uint = nextId > 1 ? nextId - 1 : 1;
            switch (category)
            {
                case ThingCategory.OUTFIT:
                    outfitsCount = count;
                    break;
                case ThingCategory.EFFECT:
                    effectsCount = count;
                    break;
                case ThingCategory.MISSILE:
                    missilesCount = count;
                    break;
            }
            return result;
        }

        private function collectEntries(category:String):Array
        {
            var list:Dictionary;
            var maxId:uint;
            switch (category)
            {
                case ThingCategory.OUTFIT:
                    list = m_objects.outfits;
                    maxId = m_objects.outfitsCount;
                    break;
                case ThingCategory.EFFECT:
                    list = m_objects.effects;
                    maxId = m_objects.effectsCount;
                    break;
                case ThingCategory.MISSILE:
                    list = m_objects.missiles;
                    maxId = m_objects.missilesCount;
                    break;
            }

            var result:Array = [];
            for (var id:uint = 1; id <= maxId; id++)
            {
                var thing:ThingType = list[id] as ThingType;
                if (!ThingUtils.isValid(thing) || ThingUtils.isEmpty(thing))
                    continue;

                var name:String = getThingName(thing);
                result.push({
                            id: id,
                            thing: thing,
                            group: getGroupName(name),
                            sortName: getSortName(name, id),
                            name: name
                        });
            }
            return result;
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

            var hash:String = sprite.getHash();
            if (!hash)
            {
                m_oldToNewSpriteId[oldId] = 0;
                return 0;
            }

            if (m_hashToNewSpriteId[hash] !== undefined)
            {
                var duplicateId:uint = uint(m_hashToNewSpriteId[hash]);
                m_oldToNewSpriteId[oldId] = duplicateId;
                reusedSpritesCount++;
                return duplicateId;
            }

            var newId:uint = m_nextSpriteId++;
            var clonedSprite:Sprite = sprite.clone();
            clonedSprite.id = newId;
            m_newSprites[newId] = clonedSprite;
            m_hashToNewSpriteId[hash] = newId;
            m_oldToNewSpriteId[oldId] = newId;
            return newId;
        }

        private function sortEntries(a:Object, b:Object):int
        {
            var groupA:String = String(a.group).toLowerCase();
            var groupB:String = String(b.group).toLowerCase();
            if (groupA < groupB)
                return -1;
            if (groupA > groupB)
                return 1;

            if (a.sortName < b.sortName)
                return -1;
            if (a.sortName > b.sortName)
                return 1;

            return uint(a.id) < uint(b.id) ? -1 : (uint(a.id) > uint(b.id) ? 1 : 0);
        }

        private function getThingName(thing:ThingType):String
        {
            if (thing.name && thing.name.length > 0)
                return thing.name;
            if (thing.marketName && thing.marketName.length > 0)
                return thing.marketName;
            return "";
        }

        private function getSortName(name:String, id:uint):String
        {
            var normalized:String = normalizeName(name);
            if (normalized.length == 0)
                return padNumber(id);
            return normalized + " " + padNumber(id);
        }

        private function getGroupName(name:String):String
        {
            var normalized:String = normalizeName(name);
            if (normalized.length == 0)
                return "Unlabeled";

            for each (var group:Object in CHARACTER_GROUPS)
            {
                var aliases:Array = group.aliases as Array;
                for each (var alias:String in aliases)
                {
                    if (containsWord(normalized, alias))
                        return String(group.name);
                }
            }

            var tokens:Array = normalized.split(" ");
            while (tokens.length > 0 && isIgnoredToken(String(tokens[0])))
                tokens.shift();
            if (tokens.length > 1 && isClanToken(String(tokens[0])))
                tokens.shift();

            if (tokens.length == 0)
                return "Unlabeled";

            return titleCase(String(tokens[0]));
        }

        private function normalizeName(value:String):String
        {
            if (!value)
                return "";

            var result:String = StringUtil.toKeyString(value);
            result = result.toLowerCase();
            result = result.replace(/[_\-\.\:\;\,\(\)\[\]\{\}\/\\]+/g, " ");
            result = result.replace(/[0-9]+/g, " ");
            result = result.replace(/\s+/g, " ");
            result = result.replace(/^\s+|\s+$/g, "");
            return result;
        }

        private function containsWord(value:String, word:String):Boolean
        {
            return (" " + value + " ").indexOf(" " + word + " ") != -1;
        }

        private function isIgnoredToken(value:String):Boolean
        {
            return IGNORED_TOKENS[value] === true;
        }

        private function isClanToken(value:String):Boolean
        {
            return CLAN_TOKENS[value] === true;
        }

        private function titleCase(value:String):String
        {
            if (!value || value.length == 0)
                return "";
            return value.charAt(0).toUpperCase() + value.substr(1);
        }

        private function padNumber(value:uint):String
        {
            var text:String = value.toString();
            while (text.length < 8)
                text = "0" + text;
            return text;
        }

        private function writeMapping(file:File):void
        {
            var stream:FileStream = new FileStream();
            stream.open(file, FileMode.WRITE);
            stream.writeUTFBytes("category,old_id,new_id,group,name" + File.lineEnding);
            for each (var row:Object in m_mapping)
            {
                stream.writeUTFBytes(csv(row.category) + "," +
                        row.oldId + "," +
                        row.newId + "," +
                        csv(row.group) + "," +
                        csv(row.name) + File.lineEnding);
            }
            stream.close();
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

        private static const CHARACTER_GROUPS:Array = [
            {name:"Naruto", aliases:["naruto"]},
            {name:"Sasuke", aliases:["sasuke"]},
            {name:"Sakura", aliases:["sakura"]},
            {name:"Kakashi", aliases:["kakashi"]},
            {name:"Itachi", aliases:["itachi"]},
            {name:"Madara", aliases:["madara"]},
            {name:"Obito", aliases:["obito", "tobi"]},
            {name:"Minato", aliases:["minato"]},
            {name:"Jiraiya", aliases:["jiraiya"]},
            {name:"Tsunade", aliases:["tsunade"]},
            {name:"Orochimaru", aliases:["orochimaru"]},
            {name:"Gaara", aliases:["gaara"]},
            {name:"Rock Lee", aliases:["rock lee"]},
            {name:"Neji", aliases:["neji"]},
            {name:"Hinata", aliases:["hinata"]},
            {name:"Shikamaru", aliases:["shikamaru"]},
            {name:"Ino", aliases:["ino"]},
            {name:"Choji", aliases:["choji", "chouji"]},
            {name:"Kiba", aliases:["kiba"]},
            {name:"Shino", aliases:["shino"]},
            {name:"Tenten", aliases:["tenten", "ten ten"]},
            {name:"Temari", aliases:["temari"]},
            {name:"Kankuro", aliases:["kankuro"]},
            {name:"Pain", aliases:["pain"]},
            {name:"Nagato", aliases:["nagato"]},
            {name:"Konan", aliases:["konan"]},
            {name:"Kisame", aliases:["kisame"]},
            {name:"Deidara", aliases:["deidara"]},
            {name:"Sasori", aliases:["sasori"]},
            {name:"Hidan", aliases:["hidan"]},
            {name:"Kakuzu", aliases:["kakuzu"]},
            {name:"Zetsu", aliases:["zetsu"]},
            {name:"Hashirama", aliases:["hashirama"]},
            {name:"Tobirama", aliases:["tobirama"]},
            {name:"Hiruzen", aliases:["hiruzen"]},
            {name:"Boruto", aliases:["boruto"]},
            {name:"Sarada", aliases:["sarada"]},
            {name:"Mitsuki", aliases:["mitsuki"]},
            {name:"Kaguya", aliases:["kaguya"]},
            {name:"Hagoromo", aliases:["hagoromo"]},
            {name:"Killer Bee", aliases:["killer bee"]},
            {name:"Yamato", aliases:["yamato"]},
            {name:"Sai", aliases:["sai"]}
        ];

        private static const IGNORED_TOKENS:Object = {
            outfit:true,
            outfits:true,
            effect:true,
            effects:true,
            missile:true,
            missiles:true,
            anim:true,
            animation:true,
            front:true,
            back:true,
            left:true,
            right:true,
            idle:true,
            walk:true,
            walking:true,
            attack:true,
            spell:true,
            jutsu:true
        };

        private static const CLAN_TOKENS:Object = {
            uchiha:true,
            uzumaki:true,
            haruno:true,
            hatake:true,
            nara:true,
            hyuga:true,
            hyuuga:true,
            akimichi:true,
            yamanaka:true,
            aburame:true,
            inuzuka:true,
            senju:true,
            sabaku:true,
            otsutsuki:true,
            ootsutsuki:true
        };
    }
}
