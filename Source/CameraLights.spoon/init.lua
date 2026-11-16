--- === CameraLights ===
---
--- Monitors camera usage and reports aggregate state changes through a callback.
--- The callback receives "on" when any allowed camera is active and "off" when all are idle.
---
--- Download: [https://github.com/offbyone/Spoons](https://github.com/offbyone/Spoons)

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "CameraLights"
obj.version = "1.1"
obj.author = "Chris Rose <offline@offby1.net>"
obj.homepage = "https://github.com/offbyone/Spoons"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Logger
obj.logger = hs.logger.new("CameraLights", "info")

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

--- CameraLights.callback
--- Variable
--- Optional callback invoked when aggregate camera usage changes.
--- The function is called with a single argument: "on" or "off".
---
--- Example:
--- ```lua
--- spoon.CameraLights.callback = function(state)
---   if state == "on" then
---     spoon.HomeAssistant:setState("input_boolean.on_air", "on")
---   else
---     spoon.HomeAssistant:setState("input_boolean.on_air", "off")
---   end
--- end
--- ```
obj.callback = nil


--- CameraLights.allowedCameras
--- Variable
--- Function or constant to filter which cameras affect aggregate state.
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

--------------------------------------------------------------------------------
-- Helper constants for camera filtering
--------------------------------------------------------------------------------

-- Safely get camera name, returning "unknown" if the camera object is stale or nil
-- Defined early so CameraFilters closures can reference it.
local function safeCameraName(camera)
    if not camera then return "unknown" end
    local ok, name = pcall(function() return camera:name() end)
    return (ok and name) or "unknown"
end

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
            return (safeCameraName(camera)):match(pattern) ~= nil
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
            return nameSet[safeCameraName(camera)] == true
        end
    end,
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local cameraWatchers = {}  -- table of camera uid -> camera object
local anyCameraInUse = false
local sleepWatcher = nil   -- hs.caffeinate.watcher for sleep/wake recovery
local healthCheckTimer = nil  -- periodic timer to catch missed camera events

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

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

-- Notify the configured callback of aggregate camera state.
local function notifyCameraState(on)
    local state = on and "on" or "off"
    obj.logger.i("Invoking camera state callback: " .. state)
    if obj.callback and type(obj.callback) == "function" then
        pcall(function() obj.callback(state) end)
    end
end

--------------------------------------------------------------------------------
-- Camera Monitoring
--------------------------------------------------------------------------------

-- Check if any allowed camera is currently in use
local function checkAnyCameraInUse()
    local cameras = hs.camera.allCameras()
    for _, camera in ipairs(cameras) do
        if isCameraAllowed(camera) then
            local ok, inUse = pcall(function() return camera:isInUse() end)
            if ok and inUse then
                return true
            end
        end
    end
    return false
end

-- Handle camera state change
local function onCameraStateChange(camera, property, scope, element)
    -- Only respond to allowed cameras
    if not isCameraAllowed(camera) then
        obj.logger.d(string.format("Ignoring camera (not allowed): %s", safeCameraName(camera)))
        return
    end
    
    local wasInUse = anyCameraInUse
    local nowInUse = checkAnyCameraInUse()

    if nowInUse and not wasInUse then
        obj.logger.i(string.format("Camera activated: %s", safeCameraName(camera)))
        anyCameraInUse = true
        notifyCameraState(true)
    elseif not nowInUse and wasInUse then
        obj.logger.i(string.format("Camera deactivated: %s", safeCameraName(camera)))
        anyCameraInUse = false
        notifyCameraState(false)
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
    obj.logger.i(string.format("Watching camera: %s (%s)", safeCameraName(camera), allowed))
end

-- Stop watching a camera
local function unwatchCamera(camera)
    if cameraWatchers[camera:uid()] then
        camera:stopPropertyWatcher()
        cameraWatchers[camera:uid()] = nil
        obj.logger.i(string.format("Stopped watching camera: %s", safeCameraName(camera)))
    end
end

-- Handle camera added/removed events
local function onCameraAddedOrRemoved(camera, event)
    if event == "Added" then
        obj.logger.i(string.format("Camera connected: %s", safeCameraName(camera)))
        watchCamera(camera)
    elseif event == "Removed" then
        obj.logger.i(string.format("Camera disconnected: %s", safeCameraName(camera)))
        unwatchCamera(camera)

        -- Check whether aggregate camera state changed.
        if anyCameraInUse and not checkAnyCameraInUse() then
            anyCameraInUse = false
            notifyCameraState(false)
        end
    end
end

-- Tear down all camera watchers and rebuild from current hardware state.
-- Used on wake from sleep and by the periodic health check.
local function rebuildCameraWatchers()
    -- Stop all existing property watchers
    for uid, camera in pairs(cameraWatchers) do
        pcall(function() camera:stopPropertyWatcher() end)
    end
    cameraWatchers = {}

    -- Re-enumerate and watch all current cameras
    local cameras = hs.camera.allCameras()
    obj.logger.i(string.format("Rebuilding camera watchers (%d cameras found)", #cameras))
    for _, camera in ipairs(cameras) do
        watchCamera(camera)
    end

    -- Sync aggregate camera state with reality.
    local wasInUse = anyCameraInUse
    anyCameraInUse = checkAnyCameraInUse()
    if anyCameraInUse and not wasInUse then
        obj.logger.i("Rebuild: a camera is now in use")
        notifyCameraState(true)
    elseif not anyCameraInUse and wasInUse then
        obj.logger.i("Rebuild: no cameras are in use")
        notifyCameraState(false)
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- CameraLights:start()
--- Method
--- Start monitoring cameras and reporting aggregate state changes
---
--- Returns:
---  * The CameraLights object
function obj:start()
    self.logger.i("=================================================")
    self.logger.i("CameraLights starting")
    if self.allowedCameras ~= nil then
        self.logger.i("Camera filtering: enabled")
    else
        self.logger.i("Camera filtering: all cameras allowed")
    end
    self.logger.i("=================================================")

    -- Watch for camera add/remove events
    hs.camera.setWatcherCallback(onCameraAddedOrRemoved)
    hs.camera.startWatcher()

    -- Establish current state before rebuilding so startup emits exactly once.
    anyCameraInUse = checkAnyCameraInUse()
    rebuildCameraWatchers()
    notifyCameraState(anyCameraInUse)

    -- Watch for sleep/wake to rebuild camera watchers.
    -- After wake, camera hardware may re-enumerate with new CMIODeviceIDs,
    -- silently invalidating existing property watchers.
    sleepWatcher = hs.caffeinate.watcher.new(function(event)
        if event == hs.caffeinate.watcher.systemDidWake then
            self.logger.i("System woke from sleep - rebuilding camera watchers in 3s")
            hs.timer.doAfter(3, function()
                rebuildCameraWatchers()
            end)
        end
    end)
    sleepWatcher:start()

    -- Periodic health check to catch any missed add/remove notifications.
    -- Verifies the watched camera set matches reality and syncs aggregate state.
    healthCheckTimer = hs.timer.doEvery(60, function()
        local currentCameras = hs.camera.allCameras()
        local currentUIDs = {}
        for _, camera in ipairs(currentCameras) do
            local ok, uid = pcall(function() return camera:uid() end)
            if ok and uid then
                currentUIDs[uid] = camera
            end
        end

        -- Add watchers for any cameras we're not tracking
        for uid, camera in pairs(currentUIDs) do
            if not cameraWatchers[uid] then
                self.logger.i(string.format("Health check: found unwatched camera %s", safeCameraName(camera)))
                watchCamera(camera)
            end
        end

        -- Remove stale entries for cameras that are gone
        for uid, _ in pairs(cameraWatchers) do
            if not currentUIDs[uid] then
                self.logger.i(string.format("Health check: removing stale watcher for %s", uid))
                pcall(function() cameraWatchers[uid]:stopPropertyWatcher() end)
                cameraWatchers[uid] = nil
            end
        end

        -- Sync aggregate state with reality.
        local wasInUse = anyCameraInUse
        anyCameraInUse = checkAnyCameraInUse()
        if anyCameraInUse ~= wasInUse then
            self.logger.i(string.format("Health check: camera state changed to %s",
                anyCameraInUse and "in use" or "idle"))
            notifyCameraState(anyCameraInUse)
        end
    end)

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

    -- Stop sleep/wake watcher
    if sleepWatcher then
        sleepWatcher:stop()
        sleepWatcher = nil
    end

    -- Stop health check timer
    if healthCheckTimer then
        healthCheckTimer:stop()
        healthCheckTimer = nil
    end

    -- Stop camera add/remove watcher
    hs.camera.stopWatcher()

    -- Stop all per-camera property watchers
    for uid, camera in pairs(cameraWatchers) do
        pcall(function() camera:stopPropertyWatcher() end)
    end
    cameraWatchers = {}

    self.logger.i("CameraLights stopped")
    
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
        local okInUse, inUse = pcall(function() return camera:isInUse() end)
        local inUseStr = (okInUse and inUse) and "IN USE" or "idle"
        local allowed = isCameraAllowed(camera) and "allowed" or "filtered"
        print(string.format("  - %s: %s (%s)", safeCameraName(camera), inUseStr, allowed))
    end

    print(string.format("Any camera in use: %s", anyCameraInUse and "yes" or "no"))
    print(string.format("Camera filtering: %s", self.allowedCameras and "enabled" or "all allowed"))
    
    return self
end

return obj
