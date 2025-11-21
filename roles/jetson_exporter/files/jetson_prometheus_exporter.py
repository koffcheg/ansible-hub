from flask import Flask, Response
from prometheus_client import Gauge, generate_latest
from jtop import jtop
import threading
import time
import shutil
import os, re

app = Flask(__name__)

try:
    # prometheus_client >= 0.15
    from prometheus_client import Info
    HAS_INFO = True
except Exception:
    HAS_INFO = False

# Use Info if available; otherwise fall back to a label-only Gauge
if HAS_INFO:
    jetson_board_info = Info('jetson_board', 'Jetson static board info')
else:
    jetson_board_info = Gauge('jetson_board', 'Jetson static board info',
                              ['model', 'module', 'soc', 'l4t', 'jetpack', 'os'])

JETPACK_FROM_L4T = {
    # Common pairs; extend if you run other releases
    # 'R##.rev' or just 'R##'
    'R32':    'JetPack 4.x',
    'R35.1':  'JetPack 5.0.2',
    'R35.2':  'JetPack 5.1',
    'R35.3.1':'JetPack 5.1.1',
    'R35.4':  'JetPack 5.1.2',
    'R36':    'JetPack 6.x',
}

def _derive_module_from_model(model_str: str | None) -> str | None:
    if not model_str:
        return None
    s = model_str.lower()
    # very light heuristics; tweak for your fleet names
    if 'agx orin' in s:       return 'AGX Orin'
    if 'orin nano' in s:      return 'Orin Nano'
    if 'orin nx' in s:        return 'Orin NX'
    if 'xavier nx' in s:      return 'Xavier NX'
    if 'agx xavier' in s:     return 'AGX Xavier'
    if 'tx2' in s:            return 'TX2'
    if 'nano' in s:           return 'Nano'
    return None

def _map_jetpack(l4t: str | None) -> str | None:
    if not l4t:
        return None
    # exact match first
    if l4t in JETPACK_FROM_L4T:
        return JETPACK_FROM_L4T[l4t]
    # prefix match (R35.x → JetPack 5.x, etc.)
    for prefix, jp in JETPACK_FROM_L4T.items():
        if l4t.startswith(prefix):
            return jp
    return None

def _read_device_tree_model():
    try:
        with open('/proc/device-tree/model', 'r') as f:
            return f.read().strip('\x00\r\n')
    except Exception:
        return None

def _read_os_release():
    try:
        kv = {}
        with open('/etc/os-release', 'r') as f:
            for line in f:
                if '=' in line:
                    k, v = line.rstrip().split('=', 1)
                    kv[k] = v.strip('"')
        return kv.get('PRETTY_NAME') or kv.get('NAME')
    except Exception:
        return None

def _read_nv_tegra_release():
    """
    Parse /etc/nv_tegra_release for L4T/JetPack hints.
    Typical line example:
      # R35 (release), REVISION: 3.1, GCID: ..., BOARD: t186ref, EABI aarch64, DATE: ...
    We’ll return l4t='R35.3.1' and leave jetpack best-effort/unknown.
    """
    try:
        with open('/etc/nv_tegra_release', 'r') as f:
            s = f.read()
        rel = re.search(r'R(\d+)', s)
        rev = re.search(r'REVISION:\s*([\d\.]+)', s)
        l4t = None
        if rel:
            l4t = f"R{rel.group(1)}"
            if rev:
                l4t = f"{l4t}.{rev.group(1)}"
        # Mapping L4T→JetPack is not always stable; omit unless you want a manual map.
        return l4t, None
    except Exception:
        return None, None

def _read_soc_from_compatible():
    """
    Try to infer SoC from device tree compatible/cpuinfo.
    """
    # Try device-tree "compatible"
    for p in ('/proc/device-tree/compatible',):
        try:
            with open(p, 'rb') as f:
                data = f.read().replace(b'\x00', b',').decode(errors='ignore')
            m = re.search(r'tegra([^,]+)', data, flags=re.I)
            if m:
                return f"Tegra{m.group(1)}"
        except Exception:
            pass
    # Fallback: /proc/cpuinfo model name
    try:
        with open('/proc/cpuinfo', 'r') as f:
            for line in f:
                if 'NVIDIA' in line or 'Tegra' in line:
                    return line.split(':', 1)[-1].strip()
    except Exception:
        pass
    return None

