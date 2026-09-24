pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: root

    readonly property int schemaVersion: 1
    readonly property string backendPath: Caching.serpantinumDir + "/bin/serpantinum-world-clock-backend"
    readonly property var fallbackCities: [
        { place: "London", label: "London", timezone: "Europe/London", latitude: 51.5074, longitude: -0.1278 },
        { place: "New York", label: "New York", timezone: "America/New_York", latitude: 40.7128, longitude: -74.0060 },
        { place: "Tokyo", label: "Tokyo", timezone: "Asia/Tokyo", latitude: 35.6762, longitude: 139.6503 },
        { place: "Sydney", label: "Sydney", timezone: "Australia/Sydney", latitude: -33.8688, longitude: 151.2093 }
    ]

    property var settings: ({
        version: 1,
        timeFormat: "bar",
        onlineSearch: true,
        globe: { autoRotate: true, rotationSpeed: 2.5 },
        cities: []
    })
    readonly property var cities: settings && settings.cities ? settings.cities : []
    readonly property var globe: settings && settings.globe ? settings.globe : ({ autoRotate: true, rotationSpeed: 2.5 })

    property var snapshot: ({ clocks: [], errors: [] })
    readonly property var clocks: snapshot && snapshot.clocks ? snapshot.clocks : []
    readonly property var snapshotErrors: snapshot && snapshot.errors ? snapshot.errors : []
    property bool snapshotBusy: false
    property bool snapshotQueued: false
    property bool backendAvailable: true
    property string backendError: ""

    property bool panelActive: false
    property bool settingsActive: false
    readonly property bool hasActiveConsumer: panelActive || settingsActive

    property string searchQuery: ""
    property var searchResults: []
    property bool searchBusy: false
    property string searchSource: "none"
    property bool searchOnlineAttempted: false
    property string searchError: ""
    property int searchGeneration: 0

    signal citySelectionRequested(string cityId)

    function clone(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function finiteNumber(value) {
        let number = Number(value);
        return isFinite(number) ? number : NaN;
    }

    function validCoordinatePair(latitude, longitude) {
        if ((latitude === undefined || latitude === null) && (longitude === undefined || longitude === null))
            return true;
        let lat = finiteNumber(latitude);
        let lon = finiteNumber(longitude);
        return !isNaN(lat) && !isNaN(lon) && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
    }

    function validTimezone(value) {
        if (typeof value !== "string" || value.length === 0 || value.length > 80)
            return false;
        if (value === "UTC" || value === "GMT")
            return true;
        return /^[A-Za-z0-9._+-]+(?:\/[A-Za-z0-9._+-]+)+$/.test(value);
    }

    function slug(value) {
        let output = String(value || "city").toLowerCase().replace(/[^a-z0-9]+/g, "-");
        output = output.replace(/^-+|-+$/g, "");
        return output.length > 0 ? output : "city";
    }

    function uniqueId(base, used) {
        let candidate = slug(base);
        let suffix = 2;
        while (used[candidate]) {
            candidate = slug(base) + "-" + suffix;
            suffix += 1;
        }
        used[candidate] = true;
        return candidate;
    }

    function normalizeCity(input, used) {
        if (!input || typeof input !== "object")
            return null;
        let place = String(input.place !== undefined ? input.place : (input.name !== undefined ? input.name : input.city || "")).trim();
        let timezone = String(input.timezone !== undefined ? input.timezone : (input.zone !== undefined ? input.zone : input.tz || "")).trim();
        if (place.length === 0 || place.length > 120 || !validTimezone(timezone))
            return null;
        let latitude = input.latitude !== undefined ? input.latitude : input.lat;
        let longitude = input.longitude !== undefined ? input.longitude : (input.lon !== undefined ? input.lon : input.lng);
        if (!validCoordinatePair(latitude, longitude))
            return null;

        let city = clone(input);
        city.id = uniqueId(input.id || timezone + "-" + place, used);
        city.place = place;
        city.label = String(input.label || place).trim().slice(0, 120) || place;
        city.timezone = timezone;
        if (latitude === undefined || latitude === null) {
            delete city.latitude;
            delete city.longitude;
        } else {
            city.latitude = finiteNumber(latitude);
            city.longitude = finiteNumber(longitude);
        }
        delete city.name;
        delete city.city;
        delete city.zone;
        delete city.tz;
        delete city.lat;
        delete city.lon;
        delete city.lng;
        return city;
    }

    function locationSeed() {
        let general = Config.getSetting("general", {});
        let location = general && general.location ? general.location : null;
        if (!location)
            return null;
        let city = {
            id: "home-" + slug(location.city || location.timezone),
            place: location.city || "Home",
            label: location.city || "Home",
            timezone: location.timezone,
            latitude: location.latitude,
            longitude: location.longitude
        };
        return normalizeCity(city, {});
    }

    function seededCities() {
        let used = {};
        let result = [];
        let seenZones = {};
        let home = locationSeed();
        if (home) {
            used[home.id] = true;
            seenZones[home.timezone] = true;
            result.push(home);
        } else {
            let utc = normalizeCity({
                id: "utc",
                place: "UTC",
                label: "UTC",
                timezone: "UTC",
                latitude: 51.4779,
                longitude: 0
            }, used);
            result.push(utc);
            seenZones.UTC = true;
        }
        for (let index = 0; index < fallbackCities.length; index++) {
            if (seenZones[fallbackCities[index].timezone])
                continue;
            let city = normalizeCity(fallbackCities[index], used);
            if (city) {
                result.push(city);
                seenZones[city.timezone] = true;
            }
        }
        return result;
    }

    function normalize(raw, settingExists) {
        let source = raw && typeof raw === "object" && !Array.isArray(raw) ? clone(raw) : {};
        let normalized = clone(source);
        normalized.version = schemaVersion;

        let timeFormat = source.timeFormat;
        if (timeFormat !== "bar" && timeFormat !== "12h" && timeFormat !== "24h") {
            if (typeof source.hour12 === "boolean")
                timeFormat = source.hour12 ? "12h" : "24h";
            else
                timeFormat = "bar";
        }
        normalized.timeFormat = timeFormat;
        normalized.onlineSearch = typeof source.onlineSearch === "boolean" ? source.onlineSearch : true;

        let oldGlobe = source.globe && typeof source.globe === "object" ? clone(source.globe) : {};
        let autoRotate = typeof oldGlobe.autoRotate === "boolean" ? oldGlobe.autoRotate : true;
        let rotationSpeed = finiteNumber(oldGlobe.rotationSpeed);
        if (isNaN(rotationSpeed) && oldGlobe.idleRotation !== undefined) {
            if (typeof oldGlobe.idleRotation === "boolean")
                autoRotate = oldGlobe.idleRotation;
            else {
                rotationSpeed = Math.abs(finiteNumber(oldGlobe.idleRotation));
                autoRotate = !isNaN(rotationSpeed) && rotationSpeed > 0;
            }
        }
        if (isNaN(rotationSpeed))
            rotationSpeed = 2.5;
        rotationSpeed = Math.max(0.25, Math.min(12, rotationSpeed));
        normalized.globe = oldGlobe;
        normalized.globe.autoRotate = autoRotate;
        normalized.globe.rotationSpeed = rotationSpeed;
        delete normalized.globe.idleRotation;

        let hadExplicitCities = source.hasOwnProperty("cities");
        let cityInput = hadExplicitCities && Array.isArray(source.cities)
            ? source.cities
            : (Array.isArray(source.regions) ? source.regions : null);
        let used = {};
        let normalizedCities = [];
        if (cityInput !== null) {
            for (let index = 0; index < cityInput.length; index++) {
                let city = normalizeCity(cityInput[index], used);
                if (city)
                    normalizedCities.push(city);
            }
        } else if (!settingExists) {
            normalizedCities = seededCities();
        }
        normalized.cities = normalizedCities;
        delete normalized.regions;
        delete normalized.hour12;
        return normalized;
    }

    function reloadSettings() {
        if (!Config.dataReady)
            return;
        let exists = Config.rawSettings && Config.rawSettings.hasOwnProperty("worldClock");
        let raw = Config.getSetting("worldClock", null);
        let normalized = normalize(raw, exists);
        settings = normalized;
        if (!exists || JSON.stringify(raw) !== JSON.stringify(normalized))
            Config.setSetting("worldClock", normalized);
        if (hasActiveConsumer)
            refreshSnapshot();
    }

    function persist(next) {
        let normalized = normalize(next, true);
        settings = normalized;
        Config.setSetting("worldClock", normalized);
        if (hasActiveConsumer)
            refreshSnapshot();
    }

    function setTimeFormat(value) {
        let next = clone(settings);
        next.timeFormat = value;
        persist(next);
    }

    function setOnlineSearch(value) {
        let next = clone(settings);
        next.onlineSearch = !!value;
        persist(next);
        if (!next.onlineSearch && searchProcess.running)
            searchProcess.running = false;
        if (searchQuery.trim().length > 0)
            scheduleSearch(searchQuery);
    }

    function setAutoRotate(value) {
        let next = clone(settings);
        next.globe = clone(next.globe || {});
        next.globe.autoRotate = !!value;
        persist(next);
    }

    function setRotationSpeed(value) {
        let next = clone(settings);
        next.globe = clone(next.globe || {});
        next.globe.rotationSpeed = Number(value);
        persist(next);
    }

    function addCity(result, personalLabel) {
        if (!result || !validTimezone(result.timezone) || !validCoordinatePair(result.latitude, result.longitude))
            return false;
        let next = clone(settings);
        let list = clone(cities);
        for (let index = 0; index < list.length; index++) {
            if (list[index].timezone === result.timezone && list[index].place === result.place)
                return false;
        }
        let used = {};
        for (let index = 0; index < list.length; index++)
            used[list[index].id] = true;
        let city = normalizeCity({
            id: result.timezone + "-" + result.place,
            place: result.place,
            label: String(personalLabel || "").trim() || result.place,
            timezone: result.timezone,
            latitude: result.latitude,
            longitude: result.longitude
        }, used);
        if (!city)
            return false;
        list.push(city);
        next.cities = list;
        persist(next);
        return true;
    }

    function removeCity(cityId) {
        let next = clone(settings);
        next.cities = cities.filter(function(city) { return city.id !== cityId; });
        persist(next);
    }

    function setCityLabel(cityId, label) {
        let next = clone(settings);
        next.cities = cities.map(function(city) {
            if (city.id !== cityId)
                return clone(city);
            let changed = clone(city);
            changed.label = String(label || "").trim().slice(0, 120) || changed.place;
            return changed;
        });
        persist(next);
    }

    function moveCity(cityId, delta) {
        let list = clone(cities);
        let from = -1;
        for (let index = 0; index < list.length; index++) {
            if (list[index].id === cityId) {
                from = index;
                break;
            }
        }
        let to = Math.max(0, Math.min(list.length - 1, from + delta));
        if (from < 0 || from === to)
            return;
        let moved = list.splice(from, 1)[0];
        list.splice(to, 0, moved);
        let next = clone(settings);
        next.cities = list;
        persist(next);
    }

    function resolvedTimeFormat() {
        if (settings.timeFormat === "12h" || settings.timeFormat === "24h")
            return settings.timeFormat;
        let bar = Config.getSetting("bar", {});
        let format = bar && bar.time && typeof bar.time.format === "string" ? bar.time.format : "HH:mm";
        return /h/.test(format) ? "12h" : "24h";
    }

    function clockForId(cityId) {
        for (let index = 0; index < clocks.length; index++) {
            if (clocks[index].id === cityId)
                return clocks[index];
        }
        return null;
    }

    function refreshSnapshot() {
        if (!hasActiveConsumer)
            return;
        if (cities.length === 0) {
            snapshot = ({ clocks: [], errors: [] });
            snapshotBusy = false;
            return;
        }
        if (!Caching.serpantinumDir) {
            backendAvailable = false;
            backendError = "World Clock backend path is unavailable";
            return;
        }
        if (snapshotProcess.running) {
            snapshotQueued = true;
            return;
        }
        snapshotQueued = false;
        snapshotBusy = true;
        backendError = "";
        snapshotProcess.command = [
            backendPath,
            "snapshot",
            "--cities-json",
            JSON.stringify(cities),
            "--format",
            resolvedTimeFormat()
        ];
        snapshotProcess.running = true;
    }

    function finishSnapshot(output) {
        try {
            let payload = JSON.parse(String(output).trim());
            if (payload.schema_version !== schemaVersion || !Array.isArray(payload.clocks) || !Array.isArray(payload.errors))
                throw new Error("unexpected snapshot schema");
            snapshot = payload;
            snapshotBusy = false;
            backendAvailable = true;
            backendError = "";
        } catch (error) {
            snapshotBusy = false;
            backendAvailable = false;
            backendError = "Invalid backend response: " + error;
        }
    }

    function scheduleSearch(query) {
        searchQuery = String(query || "").slice(0, 120);
        searchGeneration += 1;
        searchDebounce.stop();
        if (searchQuery.trim().length === 0) {
            if (searchProcess.running)
                searchProcess.running = false;
            searchResults = [];
            searchSource = "none";
            searchOnlineAttempted = false;
            searchError = "";
            searchBusy = false;
            return;
        }
        searchBusy = true;
        searchDebounce.start();
    }

    function launchSearch() {
        let query = searchQuery.trim();
        if (!settingsActive || query.length === 0) {
            searchBusy = false;
            return;
        }
        if (!Caching.serpantinumDir) {
            searchBusy = false;
            searchError = "World Clock backend path is unavailable";
            return;
        }
        if (searchProcess.running)
            searchProcess.running = false;
        searchError = "";
        searchProcess.command = [
            backendPath,
            "search",
            "--query",
            query,
            "--online",
            settings.onlineSearch ? "true" : "false",
            "--format",
            resolvedTimeFormat()
        ];
        searchProcess.running = true;
    }

    function finishSearch(output) {
        try {
            let payload = JSON.parse(String(output).trim());
            if (payload.schema_version !== schemaVersion || payload.query !== searchQuery.trim() || !Array.isArray(payload.results))
                return;
            searchResults = payload.results;
            searchSource = payload.source || "none";
            searchOnlineAttempted = !!payload.online_attempted;
            searchError = payload.error || "";
            searchBusy = false;
            backendAvailable = true;
        } catch (error) {
            searchBusy = false;
            searchError = "Invalid search response: " + error;
        }
    }

    function updateActivity() {
        alignTimer.stop();
        minuteTimer.stop();
        if (hasActiveConsumer) {
            refreshSnapshot();
            alignTimer.interval = Math.max(100, 60050 - (Date.now() % 60000));
            alignTimer.start();
        } else {
            searchDebounce.stop();
            if (searchProcess.running)
                searchProcess.running = false;
            if (snapshotProcess.running)
                snapshotProcess.running = false;
            searchBusy = false;
            snapshotBusy = false;
            snapshotQueued = false;
        }
    }

    onPanelActiveChanged: updateActivity()
    onSettingsActiveChanged: updateActivity()

    Connections {
        target: Config
        function onSettingsLoaded() { root.reloadSettings(); }
    }

    Process {
        id: snapshotProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.finishSnapshot(this.text)
        }
        stderr: StdioCollector { id: snapshotStderr }
        onExited: exitCode => {
            if (exitCode !== 0 && root.snapshotBusy) {
                root.snapshotBusy = false;
                root.backendAvailable = false;
                let stderrText = typeof snapshotStderr.text === "function" ? snapshotStderr.text() : snapshotStderr.text;
                root.backendError = String(stderrText || "World Clock backend failed").trim();
            }
            if (root.snapshotQueued)
                Qt.callLater(root.refreshSnapshot);
        }
    }

    Process {
        id: searchProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.finishSearch(this.text)
        }
        stderr: StdioCollector { id: searchStderr }
        onExited: exitCode => {
            if (exitCode !== 0 && root.searchBusy) {
                root.searchBusy = false;
                let stderrText = typeof searchStderr.text === "function" ? searchStderr.text() : searchStderr.text;
                root.searchError = String(stderrText || "City search failed").trim();
            }
        }
    }

    Timer {
        id: searchDebounce
        interval: 275
        repeat: false
        onTriggered: root.launchSearch()
    }

    Timer {
        id: alignTimer
        repeat: false
        onTriggered: {
            root.refreshSnapshot();
            if (root.hasActiveConsumer)
                minuteTimer.start();
        }
    }

    Timer {
        id: minuteTimer
        interval: 60000
        repeat: true
        onTriggered: root.refreshSnapshot()
    }

    Component.onCompleted: {
        if (Config.dataReady)
            reloadSettings();
    }
}
