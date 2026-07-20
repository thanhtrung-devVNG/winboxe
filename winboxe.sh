#!/usr/bin/env bash
set -euo pipefail

# ════════════════════════════════════════════════════════════════
#  WINBOX - Web Dashboard Edition
#  Tính năng:
#  - Web dashboard tự động tạo khi chạy (localhost:8080)
#  - Preset cấu hình: 4-4, 8-8, 16-16, Custom
#  - Chọn ISO Windows với user/mk sẵn có
#  - Hiển thị thông tin RDP sau khi VM chạy
# ════════════════════════════════════════════════════════════════

HOME="${HOME:-/root}"
USER="${USER:-$(id -un 2>/dev/null || echo root)}"
LOGNAME="${LOGNAME:-$USER}"
export HOME USER LOGNAME

# ── MÀU SẮC ────────────────────────────────────────────────────
R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'
B='\033[1;34m'; C='\033[1;36m'; W='\033[0m'

_rl_ok()   { echo -e "${G}✔${W} $1"; }
_rl_warn() { echo -e "${Y}⚠${W}  $1"; }

# ════════════════════════════════════════════════════════════════
#  WEB DASHBOARD
# ════════════════════════════════════════════════════════════════
WEB_PORT=8080
WEB_DIR="/tmp/winbox-web"
WEB_PID_FILE="/tmp/winbox-web.pid"

# ISO Windows với thông tin đăng nhập
declare -A ISO_URLS=(
    [1]="https://archive.org/download/tamnguyen-2012r2/2012.img"
    [2]="https://archive.org/download/tamnguyen-2022/2022.img"
    [3]="https://archive.org/download/win_20260203/win.img"
    [4]="https://archive.org/download/win_20260208/win.img"
    [5]="https://archive.org/download/win_20260215/win.img"
    [6]="https://archive.org/download/win_20260717/win.img"
)

declare -A ISO_NAMES=(
    [1]="Windows Server 2012 R2"
    [2]="Windows Server 2022"
    [3]="Windows 11 LTSB"
    [4]="Windows 10 LTSB 2015"
    [5]="Windows 10 LTSC 2023"
    [6]="Windows 10 LTSB 2022"
)

declare -A ISO_USERS=(
    [1]="administrator"
    [2]="administrator"
    [3]="Admin"
    [4]="Admin"
    [5]="Admin"
    [6]="Admin"
)

declare -A ISO_PASSES=(
    [1]="Tamnguyenyt@123"
    [2]="Tamnguyenyt@123"
    [3]="Tam255Z"
    [4]="Tam255Z"
    [5]="Tam255Z"
    [6]="Tam255Z"
)

declare -A ISO_UEFI=(
    [1]="no"
    [2]="no"
    [3]="yes"
    [4]="no"
    [5]="no"
    [6]="no"
)

