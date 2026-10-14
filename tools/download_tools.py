"""Download pinned official tools into the project, without system installation."""
import concurrent.futures
import urllib.request
import zipfile
import socket
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / '.tools'
TOOLS.mkdir(exist_ok=True)
socket.setdefaulttimeout(45)
downloads = {
    'godot.zip': 'https://github.com/godotengine/godot/releases/download/4.5.1-stable/Godot_v4.5.1-stable_win64.exe.zip',
    'jdk.zip': 'https://aka.ms/download-jdk/microsoft-jdk-17.0.16-windows-x64.zip',
    'gradle.zip': 'https://services.gradle.org/distributions/gradle-8.9-bin.zip',
    'sdk.zip': 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip',
}
if (Path('C:/Program Files/Eclipse Adoptium/jdk-17.0.13.11-hotspot/bin/java.exe').exists()):
    downloads.pop('jdk.zip')
    print('Using installed Java 17', flush=True)

def fetch(item):
    filename, url = item
    path = TOOLS / filename
    if not path.exists() or not zipfile.is_zipfile(path):
        print('Downloading ' + filename, flush=True)
        urllib.request.urlretrieve(url, path)
    destination = TOOLS / filename.removesuffix('.zip')
    if not destination.exists():
        destination.mkdir()
        with zipfile.ZipFile(path) as archive:
            archive.extractall(destination)
    print('Ready: ' + filename, flush=True)

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    list(pool.map(fetch, downloads.items()))
model = ROOT / 'native/pocket-ar/src/main/assets/hand_landmarker.task'
model.parent.mkdir(parents=True, exist_ok=True)
if not model.exists():
    urllib.request.urlretrieve('https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task', model)
print('Ready: MediaPipe hand model', flush=True)
