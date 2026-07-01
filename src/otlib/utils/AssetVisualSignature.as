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
    import flash.utils.ByteArray;
    import flash.utils.Dictionary;

    import otlib.animation.FrameGroup;
    import otlib.sprites.SpriteStorage;
    import otlib.things.FrameGroupType;
    import otlib.things.ThingType;

    public class AssetVisualSignature
    {
        private static const SIZE:uint = SpriteExtent.DEFAULT_SIZE;
        private static const GRID:uint = 8;
        private static const ALPHA_THRESHOLD:uint = 24;
        private static const OPAQUE_THRESHOLD:uint = 192;
        private static const COLOR_QUANT:uint = 43;
        private static const MAX_KEY_SPRITES:uint = 1;
        private static const MAX_QUALITY_SPRITES:uint = 1;

        private var m_sprites:SpriteStorage;
        private var m_spriteAnalysis:Dictionary;

        public function AssetVisualSignature(sprites:SpriteStorage)
        {
            m_sprites = sprites;
            m_spriteAnalysis = new Dictionary();
        }

        public function getThingVisualKey(thing:ThingType):String
        {
            if (!thing)
                return null;

            var parts:Array = [thing.category, "visual-quality-v2"];
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
                        frameGroup.layers,
                        frameGroup.patternX,
                        frameGroup.patternY,
                        frameGroup.patternZ,
                        frameGroup.frames);

                var spriteIds:Vector.<uint> = frameGroup.spriteIndex;
                parts.push(spriteIds ? spriteIds.length : 0);
                if (spriteIds)
                {
                    var keySamples:Vector.<uint> = getSampleIndices(spriteIds.length, MAX_KEY_SPRITES);
                    parts.push(keySamples.length);
                    for each (var sampleIndex:uint in keySamples)
                        parts.push(sampleIndex, getSpriteVisualKey(spriteIds[sampleIndex]));
                }
            }
            return parts.join("|");
        }

        public function getThingQualityScore(thing:ThingType):Number
        {
            if (!thing)
                return 0;

            var score:Number = 0;
            var spriteCount:uint = 0;
            var usedSprites:Dictionary = new Dictionary();

            for (var groupType:uint = FrameGroupType.DEFAULT; groupType <= FrameGroupType.WALKING; groupType++)
            {
                var frameGroup:FrameGroup = thing.getFrameGroup(groupType);
                if (!frameGroup || !frameGroup.spriteIndex)
                    continue;

                var qualitySamples:Vector.<uint> = getSampleIndices(frameGroup.spriteIndex.length, MAX_QUALITY_SPRITES);
                for each (var sampleIndex:uint in qualitySamples)
                {
                    var spriteId:uint = frameGroup.spriteIndex[sampleIndex];
                    if (spriteId == 0 || usedSprites[spriteId] !== undefined)
                        continue;

                    usedSprites[spriteId] = true;
                    score += getSpriteQualityScore(spriteId);
                    spriteCount++;
                }
            }

            if (spriteCount == 0)
                return 0;

            return score / spriteCount;
        }

        public function getSpriteVisualKey(spriteId:uint):String
        {
            return String(getSpriteAnalysis(spriteId).key);
        }

        public function getSpriteQualityScore(spriteId:uint):Number
        {
            return Number(getSpriteAnalysis(spriteId).score);
        }

        private function getSpriteAnalysis(spriteId:uint):Object
        {
            if (spriteId == 0 || spriteId == uint.MAX_VALUE || !m_sprites)
                return {key: "0", score: 0};

            if (m_spriteAnalysis[spriteId] !== undefined)
                return m_spriteAnalysis[spriteId];

            var analysis:Object = analyzeSprite(spriteId);
            m_spriteAnalysis[spriteId] = analysis;
            return analysis;
        }

        private function analyzeSprite(spriteId:uint):Object
        {
            var pixels:ByteArray = m_sprites.getPixels(spriteId);
            if (!pixels || pixels.length < SpriteExtent.DEFAULT_DATA_SIZE)
                return {key: "missing:" + spriteId, score: 0};

            var minX:int = int(SIZE);
            var minY:int = int(SIZE);
            var maxX:int = -1;
            var maxY:int = -1;
            var visible:uint = 0;
            var opaque:uint = 0;
            var translucent:uint = 0;
            var colorBuckets:Dictionary = new Dictionary();
            var colorBucketCount:uint = 0;

            for (var y:uint = 0; y < SIZE; y++)
            {
                for (var x:uint = 0; x < SIZE; x++)
                {
                    var offset:uint = ((y * SIZE) + x) * 4;
                    var alpha:uint = pixels[offset];
                    if (alpha < ALPHA_THRESHOLD)
                        continue;

                    var red:uint = pixels[offset + 1];
                    var green:uint = pixels[offset + 2];
                    var blue:uint = pixels[offset + 3];

                    visible++;
                    if (alpha >= OPAQUE_THRESHOLD)
                        opaque++;
                    else
                        translucent++;

                    if (int(x) < minX)
                        minX = int(x);
                    if (int(y) < minY)
                        minY = int(y);
                    if (int(x) > maxX)
                        maxX = int(x);
                    if (int(y) > maxY)
                        maxY = int(y);

                    var bucket:String = String(red >> 4) + ":" + String(green >> 4) + ":" + String(blue >> 4) + ":" + String(alpha >> 6);
                    if (colorBuckets[bucket] === undefined)
                    {
                        colorBuckets[bucket] = true;
                        colorBucketCount++;
                    }
                }
            }

            if (visible == 0)
                return {key: "empty", score: 0};

            var boxWidth:uint = uint(maxX - minX + 1);
            var boxHeight:uint = uint(maxY - minY + 1);
            var counts:Vector.<uint> = new Vector.<uint>(GRID * GRID, true);
            var sumA:Vector.<uint> = new Vector.<uint>(GRID * GRID, true);
            var sumR:Vector.<uint> = new Vector.<uint>(GRID * GRID, true);
            var sumG:Vector.<uint> = new Vector.<uint>(GRID * GRID, true);
            var sumB:Vector.<uint> = new Vector.<uint>(GRID * GRID, true);

            for (y = uint(minY); y <= uint(maxY); y++)
            {
                for (x = uint(minX); x <= uint(maxX); x++)
                {
                    offset = ((y * SIZE) + x) * 4;
                    alpha = pixels[offset];
                    if (alpha < ALPHA_THRESHOLD)
                        continue;

                    var gx:uint = uint(Math.min(GRID - 1, Math.floor((x - uint(minX)) * GRID / boxWidth)));
                    var gy:uint = uint(Math.min(GRID - 1, Math.floor((y - uint(minY)) * GRID / boxHeight)));
                    var index:uint = gy * GRID + gx;

                    counts[index]++;
                    sumA[index] += alpha;
                    sumR[index] += pixels[offset + 1];
                    sumG[index] += pixels[offset + 2];
                    sumB[index] += pixels[offset + 3];
                }
            }

            var parts:Array = [
                "s",
                quantize(boxWidth, 4),
                quantize(boxHeight, 4),
                quantize(uint(minX + maxX), 8),
                quantize(uint(minY + maxY), 8),
                quantize(visible, 16)
            ];

            for (var i:uint = 0; i < counts.length; i++)
            {
                var count:uint = counts[i];
                if (count == 0)
                {
                    parts.push("0");
                    continue;
                }

                var avgA:uint = uint(sumA[i] / count);
                var avgR:uint = uint(sumR[i] / count);
                var avgG:uint = uint(sumG[i] / count);
                var avgB:uint = uint(sumB[i] / count);

                parts.push(String(Math.min(4, count >> 2)) +
                        ":" + String(Math.min(3, avgA >> 6)) +
                        ":" + String(Math.min(5, uint(avgR / COLOR_QUANT))) +
                        ":" + String(Math.min(5, uint(avgG / COLOR_QUANT))) +
                        ":" + String(Math.min(5, uint(avgB / COLOR_QUANT))));
            }

            pixels.clear();

            var score:Number = opaque * 2.0 +
                    visible * 0.25 +
                    colorBucketCount * 6.0 +
                    translucent * 0.75;

            return {key: parts.join(","), score: score};
        }

        private function quantize(value:uint, size:uint):uint
        {
            return uint(Math.floor(value / size));
        }

        private function getSampleIndices(length:uint, maxSamples:uint):Vector.<uint>
        {
            var result:Vector.<uint> = new Vector.<uint>();
            if (length == 0 || maxSamples == 0)
                return result;

            if (length <= maxSamples)
            {
                for (var i:uint = 0; i < length; i++)
                    result.push(i);
                return result;
            }

            var last:uint = length - 1;
            for (i = 0; i < maxSamples; i++)
            {
                var index:uint = uint(Math.round(i * last / (maxSamples - 1)));
                if (result.length == 0 || result[result.length - 1] != index)
                    result.push(index);
            }
            return result;
        }
    }
}
