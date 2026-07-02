package mapused
{
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;

    public final class RmeCompactXmlWriter
    {
        public function write(outputDir:File, rows:Array, otbFile:File, itemsXmlFile:File):Object
        {
            if (!outputDir)
                throw new Error("Pasta de saida RME invalida.");
            if (!rows)
                rows = [];
            if (!outputDir.exists)
                outputDir.createDirectory();

            var rmeDir:File = outputDir.resolvePath("rme_data_use_this");
            if (!rmeDir.exists)
                rmeDir.createDirectory();

            if (otbFile && otbFile.exists)
                otbFile.copyTo(rmeDir.resolvePath("items.otb"), true);
            if (itemsXmlFile && itemsXmlFile.exists)
                itemsXmlFile.copyTo(rmeDir.resolvePath("items.xml"), true);

            var groups:Object = groupRows(rows);
            writeMaterials(rmeDir.resolvePath("materials.xml"));
            writeGrounds(rmeDir.resolvePath("grounds.xml"), groups.grounds);
            writeWalls(rmeDir.resolvePath("walls.xml"), groups.walls);
            writeDoodads(rmeDir.resolvePath("doodads.xml"), groups.doodads);
            writeBorders(rmeDir.resolvePath("borders.xml"));
            writeTilesets(rmeDir.resolvePath("tilesets.xml"), groups);

            return {
                directory: rmeDir.nativePath,
                grounds: groups.grounds.length,
                walls: groups.walls.length,
                doodads: groups.doodads.length,
                raw: groups.raw.length,
                liquids: groups.liquids.length,
                pickups: groups.pickups.length
            };
        }

        private function groupRows(rows:Array):Object
        {
            var groups:Object = {
                grounds: [],
                walls: [],
                doodads: [],
                raw: [],
                liquids: [],
                pickups: []
            };

            var seen:Object = {};
            for each (var row:Object in rows)
            {
                if (!row || row.serverId == 0 || seen[row.serverId])
                    continue;
                seen[row.serverId] = true;

                if (row.liquid)
                    groups.liquids.push(row);
                else if (row.ground)
                    groups.grounds.push(row);
                else if (row.wall)
                    groups.walls.push(row);
                else if (row.pickup)
                    groups.pickups.push(row);
                else if (row.top || row.bottom || row.unpassable)
                    groups.doodads.push(row);
                else
                    groups.raw.push(row);
            }

            sortGroup(groups.grounds);
            sortGroup(groups.walls);
            sortGroup(groups.doodads);
            sortGroup(groups.raw);
            sortGroup(groups.liquids);
            sortGroup(groups.pickups);
            return groups;
        }

        private function writeMaterials(file:File):void
        {
            var xml:String = '<materials>\r\n' +
                    '\t<include file="borders.xml"/>\r\n' +
                    '\t<include file="grounds.xml"/>\r\n' +
                    '\t<include file="walls.xml"/>\r\n' +
                    '\t<include file="doodads.xml"/>\r\n' +
                    '\t<include file="tilesets.xml"/>\r\n' +
                    '</materials>\r\n';
            writeText(file, xml);
        }

        private function writeGrounds(file:File, rows:Array):void
        {
            var xml:String = '<materials>\r\n';
            for each (var row:Object in rows)
            {
                xml += '\t<brush name="' + xmlEscape(brushName("auto ground", row)) +
                        '" type="ground" server_lookid="' + row.serverId + '" z-order="3500">\r\n' +
                        '\t\t<item id="' + row.serverId + '" chance="1000"/>\r\n' +
                        '\t</brush>\r\n';
            }
            xml += '</materials>\r\n';
            writeText(file, xml);
        }

        private function writeWalls(file:File, rows:Array):void
        {
            var xml:String = '<materials>\r\n';
            for each (var row:Object in rows)
            {
                xml += '\t<brush name="' + xmlEscape(brushName("auto wall", row)) +
                        '" type="wall" server_lookid="' + row.serverId + '">\r\n' +
                        '\t\t<wall type="horizontal">\r\n' +
                        '\t\t\t<item id="' + row.serverId + '" chance="100"/>\r\n' +
                        '\t\t</wall>\r\n' +
                        '\t</brush>\r\n';
            }
            xml += '</materials>\r\n';
            writeText(file, xml);
        }

        private function writeDoodads(file:File, rows:Array):void
        {
            var xml:String = '<materials>\r\n';
            for each (var row:Object in rows)
            {
                xml += '\t<brush name="' + xmlEscape(brushName("auto doodad", row)) +
                        '" type="doodad" server_lookid="' + row.serverId +
                        '" draggable="true" on_blocking="false">\r\n' +
                        '\t\t<item id="' + row.serverId + '" chance="1000"/>\r\n' +
                        '\t</brush>\r\n';
            }
            xml += '</materials>\r\n';
            writeText(file, xml);
        }

        private function writeBorders(file:File):void
        {
            writeText(file, '<materials>\r\n</materials>\r\n');
        }

        private function writeTilesets(file:File, groups:Object):void
        {
            var xml:String = '<materials>\r\n';
            xml += writeTileset("Map Used Grounds", "raw", groups.grounds);
            xml += writeTileset("Map Used Walls", "raw", groups.walls);
            xml += writeTileset("Map Used Doodads", "raw", groups.doodads);
            xml += writeTileset("Map Used Pickups", "raw", groups.pickups);
            xml += writeTileset("Map Used Liquids", "raw", groups.liquids);
            xml += writeTileset("Map Used Raw", "raw", groups.raw);
            xml += '</materials>\r\n';
            writeText(file, xml);
        }

        private function writeTileset(name:String, section:String, rows:Array):String
        {
            if (!rows || rows.length == 0)
                return "";

            var xml:String = '\t<tileset name="' + xmlEscape(name) + '">\r\n' +
                    '\t\t<' + section + '>\r\n';
            for each (var row:Object in rows)
                xml += '\t\t\t<item id="' + row.serverId + '"/>\r\n';
            xml += '\t\t</' + section + '>\r\n' +
                    '\t</tileset>\r\n';
            return xml;
        }

        private function brushName(prefix:String, row:Object):String
        {
            var name:String = row.name ? String(row.name) : "";
            name = name.replace(/^\s+|\s+$/g, "");
            if (name.length == 0)
                name = prefix + " " + row.serverId;
            return name + " [" + row.serverId + "]";
        }

        private function sortGroup(rows:Array):void
        {
            rows.sortOn("serverId", Array.NUMERIC);
        }

        private function writeText(file:File, text:String):void
        {
            var stream:FileStream = new FileStream();
            stream.open(file, FileMode.WRITE);
            stream.writeUTFBytes('<?xml version="1.0" encoding="UTF-8"?>\r\n' + text);
            stream.close();
        }

        private function xmlEscape(value:String):String
        {
            if (!value)
                return "";
            return value.replace(/&/g, "&amp;")
                    .replace(/</g, "&lt;")
                    .replace(/>/g, "&gt;")
                    .replace(/"/g, "&quot;");
        }
    }
}
