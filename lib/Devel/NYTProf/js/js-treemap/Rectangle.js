 /**
  * Construct a rectangle, with either zero or four arguments
  * @constructor
  * @param {number} x X coordinate of this rectangle
  * @param {number} y Y coordinate of this rectangle
  * @param {number} width Width of this rectangle
  * @param {number} height Height of this rectangle
  */
function Rectangle( x, y, width, height )
{
	this.width = this.height = this.x = this.y = 0;
	if( arguments.length != 4 ) return;

	this.x = x;
	this.y = y;
	this.width = width;
	this.height = height;
	if(( width < 0 ) || ( height < 0 ) )alert( this + ": has negative width " );
}

/**
 * Get the relative coordinates of a div, 
 * @param div HTML div to query for coordinates
 * @return {Rectangle} coordinates of the given div
 */
Rectangle.fromDIV = function( div )
{
	return new Rectangle( div.offsetLeft, div.offsetTop, div.offsetWidth, div.offsetHeight );
};

/**
 * Create a copy of this rectangle
 * @return {Rectangle} copy of this object
 */
Rectangle.prototype.clone = function()
{
	return new Rectangle( this.x, this.y, this.width, this.height );
};

/**
 * Set a DIV to have these coordinates
 * @param div HTML div to move
 */ 
Rectangle.prototype.moveDIV = function( div )
{
	var style = div.style;
	style.left = this.x +"px";
	style.top = this.y +"px";
	style.width = this.width +"px";
	style.height = this.height +"px";
};

/**
 * @return a String representation of these coordinates
 * Possibly a bit unnecessary with toSource()
 */
Rectangle.prototype.toString = function()
{
	return "(x=" + this.x + ", y=" + this.y + ", width = " + this.width + ", height=" + this.height + ")";
};

/**
 * Is this rectangle wider than it's tall?
 * @return {boolean} true if this object is wider than tall
 */
Rectangle.prototype.isWide = function()
{
	return this.width > this.height;
};

/**
 * Calculate a fraction of the distance between two numbers
 * @private
 * @return the fraction of the distance between two numbers
 */
function interp( from, to, fraction )
{
	return ( to - from ) * fraction;
}

/**
 * Create a new rectangle that is interpolated between this and another
 * @param {Rectangle} other Another Rectangle to interpolate towards
 * @param {number} fraction a real number between 0 and 1, where 0 return this object and 1 returns 'other'
 * @return {Rectangle} a new rectangle between the two 
 */
Rectangle.prototype.interpolate = function( other, fraction )
{
	// For each coordinate - get the difference
	var result = this.clone();
	result.x += interp( result.x, other.x, fraction );
	result.y += interp( result.y, other.y, fraction );
	result.width += interp( result.width, other.width, fraction );
	result.height += interp( result.height, other.height, fraction );
	return result;
};


/**
 * Margin applied in shrink
 * @private
 */
Rectangle.margin = 2;

/**
 * Createa a smaller Rectangle, or none at all
 * @param {number} space in pixels to leave at the top 
 * @return {Rectangle} a smaller box, or null if any of the dimensions become negative
 * 
 */
Rectangle.prototype.shrink = function(  topD )
{
	var result = this.clone();
	result.x += Rectangle.margin;
	result.y += Rectangle.margin + topD;
	result.width -= ( Rectangle.margin *2 );
	result.height -= ( ( Rectangle.margin *2 ) + topD );

	if( result.width <= 0 || result.height <= 0 ) return null;
	return result;

};