# Tạo dashboard files bằng Python (tránh heredoc issues)
_create_dashboard_files() {
    mkdir -p "$WEB_DIR"

    # Tạo HTML file
    python3 - "$WEB_DIR" << 'PYEOF'
import sys, os
web_dir = sys.argv[1]

html = """<!DOCTYPE html>
<html lang="vi">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>WinBox Dashboard</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Segoe UI',system-ui,sans-serif;background:linear-gradient(135deg,#1a1a2e 0%,#16213e 50%,#0f3460 100%);min-height:100vh;color:#fff;display:flex;justify-content:center;align-items:center;padding:20px}
.container{max-width:700px;width:100%;background:rgba(255,255,255,0.05);backdrop-filter:blur(20px);border-radius:24px;border:1px solid rgba(255,255,255,0.1);padding:40px;box-shadow:0 25px 50px rgba(0,0,0,0.4)}
.header{text-align:center;margin-bottom:35px}
.header h1{font-size:2.5em;background:linear-gradient(90deg,#00d4ff,#7b2cbf);-webkit-background-clip:text;-webkit-text-fill-color:transparent;margin-bottom:10px}
.header p{color:#8892b0;font-size:1.1em}
.section{margin-bottom:30px;padding:25px;background:rgba(0,0,0,0.2);border-radius:16px;border:1px solid rgba(255,255,255,0.05)}
.section-title{font-size:1.2em;font-weight:600;margin-bottom:18px;display:flex;align-items:center;gap:10px;color:#64ffda}
.option-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px}
.option-card{padding:18px;background:rgba(255,255,255,0.03);border:2px solid rgba(255,255,255,0.08);border-radius:12px;cursor:pointer;transition:all 0.3s ease;text-align:center}
.option-card:hover{border-color:#64ffda;background:rgba(100,255,218,0.05);transform:translateY(-3px)}
.option-card.selected{border-color:#00d4ff;background:rgba(0,212,255,0.1);box-shadow:0 0 20px rgba(0,212,255,0.2)}
.option-card .icon{font-size:2em;margin-bottom:8px}
.option-card .name{font-weight:600;font-size:1em}
.option-card .desc{font-size:0.85em;color:#8892b0;margin-top:5px}
.option-card .badge{display:inline-block;padding:3px 10px;border-radius:20px;font-size:0.75em;margin-top:8px;font-weight:500}
.badge-kvm{background:rgba(0,212,255,0.2);color:#00d4ff}
.badge-tcg{background:rgba(255,184,0,0.2);color:#ffb800}
.custom-inputs{display:none;margin-top:20px;padding:20px;background:rgba(0,0,0,0.3);border-radius:12px}
.custom-inputs.active{display:block}
.input-group{margin-bottom:15px}
.input-group label{display:block;margin-bottom:8px;color:#ccd6f6;font-size:0.95em}
.input-group input{width:100%;padding:12px 16px;background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.1);border-radius:10px;color:#fff;font-size:1em;outline:none;transition:border-color 0.3s}
.input-group input:focus{border-color:#64ffda}
.submit-btn{width:100%;padding:18px;background:linear-gradient(90deg,#00d4ff,#7b2cbf);border:none;border-radius:14px;color:#fff;font-size:1.2em;font-weight:700;cursor:pointer;transition:all 0.3s ease;margin-top:20px;text-transform:uppercase;letter-spacing:1px}
.submit-btn:hover{transform:translateY(-2px);box-shadow:0 10px 30px rgba(0,212,255,0.3)}
.submit-btn:disabled{opacity:0.5;cursor:not-allowed}
.status{margin-top:25px;padding:20px;border-radius:14px;display:none;text-align:center}
.status.active{display:block}
.status.loading{background:rgba(0,212,255,0.1);border:1px solid rgba(0,212,255,0.3)}
.status.success{background:rgba(0,255,136,0.1);border:1px solid rgba(0,255,136,0.3)}
.status.error{background:rgba(255,0,0,0.1);border:1px solid rgba(255,0,0,0.3)}
.spinner{display:inline-block;width:40px;height:40px;border:4px solid rgba(255,255,255,0.1);border-top-color:#00d4ff;border-radius:50%;animation:spin 1s linear infinite;margin-bottom:15px}
@keyframes spin{to{transform:rotate(360deg)}}
.rdp-info{background:rgba(0,0,0,0.3);border-radius:12px;padding:20px;margin-top:15px;text-align:left}
.rdp-info-row{display:flex;justify-content:space-between;padding:10px 0;border-bottom:1px solid rgba(255,255,255,0.05)}
.rdp-info-row:last-child{border-bottom:none}
.rdp-info-label{color:#8892b0}
.rdp-info-value{color:#64ffda;font-weight:600;font-family:monospace}
.copy-btn{background:rgba(255,255,255,0.1);border:none;padding:5px 12px;border-radius:6px;color:#fff;cursor:pointer;font-size:0.85em;margin-left:10px}
.copy-btn:hover{background:rgba(255,255,255,0.2)}
.progress-bar{width:100%;height:6px;background:rgba(255,255,255,0.05);border-radius:3px;overflow:hidden;margin:15px 0}
.progress-fill{height:100%;background:linear-gradient(90deg,#00d4ff,#64ffda);border-radius:3px;transition:width 0.5s ease;width:0%}
.footer{text-align:center;margin-top:30px;color:#8892b0;font-size:0.9em}
</style>
</head>
<body>
<div class="container">
<div class="header"><h1>WinBox</h1><p>Windows VM Dashboard - Chọn cấu hình và khởi động</p></div>

<div class="section">
<div class="section-title">⚙️ Cấu hình VM</div>
<div class="option-grid" id="preset-grid">
<div class="option-card" data-preset="1" onclick="selectPreset(1)">
<div class="icon">🖥️</div><div class="name">4 CPU + 4 GB</div><div class="desc">Cấu hình cơ bản</div><span class="badge badge-kvm">KVM Ready</span>
</div>
<div class="option-card" data-preset="2" onclick="selectPreset(2)">
<div class="icon">🚀</div><div class="name">8 CPU + 8 GB</div><div class="desc">Cấu hình mạnh</div><span class="badge badge-kvm">KVM Ready</span>
</div>
<div class="option-card" data-preset="3" onclick="selectPreset(3)">
<div class="icon">🔥</div><div class="name">16 CPU + 16 GB</div><div class="desc">Cấu hình cực mạnh</div><span class="badge badge-kvm">KVM Ready</span>
</div>
<div class="option-card" data-preset="4" onclick="selectPreset(4)">
<div class="icon">⚡</div><div class="name">Custom</div><div class="desc">Tự chọn CPU/RAM</div><span class="badge badge-tcg">TCG/Custom</span>
</div>
</div>
<div class="custom-inputs" id="custom-inputs">
<div class="input-group"><label>🧠 Số CPU cores</label><input type="number" id="custom-cpu" min="1" max="64" value="4"></div>
<div class="input-group"><label>💾 RAM (GB)</label><input type="number" id="custom-ram" min="1" max="128" value="4"></div>
</div>
</div>

<div class="section">
<div class="section-title">💿 Chọn Windows</div>
<div class="option-grid" id="iso-grid">
<div class="option-card" data-iso="1" onclick="selectIso(1)">
<div class="icon">🖥️</div><div class="name">Server 2012 R2</div><div class="desc">administrator / Tamnguyenyt@123</div>
</div>
<div class="option-card" data-iso="2" onclick="selectIso(2)">
<div class="icon">🖥️</div><div class="name">Server 2022</div><div class="desc">administrator / Tamnguyenyt@123</div>
</div>
<div class="option-card" data-iso="3" onclick="selectIso(3)">
<div class="icon">🪟</div><div class="name">Windows 11 LTSB</div><div class="desc">Admin / Tam255Z | UEFI</div>
</div>
<div class="option-card" data-iso="4" onclick="selectIso(4)">
<div class="icon">🪟</div><div class="name">Win 10 LTSB 2015</div><div class="desc">Admin / Tam255Z</div>
</div>
<div class="option-card" data-iso="5" onclick="selectIso(5)">
<div class="icon">🪟</div><div class="name">Win 10 LTSC 2023</div><div class="desc">Admin / Tam255Z</div>
</div>
<div class="option-card" data-iso="6" onclick="selectIso(6)">
<div class="icon">🎮</div><div class="name">Win 10 LTSB 2022</div><div class="desc">Admin / Tam255Z | VirtGPU 3D</div>
</div>
</div>
</div>

<button class="submit-btn" id="submit-btn" onclick="launchVM()" disabled>🚀 KHỞI ĐỘNG WINDOWS VM</button>

<div class="status loading" id="status-loading">
<div class="spinner"></div>
<div style="font-size:1.2em;font-weight:600;margin-bottom:10px">Đang khởi động VM...</div>
<div style="color:#8892b0;margin-bottom:15px">Vui lòng đợi trong giây lát</div>
<div class="progress-bar"><div class="progress-fill" id="progress-fill"></div></div>
<div id="progress-text" style="font-size:0.9em;color:#64ffda">Đang tải QEMU...</div>
</div>

<div class="status success" id="status-success">
<div style="font-size:2em;margin-bottom:10px">✅</div>
<div style="font-size:1.3em;font-weight:700;margin-bottom:5px">VM đã sẵn sàng!</div>
<div style="color:#8892b0;margin-bottom:15px">Kết nối RDP bằng thông tin bên dưới</div>
<div class="rdp-info" id="rdp-info"></div>
</div>

<div class="status error" id="status-error">
<div style="font-size:2em;margin-bottom:10px">❌</div>
<div style="font-size:1.2em;font-weight:600;margin-bottom:10px">Khởi động thất bại</div>
<div id="error-text" style="color:#ff6b6b"></div>
</div>

<div class="footer">WinBox Dashboard | QEMU VM Manager<br><span style="font-size:0.8em">Trang này tự động tắt khi đóng terminal</span></div>
</div>

<script>
let selectedPreset=null,selectedIso=null;
function selectPreset(id){selectedPreset=id;document.querySelectorAll('#preset-grid .option-card').forEach(c=>c.classList.remove('selected'));document.querySelector(`[data-preset="${id}"]`).classList.add('selected');document.getElementById('custom-inputs').classList.toggle('active',id===4);updateSubmit()}
function selectIso(id){selectedIso=id;document.querySelectorAll('#iso-grid .option-card').forEach(c=>c.classList.remove('selected'));document.querySelector(`[data-iso="${id}"]`).classList.add('selected');updateSubmit()}
function updateSubmit(){document.getElementById('submit-btn').disabled=!(selectedPreset&&selectedIso)}
function setProgress(pct,text){document.getElementById('progress-fill').style.width=pct+'%';document.getElementById('progress-text').textContent=text}
async function launchVM(){const btn=document.getElementById('submit-btn');btn.disabled=true;document.getElementById('status-loading').classList.add('active');document.getElementById('status-success').classList.remove('active');document.getElementById('status-error').classList.remove('active');let cpu=selectedPreset===4?document.getElementById('custom-cpu').value:[4,8,16][selectedPreset-1];let ram=selectedPreset===4?document.getElementById('custom-ram').value:[4,8,16][selectedPreset-1];const steps=[{pct:10,text:'Đang kiểm tra QEMU...',delay:800},{pct:30,text:'Đang tải Windows image...',delay:2000},{pct:60,text:'Đang cấu hình VM...',delay:1500},{pct:80,text:'Đang khởi động QEMU...',delay:2000},{pct:95,text:'Đang chờ VM sẵn sàng...',delay:3000}];for(const step of steps){setProgress(step.pct,step.text);await new Promise(r=>setTimeout(r,step.delay))}try{const res=await fetch('/api/launch',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({preset:selectedPreset,iso:selectedIso,cpu,ram})});const data=await res.json();document.getElementById('status-loading').classList.remove('active');if(data.success){document.getElementById('status-success').classList.add('active');document.getElementById('rdp-info').innerHTML=`<div class="rdp-info-row"><span class="rdp-info-label">🪟 Hệ điều hành</span><span class="rdp-info-value">${data.win_name}</span></div><div class="rdp-info-row"><span class="rdp-info-label">⚙️ CPU</span><span class="rdp-info-value">${data.cpu} cores</span></div><div class="rdp-info-row"><span class="rdp-info-label">💾 RAM</span><span class="rdp-info-value">${data.ram} GB</span></div><div class="rdp-info-row"><span class="rdp-info-label">📡 RDP Address</span><span class="rdp-info-value">${data.rdp_host}:${data.rdp_port}<button class="copy-btn" onclick="navigator.clipboard.writeText('${data.rdp_host}:${data.rdp_port}')">Copy</button></span></div><div class="rdp-info-row"><span class="rdp-info-label">👤 Username</span><span class="rdp-info-value">${data.rdp_user}<button class="copy-btn" onclick="navigator.clipboard.writeText('${data.rdp_user}')">Copy</button></span></div><div class="rdp-info-row"><span class="rdp-info-label">🔑 Password</span><span class="rdp-info-value">${data.rdp_pass}<button class="copy-btn" onclick="navigator.clipboard.writeText('${data.rdp_pass}')">Copy</button></span></div><div class="rdp-info-row"><span class="rdp-info-label">🖥️ VNC</span><span class="rdp-info-value">localhost:5900</span></div>`}else{document.getElementById('status-error').classList.add('active');document.getElementById('error-text').textContent=data.error||'Lỗi không xác định'}}catch(e){document.getElementById('status-loading').classList.remove('active');document.getElementById('status-error').classList.add('active');document.getElementById('error-text').textContent=e.message}btn.disabled=false}
selectPreset(1);selectIso(5);
</script>
</body>
</html>"""

with open(os.path.join(web_dir, 'index.html'), 'w') as f:
    f.write(html)

# Tạo Python server
server_py = """#!/usr/bin/env python3
import http.server, socketserver, json, os, sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
STATE_FILE = "/tmp/winbox-state.json"

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/': self.path = '/index.html'
        return super().do_GET()
    def do_POST(self):
        if self.path == '/api/launch':
            content_len = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_len)
            data = json.loads(body)
            with open(STATE_FILE, 'w') as f:
                json.dump(data, f)
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps({"success": True}).encode())
            return
        self.send_response(404)
        self.end_headers()
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        super().end_headers()

os.chdir(os.path.dirname(os.path.abspath(__file__)))
with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
    print(f"Server running at http://0.0.0.0:{PORT}")
    httpd.serve_forever()
"""

with open(os.path.join(web_dir, 'server.py'), 'w') as f:
    f.write(server_py)
os.chmod(os.path.join(web_dir, 'server.py'), 0o755)

print("Dashboard files created successfully")
PYEOF
}

