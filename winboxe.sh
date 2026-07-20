#!/usr/bin/env bash
set -euo pipefail

# ════════════════════════════════════════════════════════════════
#  WINBOX v3 - 4 Chức năng: Start | Stop | Delete | Create
#  Fix: Xóa VM nền không dừng tool, dashboard tách biệt hoàn toàn
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
_rl_info() { echo -e "${B}ℹ${W}  $1"; }

# ════════════════════════════════════════════════════════════════
#  PATHS & STATE
# ════════════════════════════════════════════════════════════════
INSTANCE_ID=1
WINVM_RDP_PORT=$((3388 + INSTANCE_ID))
WINVM_QMP_SOCK="/tmp/winvm-${INSTANCE_ID}.qmp"
WINVM_PID_FILE="/tmp/winvm-${INSTANCE_ID}.pid"
WINVM_STATE_FILE="/tmp/winvm-${INSTANCE_ID}.state"
WIN_IMG_PATH="${PWD}/win.img"
WEB_PORT=8080
WEB_DIR="/tmp/winbox-web"
WEB_PID_FILE="/tmp/winbox-web.pid"
WINBOX_STATE="/tmp/winbox-state.json"

# ════════════════════════════════════════════════════════════════
#  ISO CONFIG (indexed arrays)
# ════════════════════════════════════════════════════════════════
ISO_URL_1="https://archive.org/download/tamnguyen-2012r2/2012.img"
ISO_URL_2="https://archive.org/download/tamnguyen-2022/2022.img"
ISO_URL_3="https://archive.org/download/win_20260203/win.img"
ISO_URL_4="https://archive.org/download/win_20260208/win.img"
ISO_URL_5="https://archive.org/download/win_20260215/win.img"
ISO_URL_6="https://archive.org/download/win_20260717/win.img"

ISO_NAME_1="Windows Server 2012 R2"
ISO_NAME_2="Windows Server 2022"
ISO_NAME_3="Windows 11 LTSB"
ISO_NAME_4="Windows 10 LTSB 2015"
ISO_NAME_5="Windows 10 LTSC 2023"
ISO_NAME_6="Windows 10 LTSB 2022"

ISO_USER_1="administrator"
ISO_USER_2="administrator"
ISO_USER_3="Admin"
ISO_USER_4="Admin"
ISO_USER_5="Admin"
ISO_USER_6="Admin"

ISO_PASS_1="Tamnguyenyt@123"
ISO_PASS_2="Tamnguyenyt@123"
ISO_PASS_3="Tam255Z"
ISO_PASS_4="Tam255Z"
ISO_PASS_5="Tam255Z"
ISO_PASS_6="Tam255Z"

ISO_UEFI_1="no"
ISO_UEFI_2="no"
ISO_UEFI_3="yes"
ISO_UEFI_4="no"
ISO_UEFI_5="no"
ISO_UEFI_6="no"

_get_iso_url()  { eval echo "\$ISO_URL_$1"; }
_get_iso_name() { eval echo "\$ISO_NAME_$1"; }
_get_iso_user() { eval echo "\$ISO_USER_$1"; }
_get_iso_pass() { eval echo "\$ISO_PASS_$1"; }
_get_iso_uefi() { eval echo "\$ISO_UEFI_$1"; }

# ════════════════════════════════════════════════════════════════
#  VM STATUS HELPERS
# ════════════════════════════════════════════════════════════════
_vm_running() {
    if [[ ! -f "$WINVM_PID_FILE" ]]; then return 1; fi
    local pid; pid=$(cat "$WINVM_PID_FILE" 2>/dev/null || echo "")
    [[ -z "$pid" ]] && return 1
    kill -0 "$pid" 2>/dev/null && return 0 || return 1
}

_vm_info() {
    if [[ ! -f "$WINBOX_STATE" ]]; then
        echo -e "${Y}⚠${W}  Chưa có VM nào được tạo"
        return 1
    fi
    local iso cpu ram
    iso=$(python3 -c "import json; d=json.load(open('$WINBOX_STATE')); print(str(d.get('iso','?')))" 2>/dev/null || echo "?")
    cpu=$(python3 -c "import json; d=json.load(open('$WINBOX_STATE')); print(str(d.get('cpu','?')))" 2>/dev/null || echo "?")
    ram=$(python3 -c "import json; d=json.load(open('$WINBOX_STATE')); print(str(d.get('ram','?')))" 2>/dev/null || echo "?")
    local name user pass
    name=$(_get_iso_name "$iso")
    user=$(_get_iso_user "$iso")
    pass=$(_get_iso_pass "$iso")
    echo ""
    echo -e "${C}══════════════════════════════════════════════${W}"
    echo -e "${C}📋 THÔNG TIN VM${W}"
    echo -e "${C}══════════════════════════════════════════════${W}"
    echo -e "🪟 OS        : ${Y}${name}${W}"
    echo -e "⚙️  CPU      : ${B}${cpu}${W} cores"
    echo -e "💾 RAM       : ${B}${ram}${W} GB"
    echo -e "📡 RDP       : ${G}localhost:${WINVM_RDP_PORT}${W}"
    echo -e "👤 Username  : ${Y}${user}${W}"
    echo -e "🔑 Password  : ${Y}${pass}${W}"
    echo -e "🖥️  VNC       : ${G}:5900${W}"
    if _vm_running; then
        echo -e "🟢 Status    : ${G}RUNNING${W}"
    else
        echo -e "🔴 Status    : ${R}STOPPED${W}"
    fi
    echo -e "${C}══════════════════════════════════════════════${W}"
}

