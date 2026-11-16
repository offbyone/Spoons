local support = dofile("Tests/test_support.lua")

local tests = {}

local function test(name, fn)
    table.insert(tests, { name = name, fn = fn })
end

local function loadManager()
    local state = support.newEnvironment()
    local manager = state:loadSpoon("Source/LightManager.spoon/init.lua")
    return manager, state
end

test("exposes LightManager configuration defaults", function()
    local manager = loadManager()
    support.assertEqual(manager.name, "LightManager")
    support.assertEqual(#manager.lights, 0)
    support.assertEqual(manager.ELGATO_PORT, 9123)
    support.assertEqual(manager.HTTP_TIMEOUT, 3)
end)

test("setState sends Elgato and WLED on requests", function()
    local manager, state = loadManager()
    manager.lights = {
        { type = "elgato", ip = "10.0.0.1", brightness = 60, temperature = 4500 },
        { type = "wled", ip = "10.0.0.2", name = "Strip", brightness = 200 },
        { type = "wled", ip = "10.0.0.3", name = "Preset", camera_on_preset = 7 },
    }

    support.assertEqual(manager:setState("on"), manager)
    support.assertEqual(#state.requests, 3)
    support.assertTableEqual(state.requests[1], {
        method = "PUT",
        url = "http://10.0.0.1:9123/elgato/lights",
        payload = { lights = {{ on = 1, brightness = 60, temperature = 222 }} },
        headers = { ["Content-Type"] = "application/json" },
    })
    support.assertTableEqual(state.requests[2], {
        method = "POST",
        url = "http://10.0.0.2/json/state",
        payload = { on = true, bri = 200 },
        headers = { ["Content-Type"] = "application/json" },
    })
    support.assertTableEqual(state.requests[3], {
        method = "POST",
        url = "http://10.0.0.3/json/state",
        payload = { on = true, ps = 7 },
        headers = { ["Content-Type"] = "application/json" },
    })
end)

test("setState sends Elgato and WLED off requests", function()
    local manager, state = loadManager()
    manager.lights = {
        { type = "elgato", ip = "10.0.0.1", name = "Key" },
        { type = "wled", ip = "10.0.0.2", name = "Strip" },
        { type = "wled", ip = "10.0.0.3", name = "Preset", camera_off_preset = 9 },
    }

    manager:setState("off")
    support.assertTableEqual(state.requests[1].payload, { lights = {{ on = 0 }} })
    support.assertTableEqual(state.requests[2].payload, { on = false })
    support.assertTableEqual(state.requests[3].payload, { on = true, ps = 9 })
end)

test("manual methods use the state control path", function()
    local manager, state = loadManager()
    manager.lights = {{ type = "elgato", ip = "10.0.0.1", name = "Key" }}

    support.assertEqual(manager:lightsOn(), manager)
    support.assertEqual(state.requests[1].payload.lights[1].on, 1)
    state:clearRequests()
    support.assertEqual(manager:lightsOff(), manager)
    support.assertEqual(state.requests[1].payload.lights[1].on, 0)
end)

test("rejects invalid states before issuing requests", function()
    local manager, state = loadManager()
    manager.lights = {{ type = "elgato", ip = "10.0.0.1" }}

    local ok = pcall(function() manager:setState("maybe") end)
    support.assertEqual(ok, false)
    support.assertEqual(#state.requests, 0)
end)

test("skips malformed entries and continues dispatch", function()
    local manager, state = loadManager()
    manager.lights = {
        { type = "elgato" },
        { type = "unknown", ip = "10.0.0.8" },
        { type = "wled", ip = "10.0.0.9", name = "Valid" },
    }

    manager:setState("on")
    support.assertEqual(#state.requests, 1)
    support.assertEqual(state.requests[1].url, "http://10.0.0.9/json/state")
    support.assertTrue(#state.logs >= 2)
end)

test("non-table entries do not prevent dispatch to remaining lights", function()
    local manager, state = loadManager()
    manager.lights = {
        42,
        { type = "wled", ip = "10.0.0.9", name = "Valid" },
    }

    manager:setState("on")
    support.assertEqual(#state.requests, 1)
    support.assertEqual(state.requests[1].url, "http://10.0.0.9/json/state")
end)

test("HTTP failures do not prevent dispatch to remaining lights", function()
    local manager, state = loadManager()
    state.responses["http://10.0.0.1:9123/elgato/lights"] = { code = 500, body = "", headers = {} }
    manager.lights = {
        { type = "elgato", ip = "10.0.0.1", name = "Broken" },
        { type = "wled", ip = "10.0.0.2", name = "Working" },
    }

    manager:setState("on")
    support.assertEqual(#state.requests, 2)
    support.assertEqual(state.requests[2].url, "http://10.0.0.2/json/state")
end)

test("start prefetches only unnamed WLED names", function()
    local manager, state = loadManager()
    local infoURL = "http://10.0.0.2/json/info"
    state.responses[infoURL] = { code = 200, body = "named", headers = {} }
    state.decodedBodies.named = { name = "Desk Strip" }
    manager.lights = {
        { type = "elgato", ip = "10.0.0.1" },
        { type = "wled", ip = "10.0.0.2" },
        { type = "wled", ip = "10.0.0.3", name = "Named Strip" },
    }

    support.assertEqual(manager:start(), manager)
    support.assertEqual(#state.requests, 1)
    support.assertEqual(state.requests[1].method, "GET")
    support.assertEqual(state.requests[1].url, infoURL)
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
    error(string.format("%d LightManager test(s) failed", failures))
end

print(string.format("%d LightManager tests passed", #tests))