# Khởi động web server
_start_web_server() {
    _create_dashboard_files

    if [[ -f "$WEB_PID_FILE" ]]; then
        old_pid=$(cat "$WEB_PID_FILE" 2>/dev/null || echo "")
        [[ -n "$old_pid" ]] && kill "$old_pid" 2>/dev/null || true
    fi

    for p in 8080 8081 8082 8083 8084; do
        if ! ss -tlnp 2>/dev/null | grep -q ":$p "; then
            WEB_PORT=$p
            break
        fi
    done

    nohup python3 "$WEB_DIR/server.py" "$WEB_PORT" > /tmp/winbox-web.log 2>&1 &
    WEB_PID=$!
    echo "$WEB_PID" > "$WEB_PID_FILE"
    disown "$WEB_PID"

    sleep 1
    if kill -0 "$WEB_PID" 2>/dev/null; then
        echo -e "${G}✔${W} Web Dashboard: ${C}http://localhost:$WEB_PORT${W}"

        if command -v xdg-open &>/dev/null; then
            xdg-open "http://localhost:$WEB_PORT" 2>/dev/null || true
        elif command -v open &>/dev/null; then
            open "http://localhost:$WEB_PORT" 2>/dev/null || true
        fi

        if command -v qrencode &>/dev/null; then
            echo -e "${B}ℹ${W}  Quét QR để mở trên điện thoại:"
            qrencode -t ANSI "http://$(hostname -I 2>/dev/null | awk '{print $1}' | head -1):$WEB_PORT" 2>/dev/null || true
        fi
        return 0
    else
        echo -e "${R}✘${W} Web server failed"
        return 1
    fi
}

