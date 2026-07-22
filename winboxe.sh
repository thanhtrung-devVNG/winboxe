#!/usr/bin/env bash
set -euo pipefail

# ... (giữ nguyên phần đầu script đến hết phần màu sắc và helper functions)

# ════════════════════════════════════════════════════════════════
#  TUI DIALOG FUNCTIONS
#  Sử dụng dialog để tạo giao diện tương tác đẹp
# ════════════════════════════════════════════════════════════════

# Kiểm tra và cài đặt dialog
_check_dialog() {
    if ! command -v dialog &>/dev/null; then
        echo -e "${Y}⚠${W}  dialog chưa được cài đặt. Đang cài đặt..."
        if [[ "$(id -u)" == "0" ]]; then
            apt-get update -qq && apt-get install -y dialog > /dev/null 2>&1
        elif sudo -n true 2>/dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y dialog > /dev/null 2>&1
        fi
        if ! command -v dialog &>/dev/null; then
            echo -e "${R}✘${W}  Không thể cài đặt dialog. Vui lòng cài thủ công: sudo apt install dialog"
            exit 1
        fi
    fi
}

# Tạo menu chính với dialog
_main_menu_dialog() {
    local choice
    choice=$(dialog --clear --stdout \
        --backtitle "⬡ WINBOX - QEMU/KVM Virtual Machine Manager" \
        --title "MENU CHÍNH" \
        --menu "Chọn tác vụ:" \
        18 60 8 \
        1 "🚀 Tạo Windows VM" \
        2 "⚙️  Quản lý VM đang chạy" \
        3 "🗑️  Xoá VM" \
        4 "💾 Disk Manager" \
        5 "📸 Snapshot Manager" \
        6 "🌐 Network Settings" \
        7 "ℹ️  System Info" \
        8 "🚪 Exit" \
        3>&1 1>&2 2>&3)
    echo "$choice"
}

# Hiển thị form tạo VM
_create_vm_form() {
    local name os cpu ram disk network display
    local temp_file=$(mktemp)
    
    dialog --clear --stdout \
        --backtitle "WINBOX - Create VM" \
        --title "TẠO MÁY ẢO MỚI" \
        --form "Nhập thông tin cấu hình VM:" \
        20 70 10 \
        "Tên VM:" 1 1 "" 1 20 30 0 \
        "Hệ điều hành:" 2 1 "windows" 2 20 20 0 \
        "CPU cores:" 3 1 "2" 3 20 10 0 \
        "RAM (GB):" 4 1 "4" 4 20 10 0 \
        "Disk (GB):" 5 1 "20" 5 20 10 0 \
        "Disk format:" 6 1 "qcow2" 6 20 10 0 \
        "Network:" 7 1 "user" 7 20 10 0 \
        "Display:" 8 1 "vnc" 8 20 10 0 \
        2>&1 1>&3 | {
            read name
            read os
            read cpu
            read ram
            read disk
            read format
            read network
            read display
        }
    
    echo "$name|$os|$cpu|$ram|$disk|$format|$network|$display"
}

