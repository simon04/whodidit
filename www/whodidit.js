// WHODIDID Frontend JS. Written by Ilya Zverev, licensed WTFPL

var map;
var popup;
var vectorLayer;
var permalink;

var changeset;
var username;
var age;
var editor;
var defaultage = 7; // should be equal to the default age in tiles.php

var cookieName = '_wdi_location'; // comment out to not remember last location
var epsg4326 =  new OpenLayers.Projection("EPSG:4326"); //WGS 1984 projection

function init() {
    populateAgeBox();
    var queryString = parseQueryString();
    if( queryString.changeset ) setChangeset(queryString.changeset);
    if( queryString.user ) setUser(queryString.user);
    if( queryString.editor ) editor = queryString.editor;
    setAge(queryString.age ? queryString.age : defaultage);

    map = new OpenLayers.Map('map', {displayProjection: epsg4326});

    map.addLayer(new OpenLayers.Layer.OSM()); //Standard mapnik tiles
    map.baseLayer.attribution = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors';

    permalink = new OpenLayers.Control.Permalink('permalink', null, {createParams: myCreateArgs});
    map.addControls([
        permalink,
        new OpenLayers.Control.MousePosition({numDigits: 3})
    ]);

    projectTo = map.getProjectionObject(); //The map projection (Spherical Mercator)

    // boxLayer is used to draw rectangles, which are bounds for a RSS feed.
    boxLayer = new OpenLayers.Layer.Vector('BBOX');
    map.addLayer(boxLayer);
    boxControl = new OpenLayers.Control.DrawFeature(boxLayer, OpenLayers.Handler.RegularPolygon, {featureAdded: featureAdded, handlerOptions: {
        sides: 4,
        irregular: true
    }});

    map.addControl(boxControl);

    // Styling for tile layer
    var context = {
        getColor: function(feature) {
            if( feature.attributes.nodes_deleted > 0 && feature.attributes.nodes_modified + feature.attributes.nodes_created == 0 ) return 'red';
            if( feature.attributes.nodes_deleted > 0 && (+feature.attributes.nodes_modified) + (+feature.attributes.nodes_created) < feature.attributes.nodes_deleted * 40 ) return 'yellow';
            if( (+feature.attributes.nodes_modified) > 40 ) return 'yellow';
            return '#7f7';
        }
    };
    var template = {
        fillColor: "${getColor}",
        fillOpacity: 0.4,
        strokeColor: '#333',
        strokeOpacity: 0.4
    };
    var style = new OpenLayers.Style(template, {context: context});

    vectorLayer = new OpenLayers.Layer.Vector("WhoDidIt Tiles", {
        strategies: [new OpenLayers.Strategy.BBOX({resFactor: 2.0, ratio: 1.3})],
        protocol: new OpenLayers.Protocol.HTTP({
            url: scripts + 'tiles.php',
            params: getParams(),
            format: new OpenLayers.Format.GeoJSON(),
            handleRead: handleMessageRead,
            read: startMessageRead
        }),
        styleMap: new OpenLayers.StyleMap({'default': style, 'select': OpenLayers.Feature.Vector.style["select"]}),
        projection: epsg4326
    });

    map.addLayer(vectorLayer);

    // Set centre. The location of the last lat lon to be processed. 
    if( !map.getCenter() )
        restoreLocation();
    if (!map.getCenter()) {
        var zoom=4;
        var lonLat = new OpenLayers.LonLat(32, 50).transform(epsg4326, projectTo);
        map.setCenter (lonLat, zoom);
    }

    // Add a selector control to the vectorLayer with popup functions
    var selector = new OpenLayers.Control.SelectFeature(vectorLayer, { onSelect: createPopup, onUnselect: destroyPopup });

    function createPopup(feature) {
        var nodeinfo = feature.attributes.nodes_created + ' nodes created, ' + feature.attributes.nodes_modified + ' modified, ' + feature.attributes.nodes_deleted + ' deleted in this tile.<br>';
        var bbox = feature.geometry.bounds.clone().transform(projectTo, epsg4326);
        var josmlink = '<div class="openjosm"><a href="http://127.0.0.1:8111/load_and_zoom?left='+round2(bbox.left)+'&top='+round2(bbox.top)+'&right='+round2(bbox.right)+'&bottom='+round2(bbox.bottom)+'" target="_blank">Open in JOSM</a></div>';
        popup = new OpenLayers.Popup.FramedCloud("pop",
            feature.geometry.getBounds().getCenterLonLat(),
            null,
            '<div class="markerContent">' + nodeinfo + 'Changesets: ' + feature.attributes.changesets + '</div>' + josmlink,
            null,
            true,
            function() { selector.unselectAll(); }
        );
        // Send ajax request to get changeset information
        var request = OpenLayers.Request.GET({
            url: scripts + 'changeset.php',
            params: { id: feature.attributes.changesets },
            callback: function(req) {
                var json = new OpenLayers.Format.JSON();
                var changesets = json.read(req.responseText);
                var html = josmlink + '<div class="markerContent">' + nodeinfo + '<table id="changesets">';
                var months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
                for( i = 0; i < changesets.length; i++ ) {
                    var ch = changesets[i];
                    ch.color = ch['suspicious'] ? 'red' : 'green';
                    ch.date_str = months[ch['change_time'].substr(5,2)-1] + ' ' + ch['change_time'].substr(8,2);
                    ch.nicecomment = ch['comment'] && ch['comment'].length > 2 && ch['comment'].substring(0,5) != 'BBOX:' ? ch['comment'] : undefined;
                    ch.user_name_encoded = encodeURIComponent(ch.user_name);
                    html += tmpl('changeset_tmpl', ch);
                }
                html += '</table>' + '</div>';
                feature.popup.setContentHTML(html);
            }
        });
        feature.popup = popup;
        popup.feature = feature;
        map.addPopup(popup);
    }

    function destroyPopup(feature) {
        if( feature.popup) {
            map.removePopup(feature.popup);
            popup.feature = null;
            feature.popup.destroy();
            feature.popup = null;
            popup = null;
        }
    }

    // When map is dragged, all features are redrawn, but popup stays and becomes unclosable. This fixes it.
    vectorLayer.events.register('beforefeaturesremoved', ' ', function() { if(popup) destroyPopup(popup.feature); });

    selector.handlers.feature.stopDown = false;
    map.addControl(selector);
    selector.activate();

    // Get latest changeset date
    OpenLayers.Request.GET({
        url: scripts + 'changeset.php',
        params: { latest: 1 },
        callback: function(req) {
            var json = new OpenLayers.Format.JSON();
            var changesets = json.read(req.responseText);
            if( changesets.length > 0 ) {
                document.getElementById('logo').title = 'Last changeset from ' + changesets[0]['change_time'] + ' UTC';
            }
        }
    });

    // Add &show=1 to zoom on user/changeset tiles
    if( queryString.show ) {
        zoomToTiles();
    }

    // Remember last shown location in cookies
    map.events.register("moveend", map, saveLocation);
    saveLocation();
}

