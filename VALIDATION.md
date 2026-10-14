# Validation record

## Phone hand-control scope

- User confirmed fist hits work and requested phone hand tracking remain hits-only. Removed the uninstalled palm-movement work; desktop OpenCV movement remains available.
- Phone hints now distinguish touch movement from fist hits. Full existing gameplay, hand debounce, camera and LAN checks passed after removal. APK content verification rejects phone palm-movement identifiers to prevent packaging the abandoned implementation.

## Forgiving placement update - version 2.3 / code 5

- Built and signed APK, installed successfully on the connected SM-M317F. APK content checks confirm approximate placement and the downward offset are packaged. All Godot gameplay, camera, hand bridge and LAN checks passed, including manual placement with tracking false and switching back to scanned placement.
- Declared HIGH_SAMPLING_RATE_SENSORS. Before this update, app accelerometer/uncalibrated gyro subscriptions were 160 ms; disabling Power saving and restarting 2.2 did not change them. After installing 2.3, both subscriptions are 5 ms (200 Hz), tracking reports TRACKING/NONE and one horizontal plane with a successful center hit is detected. This is observed device evidence; no claim is made that Power saving alone caused the problem.
- Plane placement accepts the plane's rectangular extents as well as its polygon. Added Place without scan: creates an approximate horizontal court without waiting for tracking/plane detection, and labels it approximate. Camera-stale/error handling remains in place.
- Switched from approximate placement to Move court on the actual phone. Native diagnostics confirm TRACKING/NONE, anchored=true and horizontal planes detected across subsequent samples; normal detected-surface placement is verified.
- Tapped Place without scan on the actual phone and confirmed court, avatars, ball and live camera render together. Captured HUD shows 20 FPS at that instant; stable latency/frame rate is not claimed.

## Blank-camera fix verified on Galaxy M31s - version 2.2

- Connected the user's SM-M317F running Android 12 with Mali-G72 Vulkan 1.1 after enabling USB debugging. Captured the old app's own logs: repeated empty-JPEG decode errors at main.gd:445, while ARCore still published tracking status.
- The JNI singleton reports `has_method("getCameraYuv") == false` despite the packaged Java method existing. Removed these reflection gates from the known packaged native API calls (camera, hand toggle, display geometry and placement cancellation). The old gate incorrectly selected the empty legacy JPEG path.
- Added a compatible RGB/JPEG preview mode, enabled by default. Android's native YuvImage encoder runs on a separate bounded preview worker, independently of ARCore and optional hand inference. Fast raw YUV mode remains selectable. Empty startup frames are skipped rather than decoded repeatedly.
- Built, signed and installed version 2.2/code 4 over the user's existing app. Screenshot on the actual M31s confirms visible live color camera background and HUD reading 28 FPS in that capture. Updated app logs show the reflection mismatch and no empty-image error loop. This is a preview/UI observation, not a measured end-to-end camera latency or completed AR placement test.
- Full automated suite passed. Dedicated compatible-preview test verifies RGB rendering, preview IDs, texture reuse and bypassing raw YUV in Safe mode.

## Yellow-ring investigation on the connected M31s

- Camera preview is confirmed working; the user reports that the placement ring remains yellow.
- ARCore logs repeatedly report camera timestamps ahead of the latest integrated IMU pose, with latest IMU timestamps progressing about every 160 ms.
- `dumpsys sensorservice` reports active accelerometer and uncalibrated gyro subscriptions for the application at 160,000 microseconds (6.25 Hz). Android sensor privacy is disabled; `settings get global low_power` returns 1.
- Disabling Power saving and restarting 2.2 did not fix the sensor sampling. See the 2.3 device results above for the subsequent high-rate permission change.

## Android performance fix - October 14, 2026

- Final `build/NeonVolleyAR.apk` exported successfully: version 2.1/code 3, ARM64, min API 26/target 35. APK v2 signature and ZIP integrity passed. Packaged gameplay tokens confirm raw YUV upload, optional hand hits and cancelable placement; native DEX includes getCameraYuv, setHandTrackingEnabled, copyYuv and cancelPlacement.
- Native Kotlin/AAR compilation passed. The exporter stalled after completing/signing the APK; the updated build wrapper verified the fresh artifact and closed only its stalled exporter process, then returned successfully.

- Removed live JPEG encoding/decoding from the native phone camera path. ARCore selects the lowest CPU image resolution among 30 FPS-capable configurations. Stride-aware Y/U/V planes are copied into one immutable latest-frame packet and uploaded to reused R8 textures; a GPU shader converts YUV to RGB.
- Optional 320-pixel hand inference uses a separate single worker and an atomic busy gate. It starts disabled, with an explicit Hand hits toggle. ARCore updates, camera publication and plane hit tests do not wait for model loading/inference. Gesture IDs identify inference results rather than camera frames.
- Plane placement requests persist until a valid surface appears and can be canceled. The plus reticle is replaced with a labeled amber/green aim ring and hides after placement. Stale camera frames are not displayed indefinitely.
- Batched static court/net/audience boxes with MultiMesh; disabled Android shadows, unused AR light estimation and compositor by default; lowered mobile 3D scale to 60%.
- Full Godot gameplay, AR bridge, raw camera packet and ENet tests passed. A real Vulkan render verified YUV conversion produces the expected red sample; texture reuse and malformed packet rejection passed.
- These are implementation/desktop checks, not a measured Galaxy M31s frame rate. Physical-device latency, tracking, gesture throughput and placement still need testing.


