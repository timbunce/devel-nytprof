//TODO: fix the minor overflow problems.

/**
 * Create a TreeMap widget
 * @constructor
 * @param {div} rootDIV A DIV element in the HTML DOM for use by the treemap
 * @param dataRoot the data hierarchy the treemap is to explore. This must be a TreeParentNode unless an adaptor is given in the options argument
 * @param options Optional settings for the object
 * @param options.shader A Shader implementation that is used to colour individual boxes in the treemap
 * @param options.decorator A Decorator implementation, used to decorate individual boxes in the treemap
 * @param options.adaptor An adaptor object, used by the treemap to interogae the dataRoot object. Only necessary if dataRoot is not a TreeMapParent instance
 */
function DivTreeMap( rootDIV, dataRoot, options )
{
	TreeMap.call( this, ( "adaptor" in options ) ? options.adaptor : new TreeNodeAdaptor() ); // Call the parent constructor

	// Process arguments
	this.rootDIV = rootDIV;
	this.displayNode = this.rootNode = dataRoot;
	this.dimensions = { width: 0, height:0 };
	
	// Some internal state
	this.selected = null; // currently/last 'selected' DIV 
	this.animSteps = 10;
	this.animDuration = 500;
	
	// Process options
	this.shader = ( "shader" in options ) ? options.shader : null;
	this.decorator = ( "decorator" in options ) ? options.decorator : new DefaultDecorator();
	
	// Record of steps into the data
	this.history = new Array();
	
	// MUST make the root container relatively positioned - to position text usefully
	this.rootDIV.style.position = "relative";
	
	this.repaint();
//	this.paint( this.displayNode, new Rectangle( 0, 0, this.rootDIV.clientWidth, this.rootDIV.clientHeight ) );
}

/**
 * Ensure that DivTreeMap inherits from TreeMap
 */
DivTreeMap.prototype = new TreeMap();

/**
 * Space between a box label and it's parent DIV
 */
DivTreeMap.LEFT_MARGIN = 5; // LOW: arbitrary constant


DivTreeMap.prototype.requestPaint = function( displayNode, displayRect, level )
{
	var cursorStyle = this.rootDIV.style.cursor;
	this.rootDIV.style.cursor = "wait";
	
	// Clear the content
	this.clear();
	
	var self = this;
	window.setTimeout( function() {
		self.repaint();
	}, 100 );
	
	// redraw the lot
	this.paint( this.displayNode, new Rectangle( 0, 0, this.rootDIV.clientWidth, this.rootDIV.clientHeight ) );

	// Restore cursor style
	this.rootDIV.style.cursor = cursorStyle;
};

/**
 * Clear and then paint the control 
 * Used when (un)zooming and resizing
 * @private
 */
DivTreeMap.prototype.repaint = function( )
{
	// Clear the content
	this.clear();
	
	// redraw the lot
	this.paint( this.displayNode, new Rectangle( 0, 0, this.rootDIV.clientWidth, this.rootDIV.clientHeight ) );
};

/**
 * Paint this treemap
 * @param displayNode data node used to render display
 * @param {Rectangle} displayRect Rectangle of space to consume during rendition
 * @param {number} level Depth into the overall hierarchy - displayNode may not be the rootNode
 * @private
 */
DivTreeMap.prototype.paint = function( displayNode, displayRect, level )
{
	if( arguments.length != 3 )
		level = this.adaptor.getLevel( displayNode );
	
	// Place all the items inside the given space
	var nodeFacades = this.squarify( displayNode, displayRect );

	for( var i=0, l=nodeFacades.length; i<l; i++ )
	{
		var facade = nodeFacades[i];
		var coords = facade.getCoords();

		// Parent the box div
		var box = document.createElement( "div" );
		box.style.position = "absolute";
		coords.moveDIV( box );

		// Longer term - there may be something to say for merging the shader & decorator iterfaces		
		if( this.decorator ) this.decorator.decorate( box, facade );
		if( this.shader ) box.style.background = this.shader.getBackground( level );

		box.node = facade.getNode();
		this.rootDIV.appendChild( box );

		// Stick a text label in there ... it's tempting to add it to the box DIV, but that causes issues ...
		var isParentNode = ! facade.isLeaf();
		var label = document.createElement( isParentNode ? "a" : "div" );
		label.style.position = "absolute";
		label.style.left = coords.x + "px";
		label.style.top = coords.y + "px";
		label.style.marginLeft = DivTreeMap.LEFT_MARGIN + "px";
		label.innerHTML = facade.getName();
		if( this.shader ) label.style.color = this.shader.getForeground( level );
		this.rootDIV.appendChild( label );		
		
		// Get the width/height of the label - is it larger than the destined cell?
		if( label.clientWidth + DivTreeMap.LEFT_MARGIN > coords.width || label.clientHeight > coords.height )
		{
                        // a simple strategy that yields good results is to
                        // simply stop using labels when the box is too small.
                        // The user still sees the boxes (and thus their relative sizes)
                        // and hovering over them will trigger the onMouseOver
                        // callback that typically shows useful information.
                        label.innerHTML = ""; // empty, zero height and width for label
		}
		
		// Recurse into the child node - if sensible
		if( isParentNode )
		{
			label.onclick = this.createCallback( "onZoomClick", facade.getNode(), box, true );
			label.href="#"; // No HREF, and it doesn't render as a link
			
			// Shrink the coordinates to show the parent box
			var subRect = facade.getCoords().shrink( label.clientHeight );
			if( subRect !== null )
				this.paint( facade.getNode(), subRect, level +1 );
		} else {
			label.onclick = this.createCallback( "onBoxClick", facade.getNode(), box, true );
		}
		
		var dataNode = facade.getNode();
		
		// Some minimal event handling
		box.onclick = this.createCallback( "onBoxClick", facade.getNode(), box, true );
		
		// Hook up other events
		box.onmouseover = this.createCallback( "onMouseOver", facade.getNode(), box, false );
		box.onmouseout = this.createCallback( "onMouseOut", facade.getNode(), box, false );
	}
	
	// Record the GUI size
	this.dimensions = { width: displayRect.width , height: displayRect.height };	
};

