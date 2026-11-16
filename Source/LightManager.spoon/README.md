# LightManager.spoon

Controls Elgato Key Lights and WLED devices through one state-oriented API.

`LightManager` is independent of camera monitoring. Call `setState("on")` or `setState("off")` directly, or optionally use it from another spoon's callback.

## Features

- Elgato Key Light on/off, brightness, and color temperature control
- WLED on/off, brightness, and optional preset control
- WLED device-name discovery and caching
- Per-device error isolation so one bad device does not block the rest
- A callback-compatible `setState(state)` method

## Installation

Install with [SpoonInstall](https://www.hammerspoon.org/Spoons/SpoonInstall.html) or copy `LightManager.spoon` into `~/.hammerspoon/Spoons/`.

## Configuration

```lua
hs.loadSpoon("LightManager")

spoon.LightManager.lights = {
  {
    type = "elgato",
    ip = "192.168.1.100",
    name = "Desk Key Light",
    brightness = 50,
    temperature = 4500,
  },
  {
    type = "wled",
    ip = "192.168.1.151",
    name = "Bias Light",
    brightness = 200,
    camera_on_preset = 1,
    camera_off_preset = 2,
  },
}

spoon.LightManager:start()
```

Calling `start()` is optional for control; it prefetches names for unnamed WLED devices and logs the configured devices.

## Device Configuration

Every entry requires:

- `type`: `"elgato"` or `"wled"`
- `ip`: device IP address
- `name`: optional display name

### Elgato Key Light

- `brightness`: `0`–`100`, default `50`
- `temperature`: Kelvin `2900`–`7000`, default `4500`

```lua
{
  type = "elgato",
  ip = "192.168.1.100",
  brightness = 60,
  temperature = 5000,
}
```

### WLED

- `brightness`: `0`–`255`, default `128`
- `camera_on_preset`: optional preset selected for the `"on"` state
- `camera_off_preset`: optional preset selected for the `"off"` state

```lua
{
  type = "wled",
  ip = "192.168.1.151",
  brightness = 200,
  camera_on_preset = 1,
  camera_off_preset = 2,
}
```

When an off preset is configured, WLED remains on while switching to that preset; without one, the device is turned off.

## API

### `LightManager:setState(state)`

Apply `"on"` or `"off"` to every configured light and return the spoon object. Other state values raise an error without issuing requests.

```lua
spoon.LightManager:setState("on")
spoon.LightManager:setState("off")
```

### `LightManager:lightsOn()` / `LightManager:lightsOff()`

Convenience methods using the same state-control path.

### `LightManager:start()`

Prefetch unnamed WLED device names and log configuration.

### `LightManager:status()`

Print configured devices and their brightness/temperature settings.

### Configuration variables

- `LightManager.lights`: device configuration table
- `LightManager.ELGATO_PORT`: Elgato API port, default `9123`
- `LightManager.HTTP_TIMEOUT`: retained HTTP timeout configuration, default `3`

## Optional CameraLights Wiring

The spoons do not load or configure each other. To use `LightManager` as the camera callback target, wire them explicitly:

```lua
hs.loadSpoon("LightManager")
hs.loadSpoon("CameraLights")

spoon.LightManager.lights = {
  { type = "elgato", ip = "192.168.1.100", brightness = 50, temperature = 4500 },
  { type = "wled", ip = "192.168.1.151", brightness = 200 },
}

spoon.LightManager:start()
spoon.CameraLights.callback = function(state)
  spoon.LightManager:setState(state)
end
spoon.CameraLights:start()
```

`CameraLights.callback` may instead remain any custom function; using `LightManager` is optional.

## Troubleshooting

```lua
spoon.LightManager.logger.setLogLevel("debug")
spoon.LightManager:status()
spoon.LightManager:lightsOn()
spoon.LightManager:lightsOff()
```

## License

MIT