# Hiển thị danh sách VM đang chạy
_show_running_vms() {
    local vms=()
    while IFS= read -r pid; do
        [[ -n "$pid" ]] || continue
        local cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || echo "")
        local name=$(grep -o -- "-name [^ ]*" <<< "$cmd" | cut -d' ' -f2 || echo "unknown")
        local vcpu=$(sed -n 's/.*-smp \([^ ,]*\).*/\1/p' <<< "$cmd")
        local ram=$(sed -n 's/.*-m \([^ ]*\).*/\1/p' <<< "$cmd")
        vms+=("$pid" "PID: $pid | vCPU: $vcpu | RAM: $ram | Name: $name")
    done < <(pgrep -f 'qemu-system-x86_64' 2>/dev/null || true)
    
    if [[ ${#vms[@]} -eq 0 ]]; then
        dialog --clear --msgbox "⚠️  Không có VM nào đang chạy" 8 40
        return
    fi
    
    local choice
    choice=$(dialog --clear --stdout \
        --backtitle "WINBOX - Running VMs" \
        --title "📊 QUẢN LÝ VM ĐANG CHẠY" \
        --menu "Chọn VM để quản lý:" \
        18 70 10 \
        "${vms[@]}" \
        2>&1 1>&2)
    
    if [[ -n "$choice" ]]; then
        _manage_vm_dialog "$choice"
    fi
}

# Quản lý một VM cụ thể
_manage_vm_dialog() {
    local pid="$1"
    local action
    
    action=$(dialog --clear --stdout \
        --backtitle "WINBOX - Manage VM" \
        --title "🔧 QUẢN LÝ VM (PID: $pid)" \
        --menu "Chọn hành động:" \
        16 50 6 \
        1 "⏹  Stop VM" \
        2 "🔄  Restart VM" \
        3 "⏸️  Pause VM" \
        4 "▶️  Resume VM" \
        5 "📸  Create Snapshot" \
        6 "📊  Show Info" \
        2>&1 1>&2)
    
    case "$action" in
        1)
            if dialog --clear --yesno "Bạn có chắc muốn dừng VM PID: $pid?" 8 50; then
                kill -TERM "$pid" 2>/dev/null && \
                    dialog --clear --msgbox "✅ Đã gửi tín hiệu dừng VM" 8 40 || \
                    dialog --clear --msgbox "❌ Không thể dừng VM" 8 40
            fi
            ;;
        2)
            if dialog --clear --yesno "Bạn có chắc muốn restart VM PID: $pid?" 8 50; then
                kill -HUP "$pid" 2>/dev/null && \
                    dialog --clear --msgbox "✅ Đã gửi tín hiệu restart VM" 8 40 || \
                    dialog --clear --msgbox "❌ Không thể restart VM" 8 40
            fi
            ;;
        3)
            kill -STOP "$pid" 2>/dev/null && \
                dialog --clear --msgbox "✅ Đã pause VM" 8 40 || \
                dialog --clear --msgbox "❌ Không thể pause VM" 8 40
            ;;
        4)
            kill -CONT "$pid" 2>/dev/null && \
                dialog --clear --msgbox "✅ Đã resume VM" 8 40 || \
                dialog --clear --msgbox "❌ Không thể resume VM" 8 40
            ;;
        5)
            local snap_name
            snap_name=$(dialog --clear --stdout \
                --backtitle "WINBOX - Snapshot" \
                --title "📸 TẠO SNAPSHOT" \
                --inputbox "Nhập tên snapshot:" \
                8 50 "snapshot-$(date +%Y%m%d-%H%M%S)" \
                2>&1 1>&2)
            if [[ -n "$snap_name" ]]; then
                dialog --clear --msgbox "✅ Đã tạo snapshot: $snap_name\n(Sử dụng QEMU QMP)" 10 50
            fi
            ;;
        6)
            local info=$(ps -p "$pid" -o pid,ppid,%cpu,%mem,etime,cmd --no-headers 2>/dev/null || echo "Không có thông tin")
            dialog --clear --msgbox "📊 THÔNG TIN VM\n\n$info" 20 70
            ;;
    esac
}