/**
 * Create a named callback
 * @param {string} methodName Name of method to call on this, if it exists
 * @param node data node to pass to the callback
 * @param elem HTML DIV element to pass to the callback
 * @param isSelectEvent Only true is this event is a 'select' event
 * @private
 */
DivTreeMap.prototype.createCallback = function( methodName, node, elem, isSelectEvent )
{
	var self = this;
	// NB: var-args style of argument passing would be nice, 
	// but 'arguments' is NOT an array and therefore lack a 'shift' method
	return function() {
		if( isSelectEvent ) self.setSelected( node, elem );
		if( methodName in self ) self[methodName]( node );
	};
};

/**
 * Zoom into the currently selected node, with animation
 */
DivTreeMap.prototype.zoom = function()
{	
	if( !( "selected" in this ) )
		throw "Nothing selected to zoom into";
	
	var map = this;
	var selected = this.getSelected();
	var anim = new BoxAnimator( selected.div, this.getCoords(), this.animSteps, this.animDuration );
	
	anim.before = function() { map.rootDIV.style.cursor = "wait"; };
	anim.afters = function() { map.doZoom(); map.rootDIV.style.cursor = "default"; };
	anim.animate();	
};

/**
 * Called once the animation is complete to effect the zoom
 * @private
 */
DivTreeMap.prototype.doZoom = function()
{
	this.history.push( this.displayNode );
	this.displayNode = this.getSelected().node;
	this.repaint();
	this.setSelected();
} ;

/**
 * Unzoom the control a single step, if possible
 * @return the number of steps left in the zoom history
 */
DivTreeMap.prototype.unzoom = function()
{
	if( this.history.length === 0 ) return 0;
	this.displayNode = this.history.pop(); 
	this.repaint();
	this.setSelected();
	
	return this.history.length;
};

/**
 * Repaint the control if it has been resized
 */
DivTreeMap.prototype.checkResize = function( width, height )
{
	if( this.dimensions.width == this.rootDIV.clientWidth &&
		this.dimensions.height == this.rootDIV.clientHeight ) return;

	// otherwise ...
	this.repaint();		
};

/**
 * Clear the contents of the control
 * @private
 */
DivTreeMap.prototype.clear = function()
{
	// remove all DIVs and texts .. backwards
	var children = this.rootDIV.childNodes;
	for( var i=children.length-1; i >= 0  ;i-- )
		this.rootDIV.removeChild( children[i] );
};

/**
 * Get get relative coordinates of the control
 * So x = y = 0 always
 * @return {Rectangle} coordinates of ths control 
 */
DivTreeMap.prototype.getCoords = function()
{
	return new Rectangle( 0, 0, this.dimensions.width, this.dimensions.height );
};

/**
 * Return the DIV and the dataNode that are selected currently
 * @return an object with properties 'div' and 'node'
 */
DivTreeMap.prototype.getSelected = function()
{
	return this.selected;
};

/**
 * Set the currrent selected element, or unset one altogether
 * @param node Optional data node that is 'selected'
 * @param {DIV} Optional div the DIV currently 'selected' 
 */
DivTreeMap.prototype.setSelected = function( node, div )
{
	this.selected = ( arguments.length === 0) ?
		null:
		{ node: node, div: div };
};

