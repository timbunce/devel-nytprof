

/**
 * Create a simple TreeNode oObject
 * @constructor
 * @param {string} name Name of this TreeNode
 * @param {number} value Value of this TreeNode
 */
function TreeNode( name, value )
{
	if( TreeNode.arguments.length === 0 ) return; // NB: this is a base class constructor .. sometimes
	this.name = name;
	this.value = value;
	this.parent = null;
}


/**
 * Get the value of this node
 * A simple value accessor .. something TreeParentNode can overload
 * @return {number} the value of this node
 */
TreeNode.prototype.getValue = function()
{
	return this.value;
};

/**
 * Fetch a string representation for this object
 * @return {String} the fully qualified name of this node
 */
TreeNode.prototype.toString = function()
{
	return this.getFqName() + "=" + this.value;
};

/**
 * Get the name of this node, preceded by the name of all parent nodes
 * @return {string} fully qualified node name
 */
TreeNode.prototype.getFqName= function()
{
	if( this.parent === null )
		return this.name;
	else
		return this.parent.getFqName() + "/" + this.name;
};

// ============================================================================

// The TreeParentNode class

/**
 * Construct a TreeParentNode object
 * this inherits from the TreeNode class
 * @constructor
 * @param {string} name Name of this TreeNode
 * @param children Array of TreeNode objects to contain
 */
function TreeParentNode( name, children )
{
	TreeNode.call( this, name, -1 );

	// Some additional state
	this.children = new Array();
	
	// Parent the children & weed out cuckoos (cause by trailing commas in IE - bah)
	for( var i=0, l=children.length; i<l; i++ )
	{
		if( children[i] instanceof TreeNode )
		{
			children[i].parent = this;
			this.children.push( children[i] );
		}
	}
}

// Inherits from TreeNode class
TreeParentNode.prototype = new TreeNode();

/**
 * Get the value of this object, from a cache if possible
 * Otherwise recursively calculate it
 * @retun {number} the value of this object
 */
TreeParentNode.prototype.getValue = function()
{
	var result = 0;
	if( this.value < 0 ) // Check for cached values
	{
		for( var i=0, l=this.children.length; i<l; i++ )
			result += this.children[i].getValue();
		this.value = result;
	}
	return this.value;
};

/**
 * How deep does this rabbit warren go?
 * @return {number} number of levels this data model has
 */
TreeParentNode.prototype.countDepth = function()
{
	if( this.children.length === 0 ) return 0;
	
	var childDepth = 0;
	for( var i=0,l=this.children.length; i<l; i++ )
	{
		if( this.children[i] instanceof TreeParentNode )
		{
			childDepth = Math.max( childDepth, this.children[i].countDepth() );
		}
	}			
	return 1 + childDepth;
};