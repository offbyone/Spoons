--- Home Assistant Integration

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Home Assistant Integration"
obj.version = "1.0.0"
obj.author = "Chris Rose <offline@offby1.net>"
obj.homepage = "https://github.com/offbyone/Spoons"
obj.license = "Affero General Public License v3.0"

obj.logger = hs.logger.new("HomeAssistant", "debug")

-- Configuration
obj.homeAssistantUrl = "http://localhost:8123"
obj.homeAssistantToken = "YOUR_LONG_LIVED_ACCESS_TOKEN"

local function new()
    local self = setmetatable({}, obj)
    return self
end

function obj:init()
    self.logger:d("Initializing Home Assistant Integration Spoon")
    return self
end

function obj:start()
    return self
end

function obj:stop()
    return self
end

function obj:setState(entityId, state)
    baseUrl = self.homeAssistantUrl .. "/api/states/" .. entityId
    local jsonData = hs.json.encode({ state = state })
    hs.http.asyncPost(baseUrl, jsonData, { ["Authorization"] = "Bearer " .. self.homeAssistantToken, ["Content-Type"] = "application/json" }, function(status, body, headers)
        if status == 200 then
            self.logger:d("Successfully set state of " .. entityId .. " to " .. state)
        else
            self.logger:e("Failed to set state of " .. entityId .. "(" .. jsonData .. "): " .. status)
        end
    end)
end

function obj:getState(entityId)
    baseUrl = self.homeAssistantUrl .. "/api/states/" .. entityId
    hs.http.asyncGet(baseUrl, { ["Authorization"] = "Bearer " .. self.homeAssistantToken }, function(status, body, headers)
        if status == 200 then
            local state = hs.json.decode(body)
            self.logger:d("State of " .. entityId .. ": " .. hs.json.encode(state))
        else
            self.logger:e("Failed to get state of " .. entityId .. ": " .. status)
        end
    end)
end

return obj
