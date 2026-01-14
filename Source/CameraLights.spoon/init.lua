--- === CameraLights ===
---
--- Monitors camera usage and controls lights (Elgato Key Lights or WLED devices)
--- When any camera turns on (video calls, etc.) -> lights turn on
--- When all cameras turn off -> lights turn off
---
--- Download: [https://github.com/offbyone/Spoons](https://github.com/offbyone/Spoons)

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "CameraLights"
obj.version = "1.0"
obj.author = "Chris Rose <offline@offby1.net>"
obj.homepage = "https://github.com/offbyone/Spoons"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Logger
obj.logger = hs.logger.new("CameraLights", "info")

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

--- CameraLights.lights
--- Variable
--- Table of light/device configurations. Each entry must have:
---   - type: "elgato" or "wled"
---   - ip: IP address
--- 
--- Elgato Key Light fields:
---   - brightness: 0-100 (default: 50)
---   - temperature: Kelvin 2900-7000 (default: 4500)
---
--- WLED device fields:
---   - brightness: 0-255 (default: 128)
---   - camera_on_preset: (optional) preset ID to use when camera turns on
---   - camera_off_preset: (optional) preset ID to use when camera turns off
---
--- Example:
--- ```lua
--- spoon.CameraLights.lights = {
---   { type = "elgato", ip = "192.168.1.100", brightness = 50, temperature = 4500 },
---   { type = "wled", ip = "192.168.1.151", brightness = 200 },
--- }
--- ```
obj.lights = {}

--- CameraLights.allowedCameras
--- Variable
--- Function or constant to filter which cameras trigger lights.
--- - If a function: called with camera object, should return true/false
--- - If nil/not set: all cameras are allowed (default)
---
--- Example:
--- ```lua
--- -- Allow only cameras matching a pattern
--- spoon.CameraLights.allowedCameras = function(camera)
---   return camera:name():match("FaceTime")
--- end
--- ```
obj.allowedCameras = nil

--- CameraLights.ELGATO_PORT
--- Variable
--- Port number for Elgato Key Light API (default: 9123)
obj.ELGATO_PORT = 9123

--- CameraLights.HTTP_TIMEOUT
--- Variable
--- HTTP request timeout in seconds (default: 3)
obj.HTTP_TIMEOUT = 3

--------------------------------------------------------------------------------
-- Helper constants for camera filtering
--------------------------------------------------------------------------------

--- CameraLights.CameraFilters
--- Variable
--- Convenience functions for camera filtering
obj.CameraFilters = {
    --- Allow all cameras (default behavior)
    all = nil,
    
    --- Create a filter that matches camera names against a pattern
    --- @param pattern string Lua pattern to match against camera name
    --- @return function Filter function
    namePattern = function(pattern)
        return function(camera)
            return camera:name():match(pattern) ~= nil
        end
    end,
    
    --- Create a filter that only allows cameras from a specific list of names
    --- @param names table List of camera names to allow
    --- @return function Filter function
    nameList = function(names)
        local nameSet = {}
        for _, name in ipairs(names) do
            nameSet[name] = true
        end
        return function(camera)
            return nameSet[camera:name()] == true
        end
    end,
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local cameraWatchers = {}  -- table of camera uid -> camera object
local anyCameraInUse = false

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Convert Kelvin to mireds (Elgato API uses mireds)
-- Valid range: 143 (7000K) to 344 (2900K)
local function kelvinToMireds(kelvin)
    local mireds = math.floor(1000000 / kelvin)
    return math.max(143, math.min(344, mireds))
end

-- Check if a camera is allowed based on the allowedCameras filter
local function isCameraAllowed(camera)
    if obj.allowedCameras == nil then
        return true
    end
    if type(obj.allowedCameras) == "function" then
        local success, result = pcall(obj.allowedCameras, camera)
        if not success then
            obj.logger.w(string.format("Error in allowedCameras filter: %s", result))
            return false
        end
        return result == true
    end
    obj.logger.w("allowedCameras must be a function or nil")
    return false
end

--------------------------------------------------------------------------------
-- Elgato Key Light Control
--------------------------------------------------------------------------------

-- Set a single Elgato Key Light on or off
local function setElgatoLight(light, on)
    if not light.ip then
        obj.logger.w("Elgato light missing IP address")
        return
    end
    
    local url = string.format("http://%s:%d/elgato/lights", light.ip, obj.ELGATO_PORT)
    local payload
    
    local success, result = pcall(function()
        if on then
            payload = hs.json.encode({
                lights = {{
                    on = 1,
                    brightness = light.brightness or 50,
                    temperature = kelvinToMireds(light.temperature or 4500)
                }}
            })
        else
            payload = hs.json.encode({
                lights = {{ on = 0 }}
            })
        end
    end)
    
    if not success then
        obj.logger.w(string.format("Elgato Light %s: failed to encode payload - %s", light.ip, result))
        return
    end

    local headers = { ["Content-Type"] = "application/json" }

    hs.http.asyncPut(url, payload, headers, function(code, body, respHeaders)
        if code >= 200 and code < 300 then
            if on then
                obj.logger.i(string.format("Elgato Light %s: ON (brightness=%d%%, temp=%dK)",
                    light.ip, light.brightness or 50, light.temperature or 4500))
            else
                obj.logger.i(string.format("Elgato Light %s: OFF", light.ip))
            end
        elseif code == 0 then
            obj.logger.d(string.format("Elgato Light %s: unreachable (not on network)", light.ip))
        else
            obj.logger.w(string.format("Elgato Light %s: failed with code %d", light.ip, code))
        end
    end)
end

--------------------------------------------------------------------------------
-- WLED Control
--------------------------------------------------------------------------------

-- Set a single WLED device on or off
local function setWLEDDevice(device, on)
    if not device.ip then
        obj.logger.w("WLED device missing IP address")
        return
    end
    
    local url = string.format("http://%s/json/state", device.ip)
    local payload

    local success, result = pcall(function()
        if on then
            if device.camera_on_preset then
                payload = hs.json.encode({
                    on = true,
                    ps = device.camera_on_preset
                })
            else
                payload = hs.json.encode({
                    on = true,
                    bri = device.brightness or 128
                })
            end
        else
            if device.camera_off_preset then
                payload = hs.json.encode({
                    on = true,
                    ps = device.camera_off_preset
                })
            else
                payload = hs.json.encode({
                    on = false
                })
            end
        end
    end)
    
    if not success then
        obj.logger.w(string.format("WLED %s: failed to encode payload - %s", device.ip, result))
        return
    end

    local headers = { ["Content-Type"] = "application/json" }

    hs.http.asyncPost(url, payload, headers, function(code, body, respHeaders)
        if code >= 200 and code < 300 then
            if on then
                obj.logger.i(string.format("WLED %s: ON (brightness=%d)", device.ip, device.brightness or 128))
            else
                obj.logger.i(string.format("WLED %s: OFF", device.ip))
            end
        elseif code == 0 then
            obj.logger.d(string.format("WLED %s: unreachable (not on network)", device.ip))
        else
            obj.logger.w(string.format("WLED %s: failed with code %d", device.ip, code))
        end
    end)
end

--------------------------------------------------------------------------------
-- Unified Light Control Interface
--------------------------------------------------------------------------------

-- Set a single light on or off (dispatches to correct controller based on type)
local function setLight(light, on)
    local success, err = pcall(function()
        if not light then
            obj.logger.w("Attempted to control nil light")
            return
        end
        
        if not light.ip then
            obj.logger.w("Light configuration missing IP address")
            return
        end
        
        if light.type == "wled" then
            setWLEDDevice(light, on)
        elseif light.type == "elgato" then
            setElgatoLight(light, on)
        else
            obj.logger.w(string.format("Unknown light type '%s' for device %s", light.type or "nil", light.ip))
        end
    end)
    
    if not success then
        obj.logger.w(string.format("Error controlling light: %s", tostring(err)))
    end
end

-- Set all lights on or off
local function setAllLights(on)
    local state = on and "ON" or "OFF"
    obj.logger.i(string.format("Setting all lights %s", state))

    for i, light in ipairs(obj.lights) do
        local success, err = pcall(function()
            setLight(light, on)
        end)
        
        if not success then
            obj.logger.w(string.format("Failed to control light #%d: %s", i, tostring(err)))
        end
    end
end

--------------------------------------------------------------------------------
-- Camera Monitoring
--------------------------------------------------------------------------------

-- Check if any allowed camera is currently in use
local function checkAnyCameraInUse()
    local cameras = hs.camera.allCameras()
    for _, camera in ipairs(cameras) do
        if isCameraAllowed(camera) and camera:isInUse() then
            return true
        end
    end
    return false
end

-- Handle camera state change
local function onCameraStateChange(camera, property, scope, element)
    -- Only respond to allowed cameras
    if not isCameraAllowed(camera) then
        obj.logger.d(string.format("Ignoring camera (not allowed): %s", camera:name()))
        return
    end
    
    local wasInUse = anyCameraInUse
    local nowInUse = checkAnyCameraInUse()

    if nowInUse and not wasInUse then
        obj.logger.i(string.format("Camera activated: %s", camera:name()))
        anyCameraInUse = true
        setAllLights(true)
    elseif not nowInUse and wasInUse then
        obj.logger.i(string.format("Camera deactivated: %s", camera:name()))
        anyCameraInUse = false
        setAllLights(false)
    end
end

-- Set up watcher for a single camera
local function watchCamera(camera)
    if cameraWatchers[camera:uid()] then
        return
    end

    camera:setPropertyWatcherCallback(onCameraStateChange)
    camera:startPropertyWatcher()
    cameraWatchers[camera:uid()] = camera
    
    local allowed = isCameraAllowed(camera) and "allowed" or "filtered"
    obj.logger.i(string.format("Watching camera: %s (%s)", camera:name(), allowed))
end

-- Stop watching a camera
local function unwatchCamera(camera)
    if cameraWatchers[camera:uid()] then
        camera:stopPropertyWatcher()
        cameraWatchers[camera:uid()] = nil
        obj.logger.i(string.format("Stopped watching camera: %s", camera:name()))
    end
end

-- Handle camera added/removed events
local function onCameraAddedOrRemoved(camera, event)
    if event == "Added" then
        obj.logger.i(string.format("Camera connected: %s", camera:name()))
        watchCamera(camera)
    elseif event == "Removed" then
        obj.logger.i(string.format("Camera disconnected: %s", camera:name()))
        unwatchCamera(camera)

        -- Check if we need to turn off lights
        if anyCameraInUse and not checkAnyCameraInUse() then
            anyCameraInUse = false
            setAllLights(false)
        end
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- CameraLights:start()
--- Method
--- Start monitoring cameras and controlling lights
---
--- Returns:
---  * The CameraLights object
function obj:start()
    self.logger.i("=================================================")
    self.logger.i("CameraLights starting")
    self.logger.i(string.format("Configured lights/devices: %d", #self.lights))
    
    for _, light in ipairs(self.lights) do
        if light.type == "elgato" then
            self.logger.i(string.format("  - Elgato %s (brightness=%d%%, temp=%dK)",
                light.ip, light.brightness or 50, light.temperature or 4500))
        elseif light.type == "wled" then
            self.logger.i(string.format("  - WLED %s (brightness=%d)", light.ip, light.brightness or 128))
        else
            self.logger.w(string.format("  - Unknown type '%s' for %s", light.type or "nil", light.ip))
        end
    end
    
    if self.allowedCameras ~= nil then
        self.logger.i("Camera filtering: enabled")
    else
        self.logger.i("Camera filtering: all cameras allowed")
    end
    
    self.logger.i("=================================================")

    -- Watch for camera add/remove events
    hs.camera.setWatcherCallback(onCameraAddedOrRemoved)
    hs.camera.startWatcher()

    -- Set up watchers for all existing cameras
    local cameras = hs.camera.allCameras()
    if #cameras == 0 then
        self.logger.i("No cameras detected")
    else
        for _, camera in ipairs(cameras) do
            watchCamera(camera)
        end
    end

    -- Check initial state
    anyCameraInUse = checkAnyCameraInUse()
    if anyCameraInUse then
        self.logger.i("Camera already in use - turning lights on")
        setAllLights(true)
    else
        self.logger.i("No cameras in use - lights remain off")
        setAllLights(false)
    end

    self.logger.i("CameraLights ready")
    
    return self
end

--- CameraLights:stop()
--- Method
--- Stop monitoring cameras
---
--- Returns:
---  * The CameraLights object
function obj:stop()
    self.logger.i("Stopping CameraLights")

    hs.camera.stopWatcher()

    for uid, camera in pairs(cameraWatchers) do
        camera:stopPropertyWatcher()
    end
    cameraWatchers = {}

    self.logger.i("CameraLights stopped")
    
    return self
end

--- CameraLights:lightsOn()
--- Method
--- Manually turn all lights on (bypasses camera state)
---
--- Returns:
---  * The CameraLights object
function obj:lightsOn()
    setAllLights(true)
    return self
end

--- CameraLights:lightsOff()
--- Method
--- Manually turn all lights off (bypasses camera state)
---
--- Returns:
---  * The CameraLights object
function obj:lightsOff()
    setAllLights(false)
    return self
end

--- CameraLights:status()
--- Method
--- Print current status to console
---
--- Returns:
---  * The CameraLights object
function obj:status()
    local cameras = hs.camera.allCameras()
    print("=== CameraLights Status ===")
    print(string.format("Cameras detected: %d", #cameras))
    for _, camera in ipairs(cameras) do
        local inUse = camera:isInUse() and "IN USE" or "idle"
        local allowed = isCameraAllowed(camera) and "allowed" or "filtered"
        print(string.format("  - %s: %s (%s)", camera:name(), inUse, allowed))
    end
    
    print(string.format("Lights/devices configured: %d", #self.lights))
    for _, light in ipairs(self.lights) do
        if light.type == "elgato" then
            print(string.format("  - Elgato %s (brightness=%d%%, temp=%dK)",
                light.ip, light.brightness or 50, light.temperature or 4500))
        elseif light.type == "wled" then
            print(string.format("  - WLED %s (brightness=%d)", light.ip, light.brightness or 128))
        else
            print(string.format("  - Unknown %s", light.ip))
        end
    end
    
    print(string.format("Any camera in use: %s", anyCameraInUse and "yes" or "no"))
    print(string.format("Camera filtering: %s", self.allowedCameras and "enabled" or "all allowed"))
    
    return self
end

return obj
