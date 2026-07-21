#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════
#  apply_webui_patch.sh
#  Chèn Web UI quản lý VM vào winbox.sh gốc — KHÔNG sửa bất kỳ dòng
#  logic build/tải/launch QEMU nào. Chỉ chèn thêm code mới tại 4 vị
#  trí neo cố định, dùng chính các flag CLI đã có sẵn trong script
#  gốc (--stop / --restart / --snapshot=) để điều khiển VM.
#
#  Cách dùng:
#    bash apply_webui_patch.sh winbox.sh            # -> winbox_webui.sh
#    bash apply_webui_patch.sh winbox.sh out.sh      # tuỳ chỉnh tên output
#
#  An toàn: nếu không tìm thấy đủ 4 vị trí neo trong file gốc (vì bạn
#  sửa đổi file gốc khác với bản đã cung cấp), script sẽ DỪNG và báo
#  lỗi rõ ràng, KHÔNG tạo ra file output bị hỏng nửa chừng.
# ════════════════════════════════════════════════════════════════
set -euo pipefail

SRC="${1:-winbox.sh}"
OUT="${2:-winbox_webui.sh}"

if [[ ! -f "$SRC" ]]; then
    echo "✘ Không tìm thấy file gốc: $SRC" >&2
    echo "  Dùng: bash apply_webui_patch.sh /duong/dan/winbox.sh" >&2
    exit 1
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# ── 4 khối code sẽ được chèn ─────────────────────────────────────

cat > "$WORKDIR/anchor1_after.txt" << 'ANCHOR1'
ISO_VIRTIO_URL="" # URL VirtIO ISO (optional)
ANCHOR1
cat > "$WORKDIR/insert1.txt" << 'INSERT1'
WINBOX_WEBUI="${WINBOX_WEBUI:-1}"           # 1 = bật giao diện web quản lý VM (mặc định bật)
WINBOX_WEBUI_PORT="${WINBOX_WEBUI_PORT:-}"  # port tuỳ chỉnh, để trống = tự tính theo --id
INSERT1

cat > "$WORKDIR/anchor2_after.txt" << 'ANCHOR2'
        --no-vnc)      WINBOX_VNC=0 ;;
ANCHOR2
cat > "$WORKDIR/insert2.txt" << 'INSERT2'
        --no-webui)     WINBOX_WEBUI=0 ;;
        --webui-port=*) WINBOX_WEBUI_PORT="${_arg#--webui-port=}" ;;
INSERT2

cat > "$WORKDIR/anchor3_after.txt" << 'ANCHOR3'
_qmp() {
    local cmd="$1"
    if ! command -v socat &>/dev/null; then echo "socat not found"; return 1; fi
    if [[ ! -S "$WINVM_QMP_SOCK" ]]; then echo "QMP socket not found: $WINVM_QMP_SOCK"; return 1; fi
    printf '{"execute":"qmp_capabilities"}\n{"execute":"%s"}\n' "$cmd" \
        | socat - UNIX-CONNECT:"$WINVM_QMP_SOCK" 2>/dev/null | tail -1
}
ANCHOR3
cat > "$WORKDIR/insert3.txt" << 'INSERT3'

