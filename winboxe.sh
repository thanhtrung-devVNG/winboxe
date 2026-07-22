#!/usr/bin/env bash
set -euo pipefail

# Đảm bảo biến môi trường cơ bản khi chạy qua sudo su (HOME/USER có thể bị unset)
HOME="${HOME:-/root}"
USER="${USER:-$(id -un 2>/dev/null || echo root)}"
LOGNAME="${LOGNAME:-$USER}"
export HOME USER LOGNAME
NO_TUNING="${NO_TUNING:-0}"
ORIGINAL_ARGS=("$@")
ORIGINAL_PWD="$(pwd)"

# ════════════════════════════════════════════════════════════════
#  WINBOX - ToolVMBoxe Edition
#  Rootless: dùng QEMU AppImage prebuilt thay vì build libs/QEMU từ source
#  aria2: static binary (primary, ~5s), fallback apt, fallback conda (chậm)
#  Conda: CHỈ dùng làm fallback cuối (aria2 conda rất chậm, 5-20 phút)
#  Fix: removed --user from pip install (virtualenv compatibility)
#  KVM: Auto detect /dev/kvm → enable KVM acceleration if available
#  NEW: CLI flags --auto --winXXXX để chạy hoàn toàn không tương tác
#  NEW: Tự động skip build nếu QEMU đã tồn tại (--rebuild để build lại)
#
#  Cách dùng:
#    bash winbox                          # chế độ interactive như cũ
#    bash winbox --auto --win2012         # auto, Windows Server 2012 R2
#    bash winbox --auto --win2022         # auto, Windows Server 2022
#    bash winbox --auto --win11           # auto, Windows 11 LTSB
#    bash winbox --auto --win10ltsb       # auto, Windows 10 LTSB 2015
#    bash winbox --auto --win10ltsc       # auto, Windows 10 LTSC 2023
#    bash winbox --auto --win10ltsb2022   # auto, Windows 10 LTSB 2022
#    bash winbox --auto --win2012 --rdp   # auto + mở tunnel RDP
# ════════════════════════════════════════════════════════════════

# ── MÀU SẮC ────────────────────────────────────────────────────
R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'
B='\033[1;34m'; C='\033[1;36m'; W='\033[0m'

# ── ROOTLESS BUILD PROGRESS ──────────────────────────────────────
_rl_step() {
    local _n="$1" _t="$2"
    printf "${B}[%s/%s]${W}\n" "$_n" "$_t"
}
_rl_ok()   { echo -e "${G}✔${W} $1"; }
_rl_fail() { echo -e "${R}✘${W} $1"; }
_rl_warn() { echo -e "${Y}⚠${W}  $1"; }

# ════════════════════════════════════════════════════════════════
#  RESOLVE QEMU BINARY / QEMU-IMG
# ════════════════════════════════════════════════════════════════
_resolve_qemu_bin() {
    for q in \
        "${QEMU_BIN:-}" \
        "$HOME/qemu-static/bin/qemu-system-x86_64" \
        "$HOME/qemu-optimized/bin/qemu-system-x86_64" \
        "/opt/qemu-optimized/bin/qemu-system-x86_64" \
        "$(command -v qemu-system-x86_64 2>/dev/null)"; do
        [[ -n "$q" && -x "$q" ]] && { echo "$q"; return 0; }
    done
    return 1
}

_resolve_qemu_img() {
    for qi in \
        "$(dirname "${QEMU_BIN:-/nonexistent}")/qemu-img" \
        "${PREFIX:-}/bin/qemu-img" \
        "$HOME/qemu-static/bin/qemu-img" \
        "$HOME/qemu-optimized/bin/qemu-img" \
        "/opt/qemu-optimized/bin/qemu-img" \
        "/usr/bin/qemu-img" \
        "$(command -v qemu-img 2>/dev/null || true)"; do
        if [[ -x "$qi" ]]; then
            if "$qi" --version >/dev/null 2>&1; then
                echo "$qi"
                return 0
            fi
        fi
    done
    return 1
}

# ════════════════════════════════════════════════════════════════
#  PGO HELPERS
# ════════════════════════════════════════════════════════════════
_pgo_key_for_choice() {
    case "${1:-}" in
        1) echo "win2012pgo" ;;
        2) echo "win2022pgo" ;;
        3) echo "win11pgo" ;;
        4) echo "win10ltsbpgo" ;;
        5) echo "win10ltscpgo" ;;
        6|*) echo "win10ltsb2022pgo" ;;
    esac
}