/* --------------------------  END OF INIT()  ------------------------------------------- */

function parseQueryString() {
    var query_string = {};
    var query = window.location.search.substring(1);
    var vars = query.split("&");
    for( var i = 0; i < vars.length; i++ ) {
        var pair = vars[i].split("=");
        pair[1] = decodeURIComponent(pair[1]);
        if (typeof query_string[pair[0]] === "undefined") {
            // If first entry with this name
            query_string[pair[0]] = pair[1];
        } else if (typeof query_string[pair[0]] === "string") {
            // If second entry with this name
            var arr = [ query_string[pair[0]], pair[1] ];
            query_string[pair[0]] = arr;
        } else {
            // If third or later entry with this name
            query_string[pair[0]].push(pair[1]);
        }
    } 
    return query_string;
}
    
// Fiddle with permalink's url parameters
function myCreateArgs() {
    var args = OpenLayers.Control.Permalink.prototype.createParams.apply(this, arguments);
    if( changeset ) args['changeset'] = changeset; else delete args['changeset'];
    if( username ) args['user'] = username; else delete args['user'];
    if( editor ) args['editor'] = editor; else delete args['editor'];
    if( age != defaultage ) args['age'] = age; else delete args['age'];
    delete args['show'];
    return args;
}

// Overriding protocol to display error message
function startMessageRead(options) {
    document.getElementById('message').style.visibility = 'hidden';
    return OpenLayers.Protocol.HTTP.prototype.read.apply(this, arguments);
}

