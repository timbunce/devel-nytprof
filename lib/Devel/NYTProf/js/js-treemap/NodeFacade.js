/**
 * NodeFacade.js - 'Facade' for for the raw data objects - which are occasionally inviolate
 * ... meaning that extra properties cannot be added to them
 * @constructor
 * @param {Adaptor} adaptor Object used to interact with the data object
 * @param node raw data object
 */ 
function NodeFacade( adaptor, node )
{
	this.adaptor = adaptor;
	this.node = node;
	this.coords = null;
}

/**
 * Static 'bulk constructor'
 * @param {Adaptor} adaptor Object used to interact with the data objects
 * @param node Parent node to children that are to be wrapped
 * @return an array of NodeFacade objects
 */
NodeFacade.wrapChildren = function( adaptor, node )
{
	var children = adaptor.getChildren( node );
	var result = new Array( children.length );
	for( var i=0, l=result.length; i<l ;i++ )
		result[i] = new NodeFacade( adaptor, children[i] );
	return result;
};

/**
 * @return {String} a human useful string, describing this node-facade
 */
NodeFacade.prototype.toString = function()
{
	return this.coords + " node: " + this.node; 
};

/**
 * Compare one nodefacade with another
 * An ideal fit for Array.sort()
 * @param a A nodefacade object
 * @param b Another nodefacade object
 * @return {number} negative number if A>B, positive number if A<B, zero otherwise
 */
NodeFacade.compare = function( a, b )
{
	return b.getValue() - a.getValue();
};

/**
 * Fetch the value of the underlying node with the adaptor
 * Using a cached local value - if at all possible
 * @return {number} underlying node value
 */
NodeFacade.prototype.getValue = function()
{
	if( "value" in this ) return this.value;
	return this.value = this.adaptor.getValue( this.node );
};

/**
 * Fetch the name of the underlying node with the adaptor
 * @return {string} underlying node name
 */
NodeFacade.prototype.getName = function()
{
	return this.value = this.adaptor.getName( this.node );
};

/**
 * Fetch the children of the underlying node with the adaptor
 * @return {Array} underlying node children
 */
NodeFacade.prototype.getChildren = function()
{
	return this.adaptor.getChildren( this.node );
};

/**
 * Predicate - can this NodeFacade a leaf in the graph? 
 * @return {number} underlying node isLeaf value
 */
NodeFacade.prototype.isLeaf = function()
{
	return this.adaptor.isLeaf( this.node );
};


/**
 * Set the coordinates
 * @param {Rectangle} coords The new coordinates of this object
 */
NodeFacade.prototype.setCoords = function( coords )
{
	this.coords = coords;
};

/**
 * Fetch the coordinates of this object
 * @return {Rectangle} the coordinates of this object
 */
NodeFacade.prototype.getCoords = function()
{
	return this.coords;
};

/**
 * Fetch the underlying data node
 * @return the underlying data node
 */
NodeFacade.prototype.getNode = function()
{
	return this.node;
};