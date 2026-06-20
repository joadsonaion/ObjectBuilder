/*
*  Copyright (c) 2014-2023 Object Builder <https://github.com/ottools/ObjectBuilder>
*
*  Permission is hereby granted, free of charge, to any person obtaining a copy
*  of this software and associated documentation files (the "Software"), to deal
*  in the Software without restriction, including without limitation the rights
*  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
*  copies of the Software.
*/

package ob.utils
{
    import flash.display.BitmapData;
    import flash.utils.ByteArray;
    import flash.utils.Endian;

    public final class AnimatedGifEncoder
    {
        private static const CLEAR_CODE:uint = 256;
        private static const END_CODE:uint = 257;
        private static const LITERAL_CHUNK:uint = 250;

        public static function encode(frames:Vector.<BitmapData>, delays:Vector.<uint>):ByteArray
        {
            if (!frames || frames.length == 0)
                throw new ArgumentError("At least one GIF frame is required.");

            var width:uint = frames[0].width;
            var height:uint = frames[0].height;
            var output:ByteArray = new ByteArray();
            output.endian = Endian.LITTLE_ENDIAN;

            writeAscii(output, "GIF89a");
            output.writeShort(width);
            output.writeShort(height);
            output.writeByte(0xF7); // Global 256-color table, 8-bit color resolution.
            output.writeByte(0);
            output.writeByte(0);
            writePalette(output);
            writeLoopExtension(output);

            for (var i:uint = 0; i < frames.length; i++)
            {
                var frame:BitmapData = frames[i];
                if (!frame || frame.width != width || frame.height != height)
                    throw new ArgumentError("All GIF frames must have the same dimensions.");

                var delay:uint = delays && i < delays.length ? delays[i] : 100;
                writeGraphicControl(output, delay);
                writeImage(output, frame);
            }

            output.writeByte(0x3B);
            output.position = 0;
            return output;
        }

        private static function writePalette(output:ByteArray):void
        {
            for (var i:uint = 0; i < 256; i++)
            {
                if (i <= 1)
                {
                    output.writeByte(0);
                    output.writeByte(0);
                    output.writeByte(0);
                    continue;
                }

                output.writeByte(Math.round(((i >> 5) & 0x07) * 255 / 7));
                output.writeByte(Math.round(((i >> 2) & 0x07) * 255 / 7));
                output.writeByte(Math.round((i & 0x03) * 255 / 3));
            }
        }

        private static function writeLoopExtension(output:ByteArray):void
        {
            output.writeByte(0x21);
            output.writeByte(0xFF);
            output.writeByte(11);
            writeAscii(output, "NETSCAPE2.0");
            output.writeByte(3);
            output.writeByte(1);
            output.writeShort(0); // Infinite loop.
            output.writeByte(0);
        }

        private static function writeGraphicControl(output:ByteArray, delayMs:uint):void
        {
            var hundredths:uint = Math.max(2, Math.min(65535, Math.round(delayMs / 10)));
            output.writeByte(0x21);
            output.writeByte(0xF9);
            output.writeByte(4);
            output.writeByte(0x05); // Keep frame and use palette index 0 as transparent.
            output.writeShort(hundredths);
            output.writeByte(0);
            output.writeByte(0);
        }

        private static function writeImage(output:ByteArray, frame:BitmapData):void
        {
            output.writeByte(0x2C);
            output.writeShort(0);
            output.writeShort(0);
            output.writeShort(frame.width);
            output.writeShort(frame.height);
            output.writeByte(0);
            output.writeByte(8); // LZW minimum code size.

            var indexed:ByteArray = indexPixels(frame);
            var encoded:ByteArray = encodeLiteralLzw(indexed);
            encoded.position = 0;
            while (encoded.bytesAvailable > 0)
            {
                var length:uint = Math.min(255, encoded.bytesAvailable);
                output.writeByte(length);
                output.writeBytes(encoded, encoded.position, length);
                encoded.position += length;
            }
            output.writeByte(0);
        }

        private static function indexPixels(frame:BitmapData):ByteArray
        {
            var pixels:Vector.<uint> = frame.getVector(frame.rect);
            var indexed:ByteArray = new ByteArray();

            for each (var argb:uint in pixels)
            {
                if ((argb >>> 24) < 0x80)
                {
                    indexed.writeByte(0);
                    continue;
                }

                var index:uint = ((argb >> 16 & 0xFF) >> 5) << 5 |
                        ((argb >> 8 & 0xFF) >> 5) << 2 |
                        (argb & 0xFF) >> 6;
                indexed.writeByte(index == 0 ? 1 : index);
            }

            indexed.position = 0;
            return indexed;
        }

        // Literal-only LZW is intentionally used here. Frequent clear codes keep the
        // stream at nine bits and produce compact, deterministic 128x128 outfit GIFs.
        private static function encodeLiteralLzw(indexed:ByteArray):ByteArray
        {
            var output:ByteArray = new ByteArray();
            var bitBuffer:uint = 0;
            var bitCount:uint = 0;

            writeCode(CLEAR_CODE);
            var literals:uint = 0;
            while (indexed.bytesAvailable > 0)
            {
                if (literals == LITERAL_CHUNK)
                {
                    writeCode(CLEAR_CODE);
                    literals = 0;
                }
                writeCode(indexed.readUnsignedByte());
                literals++;
            }
            writeCode(END_CODE);

            if (bitCount > 0)
                output.writeByte(bitBuffer & 0xFF);
            output.position = 0;
            return output;

            function writeCode(code:uint):void
            {
                bitBuffer |= code << bitCount;
                bitCount += 9;
                while (bitCount >= 8)
                {
                    output.writeByte(bitBuffer & 0xFF);
                    bitBuffer >>>= 8;
                    bitCount -= 8;
                }
            }
        }

        private static function writeAscii(output:ByteArray, value:String):void
        {
            for (var i:uint = 0; i < value.length; i++)
                output.writeByte(value.charCodeAt(i));
        }
    }
}
