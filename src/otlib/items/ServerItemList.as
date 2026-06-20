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
    import flash.utils.Dictionary;

    /**
     * Collection of ServerItems with OTB version metadata.
     * Provides lookup by both Server ID and Client ID.
     */
    public class ServerItemList
    {
        // --------------------------------------------------------------------------
        // PROPERTIES
        // --------------------------------------------------------------------------

        /** OTB Major version */
        public var majorVersion:uint;

        /** OTB Minor version (client version identifier) */
        public var minorVersion:uint;

        /** OTB Build number */
        public var buildNumber:uint;

        /** Client version number */
        public var clientVersion:uint;

        /** Items indexed by Server ID */
        private var _items:Dictionary;

        /** Items indexed by Client ID (may have multiple items per client ID) */
        private var _itemsByClientId:Dictionary;

        /** Minimum Server ID */
        private var _minId:uint = uint.MAX_VALUE;

        /** Maximum Server ID */
        private var _maxId:uint = 0;

        // --------------------------------------------------------------------------
        // CONSTRUCTOR
        // --------------------------------------------------------------------------

        public function ServerItemList()
        {
            _items = new Dictionary();
            _itemsByClientId = new Dictionary();
        }

        // --------------------------------------------------------------------------
        // GETTERS / SETTERS
        // --------------------------------------------------------------------------

        public function get count():uint
        {
            var c:uint = 0;
            for (var key:* in _items)
                c++;
            return c;
        }

        public function get minId():uint
        {
            return _minId == uint.MAX_VALUE ? 100 : _minId;
        }

        public function get maxId():uint
        {
            return _maxId == 0 ? 100 : _maxId;
        }

        // --------------------------------------------------------------------------
        // METHODS
        // --------------------------------------------------------------------------

        /**
         * Adds a server item to the list
         */
        public function add(item:ServerItem):void
        {
            if (!item)
                return;

            _items[item.id] = item;

            // Track by client ID
            if (!_itemsByClientId[item.clientId])
                _itemsByClientId[item.clientId] = [];

            (_itemsByClientId[item.clientId] as Array).push(item);

            // Update min/max
            if (item.id < _minId)
                _minId = item.id;
            if (item.id > _maxId)
                _maxId = item.id;
        }

        /**
         * Gets a server item by Server ID
         */
        public function getItemById(serverId:uint):ServerItem
        {
            return _items[serverId] as ServerItem;
        }

        /**
         * Alias for getItemById - matches ItemEditor naming
         */
        public function getByServerId(serverId:uint):ServerItem
        {
            return getItemById(serverId);
        }

        /**
         * Gets all server items that reference a Client ID
         */
        public function getItemsByClientId(clientId:uint):Array
        {
            return _itemsByClientId[clientId] as Array || [];
        }

        /**
         * Gets the first server item that references a Client ID
         */
        public function getFirstItemByClientId(clientId:uint):ServerItem
        {
            var items:Array = getItemsByClientId(clientId);
            return items.length > 0 ? items[0] as ServerItem : null;
        }

        /**
         * Checks if a Server ID exists
         */
        public function hasItem(serverId:uint):Boolean
        {
            return _items[serverId] != null;
        }

        /**
         * Checks if any item references a Client ID
         */
        public function hasClientId(clientId:uint):Boolean
        {
            return _itemsByClientId[clientId] != null;
        }

        /**
         * Returns all items as an array
         */
        public function toArray():Array
        {
            var result:Array = [];
            for each (var item:ServerItem in _items)
                result.push(item);

            // Sort by Server ID
            result.sortOn("id", Array.NUMERIC);
            return result;
        }

        /**
         * Clears all items
         */
        public function clear():void
        {
            _items = new Dictionary();
            _itemsByClientId = new Dictionary();
            _minId = uint.MAX_VALUE;
            _maxId = 0;
        }

        /**
         * Removes a server item by Server ID
         */
        public function removeItem(serverId:uint):Boolean
        {
            var item:ServerItem = _items[serverId] as ServerItem;
            if (!item)
                return false;

            // Remove from main dictionary
            delete _items[serverId];

            // Remove from client ID lookup
            var clientItems:Array = _itemsByClientId[item.clientId] as Array;
            if (clientItems)
            {
                var idx:int = clientItems.indexOf(item);
                if (idx >= 0)
                {
                    clientItems.splice(idx, 1);
                }
                if (clientItems.length == 0)
                {
                    delete _itemsByClientId[item.clientId];
                }
            }

            // Recalculate min/max if necessary
            if (serverId == _minId || serverId == _maxId)
            {
                _minId = uint.MAX_VALUE;
                _maxId = 0;
                for (var key:* in _items)
                {
                    var id:uint = uint(key);
                    if (id < _minId)
                        _minId = id;
                    if (id > _maxId)
                        _maxId = id;
                }
            }

            return true;
        }

        /**
         * Creates missing items for Client IDs that don't have server items.
         * This is used to sync OTB with dat when dat has more items.
         *
         * @param maxClientId Maximum client ID from tibia.dat
         * @return Number of items created
         */
        public function createMissingItems(maxClientId:uint, clientIds:Array = null, minClientId:uint = 100):uint
        {
            var created:uint = 0;
            var ids:Array = clientIds;
            if (!ids)
            {
                ids = [];
                for (var scanId:uint = minClientId; scanId <= maxClientId; scanId++)
                    ids.push(scanId);
            }

            // Scan the full DAT range, including gaps below the largest OTB client ID.
            for each (var value:Object in ids)
            {
                var cid:uint = uint(value);
                if (cid < minClientId || cid > maxClientId || hasClientId(cid))
                    continue;

                var newItem:ServerItem = new ServerItem();
                newItem.id = _maxId + 1;
                newItem.clientId = cid;
                newItem.spriteHash = new flash.utils.ByteArray();
                newItem.spriteHash.length = 16;

                add(newItem);
                created++;
            }

            return created;
        }

        /**
         * Gets the highest Client ID in use
         */
        public function getMaxClientId():uint
        {
            var maxCid:uint = 0;
            for each (var item:ServerItem in _items)
            {
                if (item.clientId > maxCid)
                    maxCid = item.clientId;
            }
            return maxCid;
        }
    }
}
