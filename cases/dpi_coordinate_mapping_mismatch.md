# DPI coordinate mapping mismatch (logical vs physical)

Minimal reproducible case for the winagent coordinate-space bug found while driving WeChat
through visible UI primitives on a 150% display.

- Case: `cases/dpi_coordinate_mapping_mismatch.case`
- Driver: `cases/dpi_coordinate_mapping_mismatch.ps1`
- Status today: **fails** (`ASSERTION_FAILED`, step 1). It passes once the mapper applies the
  device scale factor.

## Symptom

```
bin\winagent.exe coordinate-map --capture-scope global_desktop --capture-left 0 --capture-top 0 \
  --capture-width 2560 --capture-height 1600 --pixel-x 1280 --pixel-y 800
```

| field | actual | expected on a 150% display |
| --- | --- | --- |
| `dpi_scale` | `1` | `1.5` |
| `screen_x` | `1280` | `853` |
| `screen_y` | `800` | `533` |
| `mapping_valid` | `true` | `true` |

The mapper reports `mapping_valid:true` for a mapping that is wrong by a constant 1.5x.
The same defect is visible end-to-end: `desktop-click` echoes a coordinate mapping whose
`capture_physical_size` is `1707x1067` while the global frame it captured is physically
`2560x1600`, and passing screenshot pixel coordinates straight to `--screen-x/--screen-y`
lands at 1/1.5 of the intended point.

Both trees ship the identical binary (`8248832` bytes, Jul 1 12:02), so
`D:\desktopvisual\bin\winagent.exe` and `D:\desktop_release\bin\winagent.exe` behave the same.

## Root cause

1. `src/winagent/ScreenshotCoordinateMapper.cpp:67-76` - `map_global_pixel_to_screen_coord` computes
   `result.screenX = input.captureRect.left + input.pixelX;` and never divides by `dpiScale`.
2. `src/winagent/ScreenshotCoordinateMapper.cpp:89-98` - `map_screen_coord_to_global_pixel` computes
   `result.pixelX = input.screenX - input.captureRect.left;` and never multiplies by `dpiScale`.
   The reverse direction is therefore equally wrong.
3. `src/winagent/WinAgent.cpp:9042-9055` - the mapping input built for `desktop-click` never assigns
   `dpiScale`, so it keeps the header default of `1.0`. Its `captureRect` comes from
   `GetSystemMetrics(SM_XVIRTUALSCREEN / SM_YVIRTUALSCREEN / SM_CXVIRTUALSCREEN / SM_CYVIRTUALSCREEN)`,
   which returns **logical** metrics because the winagent process itself is DPI-unaware (only the
   capture path switches to `per_monitor_v2`). Hence `capture_physical_size` is reported as
   `1707x1067` even though the captured frame is `2560x1600`.
4. `src/winagent/ScreenshotCoordinateMapper.cpp:35-37` - `validate_dpi_scale_consistency` only checks
   `isfinite` and `0 < dpiScale < 8`; a scale of `1` on a 150% display passes validation.
5. `src/winagent/FrameRegistry.cpp:400` already parses the frame's `dpi_scale` and
   `FrameRegistry.cpp:607` already emits it - the value reaches the frame metadata but the mapper
   never consumes it.

## Why the existing tests did not catch it

`screenshot_coordinate_mapper_selftest.ps1` lines 18-25 assert identity behaviour only
(`pixel 10,20 -> screen 10,20`, and window-origin `100,200` + pixel `25,30` -> `125,230`).
It never varies the scale factor, so a pass-through mapper satisfies it.

## Reproducing

```powershell
powershell -ExecutionPolicy Bypass -File cases\dpi_coordinate_mapping_mismatch.ps1
```

Exit code `0` = fixed, `1` = bug reproduced, `2` = host is not at 150% scaling.

## Scope and limitations

- A `.case` cannot invoke `coordinate-map`: `CaseRunner.cpp:1001-1538` has no such step and any
  unknown keyword fails with `CASE_PARSE_FAILED` at `CaseRunner.cpp:1535`. The driver therefore
  produces `artifacts/dpi_coordinate_map_actual.json` before calling `run-case`.
- `coordinate-map` has no `--dpi-scale` argument (`WinAgent.cpp:3689-3738`), so the expected values in
  the case are the ones for the host's real scale. That is why the driver refuses to run unless the
  detected scale is 150%.
- The asserted path is absolute and therefore tree-specific (`D:\desktopvisual\artifacts\...`), matching
  the convention already used by `CASE_FORMAT.md:108`. The case belongs to the developer tree; if it
  is synced to `D:\desktop_release` the path must be repointed at that tree's `artifacts` directory,
  which is the only area its `config/safety.conf` `allowed_read_roots` permits.
- Asserted values are the contract, not a suggested implementation: whichever way the mapper learns
  the scale, `dpi_scale` must report the real factor and `screen_x/screen_y` must be the logical
  coordinates. Other legitimate conventions (for example rounding differently) would need the case's
  numbers adjusted, but `853/533` are exact truncations of `1280/1.5` and `800/1.5`.
