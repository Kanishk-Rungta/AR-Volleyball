# Neon Volley AR - Tutorial 2 run and showcase guide

For your Samsung Galaxy M31s, start with **[MOBILE_AR_GUIDE.md](MOBILE_AR_GUIDE.md)** and the new **Build Android AR.cmd / Install Android AR.cmd** launchers. The new Android output is `build/NeonVolleyAR.apk`; the older `PocketTerrainAR.apk` remains the terrain demo.

On Android 2.3, aim at a table or floor and use **Place without scan** if the ring remains yellow. This places an approximate horizontal court; keep the phone roughly still for touch gameplay. Use **Place court** with a green ring for detected-plane anchoring. Approximate placement is not a verified real-world surface measurement.

## What the project is now

A tabletop arcade volleyball arena, with teal/coral teams, a net, a visible ball trail and landing ring, hit animations, sound cues, point scoring and first-to-seven matches. Practice starts with an AI opponent. A LAN player takes the opponent's place. This is a simplified teaching game: one return per team, assisted shots and no official rotation or three-touch rules.

| Feature | Purpose in the game |
| --- | --- |
| Mobile AR | Place the court on a real table, move around it and play using touch or rear-camera fist gestures |
| OpenCV + hand tracking | OpenCV captures/displays the webcam; MediaPipe detects 21 landmarks; calibrated palm motion moves the avatar and a closed fist serves/returns the ball |
| Multiplayer | Host and join a LAN match with separate avatars and shared ball, score and rally state |
| Avatar operations | Move, sprint, jump, strike, wave, change kit color and visual size |
| Compositor | Toggle the existing GPU color grading effect |
| Heightmap | View the original heightmap in the Terrain Lab; gameplay uses a flat court |

The old skin-color contour controller has been replaced. You no longer sample a skin color, use a pink box or make a fist to jump. The new controls use actual hand landmarks, a neutral-position calibration, smoothing, hysteresis, an open-palm clutch, explicit tracking loss and debounced fist events. A fist stops movement and attempts one hit; Space/touch performs jumping.

## 1. Run with keyboard first

Double-click **Run Desktop Demo.cmd**, or open `project.godot` in Godot 4.5.1 and press F5. The project now opens in a landscape window.

You are **teal**, on the near half. The coral opponent is AI until another player joins.

| Control | Action |
| --- | --- |
| WASD / arrows / touch pad | Move on your half of the court |
| F / HIT-SERVE button | Serve when it is your turn, or return a nearby ball |
| Space / JUMP button | Jump; you can hit while airborne |
| Shift / hold RUN | Sprint |
| C / Center button | Calibrate webcam neutral position, with tracker running |
| E / Effects | Toggle compositor grading |
| Kit / Size / Wave | Customize or gesture with the avatar |
| New match | Reset score and rally; controlled by host in LAN games |

Press **F** to serve. The AI returns the ball. Follow the **gold landing ring**, move underneath the ball, and press **F** when it is close. The return reach is intentionally forgiving: about 1.5 court units horizontally and up to 2.6 units above your feet. A hit is accepted only after the other team last touched the ball. Stay on your side; you cannot cross the net.

A ball landing on your half gives the other team a point. An out-of-bounds shot gives the other team a point relative to its last hitter. Low shots rebound from the net. The point winner serves next after a short pause. **First to 7 wins**; click New match to play again.

Buttons do not receive arrow/Space focus. Typing in the host address field does not move the avatar; click a game button to leave text editing.

## 2. Update the webcam environment once

The new landmark controller needs updated packages. The old OpenCV-only environment is insufficient. From PowerShell in the project folder, if you need to set up or repair it:

**This workspace's virtual environment has already been updated, and the bundled model passed its load/inference check. You can go straight to the launcher.** Use the commands below on another PC or to repair the environment.

```powershell
python -m venv .tools/hand-venv
& ./.tools/hand-venv/Scripts/python.exe -m pip uninstall -y opencv-python
& ./.tools/hand-venv/Scripts/python.exe -m pip install -r tools/requirements-hand.txt
```

The OpenCV contrib package supplies `cv2`; removing the separate `opencv-python` package avoids two packages competing for that module. Use Python 3.11. The hand model is already included at `native/pocket-ar/src/main/assets/hand_landmarker.task`. No model download is needed during play, and camera images stay on your PC.

