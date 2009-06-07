/*
 * Shader object, for use with TreeNode hierarchies
 */

/**
 * Construct a TreeNodeShader
 * @constructor
 * @param rootNode a root TreeParentNode 
 */
function TreeNodeShader( rootNode )
{
	this.levels = rootNode.countDepth();
}

/**
 * Set of colours to use
 */
TreeNodeShader.purples = [
	"#E6E6FA",
	"#D8BFD8",
	"#DDA0DD",
	"#EE82EE",
	"#DA70D6",
	"#FF00FF",
	"#BA55D3",
	"#9370DB",
	"#8A2BE2",
	"#9400D3" ];

/**
 * Fetch a background colour
 * @param {number} level Depth into the data model
 * @return {string} a CSS colour string
 */
TreeNodeShader.prototype.getBackground = function( level )
{
	return TreeNodeShader.purples[ this.scale( level ) ];
};

/**
 * Fetch a foreground colour
 * @param {number} level Depth into the data model
 * @return {string} a CSS colour string
 */
TreeNodeShader.prototype.getForeground = function( level )
{
	// LOW: fairly arbitrary judgement of when black text isn't clear enough 
	return ( this.scale( level )  <= ( TreeNodeShader.purples.length /2 ) ) ? "black" : "white";
};

/**
 * Scale a number by the ratio of level:levels
 * @private
 */
TreeNodeShader.prototype.scale = function( level )
{
	return Math.floor( ( level * TreeNodeShader.purples.length ) / this.levels );
};