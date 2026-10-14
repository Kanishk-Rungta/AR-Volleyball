"""Load the shipped model and run blank VIDEO frames without opening a webcam."""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
os.environ.setdefault('MPLCONFIGDIR', str(ROOT / '.tools/matplotlib'))

import cv2
import mediapipe as mp
import numpy as np

options = mp.tasks.vision.HandLandmarkerOptions(
    base_options=mp.tasks.BaseOptions(model_asset_path=str(ROOT / 'native/pocket-ar/src/main/assets/hand_landmarker.task')),
    running_mode=mp.tasks.vision.RunningMode.VIDEO,
    num_hands=1,
    min_hand_detection_confidence=0.7,
    min_hand_presence_confidence=0.7,
    min_tracking_confidence=0.7,
)
with mp.tasks.vision.HandLandmarker.create_from_options(options) as detector:
    frame = mp.Image(image_format=mp.ImageFormat.SRGB, data=np.zeros((480, 640, 3), dtype=np.uint8))
    for stamp in [1000, 1033, 1066]:
        assert not detector.detect_for_video(frame, stamp).hand_landmarks
print('PASS: shipped model VIDEO inference and blank-frame rejection; OpenCV', cv2.__version__)