_pgo_remote_url() {
    case "${1:-}" in
        win2012pgo)   echo "https://archive.org/download/win2012pgo.tar/win2012pgo.tar.gz" ;;
        win2022pgo)   echo "https://archive.org/download/win2022pgo.tar/win2022pgo.tar.gz" ;;
        win11pgo)     echo "https://archive.org/download/win11pgo.tar/win11pgo.tar.gz" ;;
        win10ltsbpgo) echo "https://archive.org/download/win10ltsbpgo.tar/win10ltsbpgo.tar.gz" ;;
        win10ltscpgo) echo "https://archive.org/download/win10ltscpgo.tar/win10ltscpgo.tar.gz" ;;
        win10ltsb2022pgo) echo "https://archive.org/download/win10ltsb2022pgo.tar/win10ltsb2022pgo.tar.gz" ;;
        *)            echo "" ;;
    esac
}

_pgo_download_remote() {
    local _url; _url="$(_pgo_remote_url "$PGO_PROFILE_KEY")"
    [[ -z "$_url" ]] && return 1

    echo -e "${B}ℹ${W}  Tải PGO profile từ xa: ${_url}"
    local _ok=0
    if command -v aria2c &>/dev/null; then
        aria2c "${ARIA2_OPTS[@]}" \
            "$_url" -d "$PGO_PROFILE_ROOT" -o "${PGO_PROFILE_KEY}.tar.gz" \
            >/dev/null 2>&1 && _ok=1
    elif command -v wget &>/dev/null; then
        wget -q --show-progress --continue \
            "$_url" -O "$PGO_PROFILE_ARCHIVE" 2>&1 && _ok=1
    elif command -v curl &>/dev/null; then
        curl -fL --progress-bar \
            "$_url" -o "$PGO_PROFILE_ARCHIVE" && _ok=1
    fi

    if [[ "$_ok" == "1" ]] \
        && [[ -f "$PGO_PROFILE_ARCHIVE" ]] \
        && [[ $(stat -c%s "$PGO_PROFILE_ARCHIVE" 2>/dev/null || echo 0) -gt 1024 ]] \
        && tar -tzf "$PGO_PROFILE_ARCHIVE" >/dev/null 2>&1; then
        echo -e "${G}✔${W}  PGO profile tải xong: $PGO_PROFILE_ARCHIVE"
        return 0
    else
        echo -e "${Y}⚠${W}  Tải PGO profile thất bại — sẽ generate lại"
        rm -f "$PGO_PROFILE_ARCHIVE" 2>/dev/null || true
        return 1
    fi
}

_pgo_prepare_context() {
    local _choice="${1:-5}"
    PGO_PROFILE_ROOT="${WINBOX_PGO_DIR:-$ORIGINAL_PWD}"
    mkdir -p "$PGO_PROFILE_ROOT"
    PGO_PROFILE_KEY="$(_pgo_key_for_choice "$_choice")"
    PGO_PROFILE_DIR="$PGO_PROFILE_ROOT/$PGO_PROFILE_KEY"
    PGO_PROFILE_ARCHIVE="$PGO_PROFILE_ROOT/${PGO_PROFILE_KEY}.tar.gz"
    PGO_PROFILE_READY=0
    PGO_PROFILE_KIND="gcc"
    PGO_LAUNCH_ENV=""

    if [[ ! -f "$PGO_PROFILE_ARCHIVE" ]]; then
        echo -e "${B}ℹ${W}  Không tìm thấy PGO archive local — thử tải từ xa..."
        _pgo_download_remote || true
    fi

    if [[ -f "$PGO_PROFILE_ARCHIVE" ]]; then
        if [[ $(stat -c%s "$PGO_PROFILE_ARCHIVE" 2>/dev/null || echo 0) -gt 1024 ]] && tar -tzf "$PGO_PROFILE_ARCHIVE" >/dev/null 2>&1; then
            rm -rf "$PGO_PROFILE_DIR"
            if tar -xzf "$PGO_PROFILE_ARCHIVE" -C "$PGO_PROFILE_ROOT" >/dev/null 2>&1; then
                PGO_PROFILE_READY=1
            fi
        fi
    fi
}

_pgo_stop_vm() {
    local _pid
    _pid=$(cat "$WINVM_PID_FILE" 2>/dev/null || echo "")
    if [[ -n "$_pid" ]] && kill -0 "$_pid" 2>/dev/null; then
        _qmp "quit" >/dev/null 2>&1 || true
        local _waited=0
        while kill -0 "$_pid" 2>/dev/null && [[ $_waited -lt 30 ]]; do
            sleep 1
            _waited=$(( _waited + 1 ))
        done
        if kill -0 "$_pid" 2>/dev/null; then
            kill -TERM "$_pid" 2>/dev/null || true
            sleep 5
        fi
        if kill -0 "$_pid" 2>/dev/null; then
            kill -9 "$_pid" 2>/dev/null || true
        fi
    fi
    sleep 2
}

