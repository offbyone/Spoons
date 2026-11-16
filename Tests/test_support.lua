local support = {}

local function sameValue(actual, expected, path)
    path = path or "value"
    if type(actual) ~= type(expected) then
        return false, string.format("%s: expected type %s, got %s", path, type(expected), type(actual))
    end
    if type(expected) ~= "table" then
        if actual ~= expected then
            return false, string.format("%s: expected %s, got %s", path, tostring(expected), tostring(actual))
        end
        return true
    end
    for key, value in pairs(expected) do
        local ok, err = sameValue(actual[key], value, path .. "." .. tostring(key))
        if not ok then return false, err end
    end
    for key in pairs(actual) do
        if expected[key] == nil then
            return false, string.format("%s: unexpected key %s", path, tostring(key))
        end
    end
    return true
end

function support.assertEqual(actual, expected, message)
    if actual ~= expected then
        error(message or string.format("expected %s, got %s", tostring(expected), tostring(actual)), 2)
    end
end

function support.assertTableEqual(actual, expected, message)
    local ok, err = sameValue(actual, expected)
    if not ok then error(message or err, 2) end
end

function support.assertTrue(value, message)
    if not value then error(message or "expected truthy value", 2) end
end

function support.newEnvironment()
    local state = {
        requests = {},
        logs = {},
        notifications = {},
        responses = {},
        decodedBodies = {},
        cameras = {},
        cameraWatcherStarted = false,
        cameraWatcherStopped = false,
        sleepWatchers = {},
        repeatingTimers = {},
    }

    local function log(level, message)
        table.insert(state.logs, { level = level, message = message })
    end

    local logger = {}
    for _, level in ipairs({ "d", "i", "w", "e" }) do
        logger[level] = function(message) log(level, message) end
    end

    local function request(method, url, payload, headers, callback)
        local item = { method = method, url = url, payload = payload, headers = headers }
        table.insert(state.requests, item)
        local response = state.responses[url] or { code = 200, body = "{}", headers = {} }
        callback(response.code, response.body, response.headers)
    end

    local hs = {
        logger = { new = function() return logger end },
        json = {
            encode = function(value) return value end,
            decode = function(body) return state.decodedBodies[body] end,
        },
        http = {
            asyncGet = function(url, headers, callback) request("GET", url, nil, headers, callback) end,
            asyncPut = function(url, payload, headers, callback) request("PUT", url, payload, headers, callback) end,
            asyncPost = function(url, payload, headers, callback) request("POST", url, payload, headers, callback) end,
        },
        notify = {
            new = function(notification)
                return {
                    send = function()
                        table.insert(state.notifications, notification)
                    end,
                }
            end,
        },
        timer = {
            doAfter = function(_, callback)
                callback()
                return { stop = function() end }
            end,
            doEvery = function(_, callback)
                local timer = { callback = callback, stopped = false }
                function timer:stop() self.stopped = true end
                table.insert(state.repeatingTimers, timer)
                return timer
            end,
        },
        camera = {
            allCameras = function() return state.cameras end,
            setWatcherCallback = function(callback) state.cameraWatcherCallback = callback end,
            startWatcher = function() state.cameraWatcherStarted = true end,
            stopWatcher = function() state.cameraWatcherStopped = true end,
        },
        caffeinate = {
            watcher = {
                systemDidWake = "systemDidWake",
                new = function(callback)
                    local watcher = { callback = callback, started = false, stopped = false }
                    function watcher:start() self.started = true end
                    function watcher:stop() self.stopped = true end
                    table.insert(state.sleepWatchers, watcher)
                    return watcher
                end,
            },
        },
    }

    function state:newCamera(uid, name, inUse)
        local camera = {
            _uid = uid,
            _name = name,
            _inUse = inUse or false,
            propertyWatcherStarted = false,
            propertyWatcherStopped = false,
        }
        function camera:uid() return self._uid end
        function camera:name() return self._name end
        function camera:isInUse() return self._inUse end
        function camera:setInUse(value) self._inUse = value end
        function camera:setPropertyWatcherCallback(callback) self.propertyWatcherCallback = callback end
        function camera:startPropertyWatcher() self.propertyWatcherStarted = true end
        function camera:stopPropertyWatcher() self.propertyWatcherStopped = true end
        table.insert(self.cameras, camera)
        return camera
    end

    function state:loadSpoon(path)
        local environment = setmetatable({ hs = hs }, { __index = _G })
        local chunk, err = loadfile(path, "t", environment)
        if not chunk then error(err, 2) end
        return chunk()
    end

    function state:clearRequests()
        self.requests = {}
    end

    return state, hs
end

return support
