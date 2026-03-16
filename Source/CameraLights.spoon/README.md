# CameraLights.spoon

Monitors camera usage and automatically controls lights (Elgato Key Lights or WLED devices).

## Features

- Automatically turns on configured lights when any camera activates (video calls, screen recording, etc.)
- Turns off lights when all cameras are inactive
- Supports multiple light types:
  - **Elgato Key Lights**: Control brightness and color temperature
  - **WLED devices**: Control brightness and optional presets
- Camera filtering: Optionally restrict which cameras trigger light control
- Manual light control via API methods
- Graceful handling of network-unreachable devices

## Installation

1. Copy `CameraLights.spoon` to `~/.hammerspoon/Spoons/`
2. Add to your `init.lua`:

```lua
hs.loadSpoon("CameraLights")
```

## Configuration

### Basic Usage with SpoonInstall

```lua
hs.loadSpoon("SpoonInstall")
spoon.SpoonInstall:andUse("CameraLights", {
  config = {
    lights = {
      { type = "elgato", ip = "192.168.1.100", name = "Left Key Light", brightness = 50, temperature = 4500 },
      { type = "wled", ip = "192.168.1.151", brightness = 200 },  -- name will be auto-discovered
    }
  },
  start = true
})
```

### Advanced Configuration with Camera Filtering

```lua
spoon.SpoonInstall:andUse("CameraLights", {
  config = {
    lights = {
      { type = "elgato", ip = "192.168.1.100", name = "Main Light", brightness = 75, temperature = 5000 },
      { type = "wled", ip = "192.168.1.151", name = "Background", brightness = 200, on_preset = 1, off_preset = 2 },
    },
    -- Only respond to FaceTime cameras
    allowedCameras = spoon.CameraLights.CameraFilters.namePattern("FaceTime")
  },
  start = true
})
```

### Direct Configuration

```lua
hs.loadSpoon("CameraLights")

-- Configure lights
spoon.CameraLights.lights = {
  { type = "elgato", ip = "192.168.1.100", name = "Left", brightness = 50, temperature = 4500 },
  { type = "elgato", ip = "192.168.1.101", name = "Right", brightness = 75, temperature = 5000 },
  { type = "wled", ip = "192.168.1.151", brightness = 200 },  -- name will be auto-discovered
}

-- Optional: Filter cameras (only allow specific cameras to trigger lights)
spoon.CameraLights.allowedCameras = spoon.CameraLights.CameraFilters.namePattern("FaceTime")

-- Start monitoring
spoon.CameraLights:start()
```

## Light Configuration

All light configurations support an optional `name` attribute for display purposes in logs and notifications.

### Elgato Key Light

```lua
{
  type = "elgato",
  ip = "192.168.1.100",        -- Required: IP address
  name = "Desk Light",         -- Optional: Display name (default: IP address)
  brightness = 50,             -- Optional: 0-100 (default: 50)
  temperature = 4500           -- Optional: Kelvin 2900-7000 (default: 4500)
}
```

### WLED Device

```lua
{
  type = "wled",
  ip = "192.168.1.151",        -- Required: IP address
  name = "Bias Light",         -- Optional: Display name (will auto-discover from WLED API if not provided)
  brightness = 200,            -- Optional: 0-255 (default: 128)
  on_preset = 1,               -- Optional: Preset ID for "on" state
  off_preset = 2               -- Optional: Preset ID for "off" state
}
```

**Note**: For WLED devices, if no `name` is provided, the spoon will lazily fetch the device name from the WLED API on first use and cache it. If the API call fails, the IP address will be used as the display name.

## Camera Filtering

Control which cameras trigger light automation:

### Allow All Cameras (Default)

```lua
spoon.CameraLights.allowedCameras = nil
-- or
spoon.CameraLights.allowedCameras = spoon.CameraLights.CameraFilters.all
```

### Match Camera Name Pattern

```lua
-- Only cameras with "FaceTime" in the name
spoon.CameraLights.allowedCameras = spoon.CameraLights.CameraFilters.namePattern("FaceTime")

-- Only cameras starting with "USB"
spoon.CameraLights.allowedCameras = spoon.CameraLights.CameraFilters.namePattern("^USB")
```

### Allow Specific Camera Names

```lua
spoon.CameraLights.allowedCameras = spoon.CameraLights.CameraFilters.nameList({
  "FaceTime HD Camera",
  "USB Camera"
})
```

### Custom Filter Function

```lua
spoon.CameraLights.allowedCameras = function(camera)
  -- Your custom logic here
  local name = camera:name()
  return name:match("FaceTime") or name:match("HD")
end
```

## API Methods

### `CameraLights:start()`

Start monitoring cameras and controlling lights based on camera state.

```lua
spoon.CameraLights:start()
```

### `CameraLights:stop()`

Stop monitoring cameras.

```lua
spoon.CameraLights:stop()
```

### `CameraLights:lightsOn()`

Manually turn all lights on (bypasses camera state).

```lua
spoon.CameraLights:lightsOn()
```

### `CameraLights:lightsOff()`

Manually turn all lights off (bypasses camera state).

```lua
spoon.CameraLights:lightsOff()
```

### `CameraLights:status()`

Print current status to Hammerspoon console.

```lua
spoon.CameraLights:status()
```

## Configuration Variables

### `CameraLights.lights`

Table of light configurations (required).

### `CameraLights.allowedCameras`

Function to filter cameras, or `nil` for all cameras (optional, default: `nil`).

### `CameraLights.ELGATO_PORT`

Port for Elgato Key Light API (default: `9123`).

### `CameraLights.HTTP_TIMEOUT`

HTTP request timeout in seconds (default: `3`).

## Examples

### Home Office Setup

```lua
spoon.SpoonInstall:andUse("CameraLights", {
  config = {
    lights = {
      -- Two Elgato Key Lights
      { type = "elgato", ip = "192.168.1.100", name = "Left Key Light", brightness = 60, temperature = 4500 },
      { type = "elgato", ip = "192.168.1.101", name = "Right Key Light", brightness = 80, temperature = 5000 },
      -- Bias lighting (will use WLED device name)
      { type = "wled", ip = "192.168.1.151", brightness = 150 },
    },
    -- Only respond to built-in FaceTime camera, not USB cameras
    allowedCameras = spoon.CameraLights.CameraFilters.namePattern("FaceTime HD")
  },
  start = true
})
```

### Multiple Locations with Network Detection

Since lights on unreachable networks are silently ignored, you can configure all your lights and the spoon will only control those currently reachable:

```lua
spoon.CameraLights.lights = {
  -- Home office lights
  { type = "elgato", ip = "192.168.1.100", name = "Home Key Light", brightness = 50, temperature = 4500 },
  -- Work office lights (different network)
  { type = "elgato", ip = "10.0.1.200", name = "Work Key Light", brightness = 75, temperature = 5000 },
}
spoon.CameraLights:start()
```

## Troubleshooting

### Check Status

Open Hammerspoon console and run:

```lua
spoon.CameraLights:status()
```

This shows:
- Detected cameras and their state
- Configured lights
- Current camera in-use status
- Camera filtering status

### Enable Debug Logging

```lua
spoon.CameraLights.logger.setLogLevel("debug")
```

### Test Lights Manually

```lua
-- Turn lights on
spoon.CameraLights:lightsOn()

-- Turn lights off
spoon.CameraLights:lightsOff()
```

## License

MIT License
