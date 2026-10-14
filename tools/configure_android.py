"""Configure only the bundled Godot editor; leave global editor settings untouched."""
import os
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
tools = root / '.tools'
editor = tools / 'godot/editor_data'
templates = editor / 'export_templates/4.5.1.stable'
build = root / 'android/build'
if not (build / 'build.gradle').exists():
    with zipfile.ZipFile(templates / 'android_source.zip') as archive:
        archive.extractall(build)
(root / 'android/.build_version').write_text('4.5.1.stable')
(build / '.gdignore').touch()
# Keep D8/Gradle within a modest laptop's memory budget.
properties = build / 'gradle.properties'
import re
text = re.sub(r'org.gradle.jvmargs=.*', 'org.gradle.jvmargs=-Xmx1536m -XX:MaxMetaspaceSize=512m -XX:ReservedCodeCacheSize=256m', properties.read_text())
text = re.sub(r'^org\.gradle\.(workers\.max|parallel)=.*\n?', '', text, flags=re.MULTILINE)
text += '\norg.gradle.workers.max=2\norg.gradle.parallel=false\n'
properties.write_text(text)
# Use the already downloaded compatible Gradle distribution instead of making
# the Java wrapper fetch another distribution over the network.
wrapper = build / 'gradle/wrapper/gradle-wrapper.properties'
if (tools / 'gradle.zip').exists():
    lines = wrapper.read_text().splitlines()
    wrapper.write_text('\n'.join('distributionUrl=' + (tools / 'gradle.zip').as_uri() if line.startswith('distributionUrl=') else line for line in lines) + '\n')
jdk = os.environ.get('JAVA_HOME', '')
if not jdk:
    candidates = list((tools / 'jdk').glob('*')) if (tools / 'jdk').exists() else []
    candidates += list(Path('C:/Program Files/Eclipse Adoptium').glob('jdk-17*'))
    candidate = next((p for p in candidates if (p / 'bin/java.exe').exists()), None)
    if candidate is None:
        raise SystemExit('JDK 17 missing. Run python tools/download_tools.py or set JAVA_HOME.')
    jdk = str(candidate)
sdk = os.environ.get('ANDROID_HOME', '')
if not sdk:
    sdk = str(tools / 'android-sdk')
if not (Path(sdk) / 'platform-tools/adb.exe').exists():
    raise SystemExit('Android SDK platform-tools missing. Run Build Android AR.cmd and review its license prompts first.')
# Templates package precompiled native engine libraries. Reuse the installed NDK
# for AGP's packaging tasks rather than downloading a second NDK unnecessarily.
ndks = sorted(p for p in (Path(sdk) / 'ndk').glob('*') if p.is_dir())
preferred_ndk = Path(sdk) / 'ndk/28.1.13356709'
if preferred_ndk.exists():
    ndks = [preferred_ndk]
if ndks:
    import re
    config = build / 'config.gradle'
    config.write_text(re.sub(r"ndkVersion\s*:\s*'[^']+'", "ndkVersion        : '" + ndks[-1].name + "'", config.read_text()))
def resource_path(value):
    return str(value).replace('\\', '/')
editor.mkdir(parents=True, exist_ok=True)
(editor / 'editor_settings-4.5.tres').write_text(
    '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
    f'export/android/java_sdk_path = "{resource_path(jdk)}"\n'
    f'export/android/android_sdk_path = "{resource_path(sdk)}"\n'
    f'export/android/debug_keystore = "{resource_path(tools / "debug.keystore")}"\n'
    'export/android/debug_keystore_user = "androiddebugkey"\n'
    'export/android/debug_keystore_pass = "android"\n')
print('Configured bundled editor and Android build template.')
