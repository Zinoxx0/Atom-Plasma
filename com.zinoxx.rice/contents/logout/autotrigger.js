.pragma library
// The greeter shows one view per screen. A key pressed on any of them stops every view's
// countdown, so this lives in a shared library rather than in each view.

var stops = [];

function onStop(callback) { stops.push(callback); }

function stopAll() {
    stops.forEach(function (stop) { if (stop) stop(); });
}
