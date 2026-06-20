package ob.utils
{
    import flash.display.BitmapData;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.geom.Point;
    import flash.geom.Rectangle;
    import flash.utils.ByteArray;
    import flash.utils.CompressionAlgorithm;
    import flash.utils.Endian;

    internal class ModernSheet
    {
        public var firstId:uint;
        public var lastId:uint;
        public var spriteWidth:uint;
        public var spriteHeight:uint;

        private var file:File;
        private var bitmap:BitmapData;

        public function ModernSheet(directory:File, fileName:String, first:uint, last:uint, type:uint)
        {
            file = directory.resolvePath(fileName);
            firstId = first;
            lastId = last;
            var sizes:Array = [[32, 32], [32, 64], [64, 32], [64, 64], [64, 64], [96, 96], [128, 128]];
            var size:Array = type < sizes.length ? sizes[type] : sizes[0];
            spriteWidth = size[0];
            spriteHeight = size[1];
        }

        public function getSprite(id:uint):BitmapData
        {
            ensureLoaded();
            if (!bitmap)
                return null;
            var columns:uint = Math.max(1, Math.floor(bitmap.width / spriteWidth));
            var offset:uint = id - firstId;
            var rect:Rectangle = new Rectangle((offset % columns) * spriteWidth,
                    Math.floor(offset / columns) * spriteHeight,
                    spriteWidth, spriteHeight);
            if (rect.right > bitmap.width || rect.bottom > bitmap.height)
                return null;
            var result:BitmapData = new BitmapData(spriteWidth, spriteHeight, true, 0);
            result.copyPixels(bitmap, rect, new Point());
            return result;
        }

        public function dispose():void
        {
            if (bitmap)
            {
                bitmap.dispose();
                bitmap = null;
            }
        }

        private function ensureLoaded():void
        {
            if (bitmap)
                return;
            if (!file.exists)
                throw new Error("Missing sprite sheet: " + file.nativePath);

            var stream:FileStream = new FileStream();
            var bytes:ByteArray = new ByteArray();
            stream.open(file, FileMode.READ);
            stream.readBytes(bytes);
            stream.close();
            bytes.position = 0;
            try
            {
                bytes.uncompress(CompressionAlgorithm.LZMA);
            }
            catch (error:Error)
            {
                throw new Error("Could not decompress " + file.name + ": " + error.message);
            }
            bitmap = decodeBmp(bytes);
        }

        private function decodeBmp(bytes:ByteArray):BitmapData
        {
            bytes.endian = Endian.LITTLE_ENDIAN;
            bytes.position = 0;
            if (bytes.readUTFBytes(2) != "BM")
                throw new Error("Invalid BMP sheet: " + file.name);
            bytes.position = 10;
            var pixelOffset:uint = bytes.readUnsignedInt();
            bytes.position = 18;
            var width:int = bytes.readInt();
            var rawHeight:int = bytes.readInt();
            var topDown:Boolean = rawHeight < 0;
            var height:int = Math.abs(rawHeight);
            bytes.position = 28;
            var bits:uint = bytes.readUnsignedShort();
            if (bits != 24 && bits != 32)
                throw new Error("Unsupported BMP depth " + bits + " in " + file.name);

            var result:BitmapData = new BitmapData(width, height, true, 0);
            var rowSize:uint = Math.ceil((bits * width) / 32) * 4;
            for (var row:uint = 0; row < height; row++)
            {
                var y:uint = topDown ? row : height - 1 - row;
                bytes.position = pixelOffset + row * rowSize;
                for (var x:uint = 0; x < width; x++)
                {
                    var blue:uint = bytes.readUnsignedByte();
                    var green:uint = bytes.readUnsignedByte();
                    var red:uint = bytes.readUnsignedByte();
                    var alpha:uint = bits == 32 ? bytes.readUnsignedByte() : 0xFF;
                    if (bits == 24 && red == 0xFF && green == 0 && blue == 0xFF)
                        alpha = 0;
                    result.setPixel32(x, y, (alpha << 24) | (red << 16) | (green << 8) | blue);
                }
            }
            return result;
        }
    }
}
