"""Run Godot checks, including two real ENet peers, with isolated local logs."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ENV = os.environ.copy()
ENV['APPDATA'] = str(ROOT / '.tools/user')
ENV['LOCALAPPDATA'] = ENV['APPDATA']
BASE = [str(ROOT / '.tools/godot/Godot_v4.5.1-stable_win64_console.exe'),
        '--headless', '--path', str(ROOT), '--max-fps', '60']


def command(script, role=None):
    args = BASE + ['--log-file', str(ROOT / '.tools' / (Path(script).stem + (role or '') + '.log')),
                   '--script', script]
    return args + (['--', role] if role else [])


def check_output(output):
    if 'SCRIPT ERROR:' in output or 'Assertion failed' in output or 'PASS:' not in output:
        raise RuntimeError('Godot check reported a script failure or no PASS result')


def main():
    for script in ['tests/demo_checks.gd', 'tests/volleyball_checks.gd', 'tests/ar_bridge_checks.gd', 'tests/yuv_camera_checks.gd', 'tests/camera_safe_checks.gd', 'tests/opencv_bridge_checks.gd']:
        result = subprocess.run(command(script), env=ENV, cwd=ROOT, check=True, timeout=40,
                                capture_output=True, text=True)
        print(result.stdout + result.stderr, flush=True)
        check_output(result.stdout + result.stderr)
    host = subprocess.Popen(command('tests/network_checks.gd', 'host'), env=ENV, cwd=ROOT,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        for line in host.stdout:
            print(line, end='', flush=True)
            if 'READY' in line:
                break
        if host.poll() is not None:
            raise RuntimeError('Host failed before ready')
        result = subprocess.run(command('tests/network_checks.gd', 'client'), env=ENV, cwd=ROOT,
                                check=True, timeout=35, capture_output=True, text=True)
        print(result.stdout + result.stderr, flush=True)
        check_output(result.stdout + result.stderr)
        host_output = host.communicate(timeout=30)[0]
        print(host_output)
        check_output(host_output)
        if host.returncode:
            raise RuntimeError('Host check failed')
    finally:
        if host.poll() is None:
            host.terminate()
            host.wait(timeout=10)


if __name__ == '__main__':
    main()