function handleMessageRead(resp, options) {
    var request = resp.priv;
    document.getElementById('message').style.visibility = 'hidden';
    if( request.status >= 200 && request.status < 300 ) {
        var doc = request.responseText;
        if( doc.indexOf('error') > 0 ) {
            var json = new OpenLayers.Format.JSON();
            var error = json.read(doc);
            document.getElementById('message').innerHTML = error.error;
            document.getElementById('message').style.visibility = 'inherit';
        }
    }
    OpenLayers.Protocol.HTTP.prototype.handleRead.apply(this, arguments);
}

function htmlEscape(str) {
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
}

// This is used in tiles ajax request
function getParams() {
    return {
        'age': age,
        'changeset': changeset,
        'editor': editor,
        'user': username
    };
}

function setChangeset(ch) {
    document.getElementById('tchangeset').value = ch;
    changeset = ch;
    //document.getElementById('vwhere').style.visibility = 'inherit';
    updateParams();
}

function setUser(ch) {
    document.getElementById('tuser').value = ch;
    username = ch;
    //document.getElementById('vwhere').style.visibility = 'inherit';
    updateParams();
}

function setAge(ch) {
    age = ch;
    var sel = document.getElementById('tage');
    var s = -1;
    for (var i = 0; i < sel.options.length; i++)
        if (sel.options[i].value == age)
            s = i;
    if (s >= 0) {
        sel.selectedIndex = s;
    } else {
        sel.options[sel.options.length] = new Option(age, age);
        sel.selectedIndex = sel.options.length - 1;
    }
    updateParams();
}

function applyFilter() {
    setChangeset(document.getElementById('tchangeset').value);
    setUser(document.getElementById('tuser').value);
    updateParams();
}

function performSearch() {
    OpenLayers.Request.GET({
        url: 'https://nominatim.openstreetmap.org/search',
        params: {
            limit: 1,
            format: 'json',
            q: document.getElementById('tquery').value
        },
        callback: function(r) {
            var obj = new OpenLayers.Format.JSON().read(r.responseText)
            if (obj && obj[0] && obj[0].boundingbox) {
                var bbox = obj[0].boundingbox;
                var bounds = new OpenLayers.Bounds(bbox[2], bbox[0], bbox[3], bbox[1]).transform(new OpenLayers.Projection('EPSG:4326'), map.getProjectionObject());
                map.zoomToExtent(bounds);
            }
        }
    });
}

function updateParams() {
    if( vectorLayer ) {
        vectorLayer.protocol.options.params = getParams();
        vectorLayer.refresh({
            force: true,
            params: getParams()
        });
        permalink.updateLink();
    }
}

// Callback methods for drawing box for a RSS feed
function startDrawBBOX() {
    if( boxLayer.features.length > 0 ) {
        boxLayer.removeAllFeatures();
        document.getElementById('brss').value='Get RSS link';
        document.getElementById('rssurl').style.visibility='hidden';
    } else {
        boxControl.activate();
        document.getElementById('brss').value='Draw a box';
    }
}

