package org.flixel
{
	import flash.display.Bitmap;
	import flash.display.BitmapData;
	import flash.geom.Matrix;
	import flash.geom.Rectangle;
	
	import org.flixel.system.FlxTilemapBuffer;

	/**
	 * This is a traditional tilemap display and collision class.
	 * It takes a string of comma-separated numbers and then associates
	 * those values with tiles from the sheet you pass in.
	 * It also includes some handy static parsers that can convert
	 * arrays or PNG files into strings that can be successfully loaded.
	 */
	public class FlxTilemap extends FlxObject
	{
		[Embed(source="data/autotiles.png")] static public var ImgAuto:Class;
		[Embed(source="data/autotiles_alt.png")] static public var ImgAutoAlt:Class;
		
		/**
		 * No auto-tiling.
		 */
		static public const OFF:uint = 0;
		/**
		 * Platformer-friendly auto-tiling.
		 */
		static public const AUTO:uint = 1;
		/**
		 * Top-down auto-tiling.
		 */
		static public const ALT:uint = 2;
		
		/**
		 * What tile index will you start colliding with (default: 1).
		 */
		public var collideIndex:uint;
		/**
		 * The first index of your tile sheet (default: 0) If you want to change it, do so before calling loadMap().
		 */
		public var startingIndex:uint;
		/**
		 * What tile index will you start drawing with (default: 1)  NOTE: should always be >= startingIndex.
		 * If you want to change it, do so before calling loadMap().
		 */
		public var drawIndex:uint;
		/**
		 * Set this flag to use one of the 16-tile binary auto-tile algorithms (OFF, AUTO, or ALT).
		 */
		public var auto:uint;
		
		/**
		 * Read-only variable, do NOT recommend changing after the map is loaded!
		 */
		public var widthInTiles:uint;
		/**
		 * Read-only variable, do NOT recommend changing after the map is loaded!
		 */
		public var heightInTiles:uint;
		/**
		 * Read-only variable, do NOT recommend changing after the map is loaded!
		 */
		public var totalTiles:uint;
		
		public var cameras:Array;
		
		/**
		 * Rendering helper.
		 */
		protected var _flashRect:Rectangle;
		
		protected var _tiles:BitmapData;
		protected var _buffers:Array;
		protected var _data:Array;
		protected var _rects:Array;
		protected var _tileWidth:uint;
		protected var _tileHeight:uint;
		protected var _block:FlxObject;
		protected var _callbacks:Array;
		
		/**
		 * The tilemap constructor just initializes some basic variables.
		 */
		public function FlxTilemap()
		{
			super();
			auto = OFF;
			collideIndex = 1;
			startingIndex = 0;
			drawIndex = 1;
			widthInTiles = 0;
			heightInTiles = 0;
			totalTiles = 0;
			_buffers = new Array();
			_flashRect = null;
			_data = null;
			_tileWidth = 0;
			_tileHeight = 0;
			_rects = null;
			_tiles = null;
			_block = new FlxObject();
			_block.width = _block.height = 0;
			_block.fixed = true;
			_callbacks = new Array();
			fixed = true;
			cameras = null;
		}
		
		override public function destroy():void
		{
			_flashRect = null;
			_tiles = null;
			var i:uint = 0;
			var l:uint = _buffers.length;
			while(i < l)
				(_buffers[i++] as FlxTilemapBuffer).destroy();
			_buffers = null;
			_data = null;
			_rects = null;
			_block = null;
			_callbacks = null;

			super.destroy();
		}
		
		/**
		 * Load the tilemap with string data and a tile graphic.
		 * 
		 * @param	MapData			A string of comma and line-return delineated indices indicating what order the tiles should go in.
		 * @param	TileGraphic		All the tiles you want to use, arranged in a strip corresponding to the numbers in MapData.
		 * @param	TileWidth		The width of your tiles (e.g. 8) - defaults to height of the tile graphic if unspecified.
		 * @param	TileHeight		The height of your tiles (e.g. 8) - defaults to width if unspecified.
		 * 
		 * @return	A pointer this instance of FlxTilemap, for chaining as usual :)
		 */
		public function loadMap(MapData:String, TileGraphic:Class, TileWidth:uint=0, TileHeight:uint=0):FlxTilemap
		{			
			//Figure out the map dimensions based on the data string
			var cols:Array;
			var rows:Array = MapData.split("\n");
			heightInTiles = rows.length;
			_data = new Array();
			var r:uint = 0;
			var c:uint;
			while(r < heightInTiles)
			{
				cols = rows[r++].split(",");
				if(cols.length <= 1)
				{
					heightInTiles = heightInTiles - 1;
					continue;
				}
				if(widthInTiles == 0)
					widthInTiles = cols.length;
				c = 0;
				while(c < widthInTiles)
					_data.push(uint(cols[c++]));
			}
			
			//Pre-process the map data if it's auto-tiled
			var i:uint;
			totalTiles = widthInTiles*heightInTiles;
			if(auto > OFF)
			{
				collideIndex = startingIndex = drawIndex = 1;
				i = 0;
				while(i < totalTiles)
					autoTile(i++);
			}

			//Figure out the size of the tiles
			_tiles = FlxG.addBitmap(TileGraphic);
			_tileWidth = TileWidth;
			if(_tileWidth == 0)
				_tileWidth = _tiles.height;
			_tileHeight = TileHeight;
			if(_tileHeight == 0)
				_tileHeight = _tileWidth;
			_block.width = _tileWidth;
			_block.height = _tileHeight;
			
			//Then go through and create the actual map
			width = widthInTiles*_tileWidth;
			height = heightInTiles*_tileHeight;
			_rects = new Array(totalTiles);
			i = 0;
			while(i < totalTiles)
				updateTile(i++);

			refreshHulls();
			
			return this;
		}

		/**
		 * Internal function that actually renders the tilemap to the tilemap buffer.  Called by render().
		 */
		protected function drawTilemap(Buffer:FlxTilemapBuffer,Camera:FlxCamera):void
		{
			Buffer.fill();

			//Copy tile images into the tile buffer
			getScreenXY(_point,Camera);
			_flashPoint.x = _point.x;
			_flashPoint.y = _point.y;
			var tx:int = Math.floor(-_flashPoint.x/_tileWidth);
			var ty:int = Math.floor(-_flashPoint.y/_tileHeight);
			var sr:uint = Buffer.screenRows;
			var sc:uint = Buffer.screenCols;
			if(tx < 0) tx = 0;
			if(tx > widthInTiles-sc) tx = widthInTiles-sc;
			if(ty < 0) ty = 0;
			if(ty > heightInTiles-sr) ty = heightInTiles-sr;
			var ri:int = ty*widthInTiles+tx;
			_flashPoint.y = 0;
			var r:uint = 0;
			var c:uint;
			var cri:uint;
			while(r < sr)
			{
				cri = ri;
				c = 0;
				_flashPoint.x = 0;
				while(c < sc)
				{
					_flashRect = _rects[cri++] as Rectangle;
					if(_flashRect != null)
						Buffer.pixels.copyPixels(_tiles,_flashRect,_flashPoint,null,null,true);
					_flashPoint.x += _tileWidth;
					c++;
				}
				ri += widthInTiles;
				_flashPoint.y += _tileHeight;
				r++;
			}
			Buffer.x = tx*_tileWidth;
			Buffer.y = ty*_tileHeight;
		}
		
		/**
		 * Checks to see if the tilemap needs to be refreshed or not.
		 */
		override public function update():void
		{
			super.update();
			
			if(cameras == null)
				cameras = FlxG.cameras;
			var b:FlxTilemapBuffer;
			var c:FlxCamera;
			var i:uint = 0;
			var l:uint = cameras.length;
			while(i < l)
			{
				c = cameras[i];
				if(_buffers[i] == null)
					_buffers[i] = new FlxTilemapBuffer(_tileWidth,_tileHeight,widthInTiles,heightInTiles,c);
				b = _buffers[i] as FlxTilemapBuffer;
				
				getScreenXY(_point,c);
				_point.x += b.x;
				_point.y += b.y;
				if((_point.x > 0) || (_point.y > 0) || (_point.x + b.width < c.width) || (_point.y + b.height < c.height))
					b.dirty = true;
				i++;
			}
		}
		
		/**
		 * Draws the tilemap.
		 */
		override public function draw():void
		{
			_VISIBLECOUNT++;
			
			if(cameras == null)
				cameras = FlxG.cameras;
			var c:FlxCamera;
			var b:FlxTilemapBuffer;
			var i:uint = 0;
			var l:uint = cameras.length;
			while(i < l)
			{
				c = cameras[i];
				if(_buffers[i] == null)
					_buffers[i] = new FlxTilemapBuffer(_tileWidth,_tileHeight,widthInTiles,heightInTiles,c);
				b = _buffers[i] as FlxTilemapBuffer;
				
				//Redraw the tilemap buffer if necessary
				if(b.dirty)
				{
					drawTilemap(b,c);
					b.dirty = false;
				}
				
				//Render the buffer no matter what
				getScreenXY(_point,c);
				_flashPoint.x = _point.x + b.x;
				_flashPoint.y = _point.y + b.y;
				b.draw(c,_flashPoint);
				i++;
			}
		}
		
		public function getData(Simple:Boolean=false):Array
		{
			if(!Simple)
				return _data;
			
			var l:uint = _data.length;
			var data:Array = new Array(l);
			for(var i:uint = 0; i < l; i++)
				data[i] = (_data[i] > 0)?1:0;
			return data;
		}
		
		public function setDirty(Dirty:Boolean=true):void
		{
			var l:uint = _buffers.length;
			for(var i:uint = 0; i < l; i++)
				(_buffers[i] as FlxTilemapBuffer).dirty = Dirty;
		}
		
		/**
		 * Checks for overlaps between the provided object and any tiles above the collision index.
		 * 
		 * @param	Rect		The <code>FlxRect</code> you want to check against.
		 */
		override public function overlaps(Object:FlxObject):Boolean
		{
			var d:uint;
			
			var dd:uint;
			var blocks:Array = new Array();
			
			//First make a list of all the blocks we'll use for collision
			var ix:uint = Math.floor((Object.x - x)/_tileWidth);
			var iy:uint = Math.floor((Object.y - y)/_tileHeight);
			var iw:uint = Math.ceil(Object.width/_tileWidth)+1;
			var ih:uint = Math.ceil(Object.height/_tileHeight)+1;
			var r:uint = 0;
			var c:uint;
			while(r < ih)
			{
				if(r >= heightInTiles) break;
				d = (iy+r)*widthInTiles+ix;
				c = 0;
				while(c < iw)
				{
					if(c >= widthInTiles) break;
					dd = _data[d+c] as uint;
					if(dd >= collideIndex)
						blocks.push({x:x+(ix+c)*_tileWidth,y:y+(iy+r)*_tileHeight,data:dd});
					c++;
				}
				r++;
			}
			
			//Then check for overlaps
			var bl:uint = blocks.length;
			var hx:Boolean = false;
			var i:uint = 0;
			while(i < bl)
			{
				_block.x = blocks[i].x;
				_block.y = blocks[i++].y;
				if(_block.overlaps(Object))
					return true;
			}
			return false;
		}
		
		/**
		 * Checks to see if a point in 2D space overlaps a solid tile.
		 * 
		 * @param	X			The X coordinate of the point.
		 * @param	Y			The Y coordinate of the point.
		 * @param	Camera		Specify which game camera you want.  If null getScreenXY() will just grab the first global camera.
		 * @param	PerPixel	Not available in <code>FlxTilemap</code>, ignored.
		 * 
		 * @return	Whether or not the point overlaps this object.
		 */
		override public function overlapsPoint(X:Number,Y:Number,Camera:FlxCamera=null,PerPixel:Boolean = false):Boolean
		{
			if(Camera == null)
				Camera = FlxG.camera;
			X = X + FlxU.floor(Camera.scroll.x);
			Y = Y + FlxU.floor(Camera.scroll.y);
			getScreenXY(_point,Camera);
			return getTile(uint((X-_point.x)/_tileWidth),uint((Y-_point.y)/_tileHeight)) >= collideIndex;
		}
		
		/**
		 * Called by <code>FlxObject.updateMotion()</code> and some constructors to
		 * rebuild the basic collision data for this object.
		 */
		override public function refreshHulls():void
		{
			colHullX.x = 0;
			colHullX.y = 0;
			colHullX.width = _tileWidth;
			colHullX.height = _tileHeight;
			colHullY.x = 0;
			colHullY.y = 0;
			colHullY.width = _tileWidth;
			colHullY.height = _tileHeight;
		}
		
		/**
		 * <code>FlxU.collide()</code> (and thus <code>FlxObject.collide()</code>) call
		 * this function each time two objects are compared to see if they collide.
		 * It doesn't necessarily mean these objects WILL collide, however.
		 * 
		 * @param	Object	The <code>FlxObject</code> you're about to run into.
		 */
		override public function preCollide(Object:FlxObject):void
		{
			//Collision fix, in case updateMotion() is called
			colHullX.x = 0;
			colHullX.y = 0;
			colHullY.x = 0;
			colHullY.y = 0;
			
			var r:uint;
			var c:uint;
			var rs:uint;
			var col:uint = 0;
			var ix:int = FlxU.floor((Object.x - x)/_tileWidth);
			var iy:int = FlxU.floor((Object.y - y)/_tileHeight);
			var iw:uint = ix + FlxU.ceil(Object.width/_tileWidth)+1;
			var ih:uint = iy + FlxU.ceil(Object.height/_tileHeight)+1;
			if(ix < 0)
				ix = 0;
			if(iy < 0)
				iy = 0;
			if(iw > widthInTiles)
				iw = widthInTiles;
			if(ih > heightInTiles)
				ih = heightInTiles;
			rs = iy*widthInTiles;
			r = iy;
			while(r < ih)
			{
				c = ix;
				while(c < iw)
				{
					if((_data[rs+c] as uint) >= collideIndex)
						colOffsets[col++] = new FlxPoint(x+c*_tileWidth, y+r*_tileHeight);
					c++;
				}
				rs += widthInTiles;
				r++;
			}
			if(colOffsets.length != col)
				colOffsets.length = col;
		}
		
		/**
		 * Check the value of a particular tile.
		 * 
		 * @param	X		The X coordinate of the tile (in tiles, not pixels).
		 * @param	Y		The Y coordinate of the tile (in tiles, not pixels).
		 * 
		 * @return	A uint containing the value of the tile at this spot in the array.
		 */
		public function getTile(X:uint,Y:uint):uint
		{
			return getTileByIndex(Y * widthInTiles + X);
		}
		
		/**
		 * Get the value of a tile in the tilemap by index.
		 * 
		 * @param	Index	The slot in the data array (Y * widthInTiles + X) where this tile is stored.
		 * 
		 * @return	A uint containing the value of the tile at this spot in the array.
		 */
		public function getTileByIndex(Index:uint):uint
		{
			return _data[Index] as uint;
		}
		
		/**
		 * Change the data and graphic of a tile in the tilemap.
		 * 
		 * @param	X				The X coordinate of the tile (in tiles, not pixels).
		 * @param	Y				The Y coordinate of the tile (in tiles, not pixels).
		 * @param	Tile			The new integer data you wish to inject.
		 * @param	UpdateGraphics	Whether the graphical representation of this tile should change.
		 * 
		 * @return	Whether or not the tile was actually changed.
		 */ 
		public function setTile(X:uint,Y:uint,Tile:uint,UpdateGraphics:Boolean=true):Boolean
		{
			if((X >= widthInTiles) || (Y >= heightInTiles))
				return false;
			return setTileByIndex(Y * widthInTiles + X,Tile,UpdateGraphics);
		}
		
		/**
		 * Change the data and graphic of a tile in the tilemap.
		 * 
		 * @param	Index			The slot in the data array (Y * widthInTiles + X) where this tile is stored.
		 * @param	Tile			The new integer data you wish to inject.
		 * @param	UpdateGraphics	Whether the graphical representation of this tile should change.
		 * 
		 * @return	Whether or not the tile was actually changed.
		 */
		public function setTileByIndex(Index:uint,Tile:uint,UpdateGraphics:Boolean=true):Boolean
		{
			if(Index >= _data.length)
				return false;
			
			var ok:Boolean = true;
			_data[Index] = Tile;
			
			if(!UpdateGraphics)
				return ok;
			
			setDirty();
			
			if(auto == OFF)
			{
				updateTile(Index);
				return ok;
			}

			//If this map is autotiled and it changes, locally update the arrangement
			var i:uint;
			var r:int = int(Index/widthInTiles) - 1;
			var rl:int = r + 3;
			var c:int = Index%widthInTiles - 1;
			var cl:int = c + 3;
			while(r < rl)
			{
				c = cl - 3;
				while(c < cl)
				{
					if((r >= 0) && (r < heightInTiles) && (c >= 0) && (c < widthInTiles))
					{
						i = r*widthInTiles+c;
						autoTile(i);
						updateTile(i);
					}
					c++;
				}
				r++;
			}
			
			return ok;
		}
		
		/**
		 * Bind a function Callback(Core:FlxCore,X:uint,Y:uint,Tile:uint) to a range of tiles.
		 * 
		 * @param	Tile		The tile to trigger the callback.
		 * @param	Callback	The function to trigger.  Parameters should be <code>(Core:FlxCore,X:uint,Y:uint,Tile:uint)</code>.
		 * @param	Range		If you want this callback to work for a bunch of different tiles, input the range here.  Default value is 1.
		 */
		public function setCallback(Tile:uint,Callback:Function,Range:uint=1):void
		{
			FlxG.log("WARNING: FlxTilemap.setCallback()\nhas been temporarily deprecated.");
			//if(Range <= 0) return;
			//for(var i:uint = Tile; i < Tile+Range; i++)
			//	_callbacks[i] = Callback;
		}
		
		/**
		 * Call this function to lock the automatic camera to the map's edges.
		 * 
		 * @param	Camera		Specify which game camera you want.  If null getScreenXY() will just grab the first global camera.
		 * @param	Border		Adjusts the camera follow boundary by whatever number of tiles you specify here.  Handy for blocking off deadends that are offscreen, etc.  Use a negative number to add padding instead of hiding the edges.
		 */
		public function follow(Camera:FlxCamera=null,Border:int=0,UpdateWorld:Boolean=true):void
		{
			if(Camera == null)
				Camera = FlxG.camera;
			Camera.setBounds(x+Border*_tileWidth,y+Border*_tileHeight,width-Border*_tileWidth*2,height-Border*_tileHeight*2,UpdateWorld);
		}
		
		/**
		 * Shoots a ray from the start point to the end point.
		 * If/when it passes through a tile, it stores and returns that point.
		 * 
		 * @param	StartX		The X component of the ray's start.
		 * @param	StartY		The Y component of the ray's start.
		 * @param	EndX		The X component of the ray's end.
		 * @param	EndY		The Y component of the ray's end.
		 * @param	Result		A <code>Point</code> object containing the first wall impact.
		 * @param	Resolution	Defaults to 1, meaning check every tile or so.  Higher means more checks!
		 * @return	Whether or not there was a collision between the ray and a colliding tile.
		 */
		public function ray(StartX:Number, StartY:Number, EndX:Number, EndY:Number, Result:FlxPoint, Resolution:Number=1):Boolean
		{
			var step:Number = _tileWidth;
			if(_tileHeight < _tileWidth)
				step = _tileHeight;
			step /= Resolution;
			var dx:Number = EndX - StartX;
			var dy:Number = EndY - StartY;
			var distance:Number = Math.sqrt(dx*dx + dy*dy);
			var steps:uint = Math.ceil(distance/step);
			var stepX:Number = dx/steps;
			var stepY:Number = dy/steps;
			var curX:Number = StartX - stepX;
			var curY:Number = StartY - stepY;
			var tx:uint;
			var ty:uint;
			var i:uint = 0;
			while(i < steps)
			{
				curX += stepX;
				curY += stepY;
				
				if((curX < 0) || (curX > width) || (curY < 0) || (curY > height))
				{
					i++;
					continue;
				}
				
				tx = curX/_tileWidth;
				ty = curY/_tileHeight;
				if((_data[ty*widthInTiles+tx] as uint) >= collideIndex)
				{
					//Some basic helper stuff
					tx *= _tileWidth;
					ty *= _tileHeight;
					var rx:Number = 0;
					var ry:Number = 0;
					var q:Number;
					var lx:Number = curX-stepX;
					var ly:Number = curY-stepY;
					
					//Figure out if it crosses the X boundary
					q = tx;
					if(dx < 0)
						q += _tileWidth;
					rx = q;
					ry = ly + stepY*((q-lx)/stepX);
					if((ry > ty) && (ry < ty + _tileHeight))
					{
						if(Result == null)
							Result = new FlxPoint();
						Result.x = rx;
						Result.y = ry;
						return true;
					}
					
					//Else, figure out if it crosses the Y boundary
					q = ty;
					if(dy < 0)
						q += _tileHeight;
					rx = lx + stepX*((q-ly)/stepY);
					ry = q;
					if((rx > tx) && (rx < tx + _tileWidth))
					{
						if(Result == null)
							Result = new FlxPoint();
						Result.x = rx;
						Result.y = ry;
						return true;
					}
					return false;
				}
				i++;
			}
			return false;
		}
		
		/**
		 * Converts a one-dimensional array of tile data to a comma-separated string.
		 * 
		 * @param	Data		An array full of integer tile references.
		 * @param	Width		The number of tiles in each row.
		 * @param	Invert		Recommended only for 1-bit arrays - changes 0s to 1s and vice versa.
		 * 
		 * @return	A comma-separated string containing the level data in a <code>FlxTilemap</code>-friendly format.
		 */
		static public function arrayToCSV(Data:Array,Width:int,Invert:Boolean=false):String
		{
			var r:uint = 0;
			var c:uint;
			var csv:String;
			var Height:int = Data.length / Width;
			var d:int;
			while(r < Height)
			{
				c = 0;
				while(c < Width)
				{
					d = Data[r*Width+c];
					if(Invert)
					{
						if(d == 0)
							d = 1;
						else if(d == 1)
							d = 0;
					}
					
					if(c == 0)
					{
						if(r == 0)
							csv += d;
						else
							csv += "\n"+d;
					}
					else
						csv += ", "+d;
					c++;
				}
				r++;
			}
			return csv;
		}
		
		/**
		 * Converts a <code>BitmapData</code> object to a comma-separated string.
		 * Black pixels are flagged as 'solid' by default,
		 * non-black pixels are set as non-colliding.
		 * Black pixels must be PURE BLACK.
		 * 
		 * @param	PNGFile		An embedded graphic, preferably black and white.
		 * @param	Invert		Load white pixels as solid instead.
		 * @param	Scale		1 pixel = Scale number of tiles.  Default is 1.
		 * 
		 * @return	A comma-separated string containing the level data in a <code>FlxTilemap</code>-friendly format.
		 */
		static public function bitmapToCSV(bitmapData:BitmapData,Invert:Boolean=false,Scale:uint=1):String
		{
			//Import and scale image if necessary
			if(Scale > 1)
			{
				var bd:BitmapData = bitmapData;
				bitmapData = new BitmapData(bitmapData.width*Scale,bitmapData.height*Scale);
				var mtx:Matrix = new Matrix();
				mtx.scale(Scale,Scale);
				bitmapData.draw(bd,mtx);
			}
			
			//Walk image and export pixel values
			var r:uint = 0;
			var c:uint;
			var p:uint;
			var csv:String;
			var w:uint = bitmapData.width;
			var h:uint = bitmapData.height;
			while(r < h)
			{
				c = 0;
				while(c < w)
				{
					//Decide if this pixel/tile is solid (1) or not (0)
					p = bitmapData.getPixel(c,r);
					if((Invert && (p > 0)) || (!Invert && (p == 0)))
						p = 1;
					else
						p = 0;
					
					//Write the result to the string
					if(c == 0)
					{
						if(r == 0)
							csv += p;
						else
							csv += "\n"+p;
					}
					else
						csv += ", "+p;
					c++;
				}
				r++;
			}
			return csv;
		}
		
		/**
		 * Converts a resource image file to a comma-separated string.
		 * Black pixels are flagged as 'solid' by default,
		 * non-black pixels are set as non-colliding.
		 * Black pixels must be PURE BLACK.
		 * 
		 * @param	PNGFile		An embedded graphic, preferably black and white.
		 * @param	Invert		Load white pixels as solid instead.
		 * 
		 * @return	A comma-separated string containing the level data in a <code>FlxTilemap</code>-friendly format.
		 */
		static public function imageToCSV(ImageFile:Class,Invert:Boolean=false,Scale:uint=1):String
		{
			return bitmapToCSV((new ImageFile).bitmapData,Invert,Scale);
		}
		
		/**
		 * An internal function used by the binary auto-tilers.
		 * 
		 * @param	Index		The index of the tile you want to analyze.
		 */
		protected function autoTile(Index:uint):void
		{
			if(_data[Index] == 0) return;
			_data[Index] = 0;
			if((Index-widthInTiles < 0) || (_data[Index-widthInTiles] > 0)) 		//UP
				_data[Index] += 1;
			if((Index%widthInTiles >= widthInTiles-1) || (_data[Index+1] > 0)) 		//RIGHT
				_data[Index] += 2;
			if((Index+widthInTiles >= totalTiles) || (_data[Index+widthInTiles] > 0)) //DOWN
				_data[Index] += 4;
			if((Index%widthInTiles <= 0) || (_data[Index-1] > 0)) 					//LEFT
				_data[Index] += 8;
			if((auto == ALT) && (_data[Index] == 15))	//The alternate algo checks for interior corners
			{
				if((Index%widthInTiles > 0) && (Index+widthInTiles < totalTiles) && (_data[Index+widthInTiles-1] <= 0))
					_data[Index] = 1;		//BOTTOM LEFT OPEN
				if((Index%widthInTiles > 0) && (Index-widthInTiles >= 0) && (_data[Index-widthInTiles-1] <= 0))
					_data[Index] = 2;		//TOP LEFT OPEN
				if((Index%widthInTiles < widthInTiles-1) && (Index-widthInTiles >= 0) && (_data[Index-widthInTiles+1] <= 0))
					_data[Index] = 4;		//TOP RIGHT OPEN
				if((Index%widthInTiles < widthInTiles-1) && (Index+widthInTiles < totalTiles) && (_data[Index+widthInTiles+1] <= 0))
					_data[Index] = 8; 		//BOTTOM RIGHT OPEN
			}
			_data[Index] += 1;
		}
		
		/**
		 * Internal function used in setTileByIndex() and the constructor to update the map.
		 * 
		 * @param	Index		The index of the tile you want to update.
		 */
		protected function updateTile(Index:uint):void
		{
			if(_data[Index] < drawIndex)
			{
				_rects[Index] = null;
				return;
			}
			var rx:uint = (_data[Index]-startingIndex)*_tileWidth;
			var ry:uint = 0;
			if(rx >= _tiles.width)
			{
				ry = uint(rx/_tiles.width)*_tileHeight;
				rx %= _tiles.width;
			}
			_rects[Index] = (new Rectangle(rx,ry,_tileWidth,_tileHeight));
		}
	}
}