def publish_board_info(jetson_handle=None):
    """
    Populate the jetson_board info metric once (or re-publish occasionally).
    Prefer jtop fields when present; fall back to files.
    """
    model = module = soc = None

    # Try jtop first
    try:
        if jetson_handle is not None:
            # jtop exposes several helpers on newer versions:
            # try attributes in a safe way to avoid KeyErrors on older releases
            # (These may vary by jtop version; hence the guarded lookups.)
            bj = getattr(jetson_handle, 'board', None)
            if isinstance(bj, dict):
                model = bj.get('Model') or bj.get('Name') or model
                module = bj.get('Module') or module
                soc = bj.get('SoC') or soc
            # Some versions expose .info or .status dicts:
            ij = getattr(jetson_handle, 'info', None)
            if isinstance(ij, dict):
                model = ij.get('Model') or model
                module = ij.get('Module') or module
                soc = ij.get('SoC') or soc
    except Exception:
        pass

    # Fallbacks
    model = model or _read_device_tree_model() or "unknown"
    soc = soc or _read_soc_from_compatible() or "unknown"
    l4t, jetpack = _read_nv_tegra_release() or "unknown"
    os_name = _read_os_release() or "Linux"
    module = module or _derive_module_from_model(model) or "unknown"
    jetpack = jetpack or _map_jetpack(l4t) or "unknown"

    # Publish
    labels = {
        'model': str(model),
        'module': str(module),
        'soc': str(soc),
        'l4t': str(l4t),
        'jetpack': str(jetpack),
        'os': str(os_name)
    }

    if HAS_INFO:
        jetson_board_info.info(labels)
    else:
        # label-only Gauge pattern
        jetson_board_info.labels(**labels).set(1)

# Define Prometheus metrics
jetson_uptime = Gauge('jetson_uptime', 'System Uptime in seconds')
jetson_usage_gpu = Gauge('jetson_usage_gpu', 'GPU Usage (%)')
jetson_usage_cpu = Gauge('jetson_usage_cpu', 'CPU Usage (%)', ['core'])
jetson_usage_ram = Gauge('jetson_usage_ram', 'RAM Used (%)')
jetson_usage_fan = Gauge('jetson_usage_fan', 'Fan Speed (%)')
jetson_usage_disk = Gauge('jetson_usage_disk', 'Disk Space (MB)', ['type'])
jetson_temperatures = Gauge('jetson_temperatures', 'Sensor Temperatures (°C)', ['sensor'])
jetson_usage_power = Gauge('jetson_usage_power', 'Power Consumption (mW)', ['component'])

def collect_metrics():
    with jtop() as jetson:
        publish_board_info(jetson)

        while jetson.ok():
            stats = jetson.stats

            # System Uptime
            if "uptime" in stats:
                jetson_uptime.set(stats["uptime"].total_seconds())

            # CPU Usage (Handles dynamic core names)
            for key, value in stats.items():
                if key.startswith("CPU") and key[3:].isdigit():
                    jetson_usage_cpu.labels(core=key.lower()).set(value)

            # GPU Usage
            if "GPU" in stats:
                jetson_usage_gpu.set(stats["GPU"])

            # RAM Usage
            if "RAM" in stats:
                jetson_usage_ram.set(stats["RAM"] * 100)  # Convert fraction to percentage

            # Fan Speed
            if "Fan pwmfan0" in stats:
                jetson_usage_fan.set(stats["Fan pwmfan0"])

            # Disk Usage (Fetching manually if missing)
            total, used, free = shutil.disk_usage("/")
            jetson_usage_disk.labels(type="available").set(free // (1024 * 1024))  # Convert to MB
            jetson_usage_disk.labels(type="used").set(used // (1024 * 1024))  # Convert to MB

            # Temperature Sensors (Filtering out invalid `-256` values)
            for key, value in stats.items():
                if key.startswith("Temp "):
                    sensor_name = key.replace("Temp ", "").lower()
                    if value != -256:  # Ignore invalid temperatures
                        jetson_temperatures.labels(sensor=sensor_name).set(value)

            # Power Consumption
            for key, value in stats.items():
                if key.startswith("Power "):
                    component_name = key.replace("Power ", "").lower()
                    jetson_usage_power.labels(component=component_name).set(value)

def start_metrics_thread():
    metrics_thread = threading.Thread(target=collect_metrics, daemon=True)
    metrics_thread.start()

@app.route('/metrics')
def metrics():
    return Response(generate_latest(), mimetype="text/plain")

if __name__ == '__main__':
    start_metrics_thread()
    app.run(host="0.0.0.0", port=8000)