## Android APK verified - October 14, 2026

- The user's build produced `build/NeonVolleyAR.apk` at 01:24. Export log ends with completed export; no new crash record was found for this build. The reported window crash does not establish an APK failure.
- APK verified with Android apksigner: v2 signature valid, one signer. ZIP integrity passed. AAPT reports Neon Volley AR, version 2.0/code 2, org.pocketterrain.demo, ARM64, min API 26, target API 35, landscape, camera/internet permissions and PocketAR plugin/ARCore metadata.
- APK includes volleyball/court gameplay, bundled hand model and ARM64 ARCore/MediaPipe libraries, without private build tooling. Tokenized main.gdc was decompressed and checked for current phone_fist_armed, updateDisplayGeometry and last_tracking_frame_time identifiers. Native DEX also contains updateDisplayGeometry.
- Native AAR was rebuilt at 01:22. The Android SDK packages and license acceptance are now present. Subsequent builds skip SDK package downloads when prerequisites exist and cap native Gradle memory/workers.
- ADB outside the sandbox starts correctly and reports no connected devices. Physical Galaxy M31s install, permissions, tracking, alignment, hand inference, pause/resume and performance remain untested.

Earlier blocked-build records below are historical; the current APK is available.

## Mobile AR preparation for Galaxy M31s

