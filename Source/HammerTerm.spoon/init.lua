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
-- obj.defaultTerminalAppName = "iTerm2"
obj.defaultTerminalAppName = "Ghostty"

-- A preferred terminal (by name). When set via config and the app is installed,
-- HammerTerm will use ONLY this terminal and skip scanning the list below. If it
-- is not set (or not installed) the fallback scan of `terminals` is used.
-- Set via SpoonInstall, e.g. `config = { terminalAppName = "kitty" }`.
obj.terminalAppName = nil

-- Extra terminals to make known, as a name -> bundle ID map. Merged into the
-- built-in `terminals` list at start(). Set via SpoonInstall, e.g.
-- `config = { additionalTerminals = { Alacritty = "org.alacritty" } }`.
obj.additionalTerminals = {}

-- The terminals to try, in order, before falling back to opening the default
obj.terminals = {
  {"Ghostty", "com.mitchellh.ghostty"},
  {"iTerm2", "com.googlecode.iterm2"},
  {"Wezterm", "com.github.wez.wezterm"},
  {"Terminal", "com.apple.Terminal"},
  {"kitty", "net.kovidgoyal.kitty"},
}

function obj:bindKeys()
  hs.hotkey.bind({"cmd", "ctrl"}, "'", obj.toggleTerminal)
  hs.hotkey.bind({"cmd", "ctrl"}, ";", obj.toggleEmacs)
end

function obj:toggleEmacs()
  local app = nil
  local emacsBundleId = "org.gnu.Emacs"
  app = hs.application.get(emacsBundleId)

  if app ~= nil then
    if app:isFrontmost() then
      hs.alert.show(string.format("Hiding %s", app:name()))
      app:hide()
    else
      hs.alert.show(string.format("Foregrounding %s", app:name()))
      app:activate()
    end
  else
    hs.alert.show(string.format("No active Emacs, opening %s", emacsBundleId))
    hs.application.open(emacsBundleId)
  end
end

-- Toggle a single, already-running app: hide it if it is frontmost, otherwise
-- bring it to the foreground.
function obj._toggleRunningApp(app)
  if app:isFrontmost() then
    hs.alert.show(string.format("Hiding %s", app:name()))
    app:hide()
  else
    hs.alert.show(string.format("Foregrounding %s", app:name()))
    app:activate()
  end
end

function obj:toggleTerminal()
  -- If a preferred terminal is configured and installed, use ONLY it.
  local preferred = obj.preferredTerminal
  if preferred ~= nil and hs.application.pathForBundleID(preferred.bundleId) ~= nil then
    local app = hs.application.get(preferred.bundleId)
    if app ~= nil then
      obj._toggleRunningApp(app)
    else
      hs.alert.show(string.format("Opening preferred terminal %s", preferred.name))
      hs.application.open(preferred.name)
    end
    return
  end

  -- Fallback: scan the known terminals and toggle the first one running.
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
    obj._toggleRunningApp(app)
  else
    hs.alert.show(string.format("No active terminal, opening %s", obj.defaultTerminalAppName))
    hs.application.open(obj.defaultTerminalAppName)
  end
end

-- Merge `additionalTerminals` (a name -> bundleId map) into the built-in
-- `terminals` list. De-duped by bundle ID; a matching bundle ID updates the
-- existing entry's name in place, otherwise the pair is appended.
function obj:_mergeTerminals()
  for name, bundleId in pairs(self.additionalTerminals or {}) do
    local existing = nil
    for _, terminal in ipairs(self.terminals) do
      if terminal[2] == bundleId then
        existing = terminal
        break
      end
    end
    if existing ~= nil then
      existing[1] = name
    else
      table.insert(self.terminals, {name, bundleId})
    end
  end
end

-- Resolve `terminalAppName` to a {name, bundleId} pair by looking it up in the
-- (already-merged) `terminals` list. Sets self.preferredTerminal, or leaves it
-- nil and warns if the name is unknown.
function obj:_resolvePreferredTerminal()
  self.preferredTerminal = nil
  if not self.terminalAppName then
    return
  end
  for _, terminal in ipairs(self.terminals) do
    if terminal[1] == self.terminalAppName then
      self.preferredTerminal = {name = terminal[1], bundleId = terminal[2]}
      return
    end
  end
  logger.wf("Preferred terminal %q not found in known terminals; falling back to scan", self.terminalAppName)
end

function obj:start()
  self:_mergeTerminals()
  self:_resolvePreferredTerminal()
  if self.bind then
    self:bindKeys()
  end
end

return obj
