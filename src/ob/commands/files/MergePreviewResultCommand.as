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
*/

package ob.commands.files
{
    import com.mignari.workers.WorkerCommand;

    public class MergePreviewResultCommand extends WorkerCommand
    {
        public function MergePreviewResultCommand(items:uint,
                outfits:uint,
                effects:uint,
                missiles:uint,
                newSprites:uint,
                reusedSprites:uint,
                skippedObjects:uint,
                referencedSprites:uint,
                ignoredOrphanSprites:uint,
                sourceObjects:uint)
        {
            super(items, outfits, effects, missiles, newSprites, reusedSprites,
                    skippedObjects, referencedSprites, ignoredOrphanSprites, sourceObjects);
        }
    }
}