_pgo_finalize_profile() {
    mkdir -p "$PGO_PROFILE_ROOT"
    local _has_profile=0
    if [[ "$PGO_PROFILE_KIND" == "clang" ]]; then
        if compgen -G "$PGO_PROFILE_DIR/*.profraw" >/dev/null || [[ -f "$PGO_PROFILE_DIR/default.profdata" ]]; then
            _has_profile=1
        fi
    else
        local _gcda_count
        _gcda_count=$(find "$PGO_PROFILE_DIR" -type f -name '*.gcda' 2>/dev/null | wc -l || echo 0)
        [[ "$_gcda_count" -gt 0 ]] && _has_profile=1
    fi
    if [[ "$_has_profile" -ne 1 ]]; then
        echo -e "${R}✘${W} Không tìm thấy profile hợp lệ"
        return 1
    fi
    rm -f "$PGO_PROFILE_ARCHIVE" 2>/dev/null || true
    tar -czf "$PGO_PROFILE_ARCHIVE" -C "$PGO_PROFILE_ROOT" "$PGO_PROFILE_KEY" >/dev/null 2>&1 || return 1
    return 0
}

# ════════════════════════════════════════════════════════════════
#  BOOTSTRAP TOOLS
# ════════════════════════════════════════════════════════════════
_bootstrap_tools() {
    local _apt=""
    if [[ "$(id -u)" == "0" ]] && command -v apt-get &>/dev/null; then _apt="apt-get"
    elif sudo -n true 2>/dev/null && command -v apt-get &>/dev/null; then _apt="sudo apt-get"; fi
    [[ -z "$_apt" ]] && return 0
    local _need=0
    for _t in wget curl gnupg ca-certificates; do command -v "$_t" &>/dev/null || _need=1; done
    [[ "$_need" == "0" ]] && return 0
    echo -e "${B}ℹ${W}  Bootstrap: cài công cụ thiết yếu..."
    export DEBIAN_FRONTEND=noninteractive
    $_apt update -qq > /dev/null 2>&1 || true
    for _pkg in wget curl gnupg ca-certificates lsb-release; do
        command -v "$_pkg" &>/dev/null || $_apt install -y -qq "$_pkg" > /dev/null 2>&1 || true
    done
}
_http_get() {
    local _url="$1" _out="${2:-}"
    if command -v wget &>/dev/null; then
        [[ -n "$_out" ]] && wget -qO "$_out" "$_url" || wget -qO- "$_url"
    elif command -v curl &>/dev/null; then
        [[ -n "$_out" ]] && curl -fsSL -o "$_out" "$_url" || curl -fsSL "$_url"
    else echo -e "${R}✘${W} Không có wget/curl" >&2; return 1; fi
}
_bootstrap_tools

# ════════════════════════════════════════════════════════════════
#  CLI ARGUMENT PARSER
# ════════════════════════════════════════════════════════════════
AUTO_MODE=0
AUTO_WIN=""
AUTO_BUILD=""
PGO_MODE=0
INSTANCE_ID=1
EXTRA_FWDS=()
_EXTRA_FWDS_STR=""
STATUS_MODE=0
STOP_MODE=0
RESTART_MODE=0
SNAPSHOT_CMD=""
RESIZE_IMG=""
MONITOR_MODE=0
DELETE_BUILD_MODE=0
DELETE_ISO_MODE=0
USE_HTTP_BACKEND=0
SAFE_DOWNLOAD=0
ISO_MODE=0
ISO_WIN_URL=""
ISO_VIRTIO_URL=""