# Đợi config từ web
_wait_web_config() {
    local _state_file="/tmp/winbox-state.json"
    local _timeout=300
    local _elapsed=0

    echo -e "${B}ℹ${W}  Đang đợi cấu hình từ Web Dashboard..."
    echo -e "${B}ℹ${W}  Mở ${C}http://localhost:$WEB_PORT${W} để cấu hình"

    while [[ ! -f "$_state_file" ]] && [[ $_elapsed -lt $_timeout ]]; do
        sleep 2
        _elapsed=$((_elapsed + 2))
        printf "\r${B}◜${W} Đang đợi... %ss" "$_elapsed"
    done
    printf "\n"

    if [[ -f "$_state_file" ]]; then
        win_choice=$(python3 -c "import json; print(json.load(open('$_state_file')).get('iso','5'))" 2>/dev/null || echo "5")
        local _preset=$(python3 -c "import json; print(json.load(open('$_state_file')).get('preset','1'))" 2>/dev/null || echo "1")
        local _cpu=$(python3 -c "import json; print(json.load(open('$_state_file')).get('cpu','4'))" 2>/dev/null || echo "4")
        local _ram=$(python3 -c "import json; print(json.load(open('$_state_file')).get('ram','4'))" 2>/dev/null || echo "4")

        if [[ "$_preset" == "4" ]]; then
            cpu_core="$_cpu"
            ram_size="$_ram"
        else
            cpu_core="$_cpu"
            ram_size="$_ram"
        fi

        echo -e "${G}✔${W} Nhận config:"
        echo -e "   🖥️  CPU: ${B}$cpu_core${W} cores"
        echo -e "   💾 RAM: ${B}$ram_size${W} GB"
        echo -e "   💿 ISO: ${B}${ISO_NAMES[$win_choice]}${W}"

        rm -f "$_state_file"
        return 0
    else
        echo -e "${R}✘${W} Timeout đợi config"
        return 1
    fi
}

# ════════════════════════════════════════════════════════════════
#  QEMU RESOLVE
# ════════════════════════════════════════════════════════════════
_resolve_qemu_bin() {
    for q in "${QEMU_BIN:-}" "$HOME/qemu-static/bin/qemu-system-x86_64" "$HOME/qemu-optimized/bin/qemu-system-x86_64" "/opt/qemu-optimized/bin/qemu-system-x86_64" "$(command -v qemu-system-x86_64 2>/dev/null)"; do
        [[ -n "$q" && -x "$q" ]] && { echo "$q"; return 0; }
    done
    return 1
}

_resolve_qemu_img() {
    for qi in "$(dirname "${QEMU_BIN:-/nonexistent}")/qemu-img" "${PREFIX:-}/bin/qemu-img" "$HOME/qemu-static/bin/qemu-img" "$HOME/qemu-optimized/bin/qemu-img" "/opt/qemu-optimized/bin/qemu-img" "/usr/bin/qemu-img" "$(command -v qemu-img 2>/dev/null || true)"; do
        if [[ -x "$qi" ]]; then
            if "$qi" --version >/dev/null 2>&1; then
                echo "$qi"; return 0
            fi
        fi
    done
    return 1
}

# ════════════════════════════════════════════════════════════════
#  BOOTSTRAP
# ════════════════════════════════════════════════════════════════
_bootstrap_tools() {
    local _apt=""
    if [[ "$(id -u)" == "0" ]] && command -v apt-get &>/dev/null; then _apt="apt-get"
    elif sudo -n true 2>/dev/null && command -v apt-get &>/dev/null; then _apt="sudo apt-get"; fi
    [[ -z "$_apt" ]] && return 0
    local _need=0
    for _t in wget curl python3; do command -v "$_t" &>/dev/null || _need=1; done
    [[ "$_need" == "0" ]] && return 0
    echo -e "${B}ℹ${W}  Bootstrap: cài công cụ..."
    export DEBIAN_FRONTEND=noninteractive
    $_apt update -qq > /dev/null 2>&1 || true
    for _pkg in wget curl python3 python3-pip; do
        command -v "$_pkg" &>/dev/null || $_apt install -y -qq "$_pkg" > /dev/null 2>&1 || true
    done
}
_bootstrap_tools

# ════════════════════════════════════════════════════════════════
#  KVM DETECTION
# ════════════════════════════════════════════════════════════════
KVM_AVAILABLE=0
KVM_MODE=""

