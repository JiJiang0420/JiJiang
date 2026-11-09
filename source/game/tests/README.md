# Headless integration checks

Requires Godot 4.6.3. Import the project first, then run tests in a **new disposable user-data directory**. Tests refuse to touch an existing game save or a data directory without the `wf2-smoke` marker.

From the `game` directory:

```bash
test_root="$(mktemp -d /tmp/wf2-smoke.XXXXXX)"
mkdir -p "$test_root/data" "$test_root/cache" "$test_root/config"
XDG_DATA_HOME="$test_root/data" XDG_CACHE_HOME="$test_root/cache" XDG_CONFIG_HOME="$test_root/config" \
  godot --headless --editor --path . --quit
WITCHES_FEAST_TEST=1 XDG_DATA_HOME="$test_root/data" XDG_CACHE_HOME="$test_root/cache" XDG_CONFIG_HOME="$test_root/config" \
  godot --headless --path . --script res://tests/smoke.gd
```

The suite instantiates the real main scene, disables automatic frame advancement and audio playback, and invokes the actual spell, actor, economy and save APIs with controlled fixtures. It checks independent kills, invalid-cast preservation, switching, boundary batches, projectile redirection, pause timing, collision order, the three-stage shop/boss loop, duplicate settlement, permanent purchases and damaged-save recovery.

Expected ending: `SMOKE_RESULT passed=<count> failed=0`, process exit code `0`. A failed assertion returns `1`; refusing an unsafe data location returns `2`. Corruption/invalid-data cases intentionally produce save warnings. This suite does not claim visual, input feel, platform-export or real-hardware performance validation.

The directory printed as `isolated_user_dir` contains only disposable test data and can be removed after inspection.

## Graphical input smoke test

`input_smoke.gd` opens a real 1280×800 game window, sends synthetic key/mouse events through Godot's input and viewport dispatch, and checks the resulting UI and gameplay state. It does not invoke button signals or spell functions directly for the input assertions. Static enemy fixtures isolate the input routing from AI difficulty.

Run on a working X11 display (the cloud verification uses a local Xorg display at `:99`):

```bash
test_root="$(mktemp -d /tmp/wf2-smoke-input.XXXXXX)"
mkdir -p "$test_root/data" "$test_root/cache" "$test_root/config"
DISPLAY=:99 WITCHES_FEAST_TEST=1 \
  XDG_DATA_HOME="$test_root/data" XDG_CACHE_HOME="$test_root/cache" XDG_CONFIG_HOME="$test_root/config" \
  godot --path . --script res://tests/input_smoke.gd \
  --rendering-method gl_compatibility --audio-driver Dummy --log-file "$test_root/input.log"
```

The suite checks base help/close buttons, training entry, all four movement keys, all three cloak selections, mouse-drag casting for each cloak, pause/resume, paused movement, middle-button camera rotation, camera reset and returning to base. Spell gestures send a complete press/motion/release event batch within one frame, checking that event coordinates work even between render updates. They do not wait for each point to render, which would exceed the actual 2.4-second gesture timeout on a slow software renderer. The actual viewport frame is saved to `$test_root/data/input-smoke.png`. Successful runs end with `INPUT_SMOKE_RESULT passed=<count> failed=0` and exit `0`.

The test refuses headless mode and non-isolated user data. It checks event routing and rendered output availability; it is **not** human playtesting, audio validation, Windows verification or performance certification. Software-rendered Xorg/llvmpipe results must not be reported as target-GPU performance.

## v0.2 combat changes

Run `res://tests/combat_v02.gd` with the same isolated-data procedure in a separate fresh temporary directory. The suite covers real prediction/hit agreement, branch trade-offs, secondary action lifecycles, pause timing, shop purchases, and training/save isolation. Current result: 85 assertions passed. A snap is ready 0.25 seconds after linking; early right-clicks are rejected and never queued.

The v0.2 graphical suite currently passes 52 assertions, including Q branch trials, right-click snap/launch, pending-wall direction persistence across cloak switches, removal after contact, and separate readiness for left/right clicks. Captures include `preview-0/1/2.png` and `pending-wall.png`. These remain automated checks, not a fun or usability verdict.
