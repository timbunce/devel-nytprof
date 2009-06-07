/*
 * Shader object, for use with XML hierarchies
 */

/**
 * Construct an XmlShader
 * @constructor
 * @param xmlDoc an XML Document 
 */
function XmlShader( xmlDoc )
{
	this.levels = this.countDepth( xmlDoc.documentElement  );
}

/**
 * Fetch a background colour
 * @param {number} level Depth into the data model
 * @return {string} a CSS colour string
 */
XmlShader.prototype.getBackground = function( level )
{
	return TreeNodeShader.purples[ this.scale( level ) ];
};

/**
 * Fetch a foreground colour
 * @param {number} level Depth into the data model
 * @return {string} a CSS colour string
 */
XmlShader.prototype.getForeground = function( level )
{
	return ( this.scale( level )  <= ( TreeNodeShader.purples.length /2 ) ) ? "black" : "white";
};

/**
 * Scale a number by the ratio of level:levels
 * @private
 */
XmlShader.prototype.scale = function( level )
{
	return Math.floor( ( level * TreeNodeShader.purples.length ) / this.levels );
};

/**
 * Recursively find the maximum depth of the given XML element
 * @private
 * @return {number}
 */
XmlShader.prototype.countDepth = function( elem )
{
	if( elem.childNodes.length === 0 ) return 0;
	
	var childDepth = 0;
	for( var i=0, l=elem.childNodes.length; i<l; i++ )
	{
		if( elem.childNodes[i].nodeName == "dir" )
		{
			childDepth = Math.max( childDepth, this.countDepth( elem.childNodes[i] ) );
		}
	}			
	return 1 + childDepth;
};