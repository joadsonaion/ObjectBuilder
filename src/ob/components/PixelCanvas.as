package ob.components
{
    import flash.display.Bitmap;
    import flash.display.BitmapData;
    import flash.events.Event;
    import flash.events.MouseEvent;

    import mx.core.UIComponent;

    [Event(name="change", type="flash.events.Event")]
    [Event(name="select", type="flash.events.Event")]
    public class PixelCanvas extends UIComponent
    {
        public static const TOOL_PENCIL:String = "pencil";
        public static const TOOL_ERASER:String = "eraser";
        public static const TOOL_PICKER:String = "picker";

        private var m_bitmap:Bitmap;
        private var m_data:BitmapData;
        private var m_zoom:uint = 12;
        private var m_tool:String = TOOL_PENCIL;
        private var m_color:uint = 0xFFFFFFFF;
        private var m_drawing:Boolean;
        private var m_undo:Array = [];
        private var m_redo:Array = [];

        public function PixelCanvas()
        {
            super();
            m_bitmap = new Bitmap();
            m_bitmap.smoothing = false;
            addChild(m_bitmap);
            addEventListener(MouseEvent.MOUSE_DOWN, mouseDownHandler);
            addEventListener(MouseEvent.MOUSE_MOVE, mouseMoveHandler);
            addEventListener(MouseEvent.MOUSE_UP, mouseUpHandler);
            addEventListener(MouseEvent.ROLL_OUT, mouseUpHandler);
        }

        public function get bitmapData():BitmapData
        {
            return m_data;
        }

        public function set bitmapData(value:BitmapData):void
        {
            if (m_data)
                m_data.dispose();
            m_data = value ? value.clone() : new BitmapData(32, 32, true, 0);
            m_bitmap.bitmapData = m_data;
            m_undo.length = 0;
            m_redo.length = 0;
            invalidateSize();
            invalidateDisplayList();
        }

        public function get tool():String
        {
            return m_tool;
        }

        public function set tool(value:String):void
        {
            m_tool = value;
        }

        public function get color():uint
        {
            return m_color;
        }

        public function set color(value:uint):void
        {
            m_color = value;
        }

        public function clearPixels():void
        {
            if (!m_data)
                return;
            saveUndo();
            m_data.fillRect(m_data.rect, 0x00000000);
            refresh();
        }

        public function undo():void
        {
            if (m_undo.length == 0 || !m_data)
                return;
            m_redo.push(m_data.clone());
            replaceData(BitmapData(m_undo.pop()));
        }

        public function redo():void
        {
            if (m_redo.length == 0 || !m_data)
                return;
            m_undo.push(m_data.clone());
            replaceData(BitmapData(m_redo.pop()));
        }

        override protected function measure():void
        {
            measuredWidth = m_data ? m_data.width * m_zoom : 384;
            measuredHeight = m_data ? m_data.height * m_zoom : 384;
        }

        override protected function updateDisplayList(unscaledWidth:Number, unscaledHeight:Number):void
        {
            super.updateDisplayList(unscaledWidth, unscaledHeight);
            if (!m_data)
                return;

            m_bitmap.scaleX = m_zoom;
            m_bitmap.scaleY = m_zoom;
            graphics.clear();
            graphics.lineStyle(1, 0x4A4A4A, 0.65);
            for (var x:uint = 0; x <= m_data.width; x++)
            {
                graphics.moveTo(x * m_zoom, 0);
                graphics.lineTo(x * m_zoom, m_data.height * m_zoom);
            }
            for (var y:uint = 0; y <= m_data.height; y++)
            {
                graphics.moveTo(0, y * m_zoom);
                graphics.lineTo(m_data.width * m_zoom, y * m_zoom);
            }
        }

        private function mouseDownHandler(event:MouseEvent):void
        {
            if (!m_data)
                return;
            if (m_tool == TOOL_PICKER)
            {
                pick(event.localX, event.localY);
                return;
            }
            saveUndo();
            m_drawing = true;
            paint(event.localX, event.localY);
        }

        private function mouseMoveHandler(event:MouseEvent):void
        {
            if (m_drawing)
                paint(event.localX, event.localY);
        }

        private function mouseUpHandler(event:MouseEvent):void
        {
            m_drawing = false;
        }

        private function paint(localX:Number, localY:Number):void
        {
            var px:int = int(localX / m_zoom);
            var py:int = int(localY / m_zoom);
            if (!inside(px, py))
                return;
            m_data.setPixel32(px, py, m_tool == TOOL_ERASER ? 0 : m_color);
            refresh();
        }

        private function pick(localX:Number, localY:Number):void
        {
            var px:int = int(localX / m_zoom);
            var py:int = int(localY / m_zoom);
            if (!inside(px, py))
                return;
            m_color = m_data.getPixel32(px, py);
            dispatchEvent(new Event(Event.SELECT));
        }

        private function inside(x:int, y:int):Boolean
        {
            return m_data && x >= 0 && y >= 0 && x < m_data.width && y < m_data.height;
        }

        private function saveUndo():void
        {
            m_undo.push(m_data.clone());
            if (m_undo.length > 30)
            {
                var old:BitmapData = BitmapData(m_undo.shift());
                old.dispose();
            }
            for each (var redoData:BitmapData in m_redo)
                redoData.dispose();
            m_redo.length = 0;
        }

        private function replaceData(value:BitmapData):void
        {
            if (m_data)
                m_data.dispose();
            m_data = value;
            m_bitmap.bitmapData = m_data;
            refresh();
        }

        private function refresh():void
        {
            m_bitmap.bitmapData = null;
            m_bitmap.bitmapData = m_data;
            invalidateDisplayList();
            dispatchEvent(new Event(Event.CHANGE));
        }
    }
}