## 3. Launch and use hand controls

1. Close older game/tracker windows, then double-click **Run OpenCV Hand Tracking.cmd**. It starts the arena and tracker together and enables hand input. Only one game should enable webcam input at a time.
2. Show **one whole hand**, with fingers and wrist visible, at a comfortable distance. You should see a 21-point skeleton in the camera window and the live preview inside the game.
3. Hold your hand at the position you want to mean **stop**, and press **C** in the game or camera window, or click **Center [C]**. Hold still for about half a second until calibration completes. This calibrates position, not skin color.
4. **Open your palm** and move it left/right/up/down relative to that center. Movement begins outside the neutral box. Return to the box to stop. Keyboard directions and hand directions follow the court; right means screen-right in the default desktop view.
5. **Return to the center or remove your hand to stop without hitting.** Closing into a fist stops movement and attempts a hit. A held fist does not repeatedly hit; reopen at the center to resume control.
6. To **serve or hit**, show an open palm briefly, then fold your fingers into a **closed fist**. Hold for about 0.2 seconds. One close triggers one attempt; a held fist never repeatedly strikes. Open your palm again before another hit. If the ball is too far away or it is not your turn, the game ignores the attempt.
7. Use **Space** or the JUMP button to jump. A closed fist is a volleyball hit, not a jump.
8. Press **Q in the camera window** to stop the tracker. Close the game separately.

Do not calibrate while your hand is moving. The tracker rejects unstable calibration; hold still or retry C. Keep the same camera position after calibrating. If your posture changes, recalibrate.

The game includes the camera preview, so you can keep the arena focused and use its Center button. The external camera window remains useful for debugging and Q-to-exit. To use another camera, run the tracker manually:

```powershell
& ./.tools/hand-venv/Scripts/python.exe tools/opencv_hand.py --camera 1
```

For manual startup, start the desktop game, enable **Hands on/off**, then run the tracker. Do not launch a second tracker alongside the combined launcher.

## 4. Play multiplayer

### Two windows on one PC

1. Open two desktop games. Click **Host** in the first.
2. In the second keep `127.0.0.1` and click **Join**.
3. The host is teal; the joining player is coral. The AI disappears. Both windows show the same ball and score.
4. Teal presses F or close fistes to serve. Switch between windows or use keyboard in one and hand tracking in the other. Enable webcam input in **only one** window.
5. Take turns getting underneath the ball and returning it. Customize Kit/Size and demonstrate that changes appear in both windows.
6. Click Leave in the client: the AI comes back. Rejoin to demonstrate roster recovery. If the host leaves, clients return to a fresh offline practice game.

### Two computers or PC + phone

1. Use the same private Wi-Fi. On the host PC, run `ipconfig` and find the Wi-Fi IPv4 address, for example `192.168.1.25`.
2. Host the game and allow Godot through Windows Firewall on the private network. Networking uses **UDP 7777**.
3. On the second device enter that LAN IP and Join. `127.0.0.1` only refers to the same machine.
4. On Android, place the local AR court before playing. Avatars and the ball are visible only while the court is placed and AR tracking is valid.

Up to eight players including host are supported; new players are assigned to the less-populated side. The first joining player replaces the practice opponent. All teammates share their side's turn; this is an arcade team rally. The host simulates avatars, ball, scores and match state; clients submit actions and movement, not ball positions. No internet matchmaking, accounts or host migration are included.

Each phone uses its own local ARCore anchor. They share court-local match coordinates, not a physically aligned shared AR anchor. Place both courts similarly if demonstrating two phones.

## 5. Phone AR and building Android

**The current `build/NeonVolleyAR.apk` is ready to install and was verified October 14.** You can copy it to your phone and open it in My Files, or use Install Android AR.cmd. No rebuild is needed to try the current game. `build/PocketTerrainAR.apk` is the old terrain demo. See MOBILE_AR_GUIDE.md for the phone steps and VALIDATION.md for verification details.

With internet access and accepted Android SDK licenses:

```powershell
python tools/download_tools.py
python tools/download_android_templates.py
powershell -ExecutionPolicy Bypass -File tools/build_android.ps1 -InstallSdk -ExportApk
```

Read and accept the SDK licenses when prompted. An existing toolchain can be selected with `JAVA_HOME` (JDK 17) and `ANDROID_HOME`. The export uses Godot 4.5.1 templates, ARM64, API 26 minimum and API 35 target. The Android package ID stays `org.pocketterrain.demo` so you can update the original install; the display name is Neon Volley AR.