# ════════════════════════════════════════════════════════════════
#  WEB UI — Giao diện quản lý VM (chỉ hiển thị/điều khiển, KHÔNG
#  đụng vào logic build/tải/launch QEMU. Mọi hành động (stop/restart/
#  snapshot) đều gọi lại chính script này với các flag CLI đã có sẵn
#  --stop / --restart / --snapshot=... — không tự viết logic mới.
# ════════════════════════════════════════════════════════════════
_webui_write_server() {
    local _py="$1"
    cat > "$_py" << 'PYEOF'
#!/usr/bin/env python3
import json, os, subprocess, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CFG_PATH = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("WINBOX_WEBUI_CFG", "")
with open(CFG_PATH) as f:
    CFG = json.load(f)

SCRIPT = CFG["script"]
INSTANCE_ID = str(CFG["instance_id"])

def run_script(extra_args):
    cmd = ["bash", SCRIPT, f"--id={INSTANCE_ID}"] + extra_args
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        return {"ok": p.returncode == 0, "stdout": p.stdout[-4000:], "stderr": p.stderr[-4000:]}
    except Exception as e:
        return {"ok": False, "stdout": "", "stderr": str(e)}

def read_state():
    st = {}
    try:
        with open(CFG["state_file"]) as f:
            st = json.load(f)
    except Exception:
        pass
    pid = st.get("pid")
    running = False
    if pid:
        try:
            os.kill(int(pid), 0)
            running = True
        except Exception:
            running = False
    return {
        "running": running,
        "pid": pid,
        "instance_id": CFG["instance_id"],
        "win_name": CFG.get("win_name"),
        "rdp_port": CFG.get("rdp_port"),
        "rdp_user": CFG.get("rdp_user"),
        "rdp_pass": CFG.get("rdp_pass"),
    }

def tail_log(n=200):
    path = CFG.get("log_file", "")
    if not path or not os.path.exists(path):
        return []
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            block = 8192
            data = b""
            while size > 0 and data.count(b"\n") <= n:
                step = min(block, size)
                size -= step
                f.seek(size)
                data = f.read(step) + data
        return data.decode(errors="replace").splitlines()[-n:]
    except Exception as e:
        return [f"(log read error: {e})"]

HTML = """<!doctype html>
<html lang="vi"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>WinBox VM Manager</title>
<style>
:root{color-scheme:dark}
body{font-family:system-ui,Segoe UI,Roboto,sans-serif;background:#0f1115;color:#e6e6e6;margin:0;padding:24px}
.card{background:#171a21;border:1px solid #2a2f3a;border-radius:12px;padding:20px;max-width:760px;margin:0 auto 16px}
h1{font-size:20px;margin:0 0 12px}
.row{display:flex;gap:8px;flex-wrap:wrap;margin:10px 0}
button{background:#2563eb;color:#fff;border:0;border-radius:8px;padding:9px 14px;cursor:pointer;font-size:14px}
button.danger{background:#dc2626}
button.secondary{background:#374151}
button:hover{filter:brightness(1.1)}
.badge{display:inline-block;padding:3px 10px;border-radius:999px;font-size:12px;font-weight:600}
.badge.on{background:#14532d;color:#86efac}
.badge.off{background:#450a0a;color:#fca5a5}
table{width:100%;border-collapse:collapse;font-size:14px}
td{padding:6px 4px;border-bottom:1px solid #232838}
td.k{color:#9ca3af;width:140px}
pre{background:#0b0d12;border:1px solid #232838;border-radius:8px;padding:10px;max-height:320px;overflow:auto;font-size:12px}
input{background:#0b0d12;border:1px solid #2a2f3a;color:#e6e6e6;border-radius:6px;padding:6px 8px}
.toast{position:fixed;bottom:16px;right:16px;background:#1f2937;padding:10px 14px;border-radius:8px;display:none}
</style></head>
<body>
<div class="card">
  <h1>⬡ WinBox — VM Manager <span id="badge" class="badge off">...</span></h1>
  <table id="info"></table>
  <div class="row">
    <button onclick="act('stop')" class="danger">Dừng VM</button>
    <button onclick="act('restart')" class="secondary">Khởi động lại</button>
    <button onclick="refresh()" class="secondary">Làm mới</button>
  </div>
</div>
<div class="card">
  <h1>📸 Snapshot</h1>
  <div class="row">
    <input id="snapname" placeholder="tên snapshot" value="checkpoint1">
    <button onclick="snap('save')">Lưu</button>
    <button onclick="snap('load')">Nạp</button>
    <button onclick="snap('list')" class="secondary">Danh sách</button>
  </div>
  <pre id="snapout"></pre>
</div>
<div class="card">
  <h1>📜 Log gần đây</h1>
  <pre id="log">(đang tải...)</pre>
</div>
<div class="toast" id="toast"></div>
<script>
function toast(msg){const t=document.getElementById('toast');t.textContent=msg;t.style.display='block';setTimeout(()=>t.style.display='none',3000)}
async function refresh(){
  const r = await fetch('/api/status'); const s = await r.json();
  document.getElementById('badge').textContent = s.running ? 'RUNNING' : 'STOPPED';
  document.getElementById('badge').className = 'badge ' + (s.running ? 'on' : 'off');
  document.getElementById('info').innerHTML = `
    <tr><td class="k">Windows</td><td>${s.win_name||'-'}</td></tr>
    <tr><td class="k">Instance ID</td><td>${s.instance_id}</td></tr>
    <tr><td class="k">PID</td><td>${s.pid||'-'}</td></tr>
    <tr><td class="k">RDP</td><td>localhost:${s.rdp_port}</td></tr>
    <tr><td class="k">User / Pass</td><td>${s.rdp_user} / ${s.rdp_pass}</td></tr>`;
  const lr = await fetch('/api/log'); const lj = await lr.json();
  document.getElementById('log').textContent = (lj.lines||[]).join('\\n') || '(trống)';
}
async function act(a){
  toast('Đang thực hiện: ' + a + ' ...');
  const r = await fetch('/api/action', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({action:a})});
  const j = await r.json();
  toast(j.ok ? 'Xong: ' + a : 'Lỗi: ' + a);
  setTimeout(refresh, 1500);
}
async function snap(mode){
  const name = document.getElementById('snapname').value || 'checkpoint1';
  const r = await fetch('/api/action', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({action:'snapshot', mode, name})});
  const j = await r.json();
  document.getElementById('snapout').textContent = (j.stdout||'') + '\\n' + (j.stderr||'');
}
refresh();
setInterval(refresh, 5000);
</script>
</body></html>"""

class Handler(BaseHTTPRequestHandler):
    def _send(self, code, payload, ctype="application/json"):
        body = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass

    def do_GET(self):
        if self.path == "/" or self.path.startswith("/index"):
            self._send(200, HTML.encode(), "text/html; charset=utf-8")
        elif self.path == "/api/status":
            self._send(200, read_state())
        elif self.path.startswith("/api/log"):
            self._send(200, {"lines": tail_log()})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/api/action":
            self._send(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length", 0))
        try:
            data = json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            data = {}
        action = data.get("action", "")
        if action == "stop":
            res = run_script(["--stop"])
        elif action == "restart":
            res = run_script(["--restart"])
        elif action == "snapshot":
            mode = data.get("mode", "list")
            name = data.get("name", "checkpoint1")
            if mode == "list":
                res = run_script(["--snapshot=list"])
            else:
                res = run_script([f"--snapshot={mode}:{name}"])
        else:
            res = {"ok": False, "stdout": "", "stderr": "unknown action"}
        self._send(200, res)

def main():
    port = int(CFG.get("port", 7860))
    srv = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    srv.serve_forever()

if __name__ == "__main__":
    main()
PYEOF
    chmod +x "$_py"
}

_webui_start() {
    [[ "${WINBOX_WEBUI:-1}" == "0" ]] && return 0
    if ! command -v python3 &>/dev/null; then
        echo -e "${Y}⚠${W}  python3 không có — bỏ qua Web UI quản lý VM"
        return 1
    fi

    local _port="${WINBOX_WEBUI_PORT:-$(( 7860 + INSTANCE_ID ))}"
    local _py="/tmp/winbox-webui-${INSTANCE_ID}.py"
    local _cfg="/tmp/winbox-webui-${INSTANCE_ID}.json"
    local _pidf="/tmp/winbox-webui-${INSTANCE_ID}.pid"
    local _log="/tmp/winbox-webui-${INSTANCE_ID}.serve.log"
    local _script_path
    _script_path="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"

    if [[ -f "$_pidf" ]]; then
        local _oldpid; _oldpid=$(cat "$_pidf" 2>/dev/null || echo "")
        [[ -n "$_oldpid" ]] && kill "$_oldpid" 2>/dev/null || true
    fi

    _webui_write_server "$_py"

    python3 - "$_cfg" << PYCFG
import json
json.dump({
    "script": "${_script_path}",
    "instance_id": ${INSTANCE_ID},
    "state_file": "${WINVM_STATE_FILE}",
    "log_file": "${WINVM_LOG}",
    "port": ${_port},
    "win_name": "${WIN_NAME:-}",
    "rdp_port": ${WINVM_RDP_PORT},
    "rdp_user": "${RDP_USER:-}",
    "rdp_pass": "${RDP_PASS:-}"
}, open("${_cfg}", "w"))
PYCFG

    nohup python3 "$_py" "$_cfg" > "$_log" 2>&1 &
    local _webui_pid=$!
    echo "$_webui_pid" > "$_pidf"
    disown "$_webui_pid" 2>/dev/null || true
    sleep 1

    local _pub_ip=""
    _pub_ip=$(timeout 3 curl -fsS ifconfig.me 2>/dev/null || timeout 3 curl -fsS icanhazip.com 2>/dev/null || echo "")

    echo ""
    echo -e "${C}══════════════════════════════════════════════${W}"
    echo -e "${C}🖥  WEB UI — Quản lý VM${W}"
    echo -e "${C}══════════════════════════════════════════════${W}"
    if kill -0 "$_webui_pid" 2>/dev/null; then
        echo -e "🔗 Local  : ${G}http://localhost:${_port}${W}"
        [[ -n "$_pub_ip" ]] && echo -e "🔗 Public : ${G}http://${_pub_ip}:${_port}${W} (nếu firewall/port đã mở)"
        echo -e "${B}ℹ${W}  Tắt giao diện này: kill \$(cat ${_pidf})"
        echo -e "${B}ℹ${W}  Hoặc chạy lại script với cờ: --no-webui"
    else
        echo -e "${R}✘${W}  Web UI không khởi động được — xem log: ${_log}"
    fi
    echo -e "${C}══════════════════════════════════════════════${W}"
}
INSERT3

cat > "$WORKDIR/anchor4_after.txt" << 'ANCHOR4'
# ── SUMMARY ───────────────────────────────────────────────────────
ANCHOR4
cat > "$WORKDIR/insert4.txt" << 'INSERT4'
_webui_start

ANCHOR4_LINE_KEPT_BELOW
INSERT4
# anchor4 chèn TRƯỚC dòng neo (không phải sau) nên xử lý khác 3 cái trên,
# xem logic riêng ở dưới.

python3 - "$SRC" "$OUT" "$WORKDIR" << 'PYSCRIPT'
import sys, io

src_path, out_path, workdir = sys.argv[1], sys.argv[2], sys.argv[3]

def read(p):
    with open(p, "r", encoding="utf-8") as f:
        return f.read()

src = read(src_path)

def insert_after(text, anchor, insertion, label):
    idx = text.find(anchor)
    if idx == -1:
        print(f"✘ Không tìm thấy anchor '{label}' trong file gốc — dừng lại, không tạo file lỗi.", file=sys.stderr)
        sys.exit(1)
    pos = idx + len(anchor)
    return text[:pos] + "\n" + insertion + text[pos:]

def insert_before(text, anchor, insertion, label):
    idx = text.find(anchor)
    if idx == -1:
        print(f"✘ Không tìm thấy anchor '{label}' trong file gốc — dừng lại, không tạo file lỗi.", file=sys.stderr)
        sys.exit(1)
    return text[:idx] + insertion + "\n" + text[idx:]

anchor1 = read(f"{workdir}/anchor1_after.txt").rstrip("\n")
insert1 = read(f"{workdir}/insert1.txt")
anchor2 = read(f"{workdir}/anchor2_after.txt").rstrip("\n")
insert2 = read(f"{workdir}/insert2.txt")
anchor3 = read(f"{workdir}/anchor3_after.txt").rstrip("\n")
insert3 = read(f"{workdir}/insert3.txt")
anchor4 = read(f"{workdir}/anchor4_after.txt").rstrip("\n")

out = src
out = insert_after(out, anchor1, insert1, "1: globals (ISO_VIRTIO_URL)")
out = insert_after(out, anchor2, insert2, "2: CLI flag (--no-vnc)")
out = insert_after(out, anchor3, insert3, "3: sau ham _qmp()")
out = insert_before(out, anchor4, "_webui_start\n", "4: truoc # SUMMARY")

with open(out_path, "w", encoding="utf-8") as f:
    f.write(out)

print(f"✔ Đã tạo: {out_path}")
PYSCRIPT

if command -v bash >/dev/null 2>&1; then
    if bash -n "$OUT"; then
        echo "✔ Kiểm tra cú pháp bash: OK — $OUT sẵn sàng dùng."
        chmod +x "$OUT"
    else
        echo "✘ File output có lỗi cú pháp bash — kiểm tra lại anchor trong file gốc." >&2
        exit 1
    fi
fi
