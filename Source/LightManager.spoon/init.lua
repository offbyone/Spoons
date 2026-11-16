--- === LightManager ===
---
--- Controls Elgato Key Lights and WLED devices.
---
--- Download: [https://github.com/offbyone/Spoons](https://github.com/offbyone/Spoons)

local obj = {}
obj.__index = obj

obj.name = "LightManager"
obj.version = "1.0"
obj.author = "Chris Rose <offline@offby1.net>"
obj.homepage = "https://github.com/offbyone/Spoons"
obj.license = "MIT - https://opensource.org/licenses/MIT"

obj.logger = hs.logger.new("LightManager", "info")

--- LightManager.lights
--- Variable
--- Table of Elgato Key Light and WLED device configurations.
obj.lights = {}

--- LightManager.ELGATO_PORT
--- Variable
--- Port number for the Elgato Key Light API.
obj.ELGATO_PORT = 9123

--- LightManager.HTTP_TIMEOUT
--- Variable
--- HTTP request timeout in seconds.
obj.HTTP_TIMEOUT = 3

local wledNameCache = {}

local function fetchWLEDName(ip, callback)
    local url = string.format("http://%s/json/info", ip)

    hs.http.asyncGet(url, nil, function(code, body, _)
        if code >= 200 and code < 300 then
            local success, data = pcall(function()
                return hs.json.decode(body)
            end)

            if success and data and data.name then
                wledNameCache[ip] = data.name
                obj.logger.d(string.format("Discovered WLED name for %s: %s", ip, data.name))
                if callback then callback(data.name) end
            else
                obj.logger.d(string.format("Could not parse name from WLED %s", ip))
                if callback then callback(nil) end
            end
        else
            obj.logger.d(string.format("Could not fetch WLED info for %s (code: %d)", ip, code))
            if callback then callback(nil) end
        end
    end)
end

local function getDisplayName(light)
    if light.name and light.name ~= "" then
        return light.name
    end

    if light.type == "wled" and light.ip then
        local cached = wledNameCache[light.ip]
        if cached then
            return cached
        end
        fetchWLEDName(light.ip, nil)
    end

    return light.ip or "unknown"
end

local function kelvinToMireds(kelvin)
    local mireds = math.floor(1000000 / kelvin)
    return math.max(143, math.min(344, mireds))
end

local function setElgatoLight(light, on)
    if not light.ip then
        obj.logger.w("Elgato light missing IP address")
        return
    end

    local displayName = getDisplayName(light)
    local url = string.format("http://%s:%d/elgato/lights", light.ip, obj.ELGATO_PORT)
    local payload

    local success, result = pcall(function()
        if on then
            payload = hs.json.encode({
                lights = {{
                    on = 1,
                    brightness = light.brightness or 50,
                    temperature = kelvinToMireds(light.temperature or 4500),
                }},
            })
        else
            payload = hs.json.encode({ lights = {{ on = 0 }} })
        end
    end)

    if not success then
        obj.logger.w(string.format("Elgato Light %s: failed to encode payload - %s", displayName, result))
        return
    end

    hs.http.asyncPut(url, payload, { ["Content-Type"] = "application/json" }, function(code, _, _)
        if code >= 200 and code < 300 then
            if on then
                obj.logger.i(string.format("Elgato Light %s: ON (brightness=%d%%, temp=%dK)",
                    displayName, light.brightness or 50, light.temperature or 4500))
            else
                obj.logger.i(string.format("Elgato Light %s: OFF", displayName))
            end
        elseif code == 0 then
            obj.logger.d(string.format("Elgato Light %s: unreachable (not on network)", displayName))
        else
            obj.logger.w(string.format("Elgato Light %s: failed with code %d", displayName, code))
        end
    end)
end

local function setWLEDDevice(device, on)
    if not device.ip then
        obj.logger.w("WLED device missing IP address")
        return
    end

    local displayName = getDisplayName(device)
    local url = string.format("http://%s/json/state", device.ip)
    local payload

    local success, result = pcall(function()
        if on then
            if device.camera_on_preset then
                payload = hs.json.encode({ on = true, ps = device.camera_on_preset })
            else
                payload = hs.json.encode({ on = true, bri = device.brightness or 128 })
            end
        elseif device.camera_off_preset then
            payload = hs.json.encode({ on = true, ps = device.camera_off_preset })
        else
            payload = hs.json.encode({ on = false })
        end
    end)

    if not success then
        obj.logger.w(string.format("WLED %s: failed to encode payload - %s", displayName, result))
        return
    end

    hs.http.asyncPost(url, payload, { ["Content-Type"] = "application/json" }, function(code, _, _)
        if code >= 200 and code < 300 then
            if on then
                obj.logger.i(string.format("WLED %s: ON (brightness=%d)", displayName, device.brightness or 128))
            else
                obj.logger.i(string.format("WLED %s: OFF", displayName))
            end
        elseif code == 0 then
            obj.logger.d(string.format("WLED %s: unreachable (not on network)", displayName))
        else
            obj.logger.w(string.format("WLED %s: failed with code %d", displayName, code))
        end
    end)
end

local function setLight(light, on)
    local success, dispatched = pcall(function()
        if type(light) ~= "table" then
            obj.logger.w(string.format("Light configuration must be a table, got %s", type(light)))
            return false
        end
        if not light.ip then
            obj.logger.w("Light configuration missing IP address")
            return false
        end
        if light.type == "wled" then
            setWLEDDevice(light, on)
        elseif light.type == "elgato" then
            setElgatoLight(light, on)
        else
            obj.logger.w(string.format("Unknown light type '%s' for device %s", light.type or "nil", light.ip))
            return false
        end
        return true
    end)

    if not success then
        obj.logger.w(string.format("Error controlling light: %s", tostring(dispatched)))
        return false
    end
    return dispatched
end

local function setAllLights(on)
    local state = on and "ON" or "OFF"
    obj.logger.i(string.format("Setting all lights %s", state))

    for index, light in ipairs(obj.lights) do
        local success, err = pcall(function()
            if setLight(light, on) then
                local displayName = getDisplayName(light)
                hs.notify.new({
                    title = "LightManager",
                    informativeText = string.format("Set light %s to %s", displayName, state),
                    autoWithdraw = true,
                    hasActionButton = false,
                }):send()
            end
        end)

        if not success then
            obj.logger.w(string.format("Failed to control light #%d: %s", index, tostring(err)))
        end
    end
end

--- LightManager:start()
--- Method
--- Prefetch WLED device names and log configured lights.
function obj:start()
    self.logger.i("LightManager starting")

    local fetchCount = 0
    for _, light in ipairs(self.lights) do
        if light.type == "wled" and light.ip and (not light.name or light.name == "") and not wledNameCache[light.ip] then
            fetchCount = fetchCount + 1
            fetchWLEDName(light.ip, nil)
        end
    end

    local function logConfiguration()
        for _, light in ipairs(self.lights) do
            local displayName = getDisplayName(light)
            if light.type == "elgato" then
                self.logger.i(string.format("  - Elgato %s (brightness=%d%%, temp=%dK)",
                    displayName, light.brightness or 50, light.temperature or 4500))
            elseif light.type == "wled" then
                self.logger.i(string.format("  - WLED %s (brightness=%d)", displayName, light.brightness or 128))
            else
                self.logger.w(string.format("  - Unknown type '%s' for %s", light.type or "nil", displayName))
            end
        end
    end

    if fetchCount > 0 then
        hs.timer.doAfter(0.5, logConfiguration)
    else
        logConfiguration()
    end

    self.logger.i("LightManager ready")
    return self
end

--- LightManager:setState(state)
--- Method
--- Set all configured lights to `"on"` or `"off"`.
function obj:setState(state)
    assert(state == "on" or state == "off", "state must be 'on' or 'off'")
    setAllLights(state == "on")
    return self
end

--- LightManager:lightsOn()
--- Method
--- Turn all configured lights on.
function obj:lightsOn()
    return self:setState("on")
end

--- LightManager:lightsOff()
--- Method
--- Turn all configured lights off.
function obj:lightsOff()
    return self:setState("off")
end

--- LightManager:status()
--- Method
--- Print configured light status.
function obj:status()
    print("=== LightManager Status ===")
    print(string.format("Lights/devices configured: %d", #self.lights))
    for _, light in ipairs(self.lights) do
        local displayName = getDisplayName(light)
        if light.type == "elgato" then
            print(string.format("  - Elgato %s (brightness=%d%%, temp=%dK)",
                displayName, light.brightness or 50, light.temperature or 4500))
        elseif light.type == "wled" then
            print(string.format("  - WLED %s (brightness=%d)", displayName, light.brightness or 128))
        else
            print(string.format("  - Unknown %s", displayName))
        end
    end
    return self
end

return obj
