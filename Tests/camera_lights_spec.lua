local support = dofile("Tests/test_support.lua")

local tests = {}

local function test(name, fn)
    table.insert(tests, { name = name, fn = fn })
end

local function loadCameraLights(state)
    return state:loadSpoon("Source/CameraLights.spoon/init.lua")
end

test("exposes only the camera callback boundary", function()
    local state = support.newEnvironment()
    local cameraLights = loadCameraLights(state)

    support.assertTrue(type(cameraLights.CameraFilters) == "table")
    support.assertEqual(cameraLights.lights, nil)
    support.assertEqual(cameraLights.ELGATO_PORT, nil)
    support.assertEqual(cameraLights.HTTP_TIMEOUT, nil)
    support.assertEqual(cameraLights.lightsOn, nil)
    support.assertEqual(cameraLights.lightsOff, nil)
end)

test("start emits the initial idle state once", function()
    local state = support.newEnvironment()
    state:newCamera("camera-1", "FaceTime HD", false)
    local cameraLights = loadCameraLights(state)
    local states = {}
    cameraLights.callback = function(value) table.insert(states, value) end

    support.assertEqual(cameraLights:start(), cameraLights)
    support.assertTableEqual(states, { "off" })
end)

test("start emits the initial active state once", function()
    local state = support.newEnvironment()
    state:newCamera("camera-1", "FaceTime HD", true)
    local cameraLights = loadCameraLights(state)
    local states = {}
    cameraLights.callback = function(value) table.insert(states, value) end

    cameraLights:start()
    support.assertTableEqual(states, { "on" })
end)

test("emits only aggregate camera state transitions", function()
    local state = support.newEnvironment()
    local first = state:newCamera("camera-1", "FaceTime HD", false)
    local second = state:newCamera("camera-2", "External Camera", false)
    local cameraLights = loadCameraLights(state)
    local states = {}
    cameraLights.callback = function(value) table.insert(states, value) end
    cameraLights:start()

    first:setInUse(true)
    first.propertyWatcherCallback(first)
    second:setInUse(true)
    second.propertyWatcherCallback(second)
    first:setInUse(false)
    first.propertyWatcherCallback(first)
    second:setInUse(false)
    second.propertyWatcherCallback(second)

    support.assertTableEqual(states, { "off", "on", "off" })
end)

test("filtered cameras do not affect aggregate state", function()
    local state = support.newEnvironment()
    local allowed = state:newCamera("camera-1", "Allowed Camera", false)
    local filtered = state:newCamera("camera-2", "Filtered Camera", false)
    local cameraLights = loadCameraLights(state)
    local states = {}
    cameraLights.allowedCameras = function(camera) return camera:name() == "Allowed Camera" end
    cameraLights.callback = function(value) table.insert(states, value) end
    cameraLights:start()

    filtered:setInUse(true)
    filtered.propertyWatcherCallback(filtered)
    allowed:setInUse(true)
    allowed.propertyWatcherCallback(allowed)

    support.assertTableEqual(states, { "off", "on" })
end)

test("callback errors do not stop later transitions", function()
    local state = support.newEnvironment()
    local camera = state:newCamera("camera-1", "FaceTime HD", false)
    local cameraLights = loadCameraLights(state)
    local calls = 0
    cameraLights.callback = function()
        calls = calls + 1
        if calls == 1 then error("expected callback failure") end
    end

    support.assertEqual(cameraLights:start(), cameraLights)
    camera:setInUse(true)
    camera.propertyWatcherCallback(camera)
    support.assertEqual(calls, 2)
end)

test("stop tears down camera sleep and timer watchers", function()
    local state = support.newEnvironment()
    local camera = state:newCamera("camera-1", "FaceTime HD", false)
    local cameraLights = loadCameraLights(state)
    cameraLights:start()

    support.assertEqual(cameraLights:stop(), cameraLights)
    support.assertTrue(state.cameraWatcherStopped)
    support.assertTrue(camera.propertyWatcherStopped)
    support.assertTrue(state.sleepWatchers[1].stopped)
    support.assertTrue(state.repeatingTimers[1].stopped)
end)

local failures = 0
for _, item in ipairs(tests) do
    local ok, err = pcall(item.fn)
    if ok then
        print("ok - " .. item.name)
    else
        failures = failures + 1
        io.stderr:write("not ok - " .. item.name .. ": " .. tostring(err) .. "\n")
    end
end

if failures > 0 then
    error(string.format("%d CameraLights test(s) failed", failures))
end

print(string.format("%d CameraLights tests passed", #tests))