Install the rebuilt APK by copying it to the phone and opening it, or:

```powershell
& "$env:ANDROID_HOME/platform-tools/adb.exe" devices
& "$env:ANDROID_HOME/platform-tools/adb.exe" install -r build/NeonVolleyAR.apk
```

Use an ARCore-supported phone with Vulkan support. Allow camera access and install/update Google Play Services for AR if asked. Hold the phone in landscape, scan a textured table slowly in good light, aim the center reticle, then tap **Place AR court**. The model is roughly 0.83 by 0.97 metres including its stands. Walk around the anchored arena, move using the touch pad, and use HIT/Jump/Run.

For native phone hand control, show a hand to the **rear camera**, first show an open palm, then close your fist to hit. This uses the existing on-device MediaPipe integration. Desktop OpenCV is demonstrated with the PC webcam; it does not open a second camera on Android.

## 6. Troubleshooting

| Symptom | What to do |
| --- | --- |
| No skeleton | Ensure the whole hand is visible, improve lighting, close other webcam apps or try camera 1 |
| Avatar moves at your resting pose | Press C again with the palm at your actual comfortable neutral position; hold still |
| Hand moves but avatar does not | Finish Center calibration, open at least three fingers, then move outside the center dead zone |
| Fist does nothing | Open your palm first, close your fingers, hold briefly; check your serving turn and ball proximity |
| A held fist causes repeated attempts | Report it; event IDs, release gating and cooldown are intended to prevent this |
| Preview/bind error | Close other OpenCV-enabled game/tracker instances; local ports 4242/4243/4244 must be available |
| Join times out | Check host IP, UDP 7777 firewall rule and Wi-Fi client isolation |
| Phone has no court | Place it on a detected plane and recover AR tracking; rebuilding is required to get the volleyball UI |
| New match has no effect as a client | The host controls match resets |

## 7. Showcase in 6-8 minutes

| Time | Demonstration |
| --- | --- |
| 0:00-1:00 | Show the new court, serve against AI, follow the landing ring and explain scoring |
| 1:00-2:00 | Walk/run/jump/hit, change kit and size, show the hit animation |
| 2:00-4:00 | Launch webcam controller, calibrate, show the in-game skeleton preview, neutral stop, open-palm movement, neutral stop and fist-to-hit |
| 4:00-5:30 | Join a second window/device; AI disappears; demonstrate a shared rally, score and appearance; leave and rejoin |
| 5:30-7:00 | On a rebuilt phone app, place the arena on a table, move around it, join the host and return the ball |
| 7:00-8:00 | Toggle Effects, open Heightmap/Terrain Lab and explain local AR anchors versus shared match state |

## 8. Verification and code map

```powershell
python tools/run_checks.py
& ./.tools/hand-venv/Scripts/python.exe tests/opencv_checks.py
& ./.tools/hand-venv/Scripts/python.exe tests/hand_model_checks.py
```

The Godot suite covers movement/animations, serving, net collisions, scoring, out penalties, match completion/reset, court boundaries, synthetic phone AR data, local webcam UDP commands and two actual ENet peers. The Python suite checks neutral calibration, jitter rejection, clutch stop, missing/invalid hands and fist debounce using synthetic landmarks. These are not measurements of live camera accuracy. Try your own camera and phone before class.

| File | Responsibility |
| --- | --- |
| `scripts/main.gd` | Landscape HUD, touch/keyboard controls, webcam preview and native AR consumption |
| `scripts/volleyball_court.gd` | Court, net, markings, stands and original procedural arena art |
| `scripts/volleyball.gd` | Ball physics, serving, hits, AI, landing marker, score and sound |
| `scripts/session.gd` | Host/join, team roster, authoritative input/actions and match snapshots |
| `scripts/player.gd` | Avatar movement, animations, court boundaries and appearance |
| `scripts/opencv_bridge.gd` | Validated input events, preview JPEGs and calibration commands |
| `tools/opencv_hand.py` | OpenCV webcam plus MediaPipe landmarks and stable hand controller |

Implementation references: [MediaPipe Python hand landmarking](https://developers.google.com/edge/mediapipe/solutions/vision/hand_landmarker/python), [Godot multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html).