function featureAdded(feature) {
    boxControl.deactivate();
    document.getElementById('brss').value='Clear RSS link';
    document.getElementById('rssurl').style.visibility='inherit';
    var user = document.getElementById('tuser').value;
    document.getElementById('rssurl').href=scripts + 'rss.php?bbox=' + feature.geometry.bounds.transform(projectTo, epsg4326).toBBOX() + (user ? '&user=' + user : '');
}

function zoomToTiles() {
    // zooming to tiles obviously calls for ajax request
    var request = OpenLayers.Request.GET({
        url: scripts + 'tiles.php?extent=1',
        params: getParams(),
        callback: function(req) {
            var json = new OpenLayers.Format.JSON();
            var bbox = json.read(req.responseText);
            if( bbox.length == 4 ) {
                var bounds = new OpenLayers.Bounds(bbox[0], bbox[1], bbox[2], bbox[3]);
                map.zoomToExtent(bounds.transform(epsg4326, projectTo));
            }
        }
    });
}

function saveLocation() {
    if( !cookieName ) return;
    var lonlat = map.getCenter().transform(map.getProjectionObject(), epsg4326);
    var zoom = map.getZoom();
    var expiry = new Date();
    expiry.setYear(expiry.getFullYear() + 10);
    document.cookie = cookieName + '=' + [lonlat.lon, lonlat.lat, zoom].join("|") + ';expires=' + expiry.toGMTString();
}

function restoreLocation() {
    if( !cookieName ) return;
    if( document.cookie.length > 0 ) {
        var start = document.cookie.indexOf(cookieName + '=');
        if( start >= 0 ) {
            start += cookieName.length + 1;
            var end = document.cookie.indexOf(';', start);
            if( end < 0 ) end = document.cookie.length;
            var location = document.cookie.substring(start, end).split('|');
            if( location.length == 3 ) {
                var lon = parseFloat(location[0]);
                var lat = parseFloat(location[1]);
                var zoom = parseFloat(location[2]);
                map.setCenter(new OpenLayers.LonLat(lon, lat).transform(epsg4326, map.getProjectionObject()), zoom);
            }
        }
    }
}

function populateAgeBox() {
    var sel = document.getElementById('tage');
    sel.options.length = 0;
    sel.options[sel.options.length] = new Option('6 hours', '6 hour');
    sel.options[sel.options.length] = new Option('12 hours', '12 hour');
    sel.options[sel.options.length] = new Option('day', 1);
    sel.options[sel.options.length] = new Option('3 days', 3);
    sel.options[sel.options.length] = new Option('week', 7);
    sel.options[sel.options.length] = new Option('month', '1 month');
    sel.options[sel.options.length] = new Option('half a year', '6 month');
    sel.options[sel.options.length] = new Option('eternity', 1000);
}

function round2(n) {
    return Math.round(n*1000)/1000;
}

// Simple JavaScript Templating
// John Resig - http://ejohn.org/ - MIT Licensed
(function(){
  var cache = {};

  this.tmpl = function tmpl(str, data){
    // Figure out if we're getting a template, or if we need to
    // load the template - and be sure to cache the result.
    var fn = !/\W/.test(str) ?
      cache[str] = cache[str] ||
        tmpl(document.getElementById(str).innerHTML) :

      // Generate a reusable function that will serve as a template
      // generator (and which will be cached).
      new Function("obj",
        "var p=[],print=function(){p.push.apply(p,arguments);};" +

        // Introduce the data as local variables using with(){}
        "with(obj){p.push('" +

        // Convert the template into pure JavaScript
        str
          .replace(/[\r\t\n]/g, " ")
          .split("<%").join("\t")
          .replace(/((^|%>)[^\t]*)'/g, "$1\r")
          .replace(/\t=(.*?)%>/g, "',$1,'")
          .split("\t").join("');")
          .split("%>").join("p.push('")
          .split("\r").join("\\'")
      + "');}return p.join('');");

    // Provide some basic currying to the user
    return data ? fn( data ) : fn;
  };
})();
