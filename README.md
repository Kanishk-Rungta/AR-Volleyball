# Neon Volley AR

**Current Android build: 2.3.** Includes the verified blank-camera fix, more forgiving surface bounds, and **Place without scan** for approximate placement on a floor/table without waiting for a green ring. Keep **Camera: Safe** and **Hand hits: OFF** initially. Approximate placement may drift; detected-plane placement gives better anchoring. APK: `build/NeonVolleyAR.apk`.

**Mobile AR on your Galaxy M31s:** see [MOBILE_AR_GUIDE.md](MOBILE_AR_GUIDE.md). Run **Build Android AR.cmd**, review the SDK licenses, then connect the phone and run **Install Android AR.cmd**. The new output is `build/NeonVolleyAR.apk`.

A Godot 4.5.1 arcade volleyball project for Tutorial 2: tabletop Android AR, webcam hand controls, LAN multiplayer and animated/customizable avatars.

**Start playing:** double-click **Run Desktop Demo.cmd**. WASD/arrows move, Shift runs, Space jumps and **F serves/hits**. Play first-to-seven against AI; follow the gold landing ring to return the ball.

**Hand controls:** double-click **Run OpenCV Hand Tracking.cmd** after installing the updated `tools/requirements-hand.txt` into `.tools/hand-venv`. It opens the game and tracker together, enables hand input and shows the webcam inside the arena. Show one palm, press **C / Center**, hold still briefly, then use an open palm to move and close your fist to hit. Closing the hand stops movement and attempts one hit; reopen to rearm. This replaces the unreliable skin-color contour controller with OpenCV capture and MediaPipe's 21-landmark detection.

**Multiplayer:** Host in one window, Join `127.0.0.1` in another, or enter the host's LAN IP on another device. The host owns ball physics, avatar motion and score. A human opponent replaces the AI. Networking uses UDP 7777; camera/control traffic stays on localhost ports 4242-4244.

**Phone AR:** the native ARCore integration is retained. Place the volleyball arena on a table and use touch controls or rear-camera fist-to-hit. Each phone independently places its own local anchor; match coordinates are synchronized. Android requires an ARCore/Vulkan-capable ARM64 phone.

**Ready-to-install Android APK:** [build/NeonVolleyAR.apk](build/NeonVolleyAR.apk), about 98 MB, verified October 14. Copy it to your Galaxy M31s and install from My Files, or use **Install Android AR.cmd** with USB debugging. The older `PocketTerrainAR.apk` is the terrain demo. Actual phone AR testing remains pending; see [MOBILE_AR_GUIDE.md](MOBILE_AR_GUIDE.md).

See **[SHOWCASE_GUIDE.md](SHOWCASE_GUIDE.md)** for complete setup, exact hand controls, gameplay, multiplayer, Android builds, troubleshooting and a timed presentation sequence. See **[VALIDATION.md](VALIDATION.md)** for checks performed and hardware limitations.

```powershell
python tools/run_checks.py
& ./.tools/hand-venv/Scripts/python.exe tests/opencv_checks.py
```

All court/avatar art is procedural and original. Existing heightmap assets and compositor remain available through the UI. Source includes the Android ARCore/MediaPipe plugin and bundled hand model; see ASSET_LICENSES.md.
