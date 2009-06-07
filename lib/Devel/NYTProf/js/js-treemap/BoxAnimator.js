/**
 * Create an instance of a BoxAnimator
 * @constructor
 * @param div The source DIV node to animator
 * @param {Rectangle} newCoords The coordinates to animate the DIV unto
 * @param {number} steps The number of animation steps to take
 * @param {number} millis The number of milliseconds between each step
 * @param {function} afters a callback function to execute once the animation is complete 
 * 
 * TODO: enlarge text label as part of animation
 */
function BoxAnimator( div, newCoords, steps, millis ) {
	// Get current coords
	this.div = div;
	this.oldCoords = Rectangle.fromDIV( div );
	this.newCoords = newCoords;
	this.steps = steps;
	this.millis = millis;
	this.stepTime = Math.floor( millis/steps );

	// Establish default values for callbacks
	this.afters = this.before = null;
}

/**
 * Begin the animations
 */
BoxAnimator.prototype.animate = function()
{
	if( this.before !== null ) { this.before(); }
	
	// Raise the div above the rest 
	this.div.style.zIndex = 10;
	this.setPaint( 1 );
};

/**
 * Paint an single step of the animation, or call the 'afters' callback
 * @private
 */
BoxAnimator.prototype.paintStep = function( stepNumber )
{
	if( stepNumber > this.steps ) {
		// Finally, call the next step in a bit
		if( this.afters !== null ) this.afters();
	} else {
		// Interpolate the coordinates by step/steps
		var stepCoords = this.oldCoords.interpolate( this.newCoords, stepNumber/this.steps );		
		stepCoords.moveDIV( this.div );
		
		stepNumber++;
		this.setPaint( stepNumber );
	}
};

/**
 * Set the timer for the next animation step
 * @private
 */
BoxAnimator.prototype.setPaint = function( stepNumber )
{
	var self = this;
	window.setTimeout( function() {
		self.paintStep( stepNumber );
	}, self.stepTime );
};