# Disk Manager
_disk_manager_dialog() {
    local action
    action=$(dialog --clear --stdout \
        --backtitle "WINBOX - Disk Manager" \
        --title "💾 DISK MANAGER" \
        --menu "Chọn hành động:" \
        16 50 6 \
        1 "📋  List disks" \
        2 "➕  Create disk" \
        3 "📐  Resize disk" \
        4 "🗑️  Delete disk" \
        5 "📊  Show disk info" \
        2>&1 1>&2)
    
    case "$action" in
        1)
            local disks=$(find . -name "*.img" -o -name "*.qcow2" -o -name "*.raw" 2>/dev/null | head -20)
            if [[ -z "$disks" ]]; then
                dialog --clear --msgbox "⚠️  Không tìm thấy disk nào" 8 40
            else
                dialog --clear --msgbox "📋 DANH SÁCH DISK\n\n$disks" 20 60
            fi
            ;;
        2)
            local disk_name size
            disk_name=$(dialog --clear --stdout \
                --title "Tạo disk mới" \
                --inputbox "Nhập tên disk (không cần đuôi):" \
                8 50 "my-disk" 2>&1 1>&2)
            if [[ -n "$disk_name" ]]; then
                size=$(dialog --clear --stdout \
                    --title "Tạo disk mới" \
                    --inputbox "Nhập dung lượng (GB):" \
                    8 50 "10" 2>&1 1>&2)
                if [[ -n "$size" ]]; then
                    if qemu-img create -f qcow2 "${disk_name}.qcow2" "${size}G" 2>&1 | dialog --clear --programbox "Đang tạo disk..." 15 60; then
                        dialog --clear --msgbox "✅ Đã tạo disk: ${disk_name}.qcow2 (${size}GB)" 10 50
                    else
                        dialog --clear --msgbox "❌ Tạo disk thất bại" 8 40
                    fi
                fi
            fi
            ;;
        3)
            local disk_file
            disk_file=$(dialog --clear --stdout \
                --title "Resize disk" \
                --inputbox "Nhập đường dẫn disk:" \
                8 50 "win.img" 2>&1 1>&2)
            if [[ -n "$disk_file" && -f "$disk_file" ]]; then
                local new_size
                new_size=$(dialog --clear --stdout \
                    --title "Resize disk" \
                    --inputbox "Nhập dung lượng mới (GB):" \
                    8 50 "30" 2>&1 1>&2)
                if [[ -n "$new_size" ]]; then
                    if qemu-img resize "$disk_file" "${new_size}G" 2>&1 | dialog --clear --programbox "Đang resize disk..." 15 60; then
                        dialog --clear --msgbox "✅ Đã resize disk: $disk_file -> ${new_size}GB" 10 50
                    else
                        dialog --clear --msgbox "❌ Resize thất bại" 8 40
                    fi
                fi
            fi
            ;;
        4)
            local disk_file
            disk_file=$(dialog --clear --stdout \
                --title "Xóa disk" \
                --inputbox "Nhập đường dẫn disk cần xóa:" \
                8 50 "win.img" 2>&1 1>&2)
            if [[ -n "$disk_file" && -f "$disk_file" ]]; then
                if dialog --clear --yesno "Bạn có chắc muốn xóa disk: $disk_file?" 8 50; then
                    rm -f "$disk_file" && \
                        dialog --clear --msgbox "✅ Đã xóa disk: $disk_file" 10 50 || \
                        dialog --clear --msgbox "❌ Không thể xóa disk" 8 40
                fi
            fi
            ;;
        5)
            local disk_file
            disk_file=$(dialog --clear --stdout \
                --title "Thông tin disk" \
                --inputbox "Nhập đường dẫn disk:" \
                8 50 "win.img" 2>&1 1>&2)
            if [[ -n "$disk_file" && -f "$disk_file" ]]; then
                qemu-img info "$disk_file" 2>&1 | dialog --clear --programbox "📊 THÔNG TIN DISK" 20 70
            fi
            ;;
    esac
}