# ════════════════════════════════════════════════════════════════
#  1. START VM
# ════════════════════════════════════════════════════════════════
_start_vm() {
    echo ""
    echo -e "${C}════════════════════════════════════${W}"
    echo -e "${C}▶️  START VM${W}"
    echo -e "${C}════════════════════════════════════${W}"

    if _vm_running; then
        _rl_warn "VM đang chạy rồi!"
        _vm_info
        return 0
    fi

    if [[ ! -f "$WINBOX_STATE" ]]; then
        _rl_warn "Chưa có VM nào. Hãy chọn [4] Create VM trước."
        return 1
    fi

    # Đọc config từ state
    local iso cpu ram preset
    iso=$(python3 -c "import json; d=json.load(open('$WINBOX_STATE')); print(str(d.get('iso','5')))" 2>/dev/null || echo "5")
    preset=$(python3 -c "import json; d=json.load(open('$WINBOX_STATE')); print(str(d.get('preset','1')))" 2>/dev/null || echo "1")
    cpu=$(python3 -c "import json; d=json.load(open('$WINBOX_STATE')); print(str(d.get('cpu','4')))" 2>/dev/null || echo "4")
    ram=$(python3 -c "import json; d=json.load(open('$WINBOX_STATE')); print(str(d.get('ram','4')))" 2>/dev/null || echo "4")

    if [[ "$preset" == "4" ]]; then
        cpu_core="$cpu"
        ram_size="$ram"
    else
        case "$preset" in
            1) cpu_core=4;  ram_size=4 ;;
            2) cpu_core=8;  ram_size=8 ;;
            3) cpu_core=16; ram_size=16 ;;
            *) cpu_core=4;  ram_size=4 ;;
        esac
    fi

    local win_name win_url use_uefi rdp_user rdp_pass
    win_name=$(_get_iso_name "$iso")
    win_url=$(_get_iso_url "$iso")
    use_uefi=$(_get_iso_uefi "$iso")
    rdp_user=$(_get_iso_user "$iso")
    rdp_pass=$(_get_iso_pass "$iso")

    # Kiểm tra image
    if [[ ! -f "$WIN_IMG_PATH" ]]; then
        _rl_warn "Không tìm thấy $WIN_IMG_PATH"
        _rl_info "Chạy [4] Create VM để tải image"
        return 1
    fi

    # Detect KVM
    local kvm_avail=0 kvm_mode="tcg"
    if [[ -e /dev/kvm ]] && grep -qE '(vmx|svm)' /proc/cpuinfo 2>/dev/null; then
        if [[ "$(id -u)" == "0" ]]; then
            kvm_avail=1; kvm_mode="kvm"
        else
            local grp=$(ls -l /dev/kvm 2>/dev/null | awk '{print $4}')
            if id -Gn | grep -qw "$grp"; then
                kvm_avail=1; kvm_mode="kvm"
            fi
        fi
    fi

    # Resolve QEMU
    local qemu_bin=""
    for q in "${QEMU_BIN:-}" "$HOME/qemu-static/bin/qemu-system-x86_64" "$HOME/qemu-optimized/bin/qemu-system-x86_64" "/opt/qemu-optimized/bin/qemu-system-x86_64" "$(command -v qemu-system-x86_64 2>/dev/null)"; do
        [[ -n "$q" && -x "$q" ]] && { qemu_bin="$q"; break; }
    done
    [[ -z "$qemu_bin" ]] && { _rl_warn "Không tìm thấy QEMU"; return 1; }

    # TCG tuning
    local cpu_model=""
    if [[ "$kvm_avail" == "0" ]]; then
        export MALLOC_ARENA_MAX=4
        export MALLOC_MMAP_THRESHOLD_=131072
        export QEMU_AUDIO_DRV=none
        local host_ram_gb; host_ram_gb=$(awk '/MemTotal/{printf "%.0f",$2/1024/1024}' /proc/meminfo)
        [[ "${host_ram_gb:-0}" -lt 1 ]] && host_ram_gb=4
        local tcg_tb_mb; tcg_tb_mb=$(( host_ram_gb * 1024 * 6 / 100 ))
        [[ "$tcg_tb_mb" -lt 4096  ]] && tcg_tb_mb=4096
        [[ "$tcg_tb_mb" -gt 8192 ]] && tcg_tb_mb=8192
        _rl_info "TCG TB cache: ${tcg_tb_mb}MB"
        local raw_cpu vendor
        raw_cpu=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | sed 's/^.*: //' || echo "")
        vendor=$(grep -m1 "vendor_id" /proc/cpuinfo 2>/dev/null | awk '{print $NF}' || echo "")
        local cpu_model_id
        if [[ -n "$raw_cpu" && "$raw_cpu" != "unknown" ]]; then
            cpu_model_id=$(printf '%s' "$raw_cpu" | tr ',' ' ' | tr -d '"\@#$%^&*|<>' | sed 's/[[:space:]]\+/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//' | cut -c1-48)
        else
            case "$vendor" in
                GenuineIntel) cpu_model_id="Intel Xeon Processor" ;;
                AuthenticAMD) cpu_model_id="AMD EPYC Processor" ;;
                *) cpu_model_id="Generic x86_64 Processor" ;;
            esac
        fi
        local cpu_extra=""
        grep -q ssse3  /proc/cpuinfo && cpu_extra="$cpu_extra,+ssse3"
        grep -q sse4_1 /proc/cpuinfo && cpu_extra="$cpu_extra,+sse4.1"
        grep -q sse4_2 /proc/cpuinfo && cpu_extra="$cpu_extra,+sse4.2"
        grep -q ' avx ' /proc/cpuinfo && cpu_extra="$cpu_extra,+avx"
        grep -q avx2   /proc/cpuinfo && cpu_extra="$cpu_extra,+avx2"
        cpu_model="max,hypervisor=off,tsc=on,pmu=off,l3-cache=on,+cmov,+mmx,+fxsr,+sse2,+cx16,+x2apic,+sep,+pat,+pse,+aes,+popcnt,-tsc-deadline${cpu_extra},model-id=${cpu_model_id}"
    fi

    # OVMF
    local ovmf_path=""
    if [[ "$use_uefi" == "yes" ]]; then
        for _ovmf in /usr/share/qemu/OVMF.fd /usr/share/ovmf/OVMF.fd /usr/share/OVMF/OVMF_CODE.fd; do
            [[ -f "$_ovmf" ]] && { ovmf_path="$_ovmf"; break; }
        done
        if [[ -z "$ovmf_path" && -f /tmp/ovmf/OVMF.fd ]]; then
            ovmf_path="/tmp/ovmf/OVMF.fd"
        fi
    fi

    # Build QEMU command
    rm -f "$WINVM_QMP_SOCK"
    local qemu_cmd=()
    local net_device=""

    if [[ "$kvm_avail" == "1" ]]; then
        qemu_cmd=("$qemu_bin" -machine q35,hpet=off -cpu host -smp "$cpu_core" -m "${ram_size}G" -accel kvm -rtc base=localtime,clock=host)
        net_device="-device virtio-net-pci,netdev=n0"
        _rl_ok "KVM mode: hardware acceleration"
    else
        qemu_cmd=("$qemu_bin" -machine q35,hpet=off,vmport=off,mem-merge=off -cpu "$cpu_model" -smp "$cpu_core,cores=$cpu_core,threads=1,sockets=1" -m "${ram_size}G" -accel "tcg,thread=multi,split-wx=off,one-insn-per-tb=off,tb-size=$tcg_tb_mb" -rtc base=localtime -overcommit cpu-pm=on -boot order=c,strict=on -no-shutdown -device virtio-mouse-pci -device virtio-keyboard-pci -nodefaults -smbios type=1,manufacturer="Dell Inc.",product="PowerEdge R640" -no-user-config)
        net_device="-device virtio-net-pci,netdev=n0"
        _rl_warn "TCG mode: software emulation"
    fi

    [[ -n "$ovmf_path" ]] && qemu_cmd+=(-bios "$ovmf_path")

    qemu_cmd+=(-drive "file=$WIN_IMG_PATH,if=none,id=disk0,cache=unsafe,aio=threads,format=raw" -device virtio-blk-pci,drive=disk0,iothread=io1,num-queues=4,queue-size=256 -object iothread,id=io1)
    qemu_cmd+=(-netdev "user,id=n0,hostfwd=tcp::${WINVM_RDP_PORT}-:3389" $net_device)
    qemu_cmd+=(-vga virtio -vnc :0 -device nec-usb-xhci -device usb-tablet)
    [[ -e /dev/urandom ]] && qemu_cmd+=(-object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0)
    qemu_cmd+=(-qmp "unix:$WINVM_QMP_SOCK,server,nowait")

    # Launch
    echo -e "${B}ℹ${W}  Khởi động ${win_name}..."
    local qemu_log="/tmp/qemu-launch-$$.log"
    nohup "${qemu_cmd[@]}" >> "$qemu_log" 2>&1 &
    local qemu_pid=$!
    echo "$qemu_pid" > "$WINVM_PID_FILE"
    disown "$qemu_pid"

    sleep 4
    if kill -0 "$qemu_pid" 2>/dev/null; then
        _rl_ok "VM đã khởi động (PID: $qemu_pid)"
        _vm_info
    else
        _rl_warn "VM KHÔNG khởi động được!"
        cat "$qemu_log" 2>/dev/null || true
        return 1
    fi
}

