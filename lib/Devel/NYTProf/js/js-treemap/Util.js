/**
 * Find a parent node of a specific type
 * @param node HTML node to begin the search at
 * @param {string} parentTag element type to search fo
 */
function findParentNode( node, parentTag )
{
	if( node.tagName.toLowerCase() == parentTag.toLowerCase() ) return node;
	return findParentNode( node.parentNode, parentTag );
}

/**
 * Get the absolute coordinates of a given div
 * @return Object with fields 'left' and 'top', both numbers
 */
function getAbsCoords( div )
{
	if( div === null )
	{
		return { left: 0, top: 0 };
	} else {
		var parentCoords = getAbsCoords( div.offsetParent );
		return { 
			left: div.offsetLeft + parentCoords.left, 
			top: div.offsetTop + parentCoords.top 
		};
	}
}

/**
 * Create an AJAX request object, taking platform differences into some account
 * @return {XMLHttpRequest}
 */
function createAjaxRequest()
{
	if (window.XMLHttpRequest)
		return new XMLHttpRequest();
	else {
		try {
			return new ActiveXObject( "Microsoft.XMLHTTP" );
		} catch (ex) {
			return new new ActiveXObject( "Msxml2.XMLHTTP" );
		}
	}
}

/**
 * Is this running in Internet Explorer?
 * @return {boolean}
 */
function isInternetExplorer()
{
		return navigator.appName.toLowerCase().search( "internet explorer" ) != -1;
}