_detect_kvm() {
    echo ""
    echo -e "${C}════════════════════════════════════${W}"
    echo -e "${C}🔍 KIỂM TRA KVM${W}"
    echo -e "${C}════════════════════════════════════${W}"

    if [[ ! -e /dev/kvm ]]; then
        echo -e "${Y}⚠${W}  /dev/kvm không tồn tại — dùng TCG"
        KVM_AVAILABLE=0; KVM_MODE="tcg"
        return
    fi

    local KVM_LS=$(ls -l /dev/kvm 2>/dev/null)
    local KVM_OWNER=$(echo "$KVM_LS" | awk '{print $3}')
    local KVM_GROUP=$(echo "$KVM_LS" | awk '{print $4}')
    local CAN_USE_KVM=0

    if [[ "$KVM_OWNER" == "root" ]] && [[ "$KVM_GROUP" == "root" || "$KVM_GROUP" == "kvm" ]]; then
        if [[ "$(id -u)" == "0" ]]; then
            CAN_USE_KVM=1
        else
            local CURRENT_GROUPS=$(id -Gn)
            if echo "$CURRENT_GROUPS" | grep -qw "$KVM_GROUP"; then
                CAN_USE_KVM=1
            fi
        fi
    fi

    if [[ $CAN_USE_KVM -eq 1 ]] && grep -qE '(vmx|svm)' /proc/cpuinfo 2>/dev/null; then
        KVM_AVAILABLE=1; KVM_MODE="kvm"
        echo -e "${G}🚀 KVM ACCELERATION: BẬT${W}"
    else
        echo -e "${Y}⚠${W}  Không đủ quyền dùng /dev/kvm — dùng TCG"
        KVM_AVAILABLE=0; KVM_MODE="tcg"
    fi
}

# ════════════════════════════════════════════════════════════════
#  APT DETECTION
# ════════════════════════════════════════════════════════════════
APT_CMD=""
APT_OK=0
ROOTLESS=0

_detect_apt() {
    if [[ "$(id -u)" == "0" ]] && apt-get update -qq > /dev/null 2>&1; then
        APT_CMD="apt-get"; APT_OK=1; return
    fi
    if sudo -n true 2>/dev/null && sudo apt-get update -qq > /dev/null 2>&1; then
        APT_CMD="sudo apt-get"; APT_OK=1; return
    fi
    APT_OK=0; ROOTLESS=1
}

apt_install() {
    local pkg="$1"
    $APT_CMD install -y -qq "$pkg" > /dev/null 2>&1
}

# ════════════════════════════════════════════════════════════════
#  ARIA2
# ════════════════════════════════════════════════════════════════
ARIA2_OPTS=(
    --split=16 --max-connection-per-server=16 --min-split-size=1M
    --max-concurrent-downloads=16 --file-allocation=none --continue=true
    --check-certificate=false --max-tries=5 --retry-wait=3 --timeout=60
    --connect-timeout=15 --piece-length=1M --human-readable=true
    --download-result=full --console-log-level=notice --summary-interval=3
)

_ensure_aria2() {
    command -v aria2c &>/dev/null && return 0
    local _bin_dir="${PREFIX:-$HOME/qemu-static}/bin"
    mkdir -p "$_bin_dir"
    local _aria2_url="https://github.com/abcfy2/aria2-static-build/releases/latest/download/aria2-x86_64-linux-musl_static.zip"
    local _tmp_zip="/tmp/aria2-static-$$.zip"
    local _tmp_dir="/tmp/aria2-static-$$"

    if wget -q --no-check-certificate "$_aria2_url" -O "$_tmp_zip" 2>/dev/null; then
        mkdir -p "$_tmp_dir"
        if unzip -q "$_tmp_zip" -d "$_tmp_dir" 2>/dev/null; then
            local _aria2c=$(find "$_tmp_dir" -name "aria2c" -type f | head -1)
            if [[ -n "$_aria2c" ]]; then
                install -m755 "$_aria2c" "$_bin_dir/aria2c"
                export PATH="$_bin_dir:$PATH"
                rm -rf "$_tmp_zip" "$_tmp_dir"
                return 0
            fi
        fi
        rm -rf "$_tmp_zip" "$_tmp_dir"
    fi
    if [[ -n "$APT_CMD" ]]; then
        $APT_CMD install -y -qq aria2 > /dev/null 2>&1 && return 0
    fi
    return 1
}

