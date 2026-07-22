#!/usr/bin/env bash
set -euo pipefail

# ════════════════════════════════════════════════════════════════
#  ToolVMBoxe - Setup Script cho Codespaces
#  Tự động cài đặt noVNC, websockify và khởi động dashboard
# ════════════════════════════════════════════════════════════════

R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'
B='\033[1;34m'; C='\033[1;36m'; W='\033[0m'

echo -e "${C}══════════════════════════════════════════════════${W}"
echo -e "${C}  ToolVMBoxe - Setup noVNC + Web Dashboard${W}"
echo -e "${C}══════════════════════════════════════════════════${W}"

# 1. Cài đặt dependencies
echo -e "${B}[1/5]${W} Cài đặt dependencies..."
sudo apt-get update -qq > /dev/null 2>&1 || true
sudo apt-get install -y -qq git python3-pip python3-venv novnc websockify 2>/dev/null || {
    echo -e "${Y}⚠${W}  Thử cài bằng pip..."
    pip3 install --user websockify 2>/dev/null || true
}

# 2. Clone noVNC nếu chưa có
NOVNC_DIR="$HOME/noVNC"
if [[ ! -d "$NOVNC_DIR" ]]; then
    echo -e "${B}[2/5]${W} Tải noVNC..."
    git clone --depth 1 https://github.com/novnc/noVNC.git "$NOVNC_DIR" 2>/dev/null || {
        echo -e "${Y}⚠${W}  Không clone được, dùng noVNC online..."
    }
else
    echo -e "${G}✔${W} noVNC đã có"
fi

# 3. Tạo dashboard HTML
echo -e "${B}[3/5]${W} Tạo dashboard..."
mkdir -p "$HOME/toolvmboxe"

# Copy dashboard (giả sử đã tải về)
DASHBOARD_URL="https://raw.githubusercontent.com/thanhtrung-devVNG/winboxe/main/toolvmboxe_dashboard.html"
if command -v wget &>/dev/null; then
    wget -q "$DASHBOARD_URL" -O "$HOME/toolvmboxe/index.html" 2>/dev/null || true
elif command -v curl &>/dev/null; then
    curl -fsSL "$DASHBOARD_URL" -o "$HOME/toolvmboxe/index.html" 2>/dev/null || true
fi

# 4. Tạo script khởi động VM + noVNC
cat > "$HOME/toolvmboxe/start_vm.sh" << 'EOF'
#!/bin/bash
# ToolVMBoxe - Start VM with noVNC

WINBOX_URL="https://raw.githubusercontent.com/thanhtrung-devVNG/winboxe/main/winboxe.sh"
VNC_PORT=5900
WEB_PORT=6080
WS_PORT=6081

echo "[+] Tải winbox..."
wget -q --show-progress -O winbox.sh "$WINBOX_URL" 2>/dev/null || curl -fsSL "$WINBOX_URL" -o winbox.sh

echo "[+] Khởi động VM..."
bash winbox.sh --auto --win10ltsc &

sleep 10

echo "[+] Khởi động websockify (noVNC proxy)..."
# websockify chuyển đổi WebSocket -> TCP cho VNC
websockify --web "$HOME/noVNC" --cert none "$WS_PORT" localhost:"$VNC_PORT" &

echo ""
echo "══════════════════════════════════════════════════"
echo "  🚀 ToolVMBoxe ĐÃ SẴN SÀNG!"
echo "══════════════════════════════════════════════════"
echo "  🌐 Dashboard:    http://localhost:3000"
echo "  🖥  noVNC:        http://localhost:6080/vnc.html"
echo "  📡 RDP:          localhost:3389"
echo "  👤 User:         Admin"
echo "  🔑 Pass:         Tam255Z"
echo "══════════════════════════════════════════════════"
EOF
chmod +x "$HOME/toolvmboxe/start_vm.sh"

# 5. Tạo script start server
cat > "$HOME/toolvmboxe/start_server.sh" << 'EOF'
#!/bin/bash
cd "$HOME/toolvmboxe"
python3 -m http.server 3000 &
echo "[+] Dashboard server: http://localhost:3000"
EOF
chmod +x "$HOME/toolvmboxe/start_server.sh"

echo -e "${B}[4/5]${W} Khởi động dashboard server..."
bash "$HOME/toolvmboxe/start_server.sh" &

echo -e "${B}[5/5]${W} Hoàn tất!"
echo ""
echo -e "${G}══════════════════════════════════════════════════${W}"
echo -e "${G}  ✅ ToolVMBoxe Setup Hoàn Tất!${W}"
echo -e "${G}══════════════════════════════════════════════════${W}"
echo ""
echo -e "  ${C}🌐 Dashboard Web:${W}   http://localhost:3000"
echo -e "  ${C}🖥  noVNC:${W}           http://localhost:6080/vnc.html"
echo -e "  ${C}📁 Thư mục:${W}         $HOME/toolvmboxe"
echo ""
echo -e "  ${Y}▶ Để tạo VM:${W}"
echo -e "     cd $HOME/toolvmboxe"
echo -e "     bash start_vm.sh"
echo ""
echo -e "  ${Y}▶ Hoặc chạy trực tiếp:${W}"
echo -e "     bash winboxe.sh --auto --win10ltsc"
echo ""
echo -e "${G}══════════════════════════════════════════════════${W}"