- Google lists Samsung Galaxy M31s as ARCore supported (checked https://developers.google.com/ar/devices).
- Added build/install launchers and shared PowerShell environment discovery. All three PowerShell scripts passed syntax parsing. Build preflight finds Java, Godot, Gradle, templates and hand model, and correctly reports absent Android SDK platform-tools, API 35, build-tools 35.0.0, NDK 28.1 and CMake.
- Google SDK manager now reaches its metadata successfully outside network restrictions. It reports eight unaccepted SDK licenses. No licenses were accepted on the user's behalf and no new APK was exported. The user must review the requested-package license prompts in Build Android AR.cmd.
- Added separate output `build/NeonVolleyAR.apk` to prevent installing the original terrain APK by mistake. Installation/device authorization is untested until SDK setup and phone connection are complete.
- Godot AR bridge tests passed status-only errors, frozen-frame hiding and recovery in addition to anchor/camera/hand gesture checks. Full desktop/network suite passed after the changes.
- Native source now exposes display-geometry refresh and caps CPU camera width near 640 px. Android starts at 75% 3D resolution with compositor off. These source changes have not yet been compiled or validated on a physical device.


## Closed-fist controls update

- Replaced webcam pinch-to-hit with open-palm-to-closed-fist hit events. Four open samples arm the action; three closed-fist samples trigger one hit, with cooldown and no repeat while held. Tracking loss disarms it. Thumb/index distance is no longer used.
- Phone gameplay now classifies the supplied landmarks as open/fist and requires two distinct camera-image samples for each transition. The native landmark plugin is retained; a new Android export is needed to include the changed gameplay logic.
- Updated HUD, launcher and guide: return to the neutral position or remove the hand to stop without attempting a hit.

## Neon Volley update - October 13, 2026

- Updated the actual `.tools/hand-venv` successfully: OpenCV contrib 4.11.0.86, NumPy 1.26.4, MediaPipe 0.10.21 and compatible JAX dependencies. `pip check` reports no broken requirements. The first download timed out; the retry with a longer timeout succeeded.
- Bundled `hand_landmarker.task` loaded through MediaPipe Python VIDEO mode and ran three blank frames with no false hand detections. Synthetic controller tests also passed using this updated virtual environment. No real webcam images were captured for this check.

- Converted the scene to an original procedural volleyball arena with landscape HUD, teal/coral halves, net, stands, ball bands/trail, landing marker and sound cues. Vulkan Mobile preview rendered and was visually inspected; refreshed `build/desktop-preview.png` and effects-off preview.
- Godot suite passed after conversion: six avatar animations including Hit; court movement/jump/run; valid serve trajectory clearing the net; net rebound; floor/out scoring; first-to-seven win/reset; half-court bounds; AI roster activation; synthetic phone AR pose/anchor/camera and pinch-to-hit.
- Two actual ENet processes passed host/client spawn, authoritative avatar movement, appearance, ball replication and AI replacement. Disconnect cleanup also passed. Physical two-device LAN remains untested.
- Replaced color-mask control with OpenCV webcam capture and MediaPipe 21-landmark inference. Synthetic landmark tests passed neutral calibration, neutral jitter rejection, open-palm clutch, closed/lost-hand stop, pinch release/debounce/cooldown and invalid landmark rejection. Live webcam accuracy still requires the user's hand/camera.
- OpenCV bridge passed local movement/event input, deduplicated hit actions, malformed/stale packet handling, in-game JPEG preview decoding and outgoing calibration command.
- Android native ARCore/MediaPipe source is retained; phone pinch now serves/hits. No new APK export is claimed. `build/PocketTerrainAR.apk` remains the original October 5 terrain build; missing SDK packages must be installed before exporting Neon Volley. Physical phone AR/orientation/tracking/performance remains untested.
- Godot's sandbox certificate-store diagnostic persists. Desktop rendering and local gameplay/network checks pass despite it.

Earlier records below describe the terrain project before the volleyball conversion.

## Tutorial 2 update — October 12, 2026

- `python tools/run_checks.py` passed: original terrain/avatar checks, synthetic AR bridge checks, new OpenCV UDP bridge checks and two real loopback ENet peers. Multiplayer verified remote spawn, server-simulated client movement, appearance replication (color/visual scale) and disconnect removal. Test startup waits for host readiness and caps frame rate to avoid headless CPU contention.
- OpenCV bridge verified open-to-fist jump across neutral frames, one jump per close, movement, malformed packet rejection and stale input clearing.
- `python tests/opencv_checks.py` passed synthetic empty/full-mask rejection, contour centroid and open/fist shape classification. These checks use constructed masks, not webcam footage.
- Vulkan Mobile preview rendered successfully after UI changes, with refreshed `build/desktop-preview.png` and effects-off screenshot.
- Installed Python environment has OpenCV 4.13.0 / NumPy 2.4.3; the reproducible webcam requirements target OpenCV 4.12.0.88 / NumPy 2.2.6. Live webcam accuracy and the pinned fresh environment have not been verified.
- New Android export attempted and failed: `.tools/android-sdk` lacks platform-tools/build-tools; SDK download failed to fetch manifests. **The existing APK remains the original October 5 build and contains none of the new source features.** Rebuild with SDK packages and accepted SDK licenses before demonstrating multiplayer on Android.
- Physical phone AR, native inference, two-device LAN behavior, live webcam segmentation and tracking accuracy still need hardware acceptance. Passing synthetic tests does not establish those results.
- Godot prints a certificate-store diagnostic in this sandbox. Offline desktop rendering and local input/network tests passed despite it.

The older validation record below describes the original implementation and APK.

Godot version: 4.5.1 stable. Desktop GPU: AMD Radeon integrated graphics, Vulkan 1.3, Mobile renderer.

Completed checks:

- Final debug APK exported successfully: `build/PocketTerrainAR.apk`, package `org.pocketterrain.demo`, ARM64, min SDK 26, target SDK 35. Android `apksigner verify --verbose` confirms APK Signature Scheme v2. ZIP integrity passed. APK includes the hand model, ARCore and MediaPipe native libraries, Godot scene resources, camera permission and plugin metadata; local build tools are excluded.

- Native ARCore + MediaPipe Android library compiled successfully with Gradle; final incremental build passed after the lifecycle fix. AAR includes `assets/hand_landmarker.task` and plugin manifest.
- `tests/demo_checks.gd` passed: imported heightmap, terrain collider, five animation resources, walk/run transitions, jump height and landing, Wave recovery, island bounds, and calibrated off-center frustum projection.
- `tests/ar_bridge_checks.gd` passed with **synthetic tracking input**: center anchor request, JPEG decoding, 0.09 island scale, 21-landmark overlay, single jump per pinch, release/rearm, tracking loss and recovery. This does not test native phone sensors.
- Real Vulkan Mobile renderer executed the compositor with no shader, pipeline or texture-usage errors after changing the effect to two raster passes. Effects-on/off screenshots were captured; pixel assertions confirm visible terrain over the camera and a rendered change when toggling effects.
- Synthetic camera background was visually checked: the virtual island remains visible over the background. The AR camera layer is integrated through `Environment.BG_CANVAS`.
- ADB reported **no connected Android devices**. Hardware ARCore plane finding, camera permissions, camera alignment, native hand inference and pause/resume still require a phone test.

The sandbox's Godot launch prints a system certificate-store diagnostic; the offline scene and tests run successfully. The project's camera inference runs locally and does not depend on that store.

Re-run desktop checks with the bundled engine:

```powershell
$env:APPDATA = "$PWD/.tools/user"
$env:LOCALAPPDATA = $env:APPDATA
& ./.tools/godot/Godot_v4.5.1-stable_win64_console.exe --headless --path . --log-file .tools/tests.log --script tests/demo_checks.gd
& ./.tools/godot/Godot_v4.5.1-stable_win64_console.exe --path . --log-file .tools/ar-tests.log --script tests/ar_bridge_checks.gd
```

Preview artifacts: `build/desktop-preview.png`, `build/desktop-preview-no-effects.png`, `build/synthetic-camera-check.png` and `build/synthetic-camera-no-effects.png`. Synthetic camera artifacts are labeled TEST INPUT.
