/**
 * A simple DIV decorator - that applies a CSS class - and that's it
 * @constructor
 * @param {string} cssClassName A CSS style name to apply
 * A decorator need only implement a method 'decorate' 
 */
function CssDecorator( cssClassName )
{
	this.cssClassName = cssClassName;
}

/**
 * decorate a given DIV
 * @param div the HTML DIV to decorate
 * @param node the raw data node behind this DIV
 * @param {Rectangle} coords The relative coordinates of this DIV 
 */
CssDecorator.prototype.decorate = function( div, nodeFacade )
{
	div.className = this.cssClassName;
};
// ============================================================================

/**
 * The default DIV decorator - applies something like a useful style to a given DIV
 * @constructor
 * @param {string} cssClassName A CSS style name to apply
 */
function DefaultDecorator()
{
	//LOW: figure out how to create a CSS class at runtime & apply that instead
}

DefaultDecorator.prototype = new CssDecorator();

/**
 * decorate a given DIV
 * @param div the HTML DIV to decorate
 * @param node the raw data node behind this DIV
 * @param {Rectangle} coords The relative coordinates of this DIV 
 */
DefaultDecorator.prototype.decorate = function( div, nodeFacade )
{
	var style = div.style;
	style.borderWidth = "1px";
	style.borderStyle = "outset";
//	style.cursor = "default";
};