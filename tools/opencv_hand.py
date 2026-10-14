"""OpenCV webcam + MediaPipe landmark controller for Neon Volley (local only)."""
import argparse
import json
from pathlib import Path
import socket
import time
import uuid

import cv2
import numpy as np

CONNECTIONS = [(0,1),(1,2),(2,3),(3,4),(0,5),(5,6),(6,7),(7,8),(5,9),
               (9,10),(10,11),(11,12),(9,13),(13,14),(14,15),(15,16),
               (13,17),(0,17),(17,18),(18,19),(19,20)]


class HandController:
    """Explicit neutral calibration, open-palm clutch and debounced closed-fist events."""
    def __init__(self):
        self.center = None
        self.samples = None
        self.previous = None
        self.smooth = None
        self.axis = np.zeros(2)
        self.valid_frames = 0
        self.release_frames = 0
        self.fist_frames = 0
        self.armed = False
        self.hit_id = 0
        self.last_hit = -10.0
        self.status = 'Show one palm, then press C / Center'

    def calibrate(self):
        self.samples = []
        self.center = None
        self.axis[:] = 0
        self.armed = False
        self.status = 'Hold palm still: centering...'

    def update(self, points, now, aspect=4/3):
        packet = dict(source='opencv', protocol=2, x=0.0, y=0.0, tracked=False,
                      calibrated=self.center is not None, hit_id=self.hit_id, gesture='none')
        if points is None or np.shape(points) != (21, 2) or not np.isfinite(points).all():
            self.valid_frames = self.release_frames = self.fist_frames = 0
            self.armed = False
            self.previous = self.smooth = None
            self.axis[:] = 0
            if self.samples is not None:
                self.samples.clear()
            self.status = 'Hand lost: movement stopped / show palm'
            return packet
        points = np.asarray(points, dtype=float)
        palm = points[[0, 5, 9, 13, 17]].mean(axis=0)
        pixels = points * [aspect, 1]
        span = np.linalg.norm(pixels[5] - pixels[17])
        if span < 0.035:
            return self.update(None, now, aspect)
        if self.previous is not None and np.linalg.norm(palm - self.previous) > 0.18:
            self.valid_frames = 0
            self.axis[:] = 0
            self.smooth = palm.copy()
            self.armed = False
            self.release_frames = self.fist_frames = 0
        self.previous = palm
        self.valid_frames += 1
        packet['tracked'] = True
        if self.samples is not None:
            self.samples.append(palm)
            if len(self.samples) >= 15:
                samples = np.array(self.samples[-15:])
                if samples.std(axis=0).max() < 0.025:
                    self.center = np.median(samples, axis=0)
                    self.smooth = self.center.copy()
                    self.samples = None
                else:
                    self.status = 'Hold still while centering...'
            packet['calibrated'] = self.center is not None
            return packet
        if self.center is None or self.valid_frames < 5:
            self.status = 'Press C / Center with palm in comfortable neutral position'
            return packet
        def extended(tip, joint):
            return np.linalg.norm(pixels[tip] - pixels[0]) > np.linalg.norm(pixels[joint] - pixels[0]) * 1.12
        fingers = [extended(tip, joint) for tip, joint in [(8,6),(12,10),(16,14),(20,18)]]
        opened = sum(fingers) >= 3
        fist = sum(fingers) <= 1
        if opened:
            self.release_frames += 1
            self.fist_frames = 0
            if self.release_frames >= 4:
                self.armed = True
        elif fist:
            self.release_frames = 0
            self.fist_frames += 1
            if self.armed and self.fist_frames >= 3 and now - self.last_hit >= 0.65:
                self.hit_id += 1
                self.last_hit = now
                self.armed = False
        else:
            self.release_frames = self.fist_frames = 0
        packet['hit_id'] = self.hit_id
        self.smooth = palm.copy() if self.smooth is None else self.smooth * 0.75 + palm * 0.25
        offset = self.smooth - self.center
        for i in range(2):
            if not opened or abs(offset[i]) < 0.045:
                self.axis[i] = 0
            elif abs(offset[i]) > 0.08:
                self.axis[i] = np.sign(offset[i]) * 0.7
        packet.update(x=float(self.axis[0]), y=float(self.axis[1]), gesture='fist' if fist else 'open' if opened else 'neutral')
        self.status = 'FIST / HIT - reopen to rearm' if fist else 'OPEN / move away from center' if opened else 'CLOSED / movement stopped'
        return packet


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--camera', type=int, default=0)
    parser.add_argument('--port', type=int, default=4242)
    args = parser.parse_args()
    try:
        import mediapipe as mp
    except ImportError:
        raise SystemExit('Update dependencies: .tools/hand-venv/Scripts/python.exe -m pip install -r tools/requirements-hand.txt')
    model = Path(__file__).resolve().parents[1] / 'native/pocket-ar/src/main/assets/hand_landmarker.task'
    if not model.exists():
        raise SystemExit('Hand model missing. Run python tools/download_tools.py first.')
    options = mp.tasks.vision.HandLandmarkerOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=str(model)),
        running_mode=mp.tasks.vision.RunningMode.VIDEO, num_hands=1,
        min_hand_detection_confidence=0.7, min_hand_presence_confidence=0.7,
        min_tracking_confidence=0.7)
    detector = mp.tasks.vision.HandLandmarker.create_from_options(options)
    cap = cv2.VideoCapture(args.camera)
    if not cap.isOpened():
        detector.close()
        raise SystemExit('Cannot open webcam. Close other camera apps or try --camera 1.')
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    commands = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        commands.bind(('127.0.0.1', 4244))
    except OSError:
        cap.release(); detector.close(); sock.close(); commands.close()
        raise SystemExit('Tracker already running: close its camera window before launching another.')
    commands.setblocking(False)
    controller = HandController()
    token = uuid.uuid4().hex
    last_preview = 0
    timestamp = 0
    print('Show one palm. Press C in the camera/game or click Center. Open palm moves; close fist hits.')
    try:
        while True:
            ok, image = cap.read()
            if not ok:
                raise RuntimeError('Webcam stopped delivering frames')
            image = cv2.flip(image, 1)
            height, width = image.shape[:2]
            now = time.monotonic()
            timestamp = max(timestamp + 1, int(now * 1000))
            rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            result = detector.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), timestamp)
            points = None
            if result.hand_landmarks:
                points = np.array([[p.x, p.y] for p in result.hand_landmarks[0]])
            try:
                for _ in range(10):
                    command = commands.recv(100)
                    if command == b'center':
                        controller.calibrate()
            except BlockingIOError:
                pass
            packet = controller.update(points, now, width / height)
            packet['token'] = token
            packet['status'] = controller.status
            sock.sendto(json.dumps(packet).encode(), ('127.0.0.1', args.port))
            if points is not None:
                screen = (points * [width, height]).astype(int)
                for a, b in CONNECTIONS:
                    cv2.line(image, tuple(screen[a]), tuple(screen[b]), (150, 235, 60), 2)
                for p in screen:
                    cv2.circle(image, tuple(p), 3, (240, 240, 255), -1)
            if controller.center is not None:
                cx, cy = (controller.center * [width, height]).astype(int)
                cv2.rectangle(image, (cx-int(width*.08), cy-int(height*.08)), (cx+int(width*.08), cy+int(height*.08)), (180, 190, 60), 2)
                cv2.circle(image, (cx, cy), 5, (255, 200, 30), -1)
            cv2.putText(image, 'NEON VOLLEY / C: center / Q: quit', (12, 24), 0, 0.55, (240, 245, 255), 1)
            cv2.putText(image, controller.status, (12, height-20), 0, 0.48, (240, 245, 255), 1)
            cv2.imshow('Neon Volley / hand camera', image)
            if now - last_preview > 0.1:
                ok, encoded = cv2.imencode('.jpg', cv2.resize(image, (320, 240)), [cv2.IMWRITE_JPEG_QUALITY, 65])
                if ok and len(encoded) < 60000:
                    sock.sendto(encoded.tobytes(), ('127.0.0.1', 4243))
                last_preview = now
            key = cv2.waitKey(1) & 255
            if key == ord('q') or cv2.getWindowProperty('Neon Volley / hand camera', cv2.WND_PROP_VISIBLE) < 1:
                break
            if key == ord('c'):
                controller.calibrate()
    finally:
        sock.sendto(json.dumps(dict(source='opencv', protocol=2, tracked=False, calibrated=False,
                                   x=0, y=0, hit_id=controller.hit_id, token=token)).encode(), ('127.0.0.1', args.port))
        cap.release(); detector.close(); sock.close(); commands.close()
        cv2.destroyAllWindows()


if __name__ == '__main__':
    main()