# ════════════════════════════════════════════════════════════════
#  2. STOP VM
# ════════════════════════════════════════════════════════════════
_stop_vm() {
    echo ""
    echo -e "${C}════════════════════════════════════${W}"
    echo -e "${C}⏹️  STOP VM${W}"
    echo -e "${C}════════════════════════════════════${W}"

    if ! _vm_running; then
        _rl_warn "VM không chạy"
        return 0
    fi

    local pid; pid=$(cat "$WINVM_PID_FILE" 2>/dev/null || echo "")
    if [[ -n "$pid" ]]; then
        kill "$pid" 2>/dev/null || true
        sleep 2
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
    fi
    pkill -f 'qemu-system-x86_64' 2>/dev/null || true
    rm -f "$WINVM_PID_FILE" "$WINVM_QMP_SOCK" "$WINVM_STATE_FILE"
    _rl_ok "VM đã dừng"
}

# ════════════════════════════════════════════════════════════════
#  3. DELETE VM (xóa nền, không dừng tool)
# ════════════════════════════════════════════════════════════════
_delete_vm() {
    echo ""
    echo -e "${C}════════════════════════════════════${W}"
    echo -e "${C}🗑️  DELETE VM${W}"
    echo -e "${C}════════════════════════════════════${W}"

    echo -e "${Y}⚠${W}  Bạn có chắc muốn XÓA VM?"
    echo -e "   - Dừng VM nếu đang chạy"
    echo -e "   - Xóa file win.img"
    echo -e "   - Xóa toàn bộ state"
    echo -e "   - ${R}KHÔNG THỂ HOÀN TÁC${W}"
    echo ""
    read -rp "Nhập 'yes' để xác nhận xóa: " confirm
    if [[ "$confirm" != "yes" ]]; then
        _rl_info "Đã hủy xóa VM"
        return 0
    fi

    # Xóa nền bằng subshell — không block terminal
    (
        # Dừng VM
        if [[ -f "$WINVM_PID_FILE" ]]; then
            local pid; pid=$(cat "$WINVM_PID_FILE" 2>/dev/null || echo "")
            [[ -n "$pid" ]] && { kill "$pid" 2>/dev/null; sleep 2; kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true; }
        fi
        pkill -f 'qemu-system-x86_64' 2>/dev/null || true
        rm -f "$WINVM_PID_FILE" "$WINVM_QMP_SOCK" "$WINVM_STATE_FILE"

        # Xóa image
        [[ -f "$WIN_IMG_PATH" ]] && rm -f "$WIN_IMG_PATH"

        # Xóa state & logs
        rm -f "$WINBOX_STATE" /tmp/qemu-launch.log /tmp/winbox-state.json /tmp/winbox-web.log 2>/dev/null || true

        # Xóa web files
        rm -rf "$WEB_DIR" 2>/dev/null || true
        if [[ -f "$WEB_PID_FILE" ]]; then
            local wp; wp=$(cat "$WEB_PID_FILE" 2>/dev/null || echo "")
            [[ -n "$wp" ]] && kill "$wp" 2>/dev/null || true
            rm -f "$WEB_PID_FILE"
        fi
    ) &
    local delete_pid=$!
    disown $delete_pid

    _rl_ok "Đang xóa VM nền (PID: $delete_pid)"
    _rl_info "Bạn có thể tiếp tục sử dụng menu ngay bây giờ"
    sleep 1
}

