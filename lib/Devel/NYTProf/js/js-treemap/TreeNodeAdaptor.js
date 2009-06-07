/**
 * TreeNodeAdaptor.js - an adaptor for a simple TreeNode/TreeParentNode hierarchy 
 */

/**
 * Create a TreeNodeAdaptor
 * If JavaScript had abstract classes or interfaces, I would use them in here and in XmlAdaptor
 */
function TreeNodeAdaptor()
{
	/* a do-nothing constructor */
}

/**
 * Fetch the value of the given node
 * @return {number} node value
 */
TreeNodeAdaptor.prototype.getValue = function( node )
{
	return node.getValue(); // Important for polymorphism
};

/**
 * Fetch the value of the given node
 * @return {number} node value
 */
TreeNodeAdaptor.prototype.getChildren = function( node )
{
	return node.children;
};

/**
 * Fetch the name of the given node
 * @return {string} node name
 */
TreeNodeAdaptor.prototype.getName = function( node )
{
	return node.name;
};

/**
 * Predicate: is the given node a leaf node?
 * @return {boolean} 
 */
TreeNodeAdaptor.prototype.isLeaf = function( node )
{
	return !( node instanceof TreeParentNode );
};

/**
 * Fetch the level of the given node in the overall model
 * @return {number} the depth of the given node the model
 */
TreeNodeAdaptor.prototype.getLevel = function( node )
{
	if( node.parent === null ) return 0;
	return 1 + this.getLevel( node.parent );
};