for _arg in "$@"; do
    case "$_arg" in
        --auto)       AUTO_MODE=1    ;;
        --win2012)    AUTO_WIN=1     ;;
        --win2022)    AUTO_WIN=2     ;;
        --win11)      AUTO_WIN=3     ;;
        --win10ltsb)  AUTO_WIN=4     ;;
        --win10ltsb2022) AUTO_WIN=6  ;;
        --win10ltsc)  AUTO_WIN=5     ;;
        --build|--rebuild) AUTO_BUILD="yes" ;;
        --no-build)   AUTO_BUILD="no"  ;;
        --pgo)         PGO_MODE=1 ;;
        --http-img|--no-download) USE_HTTP_BACKEND=1 ;;
        --safe-download) SAFE_DOWNLOAD=1 ;;
        --id=*)       INSTANCE_ID="${_arg#--id=}" ;;
        --status)     STATUS_MODE=1 ;;
        --stop)       STOP_MODE=1   ;;
        --restart)    RESTART_MODE=1 ;;
        --monitor)    MONITOR_MODE=1 ;;
        --resize=*)   RESIZE_IMG="${_arg#--resize=}" ;;
        --snapshot=*) SNAPSHOT_CMD="${_arg#--snapshot=}" ;;
        --delete-build) DELETE_BUILD_MODE=1 ;;
        --delete-iso)   DELETE_ISO_MODE=1   ;;
        --port-forward=*|--fwd=*)
            _fwd="${_arg#*=}"; EXTRA_FWDS+=("$_fwd") ;;
        --iso=*)       ISO_MODE=1; ISO_WIN_URL="${_arg#--iso=}" ;;
        --iso)         ISO_MODE=1 ;;
        --virtio=*)    ISO_VIRTIO_URL="${_arg#--virtio=}" ;;
        --no-vnc)      WINBOX_VNC=0 ;;
        --help|-h)
            echo "Usage: bash winbox.sh [OPTIONS]"
            echo ""
            echo "  --auto          Chạy không tương tác"
            echo "  --win2012       Windows Server 2012 R2"
            echo "  --win2022       Windows Server 2022"
            echo "  --win11         Windows 11 LTSB"
            echo "  --win10ltsb     Windows 10 LTSB 2015"
            echo "  --win10ltsc     Windows 10 LTSC 2023"
            echo "  --win10ltsb2022 Windows 10 LTSB 2022"
            echo "  --build         Force build QEMU"
            echo "  --no-build      Bỏ qua build QEMU"
            echo "  --pgo           Bật PGO optimization"
            echo "  --safe-download Tải file theo chunks 900MB"
            echo "  --http-img      Dùng QEMU HTTP backend"
            exit 0
            ;;
        *) echo -e "${Y}⚠${W}  Unknown argument: $_arg (bỏ qua)"; ;;
    esac
done

ask() {
    local prompt="$1"
    local default="$2"
    if [[ "$AUTO_MODE" == "1" ]]; then
        echo "$default"
        return
    fi
    read -rp "$prompt" ans
    ans="${ans,,}"
    echo "${ans:-$default}"
}

# ════════════════════════════════════════════════════════════════
#  INSTANCE PATHS
# ════════════════════════════════════════════════════════════════
INSTANCE_ID="${INSTANCE_ID:-1}"
WINVM_RDP_PORT=$(( 3388 + INSTANCE_ID ))
WINVM_STATE_FILE="/tmp/winvm-${INSTANCE_ID}.state"
WINVM_QMP_SOCK="/tmp/winvm-${INSTANCE_ID}.qmp"
WINVM_PID_FILE="/tmp/winvm-${INSTANCE_ID}.pid"
WINVM_LOG="/tmp/winvm-${INSTANCE_ID}.log"
WINBOX_DISK_BUS="${WINBOX_DISK_BUS:-ide}"
WIN_IMG_PATH_BASE="${WIN_IMG_PATH_BASE:-win.img}"
WINBOX_NET_DEVICE="${WINBOX_NET_DEVICE:-auto}"
WINBOX_VNC="${WINBOX_VNC:-1}"

# ── Helpers: QMP send ────────────────────────────────────────────
_qmp() {
    local cmd="$1"
    if ! command -v socat &>/dev/null; then echo "socat not found"; return 1; fi
    if [[ ! -S "$WINVM_QMP_SOCK" ]]; then echo "QMP socket not found"; return 1; fi
    printf '{"execute":"qmp_capabilities"}\n{"execute":"%s"}\n' "$cmd" \
        | socat - UNIX-CONNECT:"$WINVM_QMP_SOCK" 2>/dev/null | tail -1
}

# ── Early-exit handlers ──────────────────────────────────────────
if [[ "$STATUS_MODE" == "1" ]]; then
    echo -e "${C}══════════════════════════════════════${W}"
    echo -e "${C}🖥  VM STATUS (instance ${INSTANCE_ID})${W}"
    echo -e "${C}══════════════════════════════════════${W}"
    if [[ -f "$WINVM_PID_FILE" ]]; then
        PID_VM=$(cat "$WINVM_PID_FILE" 2>/dev/null)
        if [[ -n "$PID_VM" ]] && kill -0 "$PID_VM" 2>/dev/null; then
            echo -e "${G}🟢 RUNNING${W}  PID=$PID_VM"
        else
            echo -e "${R}🔴 STOPPED${W}"
        fi
    fi
    exit 0
fi

