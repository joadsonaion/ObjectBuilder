/*
*  Copyright (c) 2014-2023 Object Builder <https://github.com/ottools/ObjectBuilder>
*
*  Permission is hereby granted, free of charge, to any person obtaining a copy
*  of this software and associated documentation files (the "Software"), to deal
*  in the Software without restriction, including without limitation the rights
*  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
*  copies of the Software.
*/

package ob.commands.things
{
    import com.mignari.workers.WorkerCommand;

    import ob.utils.WebAssetExportItem;

    public class SetWebAssetExportListCommand extends WorkerCommand
    {
        public function SetWebAssetExportListCommand(mode:String, items:Vector.<WebAssetExportItem>)
        {
            super(mode, items);
        }
    }
}
