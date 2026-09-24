.pragma library

var DEG_TO_RAD = Math.PI / 180;
var RAD_TO_DEG = 180 / Math.PI;

function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value));
}

function normalizeLongitude(value) {
    var result = value % 360;
    if (result > 180)
        result -= 360;
    if (result < -180)
        result += 360;
    return result;
}

function nearestAngle(current, target) {
    return current + normalizeLongitude(target - current);
}

function geoVector(latitude, longitude, radius) {
    var lat = latitude * DEG_TO_RAD;
    var lon = longitude * DEG_TO_RAD;
    var cosLat = Math.cos(lat);
    return Qt.vector3d(
        radius * cosLat * Math.sin(lon),
        radius * Math.sin(lat),
        radius * cosLat * Math.cos(lon)
    );
}

function solarPosition(date) {
    var julianDate = date.getTime() / 86400000 + 2440587.5;
    var days = julianDate - 2451545.0;
    var meanLongitude = normalizeLongitude(280.460 + 0.9856474 * days);
    var meanAnomaly = normalizeLongitude(357.528 + 0.9856003 * days) * DEG_TO_RAD;
    var eclipticLongitude = (meanLongitude + 1.915 * Math.sin(meanAnomaly) + 0.020 * Math.sin(2 * meanAnomaly)) * DEG_TO_RAD;
    var obliquity = (23.439 - 0.0000004 * days) * DEG_TO_RAD;
    var rightAscension = Math.atan2(Math.cos(obliquity) * Math.sin(eclipticLongitude), Math.cos(eclipticLongitude));
    var declination = Math.asin(Math.sin(obliquity) * Math.sin(eclipticLongitude));
    var greenwichSidereal = normalizeLongitude(280.46061837 + 360.98564736629 * days);
    var subsolarLongitude = normalizeLongitude(rightAscension * RAD_TO_DEG - greenwichSidereal);
    return {
        latitude: declination * RAD_TO_DEG,
        longitude: subsolarLongitude
    };
}

function rectanglesOverlap(left, right, padding) {
    return left.x < right.x + right.width + padding
        && left.x + left.width + padding > right.x
        && left.y < right.y + right.height + padding
        && left.y + left.height + padding > right.y;
}
