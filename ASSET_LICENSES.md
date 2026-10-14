# Third-party assets and dependencies

Original generated assets: `assets/heightmap.png`, explorer mesh, tree meshes and material shaders were created for this project. No external character or environment artwork is used.

Neon Volley additions: court/stands/net geometry, ball/bands/trail/landing marker, jersey colors, volleyball SVG icon and synthesized hit/point tones are original procedural assets. Desktop tracking uses OpenCV contrib (Apache-2.0, https://github.com/opencv/opencv/blob/4.x/LICENSE) and MediaPipe Python with the same bundled Google hand model.

- Google MediaPipe Hand Landmarker model: official Google-hosted model bundle, version float16/1; retrieved by `tools/download_tools.py`. Documentation/model overview: https://ai.google.dev/edge/mediapipe/solutions/vision/hand_landmarker#models. Review Google's model terms before redistribution.
- MediaPipe Tasks Vision 0.10.21: Apache-2.0 project, https://github.com/google-ai-edge/mediapipe/blob/master/LICENSE.
- Google ARCore Android SDK 1.48.0: https://github.com/google-ar/arcore-android-sdk and its SDK terms/notices. Maven dependency remains governed by Google's terms.
- Godot 4.5.1: MIT, https://godotengine.org/license/. Preserve the engine license in distributed builds.
- Local build tooling: Eclipse Temurin JDK 17, Gradle 8.9, Android SDK. These are not included as game assets.