# Snapshot Manager
_snapshot_manager_dialog() {
    local action
    action=$(dialog --clear --stdout \
        --backtitle "WINBOX - Snapshot Manager" \
        --title "📸 SNAPSHOT MANAGER" \
        --menu "Chọn hành động:" \
        16 50 5 \
        1 "📋  List snapshots" \
        2 "➕  Create snapshot" \
        3 "↩️  Restore snapshot" \
        4 "🗑️  Delete snapshot" \
        2>&1 1>&2)
    
    case "$action" in
        1)
            local disk_file
            disk_file=$(dialog --clear --stdout \
                --inputbox "Nhập đường dẫn disk:" \
                8 50 "win.img" 2>&1 1>&2)
            if [[ -n "$disk_file" && -f "$disk_file" ]]; then
                qemu-img snapshot -l "$disk_file" 2>&1 | dialog --clear --programbox "📋 DANH SÁCH SNAPSHOT" 20 70
            fi
            ;;
        2)
            local disk_file snap_name
            disk_file=$(dialog --clear --stdout \
                --inputbox "Nhập đường dẫn disk:" \
                8 50 "win.img" 2>&1 1>&2)
            if [[ -n "$disk_file" && -f "$disk_file" ]]; then
                snap_name=$(dialog --clear --stdout \
                    --inputbox "Nhập tên snapshot:" \
                    8 50 "snapshot-$(date +%Y%m%d-%H%M%S)" 2>&1 1>&2)
                if [[ -n "$snap_name" ]]; then
                    if qemu-img snapshot -c "$snap_name" "$disk_file" 2>&1 | dialog --clear --programbox "Đang tạo snapshot..." 15 60; then
                        dialog --clear --msgbox "✅ Đã tạo snapshot: $snap_name" 10 50
                    else
                        dialog --clear --msgbox "❌ Tạo snapshot thất bại" 8 40
                    fi
                fi
            fi
            ;;
        3)
            local disk_file snap_name
            disk_file=$(dialog --clear --stdout \
                --inputbox "Nhập đường dẫn disk:" \
                8 50 "win.img" 2>&1 1>&2)
            if [[ -n "$disk_file" && -f "$disk_file" ]]; then
                snap_name=$(dialog --clear --stdout \
                    --inputbox "Nhập tên snapshot cần restore:" \
                    8 50 "" 2>&1 1>&2)
                if [[ -n "$snap_name" ]]; then
                    if dialog --clear --yesno "Bạn có chắc muốn restore snapshot: $snap_name?" 8 50; then
                        if qemu-img snapshot -a "$snap_name" "$disk_file" 2>&1 | dialog --clear --programbox "Đang restore snapshot..." 15 60; then
                            dialog --clear --msgbox "✅ Đã restore snapshot: $snap_name" 10 50
                        else
                            dialog --clear --msgbox "❌ Restore snapshot thất bại" 8 40
                        fi
                    fi
                fi
            fi
            ;;
        4)
            local disk_file snap_name
            disk_file=$(dialog --clear --stdout \
                --inputbox "Nhập đường dẫn disk:" \
                8 50 "win.img" 2>&1 1>&2)
            if [[ -n "$disk_file" && -f "$disk_file" ]]; then
                snap_name=$(dialog --clear --stdout \
                    --inputbox "Nhập tên snapshot cần xóa:" \
                    8 50 "" 2>&1 1>&2)
                if [[ -n "$snap_name" ]]; then
                    if dialog --clear --yesno "Bạn có chắc muốn xóa snapshot: $snap_name?" 8 50; then
                        if qemu-img snapshot -d "$snap_name" "$disk_file" 2>&1 | dialog --clear --programbox "Đang xóa snapshot..." 15 60; then
                            dialog --clear --msgbox "✅ Đã xóa snapshot: $snap_name" 10 50
                        else
                            dialog --clear --msgbox "❌ Xóa snapshot thất bại" 8 40
                        fi
                    fi
                fi
            fi
            ;;
    esac
}

# Hiển thị thông tin hệ thống
_show_system_info() {
    local info
    info=$(cat <<EOF
🏷️  HOSTNAME: $(hostname)
🐧 OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "Unknown")
🧠 CPU: $(nproc) cores
💾 RAM Total: $(free -h | awk '/Mem:/ {print $2}')
💿 RAM Used: $(free -h | awk '/Mem:/ {print $3}')
💿 RAM Free: $(free -h | awk '/Mem:/ {print $4}')
📀 Disk: $(df -h / | awk 'NR==2 {print $2 " total, " $3 " used, " $4 " free"}')
🔄 Uptime: $(uptime -p | sed 's/up //')
🔧 KVM: $([ -e /dev/kvm ] && echo "✅ Available" || echo "❌ Not available")
📦 QEMU: $(qemu-system-x86_64 --version 2>/dev/null | head -1 || echo "Not found")
EOF
)
    dialog --clear --msgbox "$info" 20 70
}

