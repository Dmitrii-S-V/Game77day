
function appExit() {
    btapp.showview('torrents');
    return false;
}

function getPlus() {
    btapp.showview('plus');
    return false;
}

function tryAnotherPlayer() {
    btapp.showview('chooseplayer');
    return false;
}

function hideBar() {
    var bar = document.getElementById('bar');
    bar.style.display = 'none';

    var player = document.getElementById('wmplayer');
    player.style.marginBottom = "0px";
    return false;
}


function playFile(file) {
	var player = document.getElementById('WMPEmbed');
	if(player) {
		player.FileName = file;
	}
}

function gup( varname ) {
    varname = varname.replace(/[\[]/,"\\\[").replace(/[\]]/,"\\\]");
    var regexS = "[\\?&]"+varname+"=([^&#]*)";
    var regex = new RegExp( regexS );
    var results = regex.exec( window.location.href );
    if( results == null ) return ""; else return results[1];
}

window.onload = function() {
	// hide the bottom bar if btapp.showview does not exist
	if ( btapp.showview == undefined )
		hideBar();

	var file = gup('file');
	playFile(file);
};

