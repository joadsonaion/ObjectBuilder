package ob.utils
{
    import flash.utils.ByteArray;

    internal class ProtoReader
    {
        private var bytes:ByteArray;

        public function ProtoReader(value:ByteArray)
        {
            bytes = value;
            bytes.position = 0;
        }

        public function get end():Boolean
        {
            return bytes.position >= bytes.length;
        }

        public function readVarint():uint
        {
            var result:Number = 0;
            var shift:uint = 0;
            while (!end && shift < 35)
            {
                var value:uint = bytes.readUnsignedByte();
                result += (value & 0x7F) * Math.pow(2, shift);
                if ((value & 0x80) == 0)
                    break;
                shift += 7;
            }
            return uint(result);
        }

        public function readTag():Object
        {
            var value:uint = readVarint();
            return {field: value >>> 3, wire: value & 7};
        }

        public function readLengthBytes():ByteArray
        {
            var length:uint = readVarint();
            if (length > bytes.bytesAvailable)
                throw new Error("Invalid protobuf length.");
            var result:ByteArray = new ByteArray();
            bytes.readBytes(result, 0, length);
            result.position = 0;
            return result;
        }

        public function skip(wire:uint):void
        {
            if (wire == 0) readVarint();
            else if (wire == 1) bytes.position += 8;
            else if (wire == 2) bytes.position += readVarint();
            else if (wire == 5) bytes.position += 4;
            else throw new Error("Unsupported protobuf wire type " + wire + ".");
            if (bytes.position > bytes.length)
                bytes.position = bytes.length;
        }
    }
}
