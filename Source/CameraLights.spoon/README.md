# CameraLights.spoon

Monitors macOS camera usage and reports whether any allowed camera is active through a simple callback.

`CameraLights` does not control lights or depend on any particular automation system. Its callback receives exactly one state string: `"on"` or `"off"`.

## Features

- Monitors all cameras known to Hammerspoon
- Reports aggregate state rather than individual camera events
- Supports camera filtering by name or a custom function
- Rebuilds camera watchers after wake and camera hardware changes
- Performs periodic health checks for missed camera events
- Contains callback errors so monitoring continues

## Installation

Install with [SpoonInstall](https://www.hammerspoon.org/Spoons/SpoonInstall.html) or copy `CameraLights.spoon` into `~/.hammerspoon/Spoons/`.

## Basic Usage

```lua
hs.loadSpoon("CameraLights")

spoon.CameraLights.callback = function(state)
  print("Camera state: " .. state)
end

spoon.CameraLights:start()
```

The callback is invoked during startup with the current aggregate state, then only when that state changes.

## Custom Callback

The callback is intentionally independent of `LightManager` and can drive any automation you choose:

```lua
spoon.CameraLights.callback = function(state)
  if state == "on" then
    hs.alert.show("Camera active")
  else
    hs.alert.show("Camera idle")
  end
end
```

## Camera Filtering

By default, every camera contributes to the aggregate state.

### Match a camera name pattern

```lua
spoon.CameraLights.allowedCameras =
  spoon.CameraLights.CameraFilters.namePattern("FaceTime")
```

### Allow specific camera names

```lua
spoon.CameraLights.allowedCameras =
  spoon.CameraLights.CameraFilters.nameList({
    "FaceTime HD Camera",
    "Studio Display Camera",
  })
```

### Custom filter

```lua
spoon.CameraLights.allowedCameras = function(camera)
  return not camera:name():match("Virtual")
end
```

## API

### `CameraLights:start()`

Start camera monitoring, synchronize the current aggregate state, and invoke `callback` with `"on"` or `"off"`.

### `CameraLights:stop()`

Stop camera, sleep/wake, and health-check watchers.

### `CameraLights:status()`

Print detected cameras, their usage/filter status, and the current aggregate state.

## Configuration

### `CameraLights.callback`

Optional function called with exactly one lowercase string, `"on"` or `"off"`.

### `CameraLights.allowedCameras`

Optional function receiving a camera object and returning `true` when that camera should affect aggregate state. `nil` allows all cameras.

### `CameraLights.CameraFilters`

Convenience filter constructors:

- `CameraFilters.namePattern(pattern)`
- `CameraFilters.nameList(names)`
- `CameraFilters.all` (`nil`, allowing all cameras)

## Troubleshooting

```lua
spoon.CameraLights.logger.setLogLevel("debug")
spoon.CameraLights:status()
```

## License

MIT
