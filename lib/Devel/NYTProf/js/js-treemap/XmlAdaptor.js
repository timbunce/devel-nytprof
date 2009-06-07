/*
 * XmlAdaptor.js - simple data adaptor for XML describing a directory hierarchy 
 */
 
/**
 * Create a XmlAdaptor
 * If JavaScript had abstract classes or interfaces, I would use them in here and in TreeNodeAdaptor
 */
function XmlAdaptor()
{
	/* a do-nothing constructor */
}

/**
 * Fetch the value of the given node
 * @return {number} node value
 */
XmlAdaptor.prototype.getValue = function( elem )
{
	return parseInt( elem.getAttribute( "bytes" ), 10 );
};

/**
 * Fetch the value of the given node
 * @return {number} node value
 */
XmlAdaptor.prototype.getChildren = function( elem )
{
	var result = new Array();
	for( var i=0, l=elem.childNodes.length; i<l; i++ )
	{
		if( elem.childNodes[i].nodeType == 1 )
		{
			result.push( elem.childNodes[i] );
		}
	}
	return result;
};

/**
 * Fetch the name of the given node
 * @return {string} node name
 */
XmlAdaptor.prototype.getName = function( elem )
{
	return elem.getAttribute( "name" );
};

/**
 * Predicate: is the given node a leaf node?
 * @return {boolean} 
 */
XmlAdaptor.prototype.isLeaf = function( elem )
{
	return elem.tagName == "file";
};

/**
 * Fetch the level of the given node in the overall model
 * @return {number} the depth of the given node the model
 */
XmlAdaptor.prototype.getLevel = function( elem )
{
	if( elem.parentNode == elem.ownerDocument ) return 0;
	return 1 + this.getLevel( elem.parentNode );
};