# ════════════════════════════════════════════════════════════════
#  4. CREATE VM (tạo mới — tải image + lưu config)
# ════════════════════════════════════════════════════════════════
_create_vm() {
    echo ""
    echo -e "${C}════════════════════════════════════${W}"
    echo -e "${C}🔧 CREATE VM${W}"
    echo -e "${C}════════════════════════════════════${W}"

    # Dừng VM cũ nếu đang chạy
    if _vm_running; then
        _rl_warn "VM đang chạy — đang dừng trước khi tạo mới..."
        _stop_vm
        sleep 1
    fi

    # Xóa image cũ nếu có
    if [[ -f "$WIN_IMG_PATH" ]]; then
        _rl_warn "Đã xóa image cũ"
        rm -f "$WIN_IMG_PATH"
    fi

    # Khởi động web dashboard để chọn config
    _start_web_server
    _wait_web_config || {
        _rl_warn "Không nhận được config. Thoát."
        return 1
    }

    # Đọc config từ state
    local win_choice cpu_core ram_size
    win_choice=$(python3 -c "import json; d=json.load(open('$WINBOX_STATE')); print(str(d.get('iso','5')).strip())" 2>/dev/null || echo "5")
    local _preset=$(python3 -c "import json; d=json.load(open('$WINBOX_STATE')); print(str(d.get('preset','1')).strip())" 2>/dev/null || echo "1")
    local _cpu=$(python3 -c "import json; d=json.load(open('$WINBOX_STATE')); print(str(d.get('cpu','4')).strip())" 2>/dev/null || echo "4")
    local _ram=$(python3 -c "import json; d=json.load(open('$WINBOX_STATE')); print(str(d.get('ram','4')).strip())" 2>/dev/null || echo "4")

    if [[ "$_preset" == "4" ]]; then
        cpu_core="$_cpu"
        ram_size="$_ram"
    else
        case "$_preset" in
            1) cpu_core=4;  ram_size=4 ;;
            2) cpu_core=8;  ram_size=8 ;;
            3) cpu_core=16; ram_size=16 ;;
            *) cpu_core=4;  ram_size=4 ;;
        esac
    fi

    case "$win_choice" in
        1|2|3|4|5|6) : ;;
        *) win_choice=5 ;;
    esac

    local win_name win_url use_uefi rdp_user rdp_pass
    win_name=$(_get_iso_name "$win_choice")
    win_url=$(_get_iso_url "$win_choice")
    use_uefi=$(_get_iso_uefi "$win_choice")
    rdp_user=$(_get_iso_user "$win_choice")
    rdp_pass=$(_get_iso_pass "$win_choice")

    echo -e "${G}✔${W} Config nhận được:"
    echo -e "   🖥️  CPU: ${B}$cpu_core${W} cores"
    echo -e "   💾 RAM: ${B}$ram_size${W} GB"
    echo -e "   💿 ISO: ${B}$win_choice${W} — ${C}$win_name${W}"

    # Detect apt
    local apt_cmd="" apt_ok=0 rootless=0
    if [[ "$(id -u)" == "0" ]] && apt-get update -qq >/dev/null 2>&1; then
        apt_cmd="apt-get"; apt_ok=1
    elif sudo -n true 2>/dev/null && sudo apt-get update -qq >/dev/null 2>&1; then
        apt_cmd="sudo apt-get"; apt_ok=1
    else
        apt_ok=0; rootless=1
    fi

    # Bootstrap tools
    local need=0
    for t in wget curl python3; do command -v "$t" &>/dev/null || need=1; done
    if [[ "$need" == "1" && -n "$apt_cmd" ]]; then
        _rl_info "Cài công cụ cần thiết..."
        export DEBIAN_FRONTEND=noninteractive
        $apt_cmd update -qq >/dev/null 2>&1 || true
        for pkg in wget curl python3 python3-pip; do
            command -v "$pkg" &>/dev/null || $apt_cmd install -y -qq "$pkg" >/dev/null 2>&1 || true
        done
    fi

    # Resolve QEMU
    local qemu_bin="" qemu_img=""
    for q in "${QEMU_BIN:-}" "$HOME/qemu-static/bin/qemu-system-x86_64" "$HOME/qemu-optimized/bin/qemu-system-x86_64" "/opt/qemu-optimized/bin/qemu-system-x86_64" "$(command -v qemu-system-x86_64 2>/dev/null)"; do
        [[ -n "$q" && -x "$q" ]] && { qemu_bin="$q"; break; }
    done

    if [[ -z "$qemu_bin" ]]; then
        if [[ "$rootless" == "1" || "$apt_ok" == "0" ]]; then
            _rl_info "Tải QEMU AppImage..."
            _rootless_build || { _rl_warn "Không thể có QEMU"; return 1; }
            qemu_bin="$HOME/qemu-static/bin/qemu-system-x86_64"
        else
            _rl_info "Cài QEMU qua apt..."
            $apt_cmd install -y -qq qemu-system-x86 qemu-utils 2>/dev/null || true
            qemu_bin=$(command -v qemu-system-x86_64 2>/dev/null || echo "")
            [[ -z "$qemu_bin" ]] && { _rl_warn "Không thể cài QEMU"; return 1; }
        fi
    fi

    for qi in "$(dirname "${qemu_bin:-/nonexistent}")/qemu-img" "/usr/bin/qemu-img" "$(command -v qemu-img 2>/dev/null || true)"; do
        if [[ -x "$qi" ]] && "$qi" --version >/dev/null 2>&1; then
            qemu_img="$qi"; break
        fi
    done
    [[ -z "$qemu_img" ]] && qemu_img="$(dirname "$qemu_bin")/qemu-img"

    # Tải image
    _img_valid() {
        local f="$1"
        [[ -f "$f" ]] || return 1
        local sz; sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
        [[ "$sz" -ge 2147483648 ]] && return 0
        return 1
    }

    if _img_valid "$WIN_IMG_PATH"; then
        _rl_ok "Image đã có — bỏ qua tải"
    else
        echo ""
        echo -e "${C}⬇  Đang tải: ${Y}${win_name}${W}"

        # Ensure aria2
        if ! command -v aria2c &>/dev/null; then
            local _bin_dir="${PREFIX:-$HOME/qemu-static}/bin"
            mkdir -p "$_bin_dir"
            local _tmp_zip="/tmp/aria2-static-$$.zip"
            if wget -q --no-check-certificate "https://github.com/abcfy2/aria2-static-build/releases/latest/download/aria2-x86_64-linux-musl_static.zip" -O "$_tmp_zip" 2>/dev/null; then
                local _tmp_dir="/tmp/aria2-static-$$"
                mkdir -p "$_tmp_dir"
                if unzip -q "$_tmp_zip" -d "$_tmp_dir" 2>/dev/null; then
                    local _aria2c; _aria2c=$(find "$_tmp_dir" -name "aria2c" -type f | head -1)
                    if [[ -n "$_aria2c" ]]; then
                        install -m755 "$_aria2c" "$_bin_dir/aria2c"
                        export PATH="$_bin_dir:$PATH"
                    fi
                fi
                rm -rf "$_tmp_zip" "$_tmp_dir"
            fi
            [[ -n "$apt_cmd" ]] && $apt_cmd install -y -qq aria2 >/dev/null 2>&1 || true
        fi

        if command -v aria2c &>/dev/null; then
            aria2c --split=16 --max-connection-per-server=16 --min-split-size=1M --max-concurrent-downloads=16 --file-allocation=none --continue=true --check-certificate=false --max-tries=5 --retry-wait=3 --timeout=60 --connect-timeout=15 --piece-length=1M --human-readable=true --download-result=full --console-log-level=notice --summary-interval=3 "$win_url" -d "$(dirname "$WIN_IMG_PATH")" -o "$(basename "$WIN_IMG_PATH")"
        else
            wget --progress=bar:force --continue "$win_url" -O "$WIN_IMG_PATH"
        fi

        if _img_valid "$WIN_IMG_PATH"; then
            _rl_ok "Tải xong"
        else
            _rl_warn "Tải thất bại hoặc file không hợp lệ"
            return 1
        fi
    fi

    # Resize disk
    if [[ -n "$qemu_img" && -x "$qemu_img" ]]; then
        _rl_info "Mở rộng disk +20GB..."
        "$qemu_img" resize "$WIN_IMG_PATH" "+20G" 2>/dev/null || true
    fi

    # Tải OVMF nếu cần
    if [[ "$use_uefi" == "yes" ]]; then
        local ovmf_found=0
        for _ovmf in /usr/share/qemu/OVMF.fd /usr/share/ovmf/OVMF.fd /usr/share/OVMF/OVMF_CODE.fd; do
            [[ -f "$_ovmf" ]] && { ovmf_found=1; break; }
        done
        if [[ $ovmf_found -eq 0 ]]; then
            _rl_info "Tải OVMF..."
            mkdir -p /tmp/ovmf
            wget -q -O /tmp/ovmf/OVMF.fd "https://github.com/nicowillis/ovmf-prebuilt/raw/main/OVMF.fd" 2>/dev/null || true
        fi
    fi

    _rl_ok "Create VM hoàn tất!"
    _rl_info "Chạy [1] Start VM để khởi động"
    _vm_info
}