if [[ "$STOP_MODE" == "1" || "$RESTART_MODE" == "1" ]]; then
    PID_VM=$(cat "$WINVM_PID_FILE" 2>/dev/null || echo "")
    if [[ -n "$PID_VM" ]] && kill -0 "$PID_VM" 2>/dev/null; then
        echo -e "${B}ℹ${W}  Gửi system_powerdown..."
        _qmp "system_powerdown" 2>/dev/null || true
        for _i in $(seq 1 30); do
            kill -0 "$PID_VM" 2>/dev/null || break
            sleep 1
        done
        kill -0 "$PID_VM" 2>/dev/null && { kill -9 "$PID_VM" 2>/dev/null; }
    fi
    rm -f "$WINVM_PID_FILE" "$WINVM_STATE_FILE"
    [[ "$STOP_MODE" == "1" ]] && exit 0
fi

# ════════════════════════════════════════════════════════════════
#  SPINNER
# ════════════════════════════════════════════════════════════════
_SPIN_PID=""

spin_start() {
    local msg="${1:-Processing...}"
    printf "[*] %s\n" "$msg"
    _SPIN_PID=""
    local frames=('◜' '◝' '◞' '◟')
    (
        while :; do
            for f in "${frames[@]}"; do
                printf "\r${B}%s${W} %s" "$f" "$msg"
                sleep 0.1
            done
        done
    ) &
    _SPIN_PID=$!
    disown "$_SPIN_PID"
}

spin_stop() {
    local msg="${1:-Done}"
    if [[ -n "$_SPIN_PID" ]] && kill -0 "$_SPIN_PID" 2>/dev/null; then
        kill "$_SPIN_PID" 2>/dev/null
        wait "$_SPIN_PID" 2>/dev/null || true
    fi
    _SPIN_PID=""
    printf "\r${G}✔${W} %s\n" "$msg"
}

# ════════════════════════════════════════════════════════════════
#  ARIA2
# ════════════════════════════════════════════════════════════════
ARIA2_OPTS=(
    --split=16
    --max-connection-per-server=16
    --min-split-size=1M
    --max-concurrent-downloads=16
    --file-allocation=none
    --continue=true
    --check-certificate=false
    --max-tries=5
    --retry-wait=3
    --timeout=60
    --connect-timeout=15
    --piece-length=1M
    --human-readable=true
    --download-result=full
    --console-log-level=notice
    --summary-interval=3
)

_ensure_aria2() {
    command -v aria2c &>/dev/null && return 0
    local _bin_dir="${PREFIX:-$HOME/qemu-static}/bin"
    mkdir -p "$_bin_dir"

    # Static binary
    local _aria2_url="https://github.com/abcfy2/aria2-static-build/releases/latest/download/aria2-x86_64-linux-musl_static.zip"
    local _tmp_zip="/tmp/aria2-static-$$.zip"

    if wget -q --no-check-certificate "$_aria2_url" -O "$_tmp_zip" 2>/dev/null; then
        local _tmp_dir="/tmp/aria2-static-$$"
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
    fi
    return 1
}

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
        KVM_AVAILABLE=0
        KVM_MODE="tcg"
        return
    fi

    if [[ -r /dev/kvm && -w /dev/kvm ]]; then
        if grep -qE '(vmx|svm)' /proc/cpuinfo 2>/dev/null; then
            echo -e "${G}✔${W}  KVM có sẵn — dùng hardware acceleration"
            KVM_AVAILABLE=1
            KVM_MODE="kvm"
        else
            echo -e "${Y}⚠${W}  CPU không có vmx/svm — dùng TCG"
            KVM_AVAILABLE=0
            KVM_MODE="tcg"
        fi
    else
        echo -e "${Y}⚠${W}  Không đủ quyền /dev/kvm — dùng TCG"
        KVM_AVAILABLE=0
        KVM_MODE="tcg"
    fi
}

# ════════════════════════════════════════════════════════════════
#  PACKAGE MANAGER
# ════════════════════════════════════════════════════════════════
APT_CMD=""
APT_OK=0
ROOTLESS=0

_detect_apt() {
    if [[ "$(id -u)" == "0" ]] && apt-get update -qq > /dev/null 2>&1; then
        APT_CMD="apt-get"
        APT_OK=1
        return
    fi
    if sudo -n true 2>/dev/null && sudo apt-get update -qq > /dev/null 2>&1; then
        APT_CMD="sudo apt-get"
        APT_OK=1
        return
    fi
    APT_OK=0
    ROOTLESS=1
}

apt_install() {
    local pkg="$1"
    $APT_CMD install -y -qq "$pkg" > /dev/null 2>&1
}

