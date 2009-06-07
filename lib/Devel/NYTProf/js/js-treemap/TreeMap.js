/**
 * Base functionality for treemap implementations
 * @constructor
 * @param adaptor Data adaptor
 */
function TreeMap( adaptor )
{
	if( arguments.length === 0 ) return;
	this.adaptor = adaptor;
}

TreeMap.HORIZONTAL = 1;
TreeMap.VERTICAL = 2;

/**
 * Place boxes in the given rectangle, making each as square as possible, wasting no space
 * @param parentNode, parent to children that are placed
 * @param {Rectangle} rootRect rectangle to fix boxes into
 */
TreeMap.prototype.squarify = function( parentNode, rootRect )
{
	var facades = NodeFacade.wrapChildren( this.adaptor, parentNode );

	// Sort the set of blocks
	facades.sort( NodeFacade.compare );

	// Allocate space to all the nodes
	this.divideDisplayArea( facades, rootRect );
	
	return facades;
};

/**
 * Tesselate the areas with the given areas into the given space
 * @param {Array} facades An array of NodeFacades for placing 
 * @param {Rectangle} destRectangle Destination rectangle
 * @private
 */
TreeMap.prototype.divideDisplayArea = function( facades, destRectangle )
{	
	// Check for boundary conditions
	if( facades.length === 0 ) return;

	if( facades.length == 1 )
	{
		facades[0].setCoords( destRectangle );
		return;
	}

	// Find the 'centre of gravity' for this node-list
	var halves = this.splitFairly( facades );

    // We can now divide up the available area into two
    // parts according to the lists' sizes.
	var midPoint;
	var orientation;
	
	var leftSum = this.sumValues( halves.left ),
		rightSum = this.sumValues( halves.right ),
		totalSum = leftSum + rightSum;

	// Degenerate case:  All size-zero entries.
	if( leftSum + rightSum <= 0 )
	{
		midPoint = 0;
		orientation = TreeMap.HORIZONTAL;
	} else {
		
		if( destRectangle.isWide() )
		{
			orientation = TreeMap.HORIZONTAL;
			midPoint = Math.round( ( leftSum * destRectangle.width ) / totalSum );
		} else {
			orientation = TreeMap.VERTICAL;
			midPoint = Math.round( ( leftSum * destRectangle.height ) / totalSum );
		}
	}

	// Once we've split, we recurse to divide up the two
	// new areas further, and we keep recursing until
	// we're only trying to fit one entry into any
	// given area.  This way, even size-zero entries will
	// eventually be assigned a location somewhere in the
	// display.  The rectangles below are created in
	// (x, y, width, height) format.
	
	if( orientation == TreeMap.HORIZONTAL )
	{
		this.divideDisplayArea( halves.left, new Rectangle( destRectangle.x, destRectangle.y, midPoint, destRectangle.height ) );
		this.divideDisplayArea( halves.right, new Rectangle( destRectangle.x + midPoint, destRectangle.y, destRectangle.width - midPoint, destRectangle.height ) );
	} else {
		this.divideDisplayArea( halves.left, new Rectangle( destRectangle.x, destRectangle.y, destRectangle.width, midPoint ) );
		this.divideDisplayArea( halves.right, new Rectangle( destRectangle.x, destRectangle.y + midPoint, destRectangle.width, destRectangle.height - midPoint ) );
	}
};

/*
 * Break the list in two by size, roughly
 * @param {Array} facades An array of NodeFacades
 * @private
 * @return An object with fields 'left' and 'right' containing Arrays of NodeFacade objects
 */
TreeMap.prototype.splitFairly = function( facades )
{
	var midPoint = 0;
	
	if( this.sumValues( facades ) === 0 )
	{
		midPoint = Math.round( facades.length /2 ); // JS uses floating-point maths
	} else {
		var halfValue = this.sumValues( facades ) /2;
		var accValue = 0;
		for( var l=facades.length; midPoint< l; midPoint++ )
		{
			//NB: zeroth item _always_ goes into left-hand list
			if( midPoint > 0 && ( accValue + facades[midPoint].getValue() > halfValue ) )
				break;
			accValue += facades[midPoint].getValue();
		}
	}

	return { 
		left: facades.slice( 0, midPoint ),
		right: facades.slice( midPoint )
	};
};

/*
 * Convenience function - return the sum of the values for an array of facades
 * @param {Array} facades An array of NodeFacade objects 
 * @private
 */
TreeMap.prototype.sumValues = function( facades )
{
	var result =0;
	for( var i=0, l=facades.length; i<l; i++ )
		result += facades[i].getValue();
	return result;
};
