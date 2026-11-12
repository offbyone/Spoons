# HomeAssistant Spoon

This is a utility spoon, that can access a home assistant API and allow you to trigger changes based on hammerspoon events. I use it to toggle switch states, but you can do most anything.

## Setup

If you are using SpoonInstall: 

```lua
Install:andUse("HomeAssistant", {
    homeAssistantUrl = "https://...",
    homeAssistantToken = "ey....",
})
```

Alternately, directly load it:

```lua
hs.LoadSpoon("HomeAssistant, true")
spoon.HomeAssistant.homeAssistantUrl = "https://...."
spoon.HomeAssistant.homeAssistantToken = "ey..."
```

Then, invoke:

```lua
-- then call methods on the spoon
spoon.HomeAssistant:setState("entity.id", "on") 
```