# ════════════════════════════════════════════════════════════════
#  ROOTLESS BUILD
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
    echo -e "${C}🔧 ROOTLESS APPIMAGE MODE${W}"
    echo -e "${C}════════════════════════════════════${W}"

    rm -rf "$HOME/qemu-static"
    export PREFIX="$ROOTLESS_PREFIX"
    mkdir -p "$PREFIX"

    # Download AppImage
    local _urls=(
        "https://github.com/pkgforge-dev/QEMU-AppImage/releases/download/11.0.0-1%402026-05-02_1777749420/QEMU-11.0.0-1-anylinux-x86_64.AppImage"
        "https://github.com/lucasmz1/Qemu-AppImage/releases/download/continuous-stable-jammy/QEMU-git-x86_64.AppImage"
    )

    for _url in "${_urls[@]}"; do
        echo -e "${B}ℹ${W}  Tải QEMU AppImage..."
        if wget -c --progress=bar:force -O "$ROOTLESS_APPIMAGE" "$_url" 2>/dev/null; then
            chmod +x "$ROOTLESS_APPIMAGE"
            if timeout 20 "$ROOTLESS_APPIMAGE" --appimage-extract-and-run qemu-system-x86_64 --version >/dev/null 2>&1; then
                _rootless_make_wrappers "$ROOTLESS_APPIMAGE" "$ROOTLESS_BIN_DIR"
                export QEMU_BIN="$ROOTLESS_QEMU"
                export PATH="$ROOTLESS_BIN_DIR:$PATH"
                echo -e "${G}✔${W} QEMU AppImage sẵn sàng"
                return 0
            fi
        fi
        rm -f "$ROOTLESS_APPIMAGE"
    done

    echo -e "${R}✘${W}  Không tải được QEMU AppImage"
    exit 1
}

# ════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════
QEMU_BIN="/usr/bin/qemu-system-x86_64"
ROOTLESS_QEMU="$HOME/qemu-static/bin/qemu-system-x86_64"
OPT_QEMU="/opt/qemu-optimized/bin/qemu-system-x86_64"
HOME_QEMU="$HOME/qemu-optimized/bin/qemu-system-x86_64"

_ask_win_image_early() {
    if [[ -n "${win_choice:-}" ]]; then return; fi

    if [[ -n "${AUTO_WIN:-}" ]]; then
        win_choice="$AUTO_WIN"
    elif [[ "$AUTO_MODE" == "1" ]]; then
        win_choice="5"
    else
        echo ""
        echo -e "${C}════════════════════════════════════${W}"
        echo -e "${C}🪟 CHỌN PHIÊN BẢN WINDOWS${W}"
        echo -e "${C}════════════════════════════════════${W}"
        echo "1️⃣  Windows Server 2012 R2 x64"
        echo "2️⃣  Windows Server 2022 x64"
        echo "3️⃣  Windows 11 LTSB x64"
        echo "4️⃣  Windows 10 LTSB 2015 x64"
        echo "5️⃣  Windows 10 LTSC 2023 x64"
        echo "6️⃣  Windows 10 LTSB 2022 x64"
        read -rp "👉 Nhập số [1-6]: " win_choice
    fi

    case "${win_choice:-5}" in
        1) WIN_NAME="Windows Server 2012 R2"; WIN_URL="https://archive.org/download/tamnguyen-2012r2/2012.img"; USE_UEFI="no"  ; RDP_USER="administrator"; RDP_PASS="Tamnguyenyt@123" ;;
        2) WIN_NAME="Windows Server 2022";    WIN_URL="https://archive.org/download/tamnguyen-2022/2022.img";   USE_UEFI="no"  ; RDP_USER="administrator"; RDP_PASS="Tamnguyenyt@123" ;;
        3) WIN_NAME="Windows 11 LTSB";        WIN_URL="https://archive.org/download/win_20260203/win.img";       USE_UEFI="yes" ; RDP_USER="Admin";         RDP_PASS="Tam255Z"         ;;
        4) WIN_NAME="Windows 10 LTSB 2015";   WIN_URL="https://archive.org/download/win_20260208/win.img";       USE_UEFI="no"  ; RDP_USER="Admin";         RDP_PASS="Tam255Z"         ;;
        5) WIN_NAME="Windows 10 LTSC 2023";   WIN_URL="https://archive.org/download/win_20260215/win.img";       USE_UEFI="no"  ; RDP_USER="Admin";         RDP_PASS="Tam255Z"         ;;
        6|*) WIN_NAME="Windows 10 LTSB 2022"; WIN_URL="https://archive.org/download/win_20260717/win.img";       USE_UEFI="no"  ; RDP_USER="Admin";         RDP_PASS="Tam255Z"         ;;
    esac
    echo -e "${G}✔${W} Image đã chọn: ${C}${WIN_NAME}${W}"
}

ORIGINAL_DIR="$(pwd)"
export ORIGINAL_DIR
PREFIX="${PREFIX:-$HOME/qemu-static}"
export PREFIX

_detect_apt
_detect_kvm

