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
*  The above copyright notice and this permission notice shall be included in
*  all copies or substantial portions of the Software.
*
*  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
*  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
*  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
*  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
*  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
*  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
*  THE SOFTWARE.
*/

package otlib.items
{
    import flash.events.EventDispatcher;
    import flash.filesystem.File;

    import nail.errors.NullArgumentError;
    import nail.logging.Log;

    import ob.commands.ProgressBarID;

    import otlib.events.ProgressEvent;
    import otlib.storages.events.StorageEvent;
    import otlib.things.ThingType;
    import otlib.sprites.SpriteStorage;
    import otlib.utils.OTFormat;

    /**
     * Storage for server items (OTB) with load and compile methods.
     * Follows the same pattern as ThingTypeStorage and SpriteStorage.
     */
    public class ServerItemStorage extends EventDispatcher
    {
        // --------------------------------------------------------------------------
        // PROPERTIES
        // --------------------------------------------------------------------------

        private var _file:File;
        private var _items:ServerItemList;
        private var _loaded:Boolean;
        private var _changed:Boolean;
        private var _definitionFormat:String;
        private var _binaryFormat:String;

        // --------------------------------------------------------------------------
        // CONSTRUCTOR
        // --------------------------------------------------------------------------

        public var knownAttributeKeys:Array;

        public function ServerItemStorage()
        {
            _items = new ServerItemList();
            _loaded = false;
            _changed = false;
        }

        // --------------------------------------------------------------------------
        // GETTERS / SETTERS
        // --------------------------------------------------------------------------

        public function get file():File
        {
            return _file;
        }
        public function get items():ServerItemList
        {
            return _items;
        }
        public function get loaded():Boolean
        {
            return _loaded;
        }
        public function get changed():Boolean
        {
            return _changed;
        }
        public function get definitionFormat():String
        {
            return _definitionFormat;
        }
        public function get binaryFormat():String
        {
            return _binaryFormat;
        }

        // --------------------------------------------------------------------------
        // PUBLIC METHODS
        // --------------------------------------------------------------------------

        /**
         * Loads OTB file and optionally items.xml from the same directory.
         *
         * @param file The OTB file to load.
         * @return true if load was successful, false otherwise.
         */
        public function load(file:File):Boolean
        {
            if (!file || !file.exists)
            {
                Log.error("Server items file not found: " + (file ? file.nativePath : "null"));
                return false;
            }

            if (_loaded)
            {
                unload();
            }

            // Re-initialize items if needed
            if (!_items)
                _items = new ServerItemList();

            var ext:String = file.extension ? file.extension.toLowerCase() : "";
            var success:Boolean = false;

            if (ext == "otb")
            {
                var reader:OtbReader = new OtbReader();
                if (reader.read(file))
                {
                    _items = reader.items;
                    _binaryFormat = OTFormat.OTB;
                    success = true;

                    // Legacy behavior: Try to load items.xml from same directory if loading OTB
                    var parentDir:File = file.parent;
                    if (parentDir && parentDir.exists)
                    {
                        var xmlFile:File = parentDir.resolvePath("items.xml");
                        Log.info("Attempting to load items.xml from: " + xmlFile.nativePath);

                        if (xmlFile.exists)
                        {
                            if (loadDefinitionsFromXml(xmlFile))
                            {
                                Log.info("Successfully loaded items.xml");
                                _definitionFormat = OTFormat.XML;
                            }
                            else
                            {
                                Log.error("Failed to parse items.xml");
                            }
                        }
                        else
                        {
                            Log.info("items.xml not found at expected path.");
                        }
                    }
                }
            }
            else if (ext == "dat")
            {
                // DAT-based server items: the item metadata comes from the client's DAT
                // which is already loaded in ThingTypeStorage. We just need to:
                // 1. Record that this server uses DAT format
                // 2. Load definitions from XML/TOML in the same directory
                Log.info("DAT-based server items detected: " + file.nativePath);

                // Determine if it's tibia.dat or assets.dat
                var fileName:String = file.name.toLowerCase();
                if (fileName == "assets.dat")
                    _binaryFormat = OTFormat.ASSETS;
                else
                    _binaryFormat = OTFormat.DAT;

                // Items will be populated from client's ThingTypeStorage later
                // For now, just try to load definitions from the same directory
                parentDir = file.parent;
                if (parentDir && parentDir.exists)
                {
                    xmlFile = parentDir.resolvePath("items.xml");
                    var tomlFile:File = parentDir.resolvePath("items.toml");

                    if (xmlFile.exists)
                    {
                        if (loadDefinitionsFromXml(xmlFile))
                        {
                            Log.info("Successfully loaded items.xml for DAT-based server");
                            _definitionFormat = OTFormat.XML;
                            success = true;
                        }
                        else
                        {
                            Log.error("Failed to parse items.xml");
                        }
                    }
                    else if (tomlFile.exists)
                    {
                        Log.error("TOML format not yet implemented");
                    }
                    else
                    {
                        Log.info("No items.xml or items.toml found for DAT-based server");
                        success = true; // DAT exists, definitions are optional
                    }
                }
                else
                {
                    success = true; // Just DAT, no definitions
                }
            }
            else if (ext == "toml")
            {
                Log.error("TOML format not yet implemented");
                success = false;
            }
            else
            {
                Log.error("Unknown server items format: " + ext);
                return false;
            }

            if (success)
            {
                _file = file;
                _loaded = true;
                _changed = false;
                dispatchEvent(new StorageEvent(StorageEvent.LOAD));
                dispatchEvent(new StorageEvent(StorageEvent.CHANGE));
            }

            return success;
        }

        private function loadDefinitionsFromXml(file:File):Boolean
        {
            var xmlReader:ItemsXmlReader = new ItemsXmlReader();
            if (knownAttributeKeys)
            {
                xmlReader.setKnownAttributes(knownAttributeKeys);
            }

            if (xmlReader.read(file.nativePath, _items))
            {
                // Log any missing attributes
                var missing:Array = xmlReader.getMissingAttributes();
                if (missing.length > 0)
                {
                    var xmlOutput:String = "=== Missing attributes (" + missing.length + " total) ===<br/>";
                    for each (var key:String in missing)
                    {
                        xmlOutput += '&lt;attribute key="' + key + '" type="string" category="Unknown"/&gt;<br/>';
                    }
                    Log.info(xmlOutput);
                }
                return true;
            }
            return false;
        }

        /**
         * Saves the server items to a file in the specified format (Binary/Peer).
         * Supports OTB, DAT, and ASSETS.
         *
         * @param file The destination file.
         * @param format The format to save as (e.g., OTB, DAT, ASSETS).
         * @param sourcePeer Optional source file for DAT/ASSETS format (the Client DAT file).
         */
        public function save(file:File, format:String, sourcePeer:File = null):Boolean
        {
            if (!_loaded || !_items)
                return false;

            if (format == OTFormat.OTB)
            {
                var writer:OtbWriter = new OtbWriter(_items);
                if (writer.write(file))
                {
                    _changed = false;
                    return true;
                }
            }
            else if (format == OTFormat.DAT || format == OTFormat.ASSETS)
            {
                if (sourcePeer && sourcePeer.exists)
                {
                    try
                    {
                        sourcePeer.copyTo(file, true);
                        return true;
                    }
                    catch (error:Error)
                    {
                        Log.error("Failed to copy peer file: " + error.message);
                    }
                }
                else
                {
                    Log.error("Source peer file not provided or does not exist for format: " + format);
                }
            }

            return false;
        }

        /**
         * Saves the item definitions to a file in the specified format.
         * Supports XML and TOML (Stub).
         */
        public function saveDefinitions(file:File, format:String):Boolean
        {
            if (!_loaded || !_items)
                return false;

            if (format == OTFormat.XML)
            {
                var xmlWriter:ItemsXmlWriter = new ItemsXmlWriter();
                var registry:ItemAttributeStorage = ItemAttributeStorage.getInstance();
                if (registry.isInitialized && registry.currentServer)
                {
                    xmlWriter.setAttributePriority(registry.getAttributePriority());
                    xmlWriter.setSupportsFromToId(registry.getSupportsFromToId());
                    xmlWriter.setTagAttributeKeys(registry.getTagAttributeKeys());
                }
                return xmlWriter.write(file.nativePath, _items);
            }
            else if (format == OTFormat.TOML)
            {
                Log.error("TOML format not yet implemented");
                return false;
            }

            return false;
        }

        /**
         * Unloads the current OTB data.
         */
        public function unload():void
        {
            if (!_loaded)
                return;

            dispatchEvent(new StorageEvent(StorageEvent.UNLOADING));

            _file = null;
            _items = null;
            _loaded = false;
            _changed = false;

            dispatchEvent(new StorageEvent(StorageEvent.UNLOAD));
        }

        public function getItem(serverId:uint):ServerItem
        {
            if (!_loaded || !_items)
                return null;
            return _items.getItemById(serverId);
        }

        /**
         * Removes a server item by Server ID
         */
        public function removeItem(serverId:uint):Boolean
        {
            if (!_loaded || !_items)
                return false;
            return _items.removeItem(serverId);
        }

        /**
         * Gets the first server item by its Client ID.
         */
        public function getItemByClientId(clientId:uint):ServerItem
        {
            if (!_loaded || !_items)
                return null;
            return _items.getFirstItemByClientId(clientId);
        }

        /**
         * Gets all server items that map to a Client ID.
         */
        public function getItemsByClientId(clientId:uint):Array
        {
            if (!_loaded || !_items)
                return null;
            return _items.getItemsByClientId(clientId);
        }

        /**
         * Creates missing items for client IDs that don't have OTB entries.
         *
         * @param maxClientId Maximum client ID from DAT file
         * @return Number of items created
         */
        public function createMissingItems(maxClientId:uint, clientIds:Array = null):uint
        {
            if (!_loaded || !_items)
            {
                Log.error("No OTB loaded. Cannot create missing items.");
                return 0;
            }

            var created:uint = _items.createMissingItems(maxClientId, clientIds);
            if (created > 0)
            {
                _changed = true;
                dispatchEvent(new StorageEvent(StorageEvent.CHANGE));
            }
            return created;
        }

        /**
         * Gets the maximum client ID currently in OTB
         */
        public function getMaxClientId():uint
        {
            if (!_loaded || !_items)
                return 0;
            return _items.getMaxClientId();
        }

        /**
         * Marks the storage as changed, triggering Compile to become available.
         */
        public function invalidate():void
        {
            if (!_changed)
            {
                _changed = true;

                if (hasEventListener(StorageEvent.CHANGE))
                    dispatchEvent(new StorageEvent(StorageEvent.CHANGE));
            }
        }
        public function updateItemsFromThing(thing:ThingType, version:uint, sprites:SpriteStorage):Boolean
        {
            if (!_loaded || !_items)
                return false;

            var serverItems:Array = _items.getItemsByClientId(thing.id);
            var updated:Boolean = false;

            if (serverItems && serverItems.length > 0)
            {
                for each (var si:ServerItem in serverItems)
                {
                    OtbSync.syncFromThingType(si, thing, true, version, sprites);
                    updated = true;
                }
            }

            if (updated)
            {
                invalidate();
            }

            return updated;
        }
    }
}
