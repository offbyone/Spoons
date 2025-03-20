--- === Terminal Support ===
---
--- Add commands to manage terminals
---
--- Download: [https://github.com/offbyone/HammerTerm.spoon.zip](https://github.com/offbyone/HammerTerm.spoon.zip)

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "HammerTerm"
obj.version = "0.1"
obj.author = "Chris Rose <offline@offby1.net>"
obj.homepage = "https://github.com/offbyone/HammerTerm.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"

local logger = hs.logger.new("HammerTerm")

-- whether to automatically bind keys
obj.bind = true

-- The default terminal to start
obj.defaultTerminalAppName = "iTerm2"

-- The terminals to try, in order, before falling back to opening the default
obj.terminals = {
  {"iTerm2", "com.googlecode.iterm2"},
  {"Wezterm", "com.github.wez.wezterm"},
  {"Terminal", "com.apple.Terminal"},
}

function obj:bindKeys()
  hs.hotkey.bind({"cmd", "ctrl"}, "'", obj.toggleTerminal)
end

function obj:toggleTerminal()
  local app = nil

  for _, terminal in ipairs(obj.terminals) do
    local name, bundleId = table.unpack(terminal)
    local _maybeApp = hs.application.get(bundleId)
    if _maybeApp ~= nil then
      app = _maybeApp
      break
    else
      logger.df("Didn't find %s using %s", name, bundleId)
    end
  end

  if app ~= nil then
    if app:isFrontmost() then
      hs.alert.show(string.format("Hiding %s", app:name()))
      app:hide()
    else
      hs.alert.show(string.format("Foregrounding %s", app:name()))
      app:activate()
    end
  else
    for _, terminal in ipairs(obj.terminals) do
      local name, bundleId = table.unpack(terminal)
      if name == obj.defaultTerminalAppName then
        local _maybeApp = hs.application.nameForBundleID(bundleId)
        if _maybeApp ~= nil then
          hs.alert.show(string.format("No active terminal, opening %s", name))
          hs.application.open(bundleId)

          -- early return
          return
        else
          hs.alert.show(string.format("No active terminal and the default of %s is not installed", obj.defaultTerminalAppName))
        end
      end
    end

    logger.ef("Didn't find %s using %s", obj.defaultTerminalAppName, defaultBundleId)
  end
end

function obj:start()
  if self.bind then
    self:bindKeys()
  end
end

return obj