# ════════════════════════════════════════════════════════════════
#  ROOTLESS BUILD (AppImage)
# ════════════════════════════════════════════════════════════════
_rootless_build() {
    local ROOTLESS_PREFIX="$HOME/qemu-static"
    local ROOTLESS_BIN_DIR="$ROOTLESS_PREFIX/bin"
    local ROOTLESS_APPIMAGE_DIR="$ROOTLESS_PREFIX/share/qemu-appimage"
    local ROOTLESS_APPIMAGE="$ROOTLESS_APPIMAGE_DIR/QEMU-x86_64.AppImage"
    local ROOTLESS_QEMU="$ROOTLESS_BIN_DIR/qemu-system-x86_64"

    _rootless_make_wrappers() {
        local _appimage="$1"
        local _bin_dir="$2"
        mkdir -p "$_bin_dir"
        for _cmd in qemu-system-x86_64 qemu-img qemu-nbd qemu-io; do
            printf '#!/bin/sh\nexec "%s" --appimage-extract-and-run "%s" "$@"\n' \
                "$_appimage" "$_cmd" > "$_bin_dir/$_cmd"
            chmod +x "$_bin_dir/$_cmd"
        done
    }

    mkdir -p "$ROOTLESS_PREFIX" "$ROOTLESS_APPIMAGE_DIR"

    if [[ -x "$ROOTLESS_QEMU" ]] && [[ -f "$ROOTLESS_APPIMAGE" ]]; then
        local rv=$("$ROOTLESS_QEMU" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
        echo -e "${G}⚡ QEMU AppImage v${rv} đã tồn tại${W}"
        export QEMU_BIN="$ROOTLESS_QEMU"
        export PREFIX="$ROOTLESS_PREFIX"
        export PATH="$ROOTLESS_BIN_DIR:$PATH"
        return 0
    fi

    echo -e "${C}════════════════════════════════════${W}"
    echo -e "${C}🔧 Tải QEMU AppImage...${W}"
    echo -e "${C}════════════════════════════════════${W}"

    local _urls=(
        "https://github.com/pkgforge-dev/QEMU-AppImage/releases/download/11.0.0-1%402026-05-02_1777749420/QEMU-11.0.0-1-anylinux-x86_64.AppImage"
        "https://github.com/lucasmz1/Qemu-AppImage/releases/download/continuous-stable-jammy/QEMU-git-x86_64.AppImage"
    )

    for _url in "${_urls[@]}"; do
        rm -f "$ROOTLESS_APPIMAGE"
        if wget -q --progress=bar:force:noscroll -O "$ROOTLESS_APPIMAGE" "$_url" 2>/dev/null; then
            chmod +x "$ROOTLESS_APPIMAGE"
            if timeout 20 "$ROOTLESS_APPIMAGE" --appimage-extract-and-run qemu-system-x86_64 --version >/dev/null 2>&1; then
                _rootless_make_wrappers "$ROOTLESS_APPIMAGE" "$ROOTLESS_BIN_DIR"
                export QEMU_BIN="$ROOTLESS_QEMU"
                export PREFIX="$ROOTLESS_PREFIX"
                export PATH="$ROOTLESS_BIN_DIR:$PATH"
                echo -e "${G}✔${W} QEMU AppImage sẵn sàng"
                return 0
            fi
        fi
    done

    echo -e "${R}✘${W} Không tải được QEMU AppImage"
    return 1
}

# ════════════════════════════════════════════════════════════════
#  MAIN FLOW
# ════════════════════════════════════════════════════════════════

# Khởi động web dashboard
_start_web_server

# Detect environment
_detect_apt
_detect_kvm

# Đợi config từ web
_wait_web_config || {
    echo -e "${R}✘${W} Không nhận được config. Thoát."
    exit 1
}

# Set Windows config
WIN_NAME="${ISO_NAMES[$win_choice]}"
WIN_URL="${ISO_URLS[$win_choice]}"
USE_UEFI="${ISO_UEFI[$win_choice]}"
RDP_USER="${ISO_USERS[$win_choice]}"
RDP_PASS="${ISO_PASSES[$win_choice]}"

echo -e "${G}✔${W} Image: ${C}${WIN_NAME}${W}"
echo -e "${G}✔${W} User: ${C}${RDP_USER}${W} / ${C}${RDP_PASS}${W}"

# QEMU detection/build
QEMU_BIN="/usr/bin/qemu-system-x86_64"
OPT_QEMU="/opt/qemu-optimized/bin/qemu-system-x86_64"
HOME_QEMU="$HOME/qemu-optimized/bin/qemu-system-x86_64"
ROOTLESS_QEMU="$HOME/qemu-static/bin/qemu-system-x86_64"

_qemu_found=0
for q in "$OPT_QEMU" "$HOME_QEMU" "$ROOTLESS_QEMU" "$QEMU_BIN" "$(command -v qemu-system-x86_64 2>/dev/null)"; do
    if [[ -n "$q" && -x "$q" ]]; then
        QEMU_VER=$("$q" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
        echo -e "${G}⚡ QEMU v${QEMU_VER} tại: $q${W}"
        export QEMU_BIN="$q"
        export PATH="$(dirname "$q"):$PATH"
        _qemu_found=1
        break
    fi
done

if [[ "$_qemu_found" == "0" ]]; then
    if [[ "$ROOTLESS" == "1" ]] || [[ "$APT_OK" == "0" ]]; then
        echo -e "${B}ℹ${W}  Không có QEMU — tải AppImage..."
        _rootless_build || { echo -e "${R}✘${W} Không thể có QEMU"; exit 1; }
    else
        echo -e "${B}ℹ${W}  Không có QEMU — cài qua apt..."
        $APT_CMD install -y -qq qemu-system-x86 qemu-utils 2>/dev/null || true
        if command -v qemu-system-x86_64 &>/dev/null; then
            QEMU_BIN=$(command -v qemu-system-x86_64)
            export QEMU_BIN
        else
            _rootless_build || { echo -e "${R}✘${W} Không thể có QEMU"; exit 1; }
        fi
    fi
fi

QEMU_IMG="$(_resolve_qemu_img 2>/dev/null || echo "")"
[[ -z "$QEMU_IMG" ]] && QEMU_IMG="$(dirname "$QEMU_BIN")/qemu-img"

# ════════════════════════════════════════════════════════════════
#  TẢI WINDOWS IMAGE
# ════════════════════════════════════════════════════════════════
WIN_IMG_PATH="${PWD}/win.img"

_img_valid() {
    local f="$1"
    [[ -f "$f" ]] || return 1
    local sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
    [[ "$sz" -ge 2147483648 ]] && return 0
    return 1
}

if _img_valid "$WIN_IMG_PATH"; then
    echo -e "${G}✔${W} Image đã có — bỏ qua tải"
else
    echo ""
    echo -e "${C}════════════════════════════════════${W}"
    echo -e "${C}⬇  Đang tải: ${Y}${WIN_NAME}${W}"
    echo -e "${C}════════════════════════════════════${W}"

    _ensure_aria2 || true

    if command -v aria2c &>/dev/null; then
        aria2c "${ARIA2_OPTS[@]}" "$WIN_URL" -d "$(dirname "$WIN_IMG_PATH")" -o "$(basename "$WIN_IMG_PATH")"
    else
        wget --progress=bar:force --continue "$WIN_URL" -O "$WIN_IMG_PATH"
    fi

    if _img_valid "$WIN_IMG_PATH"; then
        echo -e "${G}✔${W} Tải xong"
    else
        echo -e "${R}✘${W} Tải thất bại hoặc file không hợp lệ"
        exit 1
    fi
fi

# ════════════════════════════════════════════════════════════════
#  RESIZE DISK
# ════════════════════════════════════════════════════════════════
extra_gb=20
if [[ -n "$QEMU_IMG" && -x "$QEMU_IMG" ]]; then
    echo -e "${B}ℹ${W}  Mở rộng disk +${extra_gb}GB..."
    "$QEMU_IMG" resize "$WIN_IMG_PATH" "+${extra_gb}G" 2>/dev/null || true
fi

# ════════════════════════════════════════════════════════════════
#  CẤU HÌNH VM
# ════════════════════════════════════════════════════════════════
echo ""
echo -e "${C}════════════════════════════════════${W}"
echo -e "${C}⚙  CẤU HÌNH VM${W}"
echo -e "${C}════════════════════════════════════${W}"
echo -e "🖥️  CPU: ${B}${cpu_core}${W} cores"
echo -e "💾 RAM: ${B}${ram_size}${W} GB"

# ════════════════════════════════════════════════════════════════
#  TCG TUNING (nếu không có KVM)
# ════════════════════════════════════════════════════════════════
if [[ "$KVM_AVAILABLE" == "0" ]]; then
    export MALLOC_ARENA_MAX=4
    export MALLOC_MMAP_THRESHOLD_=131072
    export QEMU_AUDIO_DRV=none

    _host_ram_gb=$(awk '/MemTotal/{printf "%.0f",$2/1024/1024}' /proc/meminfo)
    [[ "${_host_ram_gb:-0}" -lt 1 ]] && _host_ram_gb=4
    TCG_TB_MB=$(( _host_ram_gb * 1024 * 6 / 100 ))
    [[ "$TCG_TB_MB" -lt 4096  ]] && TCG_TB_MB=4096
    [[ "$TCG_TB_MB" -gt 8192 ]] && TCG_TB_MB=8192

    echo -e "${G}⚡ TCG TB cache: ${TCG_TB_MB}MB${W}"

    _raw_cpu_name=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | sed 's/^.*: //' || echo "")
    _cpu_vendor=$(grep -m1 "vendor_id" /proc/cpuinfo 2>/dev/null | awk '{print $NF}' || echo "")

    if [[ -n "$_raw_cpu_name" && "$_raw_cpu_name" != "unknown" ]]; then
        cpu_host="$_raw_cpu_name"
        cpu_model_id=$(printf '%s' "$cpu_host" | tr ',' ' ' | tr -d '"\\@#$%^&*|<>' | sed 's/[[:space:]]\+/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//' | cut -c1-48)
    else
        case "$_cpu_vendor" in
            GenuineIntel) cpu_host="Intel Xeon"; cpu_model_id="Intel Xeon Processor" ;;
            AuthenticAMD) cpu_host="AMD EPYC"; cpu_model_id="AMD EPYC Processor" ;;
            *) cpu_host="Generic"; cpu_model_id="Generic x86_64 Processor" ;;
        esac
    fi

    CPU_EXTRA=""
    grep -q ssse3  /proc/cpuinfo && CPU_EXTRA="$CPU_EXTRA,+ssse3"
    grep -q sse4_1 /proc/cpuinfo && CPU_EXTRA="$CPU_EXTRA,+sse4.1"
    grep -q sse4_2 /proc/cpuinfo && CPU_EXTRA="$CPU_EXTRA,+sse4.2"
    grep -q ' avx ' /proc/cpuinfo && CPU_EXTRA="$CPU_EXTRA,+avx"
    grep -q avx2   /proc/cpuinfo && CPU_EXTRA="$CPU_EXTRA,+avx2"

    cpu_model="max,hypervisor=off,tsc=on,pmu=off,l3-cache=on,+cmov,+mmx,+fxsr,+sse2,+cx16,+x2apic,+sep,+pat,+pse,+aes,+popcnt,-tsc-deadline${CPU_EXTRA},model-id=${cpu_model_id}"