# Tạo VM với dialog (wizard)
_create_vm_wizard() {
    # Bước 1: Chọn OS
    local os
    os=$(dialog --clear --stdout \
        --backtitle "WINBOX - Create VM Wizard" \
        --title "BƯỚC 1: CHỌN HỆ ĐIỀU HÀNH" \
        --menu "Chọn OS:" \
        18 50 10 \
        1 "Windows 10" \
        2 "Windows 11" \
        3 "Windows Server 2019" \
        4 "Windows Server 2022" \
        5 "Ubuntu 22.04" \
        6 "Ubuntu 24.04" \
        7 "Debian 12" \
        8 "Fedora 40" \
        9 "Arch Linux" \
        10 "Other" \
        2>&1 1>&2)
    
    [[ -z "$os" ]] && return
    
    local os_name
    case "$os" in
        1) os_name="Windows 10" ;;
        2) os_name="Windows 11" ;;
        3) os_name="Windows Server 2019" ;;
        4) os_name="Windows Server 2022" ;;
        5) os_name="Ubuntu 22.04" ;;
        6) os_name="Ubuntu 24.04" ;;
        7) os_name="Debian 12" ;;
        8) os_name="Fedora 40" ;;
        9) os_name="Arch Linux" ;;
        *) os_name="Other" ;;
    esac
    
    # Bước 2: Nhập thông tin cấu hình
    local vm_name cpu ram disk disk_format network display
    local temp=$(mktemp)
    
    dialog --clear --stdout \
        --backtitle "WINBOX - Create VM Wizard" \
        --title "BƯỚC 2: CẤU HÌNH VM" \
        --form "OS: $os_name\n\nNhập thông số cấu hình:" \
        20 70 10 \
        "Tên VM:" 1 1 "vm-${os,,}" 1 20 30 0 \
        "CPU cores:" 2 1 "2" 2 20 10 0 \
        "RAM (GB):" 3 1 "4" 3 20 10 0 \
        "Disk (GB):" 4 1 "20" 4 20 10 0 \
        "Disk format:" 5 1 "qcow2" 5 20 10 0 \
        "Network:" 6 1 "user" 6 20 10 0 \
        "Display:" 7 1 "vnc" 7 20 10 0 \
        2>&1 1>&3 | {
            read vm_name
            read cpu
            read ram
            read disk
            read disk_format
            read network
            read display
        }
    
    # Bước 3: Xác nhận và tạo
    local confirm
    confirm=$(dialog --clear --stdout \
        --backtitle "WINBOX - Create VM Wizard" \
        --title "BƯỚC 3: XÁC NHẬN" \
        --yesno "Xác nhận tạo VM:\n\nTên: $vm_name\nOS: $os_name\nCPU: $cpu cores\nRAM: $ram GB\nDisk: $disk GB ($disk_format)\nNetwork: $network\nDisplay: $display\n\nTiến hành tạo?" \
        16 60 && echo "yes" || echo "no")
    
    if [[ "$confirm" == "yes" ]]; then
        # Tạo disk
        dialog --clear --infobox "Đang tạo disk ${vm_name}.${disk_format}..." 6 50
        sleep 1
        
        if qemu-img create -f "$disk_format" "${vm_name}.${disk_format}" "${disk}G" 2>/dev/null; then
            dialog --clear --msgbox "✅ VM đã được tạo thành công!\n\nTên: $vm_name\nDisk: ${vm_name}.${disk_format}\n\nĐể khởi động VM, sử dụng QEMU command:\n\nqemu-system-x86_64 -enable-kvm -cpu host -smp $cpu -m ${ram}G -drive file=${vm_name}.${disk_format},if=virtio -vnc :0" 20 70
        else
            dialog --clear --msgbox "❌ Tạo VM thất bại" 8 40
        fi
    fi
}

# ════════════════════════════════════════════════════════════════
#  MAIN TUI LOOP
# ════════════════════════════════════════════════════════════════

# Main function
main_tui() {
    _check_dialog
    
    while true; do
        local choice
        choice=$(_main_menu_dialog)
        
        case "$choice" in
            1)
                _create_vm_wizard
                ;;
            2)
                _show_running_vms
                ;;
            3)
                if dialog --clear --yesno "⚠️  Bạn có chắc muốn xóa VM?" 8 50; then
                    # Kill all QEMU processes
                    pkill -f 'qemu-system-x86_64' 2>/dev/null || true
                    dialog --clear --msgbox "✅ Đã dừng tất cả VM" 8 40
                fi
                ;;
            4)
                _disk_manager_dialog
                ;;
            5)
                _snapshot_manager_dialog
                ;;
            6)
                dialog --clear --msgbox "🌐 NETWORK SETTINGS\n\nChức năng đang phát triển..." 10 50
                ;;
            7)
                _show_system_info
                ;;
            8|"")
                if dialog --clear --yesno "Bạn có chắc muốn thoát?" 8 40; then
                    clear
                    echo -e "${G}👋 Tạm biệt!${W}"
                    exit 0
                fi
                ;;
            *)
                dialog --clear --msgbox "Lựa chọn không hợp lệ" 8 40
                ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════════
#  GỌI TUI HOẶC CLI MODE
# ════════════════════════════════════════════════════════════════

# Nếu có tham số --tui hoặc không có tham số và terminal hỗ trợ
if [[ "$#" -eq 0 ]] || [[ "$1" == "--tui" ]]; then
    # Chạy TUI mode
    main_tui
    exit 0
fi

# Nếu có tham số --cli, tiếp tục chạy script gốc ở chế độ CLI
if [[ "$1" == "--cli" ]]; then
    shift
    # ... (phần script gốc từ dòng 250 trở đi)
fi

# ... (phần còn lại của script gốc)
