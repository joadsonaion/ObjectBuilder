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

package otlib.utils
{
    import com.mignari.errors.FileNotFoundError;
    import com.mignari.errors.NullArgumentError;

    import by.blooddy.crypto.MD5;

    import flash.events.ErrorEvent;
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.filesystem.File;
    import flash.utils.ByteArray;
    import flash.utils.Dictionary;

    import ob.commands.ProgressBarID;

    import otlib.core.Version;
    import otlib.core.ClientFeatures;
    import otlib.core.otlib_internal;
    import otlib.events.ProgressEvent;
    import otlib.sprites.SpriteStorage;
    import otlib.storages.StorageQueueLoader;
    import otlib.things.ThingCategory;
    import otlib.things.ThingType;
    import otlib.things.ThingTypeStorage;
    import otlib.animation.FrameDuration;
    import otlib.animation.FrameGroup;
    import otlib.things.FrameGroupType;
    import ob.settings.ObjectBuilderSettings;

    use namespace otlib_internal;

    [Event(name="progress", type="otlib.events.ProgressEvent")]
    [Event(name="complete", type="flash.events.Event")]

    public class ClientMerger extends EventDispatcher
    {
        private var m_objects:ThingTypeStorage;
        private var m_sprites:SpriteStorage;
        private var m_spriteIds:Dictionary;
        private var m_itemsCount:uint;
        private var m_outfitsCount:uint;
        private var m_effectsCount:uint;
        private var m_missilesCount:uint;
        private var m_spritesCount:uint;
        private var m_reusedSpritesCount:uint;
        private var m_skippedObjectsCount:uint;
        private var m_sourceObjectsCount:uint;
        private var m_sourceReferencedSpritesCount:uint;
        private var m_ignoredOrphanSpritesCount:uint;
        private var m_reuseExistingSprites:Boolean;
        private var m_previewOnly:Boolean;
        private var m_mergeMode:String;
        private var m_existingSpriteIds:Dictionary;
        private var m_currentSpriteHashes:Dictionary;
        private var m_existingThingKeys:Dictionary;
        private var m_sourceSpriteIds:Dictionary;

        private var m_currentObjects:ThingTypeStorage;
        private var m_currentSprites:SpriteStorage;

        private var m_settings:ObjectBuilderSettings;

        // --------------------------------------
        // Getters / Setters
        // --------------------------------------

        public function get itemsCount():uint
        {
            return m_itemsCount;
        }
        public function get outfitsCount():uint
        {
            return m_outfitsCount;
        }
        public function get effectsCount():uint
        {
            return m_effectsCount;
        }
        public function get missilesCount():uint
        {
            return m_missilesCount;
        }
        public function get spritesCount():uint
        {
            return m_spritesCount;
        }
        public function get reusedSpritesCount():uint
        {
            return m_reusedSpritesCount;
        }
        public function get skippedObjectsCount():uint
        {
            return m_skippedObjectsCount;
        }
        public function get sourceObjectsCount():uint
        {
            return m_sourceObjectsCount;
        }
        public function get sourceReferencedSpritesCount():uint
        {
            return m_sourceReferencedSpritesCount;
        }
        public function get ignoredOrphanSpritesCount():uint
        {
            return m_ignoredOrphanSpritesCount;
        }

        // --------------------------------------------------------------------------
        // CONSTRUCTOR
        // --------------------------------------------------------------------------

        public function ClientMerger(objects:ThingTypeStorage, sprites:SpriteStorage, settings:ObjectBuilderSettings)
        {
            if (!objects)
                throw new NullArgumentError("objects");

            if (!sprites)
                throw new NullArgumentError("sprites");

            if (!settings)
                throw new NullArgumentError("settings");

            m_currentObjects = objects;
            m_currentSprites = sprites;
            m_settings = settings;
        }

        // --------------------------------------------------------------------------
        // METHODS
        // --------------------------------------------------------------------------

        // --------------------------------------
        // Public
        // --------------------------------------

        public function start(datFile:File,
                sprFile:File,
                version:Version,
                features:ClientFeatures,
                optimizeSprites:Boolean = true,
                reuseExistingSprites:Boolean = true,
                mergeMode:String = "all",
                previewOnly:Boolean = false):void
        {
            if (!datFile)
                throw new NullArgumentError("datFile");

            if (!datFile.exists)
                throw new FileNotFoundError(datFile);

            if (!sprFile)
                throw new NullArgumentError("sprFile");

            if (!sprFile.exists)
                throw new FileNotFoundError(sprFile);

            if (!version)
                throw new NullArgumentError("version");

            m_reuseExistingSprites = reuseExistingSprites;
            m_mergeMode = mergeMode ? mergeMode : ClientMergeMode.ALL;
            m_previewOnly = previewOnly;
            m_reusedSpritesCount = 0;
            m_skippedObjectsCount = 0;
            m_sourceObjectsCount = 0;
            m_sourceReferencedSpritesCount = 0;
            m_ignoredOrphanSpritesCount = 0;
            m_itemsCount = 0;
            m_outfitsCount = 0;
            m_effectsCount = 0;
            m_missilesCount = 0;
            m_spritesCount = 0;
            m_objects = new ThingTypeStorage(m_settings);
            m_objects.addEventListener(ErrorEvent.ERROR, errorHandler);

            m_sprites = new SpriteStorage();
            m_sprites.addEventListener(ErrorEvent.ERROR, errorHandler);

            var loader:StorageQueueLoader = new StorageQueueLoader();
            loader.addEventListener(Event.COMPLETE, completeHandler);
            loader.add(m_objects, m_objects.load, datFile, version, features);
            loader.add(m_sprites, m_sprites.load, sprFile, version, features);
            loader.start();

            function completeHandler(event:Event):void
            {
                loader.removeEventListener(Event.COMPLETE, completeHandler);

                if (optimizeSprites)
                    startOptimizeSprites();
                else
                    startMerge();
            }
        }

        // --------------------------------------
        // Private
        // --------------------------------------

        private function startOptimizeSprites():void
        {
            var optimizer:SpritesOptimizer = new SpritesOptimizer(m_objects, m_sprites);
            optimizer.addEventListener(ProgressEvent.PROGRESS, progressHandler);
            optimizer.addEventListener(Event.COMPLETE, completeHandler);
            optimizer.start();

            function progressHandler(event:ProgressEvent):void
            {
                dispatchEvent(event);
            }

            function completeHandler(event:Event):void
            {
                startMerge();
            }
        }

        private function startMerge():void
        {
            var oldItemsCount:uint = m_currentObjects.itemsCount;
            var oldOutfitsCount:uint = m_currentObjects.outfitsCount;
            var oldEffectsCount:uint = m_currentObjects.effectsCount;
            var oldMissilesCount:uint = m_currentObjects.missilesCount;
            var oldSpritesCount:uint = m_currentSprites.spritesCount;

            buildSourceSpriteIndex();

            if (m_reuseExistingSprites)
                buildExistingSpriteIndex();

            mergeSpriteList(1, m_sprites.spritesCount);
            dispatchEvent(new ProgressEvent(ProgressEvent.PROGRESS, ProgressBarID.DEFAULT, 1, 5));

            if (m_reuseExistingSprites)
                buildExistingThingIndex();

            mergeObjectList(m_objects.items, ThingCategory.ITEM, 100, m_objects.itemsCount);
            dispatchEvent(new ProgressEvent(ProgressEvent.PROGRESS, ProgressBarID.DEFAULT, 2, 5));

            mergeObjectList(m_objects.outfits, ThingCategory.OUTFIT, 1, m_objects.outfitsCount);
            dispatchEvent(new ProgressEvent(ProgressEvent.PROGRESS, ProgressBarID.DEFAULT, 3, 5));

            mergeObjectList(m_objects.effects, ThingCategory.EFFECT, 1, m_objects.effectsCount);
            dispatchEvent(new ProgressEvent(ProgressEvent.PROGRESS, ProgressBarID.DEFAULT, 4, 5));

            mergeObjectList(m_objects.missiles, ThingCategory.MISSILE, 1, m_objects.missilesCount);
            dispatchEvent(new ProgressEvent(ProgressEvent.PROGRESS, ProgressBarID.DEFAULT, 5, 5));

            if (!m_previewOnly)
            {
                m_itemsCount = m_currentObjects.itemsCount - oldItemsCount;
                m_outfitsCount = m_currentObjects.outfitsCount - oldOutfitsCount;
                m_effectsCount = m_currentObjects.effectsCount - oldEffectsCount;
                m_missilesCount = m_currentObjects.missilesCount - oldMissilesCount;
                m_spritesCount = m_currentSprites.spritesCount - oldSpritesCount;
            }

            if (!m_previewOnly && (m_itemsCount || m_outfitsCount || m_effectsCount || m_missilesCount))
                m_currentObjects.invalidate();
            if (!m_previewOnly && m_spritesCount)
                m_currentSprites.invalidate();

            // Cleanup temporary storages to prevent memory leak
            if (m_objects)
            {
                m_objects.unload();
                m_objects = null;
            }
            if (m_sprites)
            {
                m_sprites.unload();
                m_sprites = null;
            }
            m_spriteIds = null;
            m_existingSpriteIds = null;
            m_currentSpriteHashes = null;
            m_existingThingKeys = null;
            m_sourceSpriteIds = null;

            if (hasEventListener(Event.COMPLETE))
                dispatchEvent(new Event(Event.COMPLETE));
        }

        private function buildExistingSpriteIndex():void
        {
            m_existingSpriteIds = new Dictionary();
            m_currentSpriteHashes = new Dictionary();

            var count:uint = m_currentSprites.spritesCount;
            for (var id:uint = 1; id <= count; id++)
            {
                if (id % 1000 == 0)
                    dispatchEvent(new ProgressEvent(ProgressEvent.PROGRESS, ProgressBarID.DEFAULT, id, count, "Indexing existing sprites..."));

                if (m_currentSprites.isEmptySprite(id))
                    continue;

                var pixels:ByteArray = m_currentSprites.getPixels(id);
                if (!pixels)
                    continue;

                var hash:String = getPixelsHash(pixels);
                m_currentSpriteHashes[id] = hash;
                if (m_existingSpriteIds[hash] === undefined)
                    m_existingSpriteIds[hash] = id;
            }
        }

        private function buildExistingThingIndex():void
        {
            m_existingThingKeys = new Dictionary();

            indexThingList(m_currentObjects.items, ThingCategory.ITEM, 100, m_currentObjects.itemsCount);
            indexThingList(m_currentObjects.outfits, ThingCategory.OUTFIT, 1, m_currentObjects.outfitsCount);
            indexThingList(m_currentObjects.effects, ThingCategory.EFFECT, 1, m_currentObjects.effectsCount);
            indexThingList(m_currentObjects.missiles, ThingCategory.MISSILE, 1, m_currentObjects.missilesCount);
        }

        private function indexThingList(list:Dictionary, category:String, min:uint, max:uint):void
        {
            if (!list || max < min)
                return;

            for (var id:uint = min; id <= max; id++)
            {
                if (id % 1000 == 0)
                    dispatchEvent(new ProgressEvent(ProgressEvent.PROGRESS, ProgressBarID.DEFAULT, id, max, "Indexing existing objects..."));

                var thing:ThingType = list[id];
                if (ThingUtils.isEmpty(thing))
                    continue;

                thing.category = category;

                var key:String = getThingKey(thing);
                if (key)
                    m_existingThingKeys[key] = true;
            }
        }

        private function buildSourceSpriteIndex():void
        {
            m_sourceSpriteIds = null;

            if (!m_previewOnly && !m_reuseExistingSprites && m_mergeMode == ClientMergeMode.ALL)
                return;

            m_sourceSpriteIds = new Dictionary();
            collectSourceSpriteIds(m_objects.items, ThingCategory.ITEM, 100, m_objects.itemsCount);
            collectSourceSpriteIds(m_objects.outfits, ThingCategory.OUTFIT, 1, m_objects.outfitsCount);
            collectSourceSpriteIds(m_objects.effects, ThingCategory.EFFECT, 1, m_objects.effectsCount);
            collectSourceSpriteIds(m_objects.missiles, ThingCategory.MISSILE, 1, m_objects.missilesCount);

            var referenced:uint = 0;
            for (var key:Object in m_sourceSpriteIds)
                referenced++;
            m_sourceReferencedSpritesCount = referenced;

            for (var spriteId:uint = 1; spriteId <= m_sprites.spritesCount; spriteId++)
            {
                if (m_sourceSpriteIds[spriteId] === undefined && !m_sprites.isEmptySprite(spriteId))
                    m_ignoredOrphanSpritesCount++;
            }
        }

        private function collectSourceSpriteIds(list:Dictionary, category:String, min:uint, max:uint):void
        {
            if (!list || max < min)
                return;

            for (var id:uint = min; id <= max; id++)
            {
                var thing:ThingType = list[id];
                if (!shouldMergeThing(thing, category) || ThingUtils.isEmpty(thing))
                    continue;

                m_sourceObjectsCount++;

                for (var groupType:uint = FrameGroupType.DEFAULT; groupType <= FrameGroupType.WALKING; groupType++)
                {
                    var frameGroup:FrameGroup = thing.getFrameGroup(groupType);
                    if (!frameGroup || !frameGroup.spriteIndex)
                        continue;

                    var spriteIds:Vector.<uint> = frameGroup.spriteIndex;
                    for (var k:int = spriteIds.length - 1; k >= 0; k--)
                    {
                        var sid:uint = spriteIds[k];
                        if (sid != 0)
                            m_sourceSpriteIds[sid] = true;
                    }
                }
            }
        }

        private function mergeSpriteList(min:int, max:uint):void
        {
            m_spriteIds = new Dictionary();

            var result:ChangeResult = new ChangeResult();
            var simulatedSpriteId:uint = m_currentSprites.spritesCount;

            for (var id:int = min; id <= max; id++)
            {
                if (m_sourceSpriteIds && m_sourceSpriteIds[id] === undefined)
                {
                    m_spriteIds[id] = 0;
                    continue;
                }

                if (m_sprites.isEmptySprite(id))
                {
                    m_spriteIds[id] = 0;
                }
                else
                {
                    var pixels:ByteArray = m_sprites.getPixels(id);
                    var existingId:uint = getExistingSpriteId(pixels);
                    if (existingId != 0)
                    {
                        m_spriteIds[id] = existingId;
                        m_reusedSpritesCount++;
                    }
                    else
                    {
                        var hash:String = m_reuseExistingSprites ? getPixelsHash(pixels) : null;
                        if (m_previewOnly)
                        {
                            simulatedSpriteId++;
                            m_spritesCount++;
                            m_spriteIds[id] = simulatedSpriteId;
                        }
                        else
                        {
                            m_currentSprites.internalAddSprite(pixels, result);
                            m_spriteIds[id] = m_currentSprites.spritesCount;
                        }

                        if (m_reuseExistingSprites && hash && m_existingSpriteIds[hash] === undefined)
                            m_existingSpriteIds[hash] = m_spriteIds[id];
                        if (m_reuseExistingSprites && hash && m_currentSpriteHashes)
                            m_currentSpriteHashes[m_spriteIds[id]] = hash;
                    }
                }
            }
        }

        private function getExistingSpriteId(pixels:ByteArray):uint
        {
            if (!m_reuseExistingSprites || !pixels || !m_existingSpriteIds)
                return 0;

            var hash:String = getPixelsHash(pixels);
            if (m_existingSpriteIds[hash] !== undefined)
                return uint(m_existingSpriteIds[hash]);

            return 0;
        }

        private function getPixelsHash(pixels:ByteArray):String
        {
            pixels.position = 0;
            var hash:String = MD5.hashBytes(pixels);
            pixels.position = 0;
            return hash;
        }

        private function mergeObjectList(list:Dictionary, category:String, min:uint, max:uint):void
        {
            var objects:Vector.<ThingType> = new Vector.<ThingType>();

            for (var id:int = min; id <= max; id++)
            {
                var type:ThingType = list[id];

                if (!shouldMergeThing(type, category))
                    continue;

                type.category = category;

                if (ThingUtils.isEmpty(type))
                    continue;

                for (var groupType:uint = FrameGroupType.DEFAULT; groupType <= FrameGroupType.WALKING; groupType++)
                {
                    var frameGroup:FrameGroup = type.getFrameGroup(groupType);
                    if (!frameGroup)
                        continue;

                    var spriteIds:Vector.<uint> = frameGroup.spriteIndex;

                    for (var k:int = spriteIds.length - 1; k >= 0; k--)
                    {
                        var sid:uint = spriteIds[k];
                        if (sid != 0)
                        {
                            if (m_spriteIds[sid] !== undefined)
                                spriteIds[k] = m_spriteIds[sid];
                            else
                                spriteIds[k] = 0;
                        }
                    }
                }

                if (m_reuseExistingSprites && ThingUtils.isEmpty(type))
                    continue;

                if (m_reuseExistingSprites && isExistingThing(type))
                {
                    m_skippedObjectsCount++;
                    continue;
                }

                objects[objects.length] = type;
            }

            if (objects.length != 0)
            {
                if (m_previewOnly)
                {
                    switch (category)
                    {
                        case ThingCategory.ITEM:
                            m_itemsCount += objects.length;
                            break;
                        case ThingCategory.OUTFIT:
                            m_outfitsCount += objects.length;
                            break;
                        case ThingCategory.EFFECT:
                            m_effectsCount += objects.length;
                            break;
                        case ThingCategory.MISSILE:
                            m_missilesCount += objects.length;
                            break;
                    }
                }
                else
                {
                    m_currentObjects.addThings(objects);
                }
            }
        }

        private function shouldMergeThing(thing:ThingType, category:String):Boolean
        {
            if (!thing)
                return false;

            switch (m_mergeMode)
            {
                case ClientMergeMode.PICKUPABLE_ITEMS:
                    return category == ThingCategory.ITEM && thing.pickupable;

                case ClientMergeMode.OUTFITS:
                    return category == ThingCategory.OUTFIT;

                case ClientMergeMode.EFFECTS:
                    return category == ThingCategory.EFFECT;

                case ClientMergeMode.MISSILES:
                    return category == ThingCategory.MISSILE;

                case ClientMergeMode.OBJECTS:
                    return true;

                case ClientMergeMode.UNIQUE_ASSETS:
                    return category == ThingCategory.ITEM ||
                            category == ThingCategory.OUTFIT ||
                            category == ThingCategory.EFFECT ||
                            category == ThingCategory.MISSILE;
            }

            return true;
        }

        private function isExistingThing(thing:ThingType):Boolean
        {
            if (!m_existingThingKeys)
                return false;

            var key:String = getThingKey(thing);
            if (!key)
                return false;

            if (m_existingThingKeys[key] !== undefined)
                return true;

            m_existingThingKeys[key] = true;
            return false;
        }

        private function getThingKey(thing:ThingType):String
        {
            if (m_mergeMode == ClientMergeMode.UNIQUE_ASSETS)
                return getVisualThingKey(thing);

            if (m_reuseExistingSprites)
                return getNormalizedThingKey(thing);

            return getFullThingKey(thing);
        }

        private function getNormalizedThingKey(thing:ThingType):String
        {
            if (!thing)
                return null;

            var parts:Array = [thing.category, "normalized"];
            appendThingProperties(parts, thing);
            appendFrameGroups(parts, thing, true);
            return parts.join("|");
        }

        private function getFullThingKey(thing:ThingType):String
        {
            if (!thing)
                return null;

            var parts:Array = [thing.category];
            appendFrameGroups(parts, thing, false);
            return parts.join("|");
        }

        private function appendFrameGroups(parts:Array, thing:ThingType, useSpriteHashes:Boolean):void
        {
            if (!thing)
                return;

            for (var groupType:uint = FrameGroupType.DEFAULT; groupType <= FrameGroupType.WALKING; groupType++)
            {
                var frameGroup:FrameGroup = thing.getFrameGroup(groupType);
                if (!frameGroup)
                {
                    parts[parts.length] = groupType;
                    parts[parts.length] = "null";
                    continue;
                }

                parts[parts.length] = groupType;
                parts[parts.length] = frameGroup.width;
                parts[parts.length] = frameGroup.height;
                parts[parts.length] = frameGroup.exactSize;
                parts[parts.length] = frameGroup.layers;
                parts[parts.length] = frameGroup.patternX;
                parts[parts.length] = frameGroup.patternY;
                parts[parts.length] = frameGroup.patternZ;
                parts[parts.length] = frameGroup.frames;
                parts[parts.length] = frameGroup.isAnimation ? 1 : 0;
                parts[parts.length] = frameGroup.animationMode;
                parts[parts.length] = frameGroup.loopCount;
                parts[parts.length] = frameGroup.startFrame;

                var durations:Vector.<FrameDuration> = frameGroup.frameDurations;
                parts[parts.length] = durations ? durations.length : 0;
                if (durations)
                {
                    for (var d:uint = 0; d < durations.length; d++)
                    {
                        var duration:FrameDuration = durations[d];
                        if (duration)
                        {
                            parts[parts.length] = duration.minimum;
                            parts[parts.length] = duration.maximum;
                        }
                        else
                        {
                            parts[parts.length] = 0;
                            parts[parts.length] = 0;
                        }
                    }
                }

                var spriteIds:Vector.<uint> = frameGroup.spriteIndex;
                parts[parts.length] = spriteIds ? spriteIds.length : 0;
                if (spriteIds)
                {
                    for (var s:uint = 0; s < spriteIds.length; s++)
                        parts[parts.length] = useSpriteHashes ? getCurrentSpriteHash(spriteIds[s]) : spriteIds[s];
                }
            }
        }

        private function getVisualThingKey(thing:ThingType):String
        {
            if (!thing)
                return null;

            var parts:Array = [thing.category, "visual"];

            for (var groupType:uint = FrameGroupType.DEFAULT; groupType <= FrameGroupType.WALKING; groupType++)
            {
                var frameGroup:FrameGroup = thing.getFrameGroup(groupType);
                if (!frameGroup)
                {
                    parts[parts.length] = groupType;
                    parts[parts.length] = "null";
                    continue;
                }

                parts[parts.length] = groupType;
                parts[parts.length] = frameGroup.width;
                parts[parts.length] = frameGroup.height;
                parts[parts.length] = frameGroup.exactSize;
                parts[parts.length] = frameGroup.layers;
                parts[parts.length] = frameGroup.patternX;
                parts[parts.length] = frameGroup.patternY;
                parts[parts.length] = frameGroup.patternZ;
                parts[parts.length] = frameGroup.frames;

                var spriteIds:Vector.<uint> = frameGroup.spriteIndex;
                parts[parts.length] = spriteIds ? spriteIds.length : 0;
                if (spriteIds)
                {
                    for (var s:uint = 0; s < spriteIds.length; s++)
                        parts[parts.length] = getCurrentSpriteHash(spriteIds[s]);
                }
            }

            return parts.join("|");
        }

        private function appendThingProperties(parts:Array, thing:ThingType):void
        {
            parts[parts.length] = thing.isGround ? 1 : 0;
            parts[parts.length] = thing.groundSpeed;
            parts[parts.length] = thing.isGroundBorder ? 1 : 0;
            parts[parts.length] = thing.isOnBottom ? 1 : 0;
            parts[parts.length] = thing.isOnTop ? 1 : 0;
            parts[parts.length] = thing.isContainer ? 1 : 0;
            parts[parts.length] = thing.stackable ? 1 : 0;
            parts[parts.length] = thing.forceUse ? 1 : 0;
            parts[parts.length] = thing.multiUse ? 1 : 0;
            parts[parts.length] = thing.hasCharges ? 1 : 0;
            parts[parts.length] = thing.writable ? 1 : 0;
            parts[parts.length] = thing.writableOnce ? 1 : 0;
            parts[parts.length] = thing.maxReadWriteChars;
            parts[parts.length] = thing.maxReadChars;
            parts[parts.length] = thing.isFluidContainer ? 1 : 0;
            parts[parts.length] = thing.isFluid ? 1 : 0;
            parts[parts.length] = thing.isUnpassable ? 1 : 0;
            parts[parts.length] = thing.isUnmoveable ? 1 : 0;
            parts[parts.length] = thing.blockMissile ? 1 : 0;
            parts[parts.length] = thing.blockPathfind ? 1 : 0;
            parts[parts.length] = thing.noMoveAnimation ? 1 : 0;
            parts[parts.length] = thing.pickupable ? 1 : 0;
            parts[parts.length] = thing.hangable ? 1 : 0;
            parts[parts.length] = thing.isVertical ? 1 : 0;
            parts[parts.length] = thing.isHorizontal ? 1 : 0;
            parts[parts.length] = thing.rotatable ? 1 : 0;
            parts[parts.length] = thing.hasLight ? 1 : 0;
            parts[parts.length] = thing.lightLevel;
            parts[parts.length] = thing.lightColor;
            parts[parts.length] = thing.dontHide ? 1 : 0;
            parts[parts.length] = thing.isTranslucent ? 1 : 0;
            parts[parts.length] = thing.floorChange ? 1 : 0;
            parts[parts.length] = thing.hasOffset ? 1 : 0;
            parts[parts.length] = thing.offsetX;
            parts[parts.length] = thing.offsetY;
            parts[parts.length] = thing.hasBones ? 1 : 0;
            parts[parts.length] = thing.bonesOffsetX ? thing.bonesOffsetX.join(",") : "";
            parts[parts.length] = thing.bonesOffsetY ? thing.bonesOffsetY.join(",") : "";
            parts[parts.length] = thing.hasElevation ? 1 : 0;
            parts[parts.length] = thing.elevation;
            parts[parts.length] = thing.isLyingObject ? 1 : 0;
            parts[parts.length] = thing.animateAlways ? 1 : 0;
            parts[parts.length] = thing.miniMap ? 1 : 0;
            parts[parts.length] = thing.miniMapColor;
            parts[parts.length] = thing.isLensHelp ? 1 : 0;
            parts[parts.length] = thing.lensHelp;
            parts[parts.length] = thing.isFullGround ? 1 : 0;
            parts[parts.length] = thing.ignoreLook ? 1 : 0;
            parts[parts.length] = thing.cloth ? 1 : 0;
            parts[parts.length] = thing.clothSlot;
            parts[parts.length] = thing.isMarketItem ? 1 : 0;
            parts[parts.length] = thing.marketName ? thing.marketName : "";
            parts[parts.length] = thing.marketCategory;
            parts[parts.length] = thing.marketTradeAs;
            parts[parts.length] = thing.marketShowAs;
            parts[parts.length] = thing.marketRestrictProfession;
            parts[parts.length] = thing.marketRestrictLevel;
            parts[parts.length] = thing.hasDefaultAction ? 1 : 0;
            parts[parts.length] = thing.defaultAction;
            parts[parts.length] = thing.wrappable ? 1 : 0;
            parts[parts.length] = thing.unwrappable ? 1 : 0;
            parts[parts.length] = thing.topEffect ? 1 : 0;
            parts[parts.length] = thing.usable ? 1 : 0;
        }

        private function getCurrentSpriteHash(spriteId:uint):String
        {
            if (spriteId == 0)
                return "0";

            if (!m_currentSpriteHashes)
                m_currentSpriteHashes = new Dictionary();

            if (m_currentSpriteHashes[spriteId] !== undefined)
                return String(m_currentSpriteHashes[spriteId]);

            if (!m_currentSprites || spriteId > m_currentSprites.spritesCount)
                return "missing:" + spriteId;

            var pixels:ByteArray = m_currentSprites.getPixels(spriteId);
            if (!pixels)
                return "missing:" + spriteId;

            var hash:String = getPixelsHash(pixels);
            m_currentSpriteHashes[spriteId] = hash;
            return hash;
        }

        // --------------------------------------
        // Event Handlers
        // --------------------------------------

        private function errorHandler(event:ErrorEvent):void
        {
            trace(event.text);
        }
    }
}