fi

# ════════════════════════════════════════════════════════════════
#  OVMF (UEFI)
# ════════════════════════════════════════════════════════════════
OVMF_PATH=""
if [[ "$USE_UEFI" == "yes" ]]; then
    for _ovmf in /usr/share/qemu/OVMF.fd /usr/share/ovmf/OVMF.fd /usr/share/OVMF/OVMF_CODE.fd; do
        [[ -f "$_ovmf" ]] && { OVMF_PATH="$_ovmf"; break; }
    done

    if [[ -z "$OVMF_PATH" ]]; then
        echo -e "${Y}⚠${W}  OVMF không tìm thấy — tải..."
        mkdir -p /tmp/ovmf
        if wget -q -O /tmp/ovmf/OVMF.fd "https://github.com/nicowillis/ovmf-prebuilt/raw/main/OVMF.fd" 2>/dev/null; then
            OVMF_PATH="/tmp/ovmf/OVMF.fd"
        fi
    fi

    if [[ -n "$OVMF_PATH" ]]; then
        echo -e "${G}✔${W} OVMF: $OVMF_PATH"
    else
        echo -e "${Y}⚠${W}  Không có OVMF — dùng BIOS"
    fi
fi

# ════════════════════════════════════════════════════════════════
#  BUILD QEMU COMMAND
# ════════════════════════════════════════════════════════════════
INSTANCE_ID=1
WINVM_RDP_PORT=$((3388 + INSTANCE_ID))
WINVM_QMP_SOCK="/tmp/winvm-${INSTANCE_ID}.qmp"
WINVM_PID_FILE="/tmp/winvm-${INSTANCE_ID}.pid"

rm -f "$WINVM_QMP_SOCK"

if [[ "$KVM_AVAILABLE" == "1" ]]; then
    QEMU_CMD=(
        "$QEMU_BIN"
        -machine q35,hpet=off
        -cpu host
        -smp "$cpu_core"
        -m "${ram_size}G"
        -accel kvm
        -rtc base=localtime,clock=host
    )
    NET_DEVICE="-device virtio-net-pci,netdev=n0"
    echo -e "${G}⚡ KVM mode: -cpu host -accel kvm${W}"
