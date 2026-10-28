.pragma library
// WMO weather codes (Open-Meteo) -> a Material Symbols glyph (day, night) and a word

const TABLE = [
    [[0], "clear_day", "bedtime", "Clear"],
    [[1], "partly_cloudy_day", "partly_cloudy_night", "Mostly clear"],
    [[2], "partly_cloudy_day", "partly_cloudy_night", "Partly cloudy"],
    [[3], "cloud", "cloud", "Overcast"],
    [[45, 48], "foggy", "foggy", "Fog"],
    [[51, 53, 55, 56, 57], "rainy_light", "rainy_light", "Drizzle"],
    [[61, 63, 66, 80, 81], "rainy", "rainy", "Rain"],
    [[65, 67, 82], "rainy_heavy", "rainy_heavy", "Heavy rain"],
    [[71, 73, 75, 77, 85, 86], "weather_snowy", "weather_snowy", "Snow"],
    [[95, 96, 99], "thunderstorm", "thunderstorm", "Thunderstorm"],
];

function find(code) {
    for (const row of TABLE)
        if (row[0].indexOf(code) >= 0) return row;
    return TABLE[3];
}
function icon(code, day) { const r = find(code); return day ? r[1] : r[2] }
function word(code) { return find(code)[3] }
