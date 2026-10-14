"""Deterministic landmark control checks; not a claim of webcam accuracy."""
from pathlib import Path
import sys
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.opencv_hand import HandController

p = np.zeros((21, 2))
p[0] = [.5, .85]
for base, x in [(5,.36),(9,.48),(13,.6),(17,.7)]:
    p[base] = [x,.65]
    p[base+1] = [x,.5]
    p[base+2] = [x,.35]
    p[base+3] = [x,.2]
p[1:5] = [[.4,.8],[.3,.7],[.2,.65],[.1,.6]]
c = HandController()
assert c.update(p, 0)['x'] == 0 and c.center is None
c.calibrate()
for i in range(16):
    packet = c.update(p, i / 30)
assert c.center is not None and packet['calibrated']
for i in range(30):
    noise = .008 * np.sin(i)
    packet = c.update(p + noise, 1 + i / 30)
    assert packet['x'] == packet['y'] == 0, 'Neutral jitter must not move avatar'
for i in range(20):
    packet = c.update(p + [.14, 0], 2 + i / 30)
assert packet['x'] > .6 and packet['y'] == 0
closed = p.copy()
for tip in [8,12,16,20]:
    closed[tip] = [.5,.72]
assert c.update(closed, 3)['x'] == 0, 'Closed palm must stop movement immediately'
for i in range(12):
    c.update(p, 4 + i / 30)
fist = closed.copy()
uncalibrated = HandController()
for i in range(10):
    assert uncalibrated.update(fist, i / 30)['hit_id'] == 0
# A partly curled hand must neither hit nor be treated as an open-palm release.
partial = p.copy()
partial[8] = partial[12] = [.5, .72]
for i in range(5):
    assert c.update(partial, 4.5 + i / 30)['hit_id'] == 0
for i in range(8):
    packet = c.update(fist, 5 + i / 30)
assert packet['hit_id'] == 1 and packet['x'] == packet['y'] == 0
for i in range(20):
    assert c.update(fist, 6 + i / 30)['hit_id'] == 1
lost = c.update(None, 7)
assert lost['x'] == lost['y'] == 0 and not lost['tracked']
for i in range(10):
    assert c.update(fist, 8 + i / 30)['hit_id'] == 1, 'Hand loss must not rearm a held fist'
for i in range(8):
    c.update(p, 9 + i / 30)
for i in range(8):
    packet = c.update(fist, 10 + i / 30)
assert packet['hit_id'] == 2
assert not c.update(np.full((21, 2), np.nan), 11)['tracked']
assert not c.update(np.zeros((21, 2)), 12)['tracked']
print('PASS: neutral calibration, jitter dead zone, clutch movement, closed/lost-hand stop, fist debounce/rearm, invalid landmark rejection')