else
    QEMU_CMD=(
        "$QEMU_BIN"
        -machine q35,hpet=off,vmport=off,mem-merge=off
        -cpu "$cpu_model"
        -smp "$cpu_core,cores=$cpu_core,threads=1,sockets=1"
        -m "${ram_size}G"
        -accel "tcg,thread=multi,split-wx=off,one-insn-per-tb=off,tb-size=$TCG_TB_MB"
        -rtc base=localtime
        -overcommit cpu-pm=on
        -boot order=c,strict=on
        -no-shutdown
        -device virtio-mouse-pci
        -device virtio-keyboard-pci
        -nodefaults
        -smbios type=1,manufacturer="Dell Inc.",product="PowerEdge R640"
        -no-user-config
    )
    NET_DEVICE="-device virtio-net-pci,netdev=n0"
    echo -e "${Y}⚡ TCG mode: software emulation${W}"
fi

[[ -n "$OVMF_PATH" ]] && QEMU_CMD+=(-bios "$OVMF_PATH")

QEMU_CMD+=(
    -drive "file=$WIN_IMG_PATH,if=none,id=disk0,cache=unsafe,aio=threads,format=raw"
    -device virtio-blk-pci,drive=disk0,iothread=io1,num-queues=4,queue-size=256
    -object iothread,id=io1
)

QEMU_CMD+=(
    -netdev "user,id=n0,hostfwd=tcp::${WINVM_RDP_PORT}-:3389"
    $NET_DEVICE
)

QEMU_CMD+=(
    -vga virtio
    -vnc :0
    -device nec-usb-xhci
    -device usb-tablet
)

if [[ -e /dev/urandom ]]; then
    QEMU_CMD+=(-object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0)
fi

QEMU_CMD+=(-qmp "unix:$WINVM_QMP_SOCK,server,nowait")

# ════════════════════════════════════════════════════════════════
#  KHỞI ĐỘNG VM
# ════════════════════════════════════════════════════════════════
echo ""
echo -e "${B}ℹ${W}  Khởi động ${WIN_NAME}..."

QEMU_LOG="/tmp/qemu-launch-$$.log"
nohup "${QEMU_CMD[@]}" >> "$QEMU_LOG" 2>&1 &
QEMU_PID=$!
echo "$QEMU_PID" > "$WINVM_PID_FILE"
disown "$QEMU_PID"

sleep 4
if kill -0 "$QEMU_PID" 2>/dev/null; then
    echo -e "${G}✔${W} VM đã khởi động (PID: $QEMU_PID)"
else
    echo -e "${R}✘${W} VM KHÔNG khởi động được!"
    cat "$QEMU_LOG"
    exit 1
fi

# ════════════════════════════════════════════════════════════════
#  HIỂN THỊ THÔNG TIN KẾT NỐI
# ════════════════════════════════════════════════════════════════
echo ""
echo -e "${C}══════════════════════════════════════════════${W}"
echo -e "${C}🚀 WINBOX READY${W}"
echo -e "${C}══════════════════════════════════════════════${W}"
echo -e "🪟 OS        : ${Y}${WIN_NAME}${W}"
echo -e "⚙️  CPU      : ${B}${cpu_core}${W} cores"
echo -e "💾 RAM       : ${B}${ram_size}${W} GB"
if [[ "$KVM_AVAILABLE" == "1" ]]; then
    echo -e "⚡ Accel     : ${G}KVM (hardware)${W}"
else
    echo -e "⚡ Accel     : ${Y}TCG (software)${W}"
fi
echo -e "${C}──────────────────────────────────────────────${W}"
echo -e "📡 RDP       : ${G}localhost:${WINVM_RDP_PORT}${W}"
echo -e "👤 Username  : ${Y}${RDP_USER}${W}"
echo -e "🔑 Password  : ${Y}${RDP_PASS}${W}"
echo -e "${C}──────────────────────────────────────────────${W}"
echo -e "🖥️  VNC       : ${G}:5900${W}"
echo -e "   → vncviewer localhost:5900"
echo -e "${C}══════════════════════════════════════════════${W}"
echo -e "${G}🟢 Status    : RUNNING (PID: $QEMU_PID)${W}"
echo -e "${C}══════════════════════════════════════════════${W}"

# Cập nhật web dashboard với thông tin RDP
if [[ -f "$WEB_PID_FILE" ]]; then
    python3 - "$WEB_DIR" "$WIN_NAME" "$cpu_core" "$ram_size" "$WINVM_RDP_PORT" "$RDP_USER" "$RDP_PASS" << 'PYUPDATE'
import sys, os, json
web_dir, win_name, cpu, ram, rdp_port, rdp_user, rdp_pass = sys.argv[1:8]
info = {
    "win_name": win_name, "cpu": cpu, "ram": ram,
    "rdp_host": "localhost", "rdp_port": rdp_port,
    "rdp_user": rdp_user, "rdp_pass": rdp_pass,
    "vnc": "localhost:5900", "status": "running"
}
with open(os.path.join(web_dir, 'rdp-info.json'), 'w') as f:
    json.dump(info, f)
PYUPDATE
fi

# Giữ script chạy
if [[ -t 0 ]]; then
    echo ""
    echo -e "${B}ℹ${W}  Nhấn ${C}Ctrl+C${W} để dừng VM và thoát"
    trap 'echo -e "\n${Y}⚠${W}  Đang dừng VM..."; kill "$QEMU_PID" 2>/dev/null; rm -f "$WINVM_PID_FILE" "$WEB_PID_FILE"; exit 0' INT
    while kill -0 "$QEMU_PID" 2>/dev/null; do
        sleep 5
    done
    echo -e "${R}✘${W} VM đã dừng"
else
    echo -e "${G}✔${W} VM đang chạy nền. PID: $QEMU_PID"
fi