# ════════════════════════════════════════════════════════════════
#  MENU CHÍNH
# ════════════════════════════════════════════════════════════════
echo ""
echo -e "${C}════════════════════════════════════${W}"
echo -e "${C}⬡  WINBOX - ToolVMBoxe${W}"
if [[ "$KVM_AVAILABLE" == "1" ]]; then
    echo -e "${C}⚡ Acceleration: ${G}KVM (hardware)${C}${W}"
else
    echo -e "${C}⚡ Acceleration: ${Y}TCG (software)${C}${W}"
fi
echo -e "${C}════════════════════════════════════${W}"

if [[ "$AUTO_MODE" == "1" ]]; then
    echo -e "${G}🤖 AUTO MODE${W}"
    main_choice="1"
else
    echo "1️⃣  Tạo Windows VM"
    echo "2️⃣  Quản Lý Windows VM"
    echo "3️⃣  Xoá VM"
    echo -e "${C}════════════════════════════════════${W}"
    read -rp "👉 Nhập lựa chọn [1-3]: " main_choice
fi

case "$main_choice" in
2)
    echo -e "${C}🚀 ===== MANAGE RUNNING VM =====${W}"
    if pgrep -f 'qemu-system-x86_64' > /dev/null; then
        pgrep -f 'qemu-system-x86_64' | while read pid; do
            [[ -n "$pid" ]] || continue
            cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline")
            echo -e "🆔 PID: ${Y}${pid}${W}"
        done
    else
        echo -e "${R}❌ Không có VM nào đang chạy${W}"
    fi
    exit 0
    ;;
3)
    echo -e "${C}🗑️  ===== XOÁ VM =====${W}"
    pkill -f 'qemu-system-x86_64' 2>/dev/null || true
    rm -f win.img 2>/dev/null || true
    echo -e "${G}✅ Đã xoá VM${W}"
    exit 0
    ;;
esac

_ask_win_image_early
WIN_IMG_PATH="${ORIGINAL_DIR:-$(pwd)}/win.img"
export WIN_IMG_PATH

# PGO auto cho Win11
if [[ "${win_choice:-}" == "3" && "${PGO_MODE:-0}" == "0" && "${KVM_AVAILABLE:-0}" == "0" ]]; then
    _AUTO_PGO_KEY="win11pgo"
    _AUTO_PGO_ROOT="${WINBOX_PGO_DIR:-$ORIGINAL_PWD}"
    _AUTO_PGO_ARCHIVE="$_AUTO_PGO_ROOT/${_AUTO_PGO_KEY}.tar.gz"
    _AUTO_PGO_URL="https://archive.org/download/win11pgo.tar/win11pgo.tar.gz"

    if wget -q --show-progress --continue "$_AUTO_PGO_URL" -O "$_AUTO_PGO_ARCHIVE" 2>/dev/null; then
        echo -e "${G}✔${W}  PGO profile Win11 tải xong"
        PGO_MODE=1
        PGO_PHASE="use"
        export PGO_MODE PGO_PHASE
    fi
fi

if [[ "$PGO_MODE" == "1" ]]; then
    _pgo_prepare_context "${win_choice:-5}"
    if [[ "$PGO_PROFILE_READY" == "1" ]]; then
        PGO_PHASE="use"
    else
        PGO_PHASE="generate"
    fi
    export PGO_PHASE
fi

