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
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.utils.Dictionary;

    import nail.errors.NullArgumentError;

    import ob.commands.ProgressBarID;

    import otlib.core.otlib_internal;
    import otlib.events.ProgressEvent;
    import otlib.resources.Resources;
    import otlib.sprites.Sprite;
    import otlib.sprites.SpriteStorage;
    import otlib.things.ThingType;
    import otlib.things.ThingTypeStorage;
    import otlib.animation.FrameGroup;
    import otlib.things.FrameGroupType;
    import otlib.animation.FrameDuration;

    use namespace otlib_internal;

    [Event(name="progress", type="otlib.events.ProgressEvent")]
    [Event(name="complete", type="flash.events.Event")]

    public class FrameDurationsOptimizer extends EventDispatcher
    {
        private static const MINIMUM_ITEMS_ADAPTIVE_FRAME_DURATION:uint = 80;
        private static const MINIMUM_OUTFITS_ADAPTIVE_FRAME_DURATION:uint = 90;
        private static const MINIMUM_EFFECTS_ADAPTIVE_FRAME_DURATION:uint = 70;
        private static const MINIMUM_MISSILES_ADAPTIVE_FRAME_DURATION:uint = 60;

        // --------------------------------------------------------------------------
        // PROPERTIES
        // --------------------------------------------------------------------------

        private var m_objects:ThingTypeStorage;
        private var m_finished:Boolean;
        private var m_itemsEnabled:Boolean;
        private var m_itemsMinimumDuration:uint;
        private var m_itemsMaximumDuration:uint;
        private var m_outfitsEnabled:Boolean;
        private var m_outfitsMinimumDuration:uint;
        private var m_outfitsMaximumDuration:uint;
        private var m_effectsEnabled:Boolean;
        private var m_effectsMinimumDuration:uint;
        private var m_effectsMaximumDuration:uint;
        private var m_missilesEnabled:Boolean;
        private var m_missilesMinimumDuration:uint;
        private var m_missilesMaximumDuration:uint;
        private var m_spreadDurationAcrossFrames:Boolean;
        private var m_changed:Boolean;

        // --------------------------------------------------------------------------
        // CONSTRUCTOR
        // --------------------------------------------------------------------------

        public function FrameDurationsOptimizer(objects:ThingTypeStorage, items:Boolean, itemsMinimumDuration:uint, itemsMaximumDuration:uint,
                outfits:Boolean, outfitsMinimumDuration:uint, outfitsMaximumDuration:uint,
                effects:Boolean, effectsMinimumDuration:uint, effectsMaximumDuration:uint,
                missiles:Boolean = false, missilesMinimumDuration:uint = 0, missilesMaximumDuration:uint = 0,
                spreadDurationAcrossFrames:Boolean = false)
        {
            if (!objects)
                throw new NullArgumentError("objects");

            m_objects = objects;
            m_itemsEnabled = items;
            m_itemsMinimumDuration = itemsMinimumDuration;
            m_itemsMaximumDuration = itemsMaximumDuration;

            m_outfitsEnabled = outfits;
            m_outfitsMinimumDuration = outfitsMinimumDuration;
            m_outfitsMaximumDuration = outfitsMaximumDuration;

            m_effectsEnabled = effects;
            m_effectsMinimumDuration = effectsMinimumDuration;
            m_effectsMaximumDuration = effectsMaximumDuration;

            m_missilesEnabled = missiles;
            m_missilesMinimumDuration = missilesMinimumDuration;
            m_missilesMaximumDuration = missilesMaximumDuration;
            m_spreadDurationAcrossFrames = spreadDurationAcrossFrames;
        }

        // --------------------------------------------------------------------------
        // METHODS
        // --------------------------------------------------------------------------

        // --------------------------------------
        // Public
        // --------------------------------------

        public function start():void
        {
            if (m_finished)
                return;

            var steps:uint = 6;
            var step:uint = 0;

            dispatchProgress(step++, steps, Resources.getString("startingTheOptimization"));
            dispatchProgress(step++, steps, Resources.getString("changingDurationsInItems"));
            if (m_itemsEnabled)
                changeFrameDurations(m_objects.items, m_itemsMinimumDuration, m_itemsMaximumDuration, MINIMUM_ITEMS_ADAPTIVE_FRAME_DURATION);

            dispatchProgress(step++, steps, Resources.getString("changingDurationsInOutfits"));
            if (m_outfitsEnabled)
                changeFrameDurations(m_objects.outfits, m_outfitsMinimumDuration, m_outfitsMaximumDuration, MINIMUM_OUTFITS_ADAPTIVE_FRAME_DURATION);

            dispatchProgress(step++, steps, Resources.getString("changingDurationsInEffects"));
            if (m_effectsEnabled)
                changeFrameDurations(m_objects.effects, m_effectsMinimumDuration, m_effectsMaximumDuration,
                        MINIMUM_EFFECTS_ADAPTIVE_FRAME_DURATION);

            dispatchProgress(step++, steps, Resources.getString("changingDurationsInMissiles"));
            if (m_missilesEnabled)
                changeFrameDurations(m_objects.missiles, m_missilesMinimumDuration, m_missilesMaximumDuration,
                        MINIMUM_MISSILES_ADAPTIVE_FRAME_DURATION);

            if (m_changed)
                m_objects.invalidate();

            m_finished = true;
            dispatchEvent(new Event(Event.COMPLETE));
        }

        private function changeFrameDurations(list:Dictionary, minimum:uint, maximum:uint, minimumSpreadFrameDuration:uint):void
        {
            for each (var thing:ThingType in list)
            {
                for (var groupType:uint = FrameGroupType.DEFAULT; groupType <= FrameGroupType.WALKING; groupType++)
                {
                    var frameGroup:FrameGroup = thing.getFrameGroup(groupType);
                    if (!frameGroup || frameGroup.frames <= 1)
                        continue;

                    if (!frameGroup.frameDurations || frameGroup.frameDurations.length != frameGroup.frames)
                        frameGroup.frameDurations = new Vector.<FrameDuration>(frameGroup.frames, true);

                    for (var frame:uint = 0; frame < frameGroup.frames; frame++)
                    {
                        var minimumFrameDuration:uint = m_spreadDurationAcrossFrames ? getFrameDuration(minimum, frame, frameGroup.frames, minimumSpreadFrameDuration) : minimum;
                        var maximumFrameDuration:uint = m_spreadDurationAcrossFrames ? getFrameDuration(maximum, frame, frameGroup.frames, minimumSpreadFrameDuration) : maximum;
                        var duration:FrameDuration = frameGroup.getFrameDuration(frame);
                        if (!duration ||
                                duration.minimum != minimumFrameDuration ||
                                duration.maximum != maximumFrameDuration)
                        {
                            frameGroup.frameDurations[frame] = new FrameDuration(minimumFrameDuration, maximumFrameDuration);
                            m_changed = true;
                        }
                    }
                }
            }
        }

        private function getFrameDuration(baseDuration:uint, frame:uint, frames:uint, minimumFrameDuration:uint):uint
        {
            if (!m_spreadDurationAcrossFrames || frames <= 1)
                return baseDuration;

            if (baseDuration == 0)
                return 0;

            // Treat the configured value as the legacy per-frame pace. Scaling by
            // sqrt(frames) keeps long effects readable without making them linearly
            // slower, while the category floor avoids near-zero frame durations.
            var duration:uint = Math.round(baseDuration / Math.sqrt(frames));
            return Math.max(minimumFrameDuration, duration);
        }

        private function dispatchProgress(current:uint, target:uint, label:String):void
        {
            dispatchEvent(new ProgressEvent(ProgressEvent.PROGRESS, ProgressBarID.OPTIMIZE, current, target, label));
        }
    }
}
