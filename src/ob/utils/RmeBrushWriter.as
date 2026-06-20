package ob.utils
{
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;

    import otlib.utils.ThingListItem;

    public final class RmeBrushWriter
    {
        private static const BORDER_EDGES:Array = ["n", "e", "s", "w", "cnw", "cne", "csw", "cse", "dnw", "dne", "dse", "dsw"];
        private static const WALL_TYPES:Array = ["horizontal", "vertical", "corner", "pole"];
        private static const TABLE_TYPES:Array = ["alone", "vertical", "horizontal", "north", "south", "east", "west"];

        public static function write(directory:File,
                type:String,
                name:String,
                tilesetName:String,
                selected:Vector.<ThingListItem>):String
        {
            if (!directory || !directory.exists || !directory.isDirectory)
                throw new Error("Invalid RME data directory.");
            if (!selected || selected.length == 0)
                throw new Error("Select item objects first.");

            var ids:Array = getServerIds(selected);
            validateAmount(type, ids.length);
            name = trim(name);
            tilesetName = trim(tilesetName);
            if (name.length == 0)
                throw new Error("Brush name is required.");
            if (tilesetName.length == 0)
                tilesetName = "Custom";

            var targetName:String = type == "wall" ? "walls.xml" :
                    type == "doodad" ? "doodads.xml" :
                    type == "border" ? "borders.xml" : "grounds.xml";
            var target:File = directory.resolvePath(targetName);
            var xml:XML = loadXml(target, "materials");

            if (type != "border" && hasBrush(xml, name))
                throw new Error("A brush named '" + name + "' already exists in " + targetName + ".");

            var brush:XML;
            var result:String;
            if (type == "border")
            {
                var borderId:uint = nextBorderId(xml);
                brush = <border/>;
                brush.@id = borderId;
                for (var edge:uint = 0; edge < BORDER_EDGES.length; edge++)
                {
                    var borderItem:XML = <borderitem/>;
                    borderItem.@edge = BORDER_EDGES[edge];
                    borderItem.@item = ids[edge];
                    brush.appendChild(borderItem);
                }
                xml.appendChild(brush);
                saveXml(target, xml);
                addRawTileset(directory, tilesetName, ids);
                result = "Border #" + borderId + " created in borders.xml and " + tilesetName + ".";
            }
            else
            {
                brush = <brush/>;
                brush.@name = name;
                brush.@type = type == "carpet" || type == "table" ? type : type;
                brush.@server_lookid = ids[0];

                if (type == "ground")
                    appendGroundItems(brush, ids);
                else if (type == "wall")
                    appendWalls(brush, ids);
                else if (type == "doodad")
                    appendDoodads(brush, ids);
                else if (type == "carpet")
                    appendCarpet(brush, ids);
                else if (type == "table")
                    appendTable(brush, ids);

                xml.appendChild(brush);
                saveXml(target, xml);
                addBrushTileset(directory, tilesetName, name, type == "doodad" ? "doodad" : "terrain");
                result = "Brush '" + name + "' created in " + targetName + " and " + tilesetName + ".";
            }
            return result;
        }

        private static function getServerIds(selected:Vector.<ThingListItem>):Array
        {
            var result:Array = [];
            var seen:Object = {};
            for each (var item:ThingListItem in selected)
            {
                if (!item || !item.thing)
                    continue;
                var id:uint = item.serverId;
                if (id == 0)
                    throw new Error("Client ID " + item.id + " has no Server ID in the loaded OTB.");
                if (!seen[id])
                {
                    seen[id] = true;
                    result.push(id);
                }
            }
            return result;
        }

        private static function validateAmount(type:String, count:uint):void
        {
            var required:uint = type == "border" ? 12 : type == "wall" ? 4 :
                    type == "carpet" ? 13 : type == "table" ? 7 : 1;
            if (count < required)
                throw new Error(type + " requires at least " + required + " selected items; found " + count + ".");
        }

        private static function appendGroundItems(brush:XML, ids:Array):void
        {
            var chance:uint = Math.max(1, Math.floor(1000 / ids.length));
            for each (var id:uint in ids)
            {
                var item:XML = <item/>;
                item.@id = id;
                item.@chance = chance;
                brush.appendChild(item);
            }
        }

        private static function appendWalls(brush:XML, ids:Array):void
        {
            for (var i:uint = 0; i < WALL_TYPES.length; i++)
            {
                var wall:XML = <wall/>;
                wall.@type = WALL_TYPES[i];
                var item:XML = <item/>;
                item.@id = ids[i];
                item.@chance = 100;
                wall.appendChild(item);
                brush.appendChild(wall);
            }
        }

        private static function appendDoodads(brush:XML, ids:Array):void
        {
            brush.@draggable = "true";
            brush.@on_blocking = "false";
            var chance:uint = Math.max(1, Math.floor(1000 / ids.length));
            for each (var id:uint in ids)
            {
                var item:XML = <item/>;
                item.@id = id;
                item.@chance = chance;
                brush.appendChild(item);
            }
        }

        private static function appendCarpet(brush:XML, ids:Array):void
        {
            var center:XML = <carpet/>;
            center.@align = "center";
            center.@id = ids[0];
            brush.appendChild(center);
            for (var i:uint = 0; i < BORDER_EDGES.length; i++)
            {
                var part:XML = <carpet/>;
                part.@align = BORDER_EDGES[i];
                part.@id = ids[i + 1];
                brush.appendChild(part);
            }
        }

        private static function appendTable(brush:XML, ids:Array):void
        {
            for (var i:uint = 0; i < TABLE_TYPES.length; i++)
            {
                var table:XML = <table/>;
                table.@align = TABLE_TYPES[i];
                var item:XML = <item/>;
                item.@id = ids[i];
                item.@chance = 100;
                table.appendChild(item);
                brush.appendChild(table);
            }
        }

        private static function addBrushTileset(directory:File, tilesetName:String, brushName:String, sectionName:String):void
        {
            var file:File = directory.resolvePath("tilesets.xml");
            var xml:XML = loadXml(file, "materials");
            var tileset:XML = findTileset(xml, tilesetName);
            if (!tileset)
            {
                tileset = <tileset/>;
                tileset.@name = tilesetName;
                xml.appendChild(tileset);
            }

            var section:XML = findDirectChild(tileset, sectionName);
            if (!section)
            {
                section = new XML("<" + sectionName + "/>");
                tileset.appendChild(section);
            }

            for each (var existing:XML in section.brush)
            {
                if (String(existing.@name) == brushName)
                    return;
            }
            var reference:XML = <brush/>;
            reference.@name = brushName;
            section.appendChild(reference);
            saveXml(file, xml);
        }

        private static function addRawTileset(directory:File, tilesetName:String, ids:Array):void
        {
            var file:File = directory.resolvePath("tilesets.xml");
            var xml:XML = loadXml(file, "materials");
            var tileset:XML = findTileset(xml, tilesetName);
            if (!tileset)
            {
                tileset = <tileset/>;
                tileset.@name = tilesetName;
                xml.appendChild(tileset);
            }
            var raw:XML = findDirectChild(tileset, "raw");
            if (!raw)
            {
                raw = <raw/>;
                tileset.appendChild(raw);
            }
            var existing:Object = {};
            for each (var old:XML in raw.item)
                existing[uint(old.@id)] = true;
            for each (var id:uint in ids)
            {
                if (existing[id])
                    continue;
                var item:XML = <item/>;
                item.@id = id;
                raw.appendChild(item);
            }
            saveXml(file, xml);
        }

        private static function hasBrush(xml:XML, name:String):Boolean
        {
            for each (var brush:XML in xml..brush)
            {
                if (String(brush.@name) == name)
                    return true;
            }
            return false;
        }

        private static function nextBorderId(xml:XML):uint
        {
            var max:uint = 0;
            for each (var border:XML in xml..border)
                max = Math.max(max, uint(border.@id));
            return max + 1;
        }

        private static function findTileset(xml:XML, name:String):XML
        {
            for each (var tileset:XML in xml..tileset)
            {
                if (String(tileset.@name) == name)
                    return tileset;
            }
            return null;
        }

        private static function findDirectChild(parent:XML, name:String):XML
        {
            for each (var child:XML in parent.children())
            {
                if (child.name() && child.name().localName == name)
                    return child;
            }
            return null;
        }

        private static function loadXml(file:File, rootName:String):XML
        {
            if (!file.exists)
                return new XML("<" + rootName + "/>");
            var stream:FileStream = new FileStream();
            stream.open(file, FileMode.READ);
            var text:String = stream.readUTFBytes(stream.bytesAvailable);
            stream.close();
            XML.ignoreWhitespace = true;
            return new XML(text);
        }

        private static function saveXml(file:File, xml:XML):void
        {
            if (file.exists)
                file.copyTo(file.parent.resolvePath(file.name + ".bak"), true);
            XML.prettyPrinting = true;
            XML.prettyIndent = 1;
            var stream:FileStream = new FileStream();
            stream.open(file, FileMode.WRITE);
            stream.writeUTFBytes("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\r\n" + xml.toXMLString() + "\r\n");
            stream.close();
        }

        private static function trim(value:String):String
        {
            return value ? value.replace(/^\s+|\s+$/g, "") : "";
        }
    }
}
