/*
*	treemap plugin for jQuery (version 1.0.3 13/8/2008)
*	Copyright (c) 2007-2008 Renato Formato <renatoformato@virgilio.it>
*	Dual licensed under the MIT (MIT-LICENSE.txt)
* and GPL (GPL-LICENSE.txt) licenses.
*/
(function($) {
$.fn.treemap = function(w,h,options) {
	options = $.extend({labelCell:0,dataCell:1,colorCell:2,headHeight:20,borderWidth:1,sort:true,nested:false,legend:false},options);
	var or_target = options.target;
	return this.pushStack($.map(this,function(el){
		var data;
		if(!options.getData) {
			if(!$.nodeName(el,"table")) return; 
			data = treemap.getDataFromTable(el,options);
		} else {
			data = options.getData(el);
		}
		
		//copy data because during the processing elements are deleted
		data = data.concat();
		
		if($.fn.treemap.caller!=treemap.layoutRow) {
			options.minColorValue = Number.POSITIVE_INFINITY;
			options.maxColorValue = Number.NEGATIVE_INFINITY;
			if(!options.colorDiscreteVal) options.colorDiscreteVal = {num:0};
			treemap.normalizeValues(data,options);
			options.colorDiscrete = options.minColorValue == Number.POSITIVE_INFINITY;
			options.rangeColorValue = options.maxColorValue-options.minColorValue;
		}
		
		if (options.sort)
			data.sort(function(a,b){
				var val1 = b[1], val2 = a[1];
				val1 = val1.constructor==Array?treemap.getValue(val1):val1;
				val2 = val2.constructor==Array?treemap.getValue(val2):val2;
				return val1-val2;
			});
		
		options.target = or_target || el;
		options.numSquare = 0;
		   
		treemap.render(data,h,w,options);
		
		if($.fn.treemap.caller!=treemap.layoutRow && options.legend) {
			jQuery(options.target).append(treemap.legend(h,options));
		}
		
		if(options.target==el && $.nodeName(el,"table")) {
			var newObj = jQuery(el).find(">").insertBefore(el);
			$(el).remove();
			el = newObj.get();
		}
		return el; 
	}));
}

$.fn.treemapClone = function() {
	return this.pushStack( jQuery.map( this, function(a){
 		return a.outerHTML ? jQuery(a.outerHTML)[0] : a.cloneNode(true);
 	})); 
}

$.fn.treemapAppend = function(arguments) {
	var el = this[0];
	for(var i=0,l=arguments.length;i<l;i++)
		el.appendChild(arguments[i]);
	return this; 
}


var treemap = {
	 normalizeValues : function(data,options) {
		for(var i=0,dl=data.length;i<dl;i++)
			if(data[i][1].constructor==Array) 
				treemap.normalizeValues(data[i][1],options);
			else {
				var val = data[i][1] = parseFloat(data[i][1]);
				var color = data[i][2];
				if(color<options.minColorValue) options.minColorValue=color;
				if(color>options.maxColorValue) options.maxColorValue=color;
				if(!options.colorDiscreteVal[color]) options.colorDiscreteVal[color] = options.colorDiscreteVal.num++;
			} 	
	},
	
	getDataFromTable : function(table,options) {
		var data = [];
		if(options.labelCell==undefined) options.labelCell = options.dataCell;
		$("tbody tr",table).each(function(){
			var cells = $(">",this);
			var row = [cells.eq(options.labelCell).html(),
								 cells.eq(options.dataCell).html(),
								 cells.eq(options.colorCell).html()];
			data.push(row);
		});
		return data;
	}, 
	
	emptyView: $("<div>").addClass("treemapView"),
	
	render : function(data,h,w,options) {
		options.height = h;
		options.width = w;
		var s = treemap.calculateArea(data);
		options.viewAreaCoeff = w*h/s;
		options.view = treemap.emptyView.clone().css({'width':w,'height':h});
		options.content = []; 
    treemap.squarify(data,[],h,true,options);
		options.view.treemapAppend(options.content);
		$(options.target).empty().treemapAppend(options.view);
	},
	
	squarify : function(data,row,w,orientation,options) {
		if(w<=0) return; //exit if there's no space left on the treemap
		var widerRow = row,s,s2,current;
		do {
			row = widerRow; 
			s = treemap.calculateArea(row);
			if(data.length==0) return treemap.layoutRow(row,w,orientation,s,options,true);
			current = data.shift();
			widerRow = row.concat();
			widerRow.push(current);
			s2 = s+(current[1].constructor==Array?treemap.getValue(current[1]):current[1]);
		} while (treemap.worst(row,w,s,options.viewAreaCoeff)>=treemap.worst(widerRow,w,s2,options.viewAreaCoeff))		

		var rowDim = treemap.layoutRow(row,w,orientation,s,options);
		data.unshift(current);

		if(!rowDim) rowDim = treemap.layoutRow([['',s]],w,orientation,s,options,true);
		var width;
		if(orientation) {
			options.width -= rowDim;
			width = options.width;
		} else {
			options.height -= rowDim;
			width = options.height;
		}
		treemap.squarify(data,[],width,!orientation,options);
	},
	
	worst : function(row,w,s,coeff) {
		var rl = row.length;
		if(!rl) return Number.POSITIVE_INFINITY;
		var w2 = w*w, s2 = s*s*coeff;
		var r1 = (w2*(row[0][1].constructor==Array?treemap.getValue(row[0][1]):row[0][1]))/s2;
		var r2 = s2/(w2*(row[rl-1][1].constructor==Array?treemap.getValue(row[rl-1][1]):row[rl-1][1]));
		return Math.max( r1, r2 );
	},
	
	emptyCell: $("<div>").addClass("treemapCell").css({'float':'left','overflow':'hidden'}),
	emptySquare: $("<div>").addClass("treemapSquare").css('float','left'),
	
	layoutRow : function(row,w,orientation,s,options,last) {
		var square = treemap.emptySquare.treemapClone();
		var rowDim, h = s/w;
		if(orientation) {
			rowDim = last?options.width:Math.min(Math.round(h*options.viewAreaCoeff),options.width);
			square.css({'width':rowDim,'height':w}).addClass("treemapV");
		} else {
			rowDim = last?options.height:Math.min(Math.round(h*options.viewAreaCoeff),options.height);
			square.css({'height':rowDim,'width':w}).addClass("treemapH");
		}
		var rl = row.length-1,sum = 0, bw = options.borderWidth, bw2 = bw*2, cells = []; 
		for(var i=0;i<=rl;i++) {
			var n = row[i],hier = n[1].constructor == Array, head = [], val = hier?treemap.getValue(n[1]):n[1];
			var cell = treemap.emptyCell.treemapClone();
			if(!hier) cell.append(n[0])[0].title = cell.text()+' ('+val+')'; 
			var lastCell = i==rl;
			var fixedDim = rowDim, varDim = lastCell ? w-sum : Math.round(val/h);
			if(varDim<=0) break;
			sum += varDim;
			var cellStyles = {};
			if(bw && rowDim>bw2 && varDim>bw2) {
				if(jQuery.boxModel) {
					fixedDim -= bw*(2-(options.numSquare>=2 || !options.numSquare && options.nested?1:0)-(last && options.nested?1:0));
					varDim -= bw*(2-(!lastCell||options.nested?1:0)-(options.numSquare>=1 && !i?1:0));
				}
				cellStyles.border = bw+'px solid';
				if(!lastCell || options.nested) 
					cellStyles['border'+(orientation?'Bottom':'Right')] = 'none';
				if(options.numSquare>=2 || !options.numSquare && options.nested) 
					cellStyles['border'+(orientation?'Left':'Top')] = 'none';
				if(options.numSquare>=1 && !i) 
					cellStyles['border'+(orientation?'Top':'Left')] = 'none';
				if(last && options.nested)
					cellStyles['border'+(orientation?'Right':'Bottom')] = 'none';
			} 
			var height = orientation?varDim:fixedDim, width = orientation?fixedDim:varDim;
			
			cellStyles.height = height+'px';
			cellStyles.width = width+'px';
			if(hier) {
				if(options.headHeight) {
					head = $("<div class='treemapHead'>").css({"width":width,"height":options.headHeight,"overflow":"hidden"}).html(n[0]).attr('title',n[0]+' ('+val+')');
					if(orientation) 
						height = varDim -= options.headHeight;
					else
						height = fixedDim -= options.headHeight;
					 
				}
				if(height>0) {
					var new_opt = {};
					for(var prop in options) new_opt[prop] = options[prop]; 
					new_opt["target"] = null;
					new_opt = jQuery.extend(new_opt,{getData:function(){return n[1].concat()},nested:true});
					cell.treemap(width,height,new_opt);
				}
				cell.prepend(head);
			} else {
				if(n[2]) cellStyles.backgroundColor = treemap.getColor(n[2],options);
			}
			
			//cell.css(cellStyles);
			var cellstyle = cell[0].style;
      for(var prop in cellStyles)
        cellstyle[prop] = cellStyles[prop];

			cells.push(cell[0]);
		}
		options.content.push(square.treemapAppend(cells)[0]);
		options.numSquare++;
		return rowDim;
	},
	
	calculateArea : function(row) {
		if(row.total) return row.total;
		var s = 0,rl = row.length;
		for(var i=0;i<rl;i++) {  
			var val = row[i][1];
			s += val.constructor==Array?treemap.getValue(val):val;
		}
		
		return row.total = s;
	},
	
	getValue : function(val) {
			if(!val.total) val.total=treemap.calculateArea(val);
			return val.total;
	},
	
	getColor : function(val,options) {
		var colorCode;
		if(options.colorDiscrete) {
			colorCode = options.colorDiscreteVal[val]/options.colorDiscreteVal.num;
		} else {
			colorCode = (val-options.minColorValue)/options.rangeColorValue;
		}
		return treemap.getColorCode(colorCode);
	},
	
	getColorCode : function(colorCode) {
		colorCode = Math.round(colorCode*510);
		if(colorCode==0) return "#0000FF";
		if(colorCode<=255) {
			var code1 = colorCode.toString(16);
			if(code1.length<2) code1 = "0"+code1;
			var code2 = (255-colorCode).toString(16);
			if(code2.length<2) code2 = "0"+code2;
			return "#00"+code1+code2;
		}
		if(colorCode<=510) {
			colorCode -= 255
			var code1 = (colorCode).toString(16);
			if(code1.length<2) code1 = "0"+code1;
			var code2 = (255-colorCode).toString(16);
			if(code2.length<2) code2 = "0"+code2;
			return "#"+code1+code2+"00";
		}	
	},
	
	emptyLegendDescr : $("<div class='treemapLegendDescr'>").css({position:'absolute',left:25,width:200}),
	
	legend : function(h,options) {
		var l = $("<div class='treemapLegend'>").css({position:'relative','float':'left',height:h-2});
		var bar = $("<div>").css({width:20,height:h-2,border:"1px solid"});
		options.view.css({'float':'left','marginRight':20});
		if(options.colorDiscrete) {
			$.each(options.colorDiscreteVal,function(i,n){
				if(i!='num') {
					i = options.descriptionCallback ? options.descriptionCallback(i):i;
					var height = Math.round(n*h/options.colorDiscreteVal.num);
					var bar = $("<div>").css({height:20,width:20,backgroundColor:treemap.getColor(i,options),position:'absolute',bottom:height});
					var desc = treemap.emptyLegendDescr.clone().text(i).css('bottom',height);
					l.append(bar).append(desc);
				}
			});
		} else {
			for(var i=h-1;i>1;i--) {
				var color = $("<div>").height(1).css("backgroundColor",treemap.getColorCode(i/h));
				bar.append(color);
			};
			l.append(bar);
			for(var i=0;i<10;i++) {
				var val = i*options.rangeColorValue/10+options.minColorValue;
				val = options.descriptionCallback ? options.descriptionCallback(val):val; 
				var desc = treemap.emptyLegendDescr.clone().text(val.toString()).css('bottom',Math.round(i*h/10));
				l.append(desc);
			};		
		}
		return l;
	}
}
})(jQuery)
