# ════════════════════════════════════════════════════════════════
#  WEB UI — HTTP Server nhẹ để quản lý VM
#  Chạy trên port 8888 (có thể đổi bằng WEB_UI_PORT)
# ════════════════════════════════════════════════════════════════

WEB_UI_PORT="${WEB_UI_PORT:-8888}"
WEB_UI_PID_FILE="/tmp/winbox-webui-${INSTANCE_ID}.pid"

_web_ui_server() {
    local _port="$1"
    local _pid_file="$2"
    local _web_dir="/tmp/winbox-webui-$$"
    mkdir -p "$_web_dir"

    # Tạo HTML giao diện
    cat > "$_web_dir/index.html" <<'HTML_EOF'
<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>WinBox - VM Manager</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', sans-serif; background: #0d1117; color: #e6edf3; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 { color: #58a6ff; margin-bottom: 10px; font-size: 28px; }
        .subtitle { color: #8b949e; margin-bottom: 30px; }
        .vm-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(350px, 1fr)); gap: 20px; }
        .vm-card { background: #161b22; border: 1px solid #30363d; border-radius: 12px; padding: 20px; transition: 0.3s; }
        .vm-card:hover { border-color: #58a6ff; transform: translateY(-2px); }
        .vm-card .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; }
        .vm-card .name { font-size: 18px; font-weight: bold; color: #f0f6fc; }
        .vm-card .status { padding: 4px 12px; border-radius: 20px; font-size: 12px; font-weight: 600; }
        .status.running { background: #238636; color: #fff; }
        .status.stopped { background: #8b949e; color: #fff; }
        .status.error { background: #da3633; color: #fff; }
        .vm-card .info { color: #8b949e; font-size: 14px; margin: 8px 0; }
        .vm-card .info span { color: #e6edf3; }
        .vm-card .actions { display: flex; gap: 8px; margin-top: 12px; flex-wrap: wrap; }
        .vm-card .actions button { padding: 6px 16px; border: none; border-radius: 6px; font-size: 13px; cursor: pointer; transition: 0.2s; }
        .btn-start { background: #238636; color: #fff; }
        .btn-start:hover { background: #2ea043; }
        .btn-stop { background: #da3633; color: #fff; }
        .btn-stop:hover { background: #f85149; }
        .btn-restart { background: #1f6feb; color: #fff; }
        .btn-restart:hover { background: #388bfd; }
        .btn-create { background: #238636; color: #fff; padding: 10px 24px; border: none; border-radius: 8px; font-size: 16px; cursor: pointer; margin-bottom: 20px; }
        .btn-create:hover { background: #2ea043; }
        .modal { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.7); z-index: 1000; justify-content: center; align-items: center; }
        .modal.active { display: flex; }
        .modal-content { background: #161b22; border: 1px solid #30363d; border-radius: 16px; padding: 30px; max-width: 500px; width: 90%; max-height: 80vh; overflow-y: auto; }
        .modal-content h2 { color: #58a6ff; margin-bottom: 20px; }
        .modal-content label { display: block; margin: 12px 0 4px; color: #8b949e; font-size: 14px; }
        .modal-content select, .modal-content input { width: 100%; padding: 10px; background: #0d1117; border: 1px solid #30363d; border-radius: 6px; color: #e6edf3; font-size: 14px; }
        .modal-content select:focus, .modal-content input:focus { outline: none; border-color: #58a6ff; }
        .modal-content .row { display: flex; gap: 12px; }
        .modal-content .row > * { flex: 1; }
        .modal-actions { display: flex; gap: 12px; margin-top: 20px; justify-content: flex-end; }
        .modal-actions button { padding: 8px 20px; border: none; border-radius: 6px; font-size: 14px; cursor: pointer; }
        .modal-actions .cancel { background: #21262d; color: #e6edf3; }
        .modal-actions .cancel:hover { background: #30363d; }
        .modal-actions .confirm { background: #238636; color: #fff; }
        .modal-actions .confirm:hover { background: #2ea043; }
        .creds { background: #0d1117; border-radius: 6px; padding: 10px; margin-top: 10px; font-size: 13px; }
        .creds code { color: #f0883e; background: #1c1c1c; padding: 2px 6px; border-radius: 4px; }
        .refresh-btn { background: #21262d; color: #e6edf3; padding: 8px 16px; border: none; border-radius: 6px; cursor: pointer; margin-bottom: 20px; }
        .refresh-btn:hover { background: #30363d; }
        .toast { position: fixed; bottom: 20px; right: 20px; background: #161b22; border: 1px solid #30363d; padding: 16px 24px; border-radius: 8px; color: #e6edf3; display: none; z-index: 2000; }
        .toast.show { display: block; animation: fadeIn 0.3s; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
        .loading { opacity: 0.6; pointer-events: none; }
    </style>
</head>
<body>
<div class="container">
    <h1>⬡ WinBox VM Manager</h1>
    <div class="subtitle">Quản lý Windows VMs trên QEMU</div>
    <div style="display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 20px;">
        <button class="btn-create" onclick="showCreateModal()">＋ Tạo VM Mới</button>
        <button class="refresh-btn" onclick="refreshVMs()">🔄 Làm mới</button>
    </div>
    <div id="vm-list" class="vm-grid">
        <div style="color: #8b949e; grid-column: 1/-1; text-align: center; padding: 40px;">⏳ Đang tải danh sách VM...</div>
    </div>
</div>

<!-- Modal tạo VM -->
<div id="create-modal" class="modal">
    <div class="modal-content">
        <h2>＋ Tạo VM mới</h2>
        <form id="create-form" onsubmit="createVM(event)">
            <label>Hệ điều hành</label>
            <select id="os-select" required>
                <option value="1">Windows Server 2012 R2</option>
                <option value="2">Windows Server 2022</option>
                <option value="3">Windows 11 LTSB</option>
                <option value="4">Windows 10 LTSB 2015</option>
                <option value="5" selected>Windows 10 LTSC 2023</option>
                <option value="6">Windows 10 LTSB 2022</option>
            </select>
            <div class="row">
                <div><label>CPU Cores</label><input id="cpu-input" type="number" value="4" min="1" max="16"/></div>
                <div><label>RAM (GB)</label><input id="ram-input" type="number" value="8" min="2" max="64"/></div>
            </div>
            <div><label>Dung lượng disk (GB)</label><input id="disk-input" type="number" value="60" min="20" max="500"/></div>
            <div class="creds">
                🔑 <strong>Thông tin đăng nhập mặc định:</strong><br>
                <span id="creds-display">Admin / Tam255Z</span>
            </div>
            <div class="modal-actions">
                <button type="button" class="cancel" onclick="closeModal()">Huỷ</button>
                <button type="submit" class="confirm">Tạo VM</button>
            </div>
        </form>
    </div>
</div>

<div id="toast" class="toast"></div>

<script>
const API_BASE = '/api';
let vmData = [];

// Mapping OS
const OS_MAP = {
    1: { name: 'Windows Server 2012 R2', user: 'administrator', pass: 'Tamnguyenyt@123' },
    2: { name: 'Windows Server 2022', user: 'administrator', pass: 'Tamnguyenyt@123' },
    3: { name: 'Windows 11 LTSB', user: 'Admin', pass: 'Tam255Z' },
    4: { name: 'Windows 10 LTSB 2015', user: 'Admin', pass: 'Tam255Z' },
    5: { name: 'Windows 10 LTSC 2023', user: 'Admin', pass: 'Tam255Z' },
    6: { name: 'Windows 10 LTSB 2022', user: 'Admin', pass: 'Tam255Z' }
};

document.getElementById('os-select').addEventListener('change', function() {
    const os = OS_MAP[this.value];
    document.getElementById('creds-display').textContent = os ? `${os.user} / ${os.pass}` : 'Admin / Tam255Z';
});

async function refreshVMs() {
    try {
        const resp = await fetch(API_BASE + '/vms');
        const data = await resp.json();
        vmData = data.vms || [];
        renderVMs();
    } catch(e) {
        showToast('Lỗi tải danh sách VM: ' + e.message);
    }
}

function renderVMs() {
    const container = document.getElementById('vm-list');
    if (!vmData.length) {
        container.innerHTML = '<div style="color: #8b949e; grid-column: 1/-1; text-align: center; padding: 40px;">📭 Chưa có VM nào. Nhấn "＋ Tạo VM Mới" để bắt đầu.</div>';
        return;
    }
    container.innerHTML = vmData.map(vm => `
        <div class="vm-card">
            <div class="header">
                <span class="name">${escapeHtml(vm.name)}</span>
                <span class="status ${vm.status}">${vm.status === 'running' ? '🟢 Running' : '⏹ Stopped'}</span>
            </div>
            <div class="info">🖥️ PID: <span>${vm.pid || 'N/A'}</span> | CPU: <span>${vm.cpu || '?'}</span> | RAM: <span>${vm.ram || '?'} GB</span></div>
            <div class="info">📡 RDP: <span>${vm.rdp_url || 'N/A'}</span></div>
            ${vm.vnc_url ? `<div class="info">🖼️ VNC: <span><a href="${vm.vnc_url}" target="_blank" style="color:#58a6ff;">${vm.vnc_url}</a></span></div>` : ''}
            <div class="creds">👤 ${escapeHtml(vm.user)} / 🔑 ${escapeHtml(vm.pass)}</div>
            <div class="actions">
                ${vm.status === 'running' ? `
                    <button class="btn-stop" onclick="vmAction(${vm.id}, 'stop')">⏹ Stop</button>
                    <button class="btn-restart" onclick="vmAction(${vm.id}, 'restart')">🔄 Restart</button>
                ` : `
                    <button class="btn-start" onclick="vmAction(${vm.id}, 'start')">▶️ Start</button>
                `}
            </div>
        </div>
    `).join('');
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

async function vmAction(id, action) {
    try {
        const resp = await fetch(API_BASE + '/vm/' + id + '/' + action, { method: 'POST' });
        const result = await resp.json();
        showToast(result.message || 'Thành công');
        refreshVMs();
    } catch(e) {
        showToast('Lỗi: ' + e.message);
    }
}

function showCreateModal() {
    document.getElementById('create-modal').classList.add('active');
}

function closeModal() {
    document.getElementById('create-modal').classList.remove('active');
}

async function createVM(e) {
    e.preventDefault();
    const os = document.getElementById('os-select').value;
    const cpu = document.getElementById('cpu-input').value;
    const ram = document.getElementById('ram-input').value;
    const disk = document.getElementById('disk-input').value;

    try {
        const resp = await fetch(API_BASE + '/create', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ os: parseInt(os), cpu, ram, disk })
        });
        const result = await resp.json();
        closeModal();
        showToast(result.message || 'VM đang được tạo!');
        refreshVMs();
        // Refresh sau 2 giây để cập nhật trạng thái
        setTimeout(refreshVMs, 3000);
    } catch(e) {
        showToast('Lỗi tạo VM: ' + e.message);
    }
}

function showToast(msg) {
    const toast = document.getElementById('toast');
    toast.textContent = msg;
    toast.classList.add('show');
    setTimeout(() => toast.classList.remove('show'), 4000);
}

// Auto refresh mỗi 10 giây
setInterval(refreshVMs, 10000);
refreshVMs();
</script>
</body>
</html>
HTML_EOF

    # Tạo Python HTTP server với API endpoints
    cat > "$_web_dir/server.py" <<'PY_EOF'
#!/usr/bin/env python3
import os
import sys
import json
import subprocess
import time
import re
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import threading
import glob

WEB_PORT = int(os.environ.get('WEB_UI_PORT', '8888'))
INSTANCE_ID = int(os.environ.get('INSTANCE_ID', '1'))

VM_STATE_FILE = f"/tmp/winvm-{INSTANCE_ID}.state"
VM_PID_FILE = f"/tmp/winvm-{INSTANCE_ID}.pid"
QEMU_CMD_FILE = "/tmp/qemu-launch.log"

# OS mapping
OS_MAP = {
    1: {'name': 'Windows Server 2012 R2', 'url': 'https://archive.org/download/tamnguyen-2012r2/2012.img', 'user': 'administrator', 'pass': 'Tamnguyenyt@123', 'uefi': False},
    2: {'name': 'Windows Server 2022', 'url': 'https://archive.org/download/tamnguyen-2022/2022.img', 'user': 'administrator', 'pass': 'Tamnguyenyt@123', 'uefi': False},
    3: {'name': 'Windows 11 LTSB', 'url': 'https://archive.org/download/win_20260203/win.img', 'user': 'Admin', 'pass': 'Tam255Z', 'uefi': True},
    4: {'name': 'Windows 10 LTSB 2015', 'url': 'https://archive.org/download/win_20260208/win.img', 'user': 'Admin', 'pass': 'Tam255Z', 'uefi': False},
    5: {'name': 'Windows 10 LTSC 2023', 'url': 'https://archive.org/download/win_20260215/win.img', 'user': 'Admin', 'pass': 'Tam255Z', 'uefi': False},
    6: {'name': 'Windows 10 LTSB 2022', 'url': 'https://archive.org/download/win_20260717/win.img', 'user': 'Admin', 'pass': 'Tam255Z', 'uefi': False},
}

def get_vm_status():
    """Lấy trạng thái VM hiện tại"""
    vms = []
    # Tìm tất cả VM đang chạy (dựa trên process)
    try:
        output = subprocess.check_output(['pgrep', '-f', 'qemu-system-x86_64'], text=True, stderr=subprocess.DEVNULL)
        pids = [p.strip() for p in output.split('\n') if p.strip()]
    except:
        pids = []

    # Đọc state file
    state = {}
    if os.path.exists(VM_STATE_FILE):
        try:
            with open(VM_STATE_FILE) as f:
                state = json.load(f)
        except:
            pass

    # Đọc PID từ file
    pid_from_file = None
    if os.path.exists(VM_PID_FILE):
        try:
            with open(VM_PID_FILE) as f:
                pid_from_file = int(f.read().strip())
        except:
            pass

    # Kiểm tra PID có đang chạy không
    is_running = False
    if pid_from_file:
        try:
            os.kill(pid_from_file, 0)
            is_running = True
        except OSError:
            is_running = False

    # Lấy thông tin CPU/RAM từ QEMU command
    cpu = '?'; ram = '?'
    if is_running:
        try:
            with open('/proc/' + str(pid_from_file) + '/cmdline', 'rb') as f:
                cmd = f.read().decode('utf-8', errors='ignore').replace('\x00', ' ')
                cpu_match = re.search(r'-smp\s+(\d+)', cmd)
                ram_match = re.search(r'-m\s+(\d+)', cmd)
                if cpu_match: cpu = cpu_match.group(1)
                if ram_match: ram = ram_match.group(1)
        except:
            pass

    # Đọc tên OS từ state
    os_name = state.get('win_name', 'Windows VM')
    rdp_port = state.get('rdp_port', 3388 + INSTANCE_ID)
    rdp_user = state.get('rdp_user', 'Admin')
    rdp_pass = 'Tam255Z'  # mặc định

    # Xác định mật khẩu từ OS mapping (dựa vào tên)
    for k, v in OS_MAP.items():
        if v['name'] in os_name:
            rdp_user = v['user']
            rdp_pass = v['pass']
            break

    vms.append({
        'id': 1,
        'name': os_name,
        'status': 'running' if is_running else 'stopped',
        'pid': pid_from_file if is_running else None,
        'cpu': cpu,
        'ram': ram,
        'rdp_url': f'localhost:{rdp_port}',
        'vnc_url': 'http://localhost:6080' if is_running else None,
        'user': rdp_user,
        'pass': rdp_pass
    })

    return vms

class WinBoxHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == '/':
            self.serve_html()
        elif path == '/api/vms':
            self.send_json({'vms': get_vm_status()})
        else:
            self.send_error(404)

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == '/api/create':
            self.handle_create()
        elif path.startswith('/api/vm/'):
            parts = path.split('/')
            if len(parts) >= 4:
                vm_id = parts[3]
                action = parts[4] if len(parts) > 4 else None
                self.handle_vm_action(vm_id, action)
        else:
            self.send_error(404)

    def serve_html(self):
        html_path = os.path.join(os.path.dirname(__file__), 'index.html')
        try:
            with open(html_path, 'rb') as f:
                self.send_response(200)
                self.send_header('Content-Type', 'text/html')
                self.end_headers()
                self.wfile.write(f.read())
        except:
            self.send_error(500)

    def send_json(self, data):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def send_json_error(self, msg, code=400):
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({'error': msg}).encode())

    def handle_create(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        try:
            data = json.loads(body)
            os_choice = data.get('os', 5)
            cpu = data.get('cpu', 4)
            ram = data.get('ram', 8)
            disk = data.get('disk', 60)

            # Lưu config để script chính sử dụng
            config = {
                'os': os_choice,
                'cpu': cpu,
                'ram': ram,
                'disk': disk
            }
            with open('/tmp/winbox-create-config.json', 'w') as f:
                json.dump(config, f)

            # Chạy script winbox với tham số tự động
            # Sử dụng subprocess trong background
            script_path = os.path.realpath(__file__)
            # Tìm script gốc (winbox.sh)
            winbox_script = os.environ.get('WINBOX_SCRIPT', 'winbox.sh')
            if not os.path.exists(winbox_script):
                winbox_script = os.path.join(os.path.dirname(os.path.dirname(script_path)), 'winbox.sh')
            if not os.path.exists(winbox_script):
                # Thử tìm trong PATH
                import shutil
                winbox_script = shutil.which('winbox.sh') or 'winbox.sh'

            os_choice_map = {1: '--win2012', 2: '--win2022', 3: '--win11', 4: '--win10ltsb', 5: '--win10ltsc', 6: '--win10ltsb2022'}
            os_flag = os_choice_map.get(os_choice, '--win10ltsc')

            cmd = [
                'bash', winbox_script,
                '--auto', os_flag,
                '--id=' + str(INSTANCE_ID)
            ]

            # Chạy trong background
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            self.send_json({
                'success': True,
                'message': f'Đang tạo VM {OS_MAP.get(os_choice, {}).get("name", "Windows")} với CPU={cpu}, RAM={ram}GB, Disk={disk}GB'
            })
        except Exception as e:
            self.send_json_error(str(e))

    def handle_vm_action(self, vm_id, action):
        if action == 'stop':
            # Gửi ACPI shutdown
            qmp_sock = f"/tmp/winvm-{INSTANCE_ID}.qmp"
            if os.path.exists(qmp_sock):
                try:
                    import socket
                    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    s.connect(qmp_sock)
                    s.send(b'{"execute":"qmp_capabilities"}\n{"execute":"system_powerdown"}\n')
                    s.close()
                    self.send_json({'message': 'Đã gửi lệnh tắt VM'})
                except:
                    self.send_json({'message': 'Không thể gửi tín hiệu tắt'})
            else:
                # Fallback: kill process
                if os.path.exists(VM_PID_FILE):
                    try:
                        with open(VM_PID_FILE) as f:
                            pid = int(f.read().strip())
                        os.kill(pid, 15)  # SIGTERM
                        self.send_json({'message': 'Đã kill VM (SIGTERM)'})
                    except:
                        self.send_json_error('Không thể tắt VM')
                else:
                    self.send_json_error('Không tìm thấy VM')
        elif action == 'start':
            # Khởi động lại VM
            winbox_script = os.environ.get('WINBOX_SCRIPT', 'winbox.sh')
            if not os.path.exists(winbox_script):
                import shutil
                winbox_script = shutil.which('winbox.sh') or 'winbox.sh'
            subprocess.Popen(['bash', winbox_script, '--id=' + str(INSTANCE_ID)], 
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.send_json({'message': 'Đang khởi động VM'})
        elif action == 'restart':
            # Stop + Start
            # Gửi shutdown
            qmp_sock = f"/tmp/winvm-{INSTANCE_ID}.qmp"
            if os.path.exists(qmp_sock):
                try:
                    import socket
                    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    s.connect(qmp_sock)
                    s.send(b'{"execute":"qmp_capabilities"}\n{"execute":"system_powerdown"}\n')
                    s.close()
                except:
                    pass
            # Chờ 2s rồi start lại
            time.sleep(2)
            winbox_script = os.environ.get('WINBOX_SCRIPT', 'winbox.sh')
            if not os.path.exists(winbox_script):
                import shutil
                winbox_script = shutil.which('winbox.sh') or 'winbox.sh'
            subprocess.Popen(['bash', winbox_script, '--id=' + str(INSTANCE_ID)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.send_json({'message': 'Đang khởi động lại VM'})
        else:
            self.send_json_error('Action không hợp lệ')

def run_server():
    server = HTTPServer(('0.0.0.0', WEB_PORT), WinBoxHandler)
    print(f'🌐 Web UI running on http://localhost:{WEB_PORT}')
    server.serve_forever()

if __name__ == '__main__':
    run_server()
PY_EOF

    # Chạy web server trong background
    export WEB_UI_PORT="$WEB_UI_PORT"
    export INSTANCE_ID="$INSTANCE_ID"
    export WINBOX_SCRIPT="$0"
    cd "$_web_dir"
    nohup python3 server.py > /tmp/winbox-webui-${INSTANCE_ID}.log 2>&1 &
    WEB_UI_PID=$!
    echo "$WEB_UI_PID" > "$WEB_UI_PID_FILE"
    disown "$WEB_UI_PID"
    cd - >/dev/null

    echo -e "${G}🌐 Web UI: http://localhost:${WEB_UI_PORT}${W}"
    echo -e "${B}ℹ${W}  Dùng trình duyệt mở link trên để quản lý VM"
}

# Khởi động Web UI nếu chưa chạy (chỉ cho instance 1 để tránh conflict)
if [[ "$INSTANCE_ID" == "1" ]] && [[ ! -f "$WEB_UI_PID_FILE" ]] || ! kill -0 "$(cat "$WEB_UI_PID_FILE" 2>/dev/null)" 2>/dev/null; then
    _web_ui_server "$WEB_UI_PORT" "$WEB_UI_PID_FILE"
fi