# Detect existing QEMU
_detect_existing_qemu() {
    for q in "$OPT_QEMU" "$HOME_QEMU" "$ROOTLESS_QEMU" "$QEMU_BIN" \
              "$(command -v qemu-system-x86_64 2>/dev/null)"; do
        if [[ -n "$q" && -x "$q" ]]; then
            local qv=$("$q" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
            echo -e "${G}⚡ QEMU v${qv} tại: $q${W}"
            export QEMU_BIN="$q"
            export PATH="$(dirname "$q"):$PATH"
            return 0
        fi
    done
    return 1
}

# KVM fast path
if [[ "${KVM_AVAILABLE:-0}" == "1" && "$AUTO_BUILD" != "yes" ]]; then
    echo -e "${C}⚡ KVM DETECTED — AppImage fast path${W}"
    if [[ -x "$HOME/qemu-static/bin/qemu-system-x86_64" ]]; then
        export QEMU_BIN="$HOME/qemu-static/bin/qemu-system-x86_64"
    else
        _rootless_build
    fi
    choice="n"
fi

if [[ "${choice:-}" != "n" ]]; then
    if _detect_existing_qemu; then
        choice="n"
    else
        choice="y"
    fi
fi

if [[ "$choice" == "y" ]]; then
    if [[ "$ROOTLESS" == "1" ]]; then
        _rootless_build
    else
        echo -e "${B}ℹ${W}  Cài đặt dependencies..."
        $APT_CMD update -qq > /dev/null 2>&1
        for pkg in build-essential ninja-build git python3-venv python3-pip pkg-config aria2 ovmf libglib2.0-dev libpixman-1-dev zlib1g-dev libslirp-dev meson; do
            apt_install "$pkg" || true
        done

        # Build QEMU from source
        if [[ ! -d /tmp/qemu-src ]]; then
            git clone --depth 1 --branch v11.0.0 https://gitlab.com/qemu-project/qemu.git /tmp/qemu-src
        fi

        rm -rf /tmp/qemu-build
        mkdir -p /tmp/qemu-build
        cd /tmp/qemu-build

        ../qemu-src/configure \
            --prefix=/opt/qemu-optimized \
            --target-list=x86_64-softmmu \
            --enable-tcg \
            --enable-kvm \
            --enable-slirp \
            --enable-vnc \
            --disable-gtk --disable-sdl --disable-spice \
            --disable-debug-info --disable-docs --disable-werror \
            > /tmp/qemu-configure.log 2>&1

        ninja -j"$(nproc)" > /tmp/qemu-build.log 2>&1
        sudo ninja install > /tmp/qemu-install.log 2>&1

        export QEMU_BIN="/opt/qemu-optimized/bin/qemu-system-x86_64"
        export PATH="/opt/qemu-optimized/bin:$PATH"
    fi
fi

# ════════════════════════════════════════════════════════════════
#  CẤU HÌNH VM
# ════════════════════════════════════════════════════════════════
echo ""
echo -e "${C}════════════════════════════════════${W}"
echo -e "${C}⚙  CẤU HÌNH VM${W}"
echo -e "${C}════════════════════════════════════${W}"

if [[ "$AUTO_MODE" == "1" ]]; then
    cpu_core="${WINBOX_VCPUS:-4}"
    ram_size="${WINBOX_RAM_GB:-4}"
    echo -e "${G}🤖 AUTO MODE${W}"
else
    read -rp "⚙  CPU core (default 4): " cpu_core
    read -rp "💾 RAM GB (default 4): " ram_size
    cpu_core="${cpu_core:-4}"
    ram_size="${ram_size:-4}"
fi

# Tải image
if [[ ! -f "$WIN_IMG_PATH" ]]; then
    echo -e "${C}⬇  Đang tải: ${Y}$WIN_NAME${W}"
    if command -v aria2c &>/dev/null; then
        aria2c "${ARIA2_OPTS[@]}" "$WIN_URL" -d "$(dirname "$WIN_IMG_PATH")" -o "$(basename "$WIN_IMG_PATH")"
    else
        wget --progress=bar:force "$WIN_URL" -O "$WIN_IMG_PATH"
    fi
fi

# ════════════════════════════════════════════════════════════════
#  KHỞI ĐỘNG VM
# ════════════════════════════════════════════════════════════════
echo -e "${B}ℹ${W}  Khởi động VM ${WIN_NAME}..."

if [[ "$KVM_AVAILABLE" == "1" ]]; then
    ACCEL_OPT="-accel kvm"
    CPU_OPT="-cpu host"
else
    ACCEL_OPT="-accel tcg,thread=multi"
    CPU_OPT="-cpu qemu64"
fi

QEMU_CMD=(
    "$QEMU_BIN"
    -machine q35
    $CPU_OPT
    -smp "$cpu_core"
    -m "${ram_size}G"
    $ACCEL_OPT
    -drive file="$WIN_IMG_PATH",if=virtio,cache=unsafe,format=raw
    -netdev user,id=n0,hostfwd=tcp::3389-:3389
    -device virtio-net-pci,netdev=n0
    -vga virtio
    -vnc :0
    -daemonize
)

nohup "${QEMU_CMD[@]}" > /tmp/qemu-launch.log 2>&1 &
QEMU_PID=$!
echo "$QEMU_PID" > "$WINVM_PID_FILE"

echo ""
echo -e "${C}══════════════════════════════════════════════${W}"
echo -e "${C}🚀 WINBOX DEPLOYED${W}"
echo -e "${C}══════════════════════════════════════════════${W}"
echo -e "🪟 OS: ${Y}$WIN_NAME${W}"
echo -e "⚙  CPU: ${B}$cpu_core${W} cores"
echo -e "💾 RAM: ${B}${ram_size} GB${W}"
echo -e "📡 RDP: ${G}localhost:3389${W}"
echo -e "👤 User: ${Y}$RDP_USER${W}"
echo -e "🔑 Pass: ${Y}$RDP_PASS${W}"
echo -e "🖥  VNC: ${G}:5900${W}"
echo -e "${C}══════════════════════════════════════════════${W}"