# ════════════════════════════════════════════════════════════════
#  WEB DASHBOARD FILES
# ════════════════════════════════════════════════════════════════
_create_dashboard_files() {
    mkdir -p "$WEB_DIR"

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
.container{max-width:750px;width:100%;background:rgba(255,255,255,0.05);backdrop-filter:blur(20px);border-radius:24px;border:1px solid rgba(255,255,255,0.1);padding:40px;box-shadow:0 25px 50px rgba(0,0,0,0.4)}
.header{text-align:center;margin-bottom:35px}
.header h1{font-size:2.5em;background:linear-gradient(90deg,#00d4ff,#7b2cbf);-webkit-background-clip:text;-webkit-text-fill-color:transparent;margin-bottom:10px}
.header p{color:#8892b0;font-size:1.1em}
.section{margin-bottom:25px;padding:22px;background:rgba(0,0,0,0.2);border-radius:16px;border:1px solid rgba(255,255,255,0.05)}
.section-title{font-size:1.15em;font-weight:600;margin-bottom:15px;display:flex;align-items:center;gap:10px;color:#64ffda}
.option-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:10px}
.option-card{padding:15px;background:rgba(255,255,255,0.03);border:2px solid rgba(255,255,255,0.08);border-radius:12px;cursor:pointer;transition:all 0.3s ease;text-align:center}
.option-card:hover{border-color:#64ffda;background:rgba(100,255,218,0.05);transform:translateY(-2px)}
.option-card.selected{border-color:#00d4ff;background:rgba(0,212,255,0.1);box-shadow:0 0 20px rgba(0,212,255,0.2)}
.option-card .icon{font-size:1.8em;margin-bottom:6px}
.option-card .name{font-weight:600;font-size:0.95em}
.option-card .desc{font-size:0.8em;color:#8892b0;margin-top:4px}
.option-card .badge{display:inline-block;padding:2px 8px;border-radius:20px;font-size:0.7em;margin-top:6px;font-weight:500}
.badge-kvm{background:rgba(0,212,255,0.2);color:#00d4ff}
.badge-tcg{background:rgba(255,184,0,0.2);color:#ffb800}
.custom-inputs{display:none;margin-top:15px;padding:15px;background:rgba(0,0,0,0.3);border-radius:12px}
.custom-inputs.active{display:block}
.input-group{margin-bottom:12px}
.input-group label{display:block;margin-bottom:6px;color:#ccd6f6;font-size:0.9em}
.input-group input{width:100%;padding:10px 14px;background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.1);border-radius:10px;color:#fff;font-size:1em;outline:none}
.input-group input:focus{border-color:#64ffda}
.btn-row{display:flex;gap:12px;margin-top:20px}
.btn-row .submit-btn{flex:1}
.submit-btn{width:100%;padding:16px;background:linear-gradient(90deg,#00d4ff,#7b2cbf);border:none;border-radius:14px;color:#fff;font-size:1.1em;font-weight:700;cursor:pointer;transition:all 0.3s ease;text-transform:uppercase;letter-spacing:1px}
.submit-btn:hover{transform:translateY(-2px);box-shadow:0 10px 30px rgba(0,212,255,0.3)}
.submit-btn:disabled{opacity:0.5;cursor:not-allowed}
.submit-btn.danger{background:linear-gradient(90deg,#ff4757,#ff6b81)}
.submit-btn.danger:hover{box-shadow:0 10px 30px rgba(255,71,87,0.3)}
.submit-btn.warning{background:linear-gradient(90deg,#ffa502,#ffc048)}
.submit-btn.warning:hover{box-shadow:0 10px 30px rgba(255,165,2,0.3)}
.status{margin-top:20px;padding:18px;border-radius:14px;display:none;text-align:center}
.status.active{display:block}
.status.loading{background:rgba(0,212,255,0.1);border:1px solid rgba(0,212,255,0.3)}
.status.success{background:rgba(0,255,136,0.1);border:1px solid rgba(0,255,136,0.3)}
.status.error{background:rgba(255,0,0,0.1);border:1px solid rgba(255,0,0,0.3)}
.spinner{display:inline-block;width:35px;height:35px;border:3px solid rgba(255,255,255,0.1);border-top-color:#00d4ff;border-radius:50%;animation:spin 1s linear infinite;margin-bottom:12px}
@keyframes spin{to{transform:rotate(360deg)}}
.rdp-info{background:rgba(0,0,0,0.3);border-radius:12px;padding:18px;margin-top:12px;text-align:left}
.rdp-info-row{display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px solid rgba(255,255,255,0.05)}
.rdp-info-row:last-child{border-bottom:none}
.rdp-info-label{color:#8892b0;font-size:0.9em}
.rdp-info-value{color:#64ffda;font-weight:600;font-family:monospace;font-size:0.95em}
.copy-btn{background:rgba(255,255,255,0.1);border:none;padding:4px 10px;border-radius:6px;color:#fff;cursor:pointer;font-size:0.8em;margin-left:8px}
.copy-btn:hover{background:rgba(255,255,255,0.2)}
.progress-bar{width:100%;height:5px;background:rgba(255,255,255,0.05);border-radius:3px;overflow:hidden;margin:12px 0}
.progress-fill{height:100%;background:linear-gradient(90deg,#00d4ff,#64ffda);border-radius:3px;transition:width 0.5s ease;width:0%}
.vm-status{padding:12px;background:rgba(0,0,0,0.2);border-radius:10px;margin-bottom:15px;text-align:center;font-size:0.9em}
.vm-status.running{color:#64ffda;border:1px solid rgba(100,255,218,0.2)}
.vm-status.stopped{color:#ff6b6b;border:1px solid rgba(255,107,107,0.2)}
.footer{text-align:center;margin-top:25px;color:#8892b0;font-size:0.85em}
</style>
</head>
<body>
<div class="container">
<div class="header"><h1>🪟 WinBox</h1><p>Windows VM Dashboard</p></div>

<div class="vm-status stopped" id="vm-status">🔴 VM chưa được tạo</div>

<div class="section">
<div class="section-title">⚙️ Cấu hình VM</div>
<div class="option-grid" id="preset-grid">
<div class="option-card" data-preset="1" onclick="selectPreset(1)">
<div class="icon">🖥️</div><div class="name">4 CPU + 4 GB</div><div class="desc">Cơ bản</div><span class="badge badge-kvm">KVM</span>
</div>
<div class="option-card" data-preset="2" onclick="selectPreset(2)">
<div class="icon">🚀</div><div class="name">8 CPU + 8 GB</div><div class="desc">Mạnh</div><span class="badge badge-kvm">KVM</span>
</div>
<div class="option-card" data-preset="3" onclick="selectPreset(3)">
<div class="icon">🔥</div><div class="name">16 CPU + 16 GB</div><div class="desc">Cực mạnh</div><span class="badge badge-kvm">KVM</span>
</div>
<div class="option-card" data-preset="4" onclick="selectPreset(4)">
<div class="icon">⚡</div><div class="name">Custom</div><div class="desc">Tự chọn</div><span class="badge badge-tcg">Custom</span>
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
<div class="icon">🪟</div><div class="name">Win 10 LTSC 2023</div><div class="desc">Auto / Tam255Z</div>
</div>
<div class="option-card" data-iso="6" onclick="selectIso(6)">
<div class="icon">🎮</div><div class="name">Win 10 LTSB 2022</div><div class="desc">Auto / Tam255Z | VirtGPU 3D</div>
</div>
</div>
</div>

<div class="btn-row">
<button class="submit-btn" id="submit-btn" onclick="createVM()" disabled>✅ TẠO VM</button>
</div>

<div class="status loading" id="status-loading">
<div class="spinner"></div>
<div style="font-size:1.1em;font-weight:600;margin-bottom:8px">Đang xử lý...</div>
<div style="color:#8892b0;margin-bottom:12px;font-size:0.9em" id="loading-text">Vui lòng đợi</div>
<div class="progress-bar"><div class="progress-fill" id="progress-fill"></div></div>
</div>

<div class="status success" id="status-success">
<div style="font-size:1.8em;margin-bottom:8px">✅</div>
<div style="font-size:1.2em;font-weight:700;margin-bottom:5px">Đã lưu cấu hình!</div>
<div style="color:#8892b0;margin-bottom:12px;font-size:0.9em">Quay lại terminal và chọn [1] Start VM</div>
<div class="rdp-info" id="rdp-info"></div>
</div>

<div class="status error" id="status-error">
<div style="font-size:1.8em;margin-bottom:8px">❌</div>
<div style="font-size:1.1em;font-weight:600;margin-bottom:8px">Thất bại</div>
<div id="error-text" style="color:#ff6b6b;font-size:0.9em"></div>
</div>

<div class="footer">WinBox Dashboard v3.0 | 4 Chức năng: Start | Stop | Delete | Create</div>
</div>

<script>
let selectedPreset=null,selectedIso=null;

function selectPreset(id){
    selectedPreset=id;
    document.querySelectorAll('#preset-grid .option-card').forEach(c=>c.classList.remove('selected'));
    document.querySelector(`[data-preset="${id}"]`).classList.add('selected');
    document.getElementById('custom-inputs').classList.toggle('active',id===4);
    updateButtons();
}

function selectIso(id){
    selectedIso=id;
    document.querySelectorAll('#iso-grid .option-card').forEach(c=>c.classList.remove('selected'));
    document.querySelector(`[data-iso="${id}"]`).classList.add('selected');
    updateButtons();
}

function updateButtons(){
    document.getElementById('submit-btn').disabled=!(selectedPreset&&selectedIso);
}

function setProgress(pct,text){
    document.getElementById('progress-fill').style.width=pct+'%';
    if(text) document.getElementById('loading-text').textContent=text;
}

function hideAllStatus(){
    ['status-loading','status-success','status-error'].forEach(id=>{
        document.getElementById(id).classList.remove('active');
    });
}

async function createVM(){
    hideAllStatus();
    document.getElementById('status-loading').classList.add('active');
    document.getElementById('submit-btn').disabled=true;

    let cpu=selectedPreset===4?document.getElementById('custom-cpu').value:[4,8,16][selectedPreset-1];
    let ram=selectedPreset===4?document.getElementById('custom-ram').value:[4,8,16][selectedPreset-1];

    const steps=[{pct:20,text:'Lưu cấu hình...',delay:500},{pct:60,text:'Đang ghi state...',delay:500},{pct:100,text:'Hoàn tất!',delay:500}];
    for(const step of steps){setProgress(step.pct,step.text);await new Promise(r=>setTimeout(r,step.delay));}

    try{
        const res=await fetch('/api/create',{
            method:'POST',
            headers:{'Content-Type':'application/json'},
            body:JSON.stringify({preset:selectedPreset,iso:selectedIso,cpu,ram})
        });
        const data=await res.json();
        hideAllStatus();
        if(data.success){
            document.getElementById('status-success').classList.add('active');
            document.getElementById('vm-status').className='vm-status running';
            document.getElementById('vm-status').textContent='✅ Đã lưu cấu hình — quay lại terminal';
            document.getElementById('rdp-info').innerHTML=`<div class="rdp-info-row"><span class="rdp-info-label">🪟 Hệ điều hành</span><span class="rdp-info-value">${data.win_name}</span></div><div class="rdp-info-row"><span class="rdp-info-label">⚙️ CPU</span><span class="rdp-info-value">${data.cpu} cores</span></div><div class="rdp-info-row"><span class="rdp-info-label">💾 RAM</span><span class="rdp-info-value">${data.ram} GB</span></div><div class="rdp-info-row"><span class="rdp-info-label">📡 RDP Address</span><span class="rdp-info-value">${data.rdp_host}:${data.rdp_port}</span></div><div class="rdp-info-row"><span class="rdp-info-label">👤 Username</span><span class="rdp-info-value">${data.rdp_user}</span></div><div class="rdp-info-row"><span class="rdp-info-label">🔑 Password</span><span class="rdp-info-value">${data.rdp_pass}</span></div>`;
        }else{
            document.getElementById('status-error').classList.add('active');
            document.getElementById('error-text').textContent=data.error||'Lỗi không xác định';
        }
    }catch(e){
        hideAllStatus();
        document.getElementById('status-error').classList.add('active');
        document.getElementById('error-text').textContent=e.message;
    }
    document.getElementById('submit-btn').disabled=false;
}

selectPreset(1);
selectIso(5);
</script>
</body>
</html>"""

with open(os.path.join(web_dir, 'index.html'), 'w') as f:
    f.write(html)

server_py = """#!/usr/bin/env python3
import http.server, socketserver, json, os, sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
STATE_FILE = "/tmp/winbox-state.json"

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/': self.path = '/index.html'
        return super().do_GET()

    def do_POST(self):
        content_len = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_len) if content_len > 0 else b'{}'
        try: data = json.loads(body)
        except: data = {}

        if self.path == '/api/create':
            with open(STATE_FILE, 'w') as f: json.dump(data, f)
            self.send_json({"success": True})
            return

        self.send_response(404)
        self.end_headers()

    def send_json(self, obj):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(obj).encode())

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
print("Dashboard files created")
PYEOF
}

# ════════════════════════════════════════════════════════════════
#  WEB SERVER
# ════════════════════════════════════════════════════════════════
_start_web_server() {
    _create_dashboard_files

    if [[ -f "$WEB_PID_FILE" ]]; then
        local old_pid; old_pid=$(cat "$WEB_PID_FILE" 2>/dev/null || echo "")
        [[ -n "$old_pid" ]] && kill "$old_pid" 2>/dev/null || true
    fi

    for p in 8080 8081 8082 8083 8084 3000 5000; do
        if ! ss -tlnp 2>/dev/null | grep -q ":$p "; then
            WEB_PORT=$p
            break
        fi
    done

    nohup python3 "$WEB_DIR/server.py" "$WEB_PORT" > /tmp/winbox-web.log 2>&1 &
    local web_pid=$!
    echo "$web_pid" > "$WEB_PID_FILE"
    disown "$web_pid"

    sleep 1
    if kill -0 "$web_pid" 2>/dev/null; then
        echo -e "${G}✔${W} Dashboard: ${C}http://localhost:$WEB_PORT${W}"
        local _host_ip; _host_ip=$(hostname -I 2>/dev/null | awk '{print $1}' | head -1 || echo "localhost")
        echo -e "${B}ℹ${W}  Hoặc: ${C}http://${_host_ip}:$WEB_PORT${W}"
        if command -v xdg-open &>/dev/null; then
            xdg-open "http://localhost:$WEB_PORT" 2>/dev/null || true
        elif command -v open &>/dev/null; then
            open "http://localhost:$WEB_PORT" 2>/dev/null || true
        fi
        return 0
    else
        echo -e "${R}✘${W} Web server failed"
        return 1
    fi
}

# ════════════════════════════════════════════════════════════════
#  ĐỢI CONFIG TỪ WEB
# ════════════════════════════════════════════════════════════════
_wait_web_config() {
    local _state_file="$WINBOX_STATE"
    local _timeout=300
    local _elapsed=0

    echo -e "${B}ℹ${W}  Đang đợi cấu hình từ Dashboard..."
    echo -e "${B}ℹ${W}  Mở ${C}http://localhost:$WEB_PORT${W} để chọn cấu hình"

    while [[ ! -f "$_state_file" ]] && [[ $_elapsed -lt $_timeout ]]; do
        sleep 2
        _elapsed=$(( $_elapsed + 2 ))
        printf "\r${B}◜${W} Đang đợi... %ss" "$_elapsed"
    done
    printf "\n"

    if [[ -f "$_state_file" ]]; then
        echo -e "${G}✔${W} Đã nhận cấu hình từ Dashboard"
        return 0
    else
        echo -e "${R}✘${W} Timeout đợi config"
        return 1
    fi
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

    mkdir -p "$ROOTLESS_PREFIX" "$ROOTLESS_APPIMAGE_DIR"

    if [[ -x "$ROOTLESS_QEMU" ]] && [[ -f "$ROOTLESS_APPIMAGE" ]]; then
        local rv; rv=$("$ROOTLESS_QEMU" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
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
                for _cmd in qemu-system-x86_64 qemu-img qemu-nbd qemu-io; do
                    printf '#!/bin/sh\nexec "%s" --appimage-extract-and-run "%s" "$@"\n' "$ROOTLESS_APPIMAGE" "$_cmd" > "$ROOTLESS_BIN_DIR/$_cmd"
                    chmod +x "$ROOTLESS_BIN_DIR/$_cmd"
                done
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
#  MAIN MENU
# ════════════════════════════════════════════════════════════════
_show_menu() {
    echo ""
    echo -e "${C}══════════════════════════════════════════════════${W}"
    echo -e "${C}           🪟 WINBOX v3 - MENU CHÍNH${W}"
    echo -e "${C}══════════════════════════════════════════════════${W}"
    echo ""
    echo -e "  ${G}[1]${W} ▶️  START VM    — Khởi động VM đã tạo"
    echo -e "  ${Y}[2]${W} ⏹️  STOP VM     — Dừng VM đang chạy"
    echo -e "  ${R}[3]${W} 🗑️  DELETE VM   — Xóa toàn bộ VM (nền)"
    echo -e "  ${B}[4]${W} 🔧 CREATE VM   — Tạo VM mới (chọn config)"
    echo ""
    echo -e "  ${C}[5]${W} ℹ️  VM INFO     — Xem thông tin VM"
    echo -e "  ${C}[0]${W} 🚪 THOÁT"
    echo ""
    echo -e "${C}══════════════════════════════════════════════════${W}"
}

# ════════════════════════════════════════════════════════════════
#  MAIN LOOP
# ════════════════════════════════════════════════════════════════
main() {
    while true; do
        _show_menu
        read -rp "Chọn chức năng [0-5]: " choice
        case "$choice" in
            1) _start_vm ;;
            2) _stop_vm ;;
            3) _delete_vm ;;
            4) _create_vm ;;
            5) _vm_info ;;
            0|q|exit) echo -e "${G}✔${W} Tạm biệt!"; exit 0 ;;
            *) _rl_warn "Lựa chọn không hợp lệ"; ;;
        esac
        echo ""
        read -rp "Nhấn Enter để tiếp tục..."
    done
}

main "$@"
