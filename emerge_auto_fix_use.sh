#!/bin/bash

TMPLOG="/tmp/emerge_system_use.log"

echo ">>> Đang chạy emerge để lấy USE flags từ @system..."
echo "!!! CẢNH BÁO QUAN TRỌNG !!!"
echo "Lệnh 'emerge -eav @system' sẽ tiến hành biên dịch lại TOÀN BỘ các gói trong tập @system."
echo "Đây là một tác vụ rất nặng, có thể mất nhiều thời gian và tài nguyên hệ thống."
# Thêm bước xác nhận từ người dùng
read -p "Bạn có chắc chắn muốn tiếp tục chạy 'emerge -eav @system'? (y/N): " confirm_emerge
if [[ "$confirm_emerge" != "y" && "$confirm_emerge" != "Y" ]]; then
    echo ">>> Hủy bỏ bởi người dùng. Script kết thúc."
    exit 0
fi
emerge -eav @system 2>&1 | tee "$TMPLOG"

echo ">>> Đang xử lý USE flags từ log ${TMPLOG}..."

# Kiểm tra flaggie đã được cài chưa
if ! command -v flaggie >/dev/null 2>&1; then
  echo "!!! 'flaggie' chưa được cài. Cài bằng: emerge -av app-portage/flaggie"
  exit 1
fi
echo ">>> Tiện ích 'flaggie' đã được cài đặt."

# Sử dụng awk để xử lý log và trích xuất thông tin
# Tập trung vào các dòng [ebuild ...] vì chúng thường chứa thông tin USE rõ ràng cho package đang được build.
echo ">>> Các đề xuất lệnh flaggie dựa trên log (chưa thực thi):"
awk '
    # Mẫu tìm dòng [ebuild ...] package USE="..."
    # Ví dụ: [ebuild     U  ] app-editors/vim-9.0.1200 [9.0.0900] USE="X acl gpm nls -cjk -debug ..."
    /^\s*\[ebuild[^]]*\]\s+([^\s]+)\s+USE="([^"]+)"/ {
        full_atom_with_maybe_repo_and_old_version = $2 # Ví dụ: app-editors/vim-9.0.1200 hoặc app-editors/vim-9.0.1200::gentoo
        use_flags_string = $0 # Lấy cả dòng đểgsub

        # Lấy phần atom chính, loại bỏ repo nếu có (ví dụ ::gentoo)
        full_atom = full_atom_with_maybe_repo_and_old_version
        sub(/::.*/, "", full_atom) # Bỏ phần ::repo

        gsub(/^.*USE="/, "", use_flags_string) # Xóa phần đầu đến USE="
        gsub(/".*$/, "", use_flags_string)    # Xóa phần cuối từ " (và những gì sau nó trên dòng)

        # Tách category/package từ full_atom (ví dụ: app-category/package-1.2.3:slot -> app-category/package)
        # Đây là một phép phỏng đoán và có thể không hoàn hảo cho mọi trường hợp phức tạp.
        package_name = full_atom
        # 1. Bỏ phần :slot đi nếu có
        sub(/:.*/, "", package_name)
        # 2. Bỏ phần phiên bản (-1.2.3 hoặc -1.2.3-r1).
        # Regex này cố gắng tìm chuỗi phiên bản ở cuối và loại bỏ nó.
        # Ví dụ: app-editors/vim-9.0.1200 -> app-editors/vim
        #         sys-devel/gcc-12.2.0-r2 -> sys-devel/gcc
        #         sys-apps/module-init-tools-3.12 -> sys-apps/module-init-tools (tên có số nhưng không phải version ở cuối)
        # Cần cẩn thận với package có số trong tên không phải là version.
        # Heuristic: nếu phần cuối cùng khớp với mẫu version phổ biến.
        original_package_name_for_debug = package_name
        if (package_name ~ /-[0-9]+(\.[0-9a-zA-Z_]+)*(-r[0-9]+)?$/) {
            sub(/-[0-9]+(\.[0-9a-zA-Z_]+)*(-r[0-9]+)?$/, "", package_name)
        } else {
            # Có thể package không có version ở cuối tên (ví dụ: app-portage/eix)
            # hoặc tên package phức tạp hơn. Giữ nguyên.
        }
        
        # Chỉ xử lý nếu package_name sau khi tách có vẻ hợp lệ (category/name)
        if (package_name !~ /^[a-zA-Z0-9._-]+\/[a-zA-Z0-9._+-]+$/) {
             # print "!!! DEBUG: Tên package sau xử lý '" package_name "' (từ '" original_package_name_for_debug "' / '" full_atom "') không hợp lệ. Bỏ qua." > "/dev/stderr"
             next # Bỏ qua dòng này nếu tên package không hợp lệ
        }

        # Chuyển đổi USE string (ví dụ "flag1 -flag2") sang định dạng cho flaggie (+flag1 -flag2)
        flaggie_use_string = ""
        n = split(use_flags_string, flags_array, " ") # Tách các flags bằng khoảng trắng
        for (i = 1; i <= n; i++) {
            current_flag = flags_array[i]
            if (length(current_flag) == 0) { # Bỏ qua flag rỗng nếu có (do split)
                continue
            }
            if (current_flag ~ /^[-+]/) { # Flag đã có tiền tố - hoặc +
                flaggie_use_string = flaggie_use_string " " current_flag
            } else { # Không có tiền tố, mặc định là bật (+)
                flaggie_use_string = flaggie_use_string " +" current_flag
            }
        }
        sub(/^[ \t]+/, "", flaggie_use_string) # Loại bỏ khoảng trắng thừa ở đầu

        # In ra thông tin và lệnh flaggie đề xuất
        # Chỉ thực hiện nếu cả package_name và flaggie_use_string đều có nội dung
        if (length(package_name) > 0 && length(flaggie_use_string) > 0) {
            printf "echo \"--- Package: %s (Từ atom: %s)\"\n", package_name, full_atom
            printf "echo \"    USE flags đã thấy trong log: [%s]\"\n", use_flags_string
            printf "echo \"    Lệnh flaggie đề xuất: flaggie \\\"%s\\\" %s\"\n\n", package_name, flaggie_use_string
            
            # PHẦN QUAN TRỌNG: Quyết định có chạy flaggie không.
            # Để chạy tự động, bỏ comment dòng dưới và comment các dòng printf echo ở trên.
            # Thêm kiểm tra hoặc xác nhận nếu cần thiết trước khi chạy tự động.
            # system(sprintf("flaggie \"%s\" %s", package_name, flaggie_use_string))
        }
    }
' "$TMPLOG" # Truyền file log cho awk xử lý

echo ""
echo ">>> Xử lý USE flags hoàn tất."
echo ">>> LƯU Ý QUAN TRỌNG:"
echo "1. Các lệnh 'flaggie' được liệt kê ở trên CHỈ LÀ ĐỀ XUẤT và CHƯA được thực thi."
echo "2. Việc trích xuất tên package gốc từ phiên bản đầy đủ là phỏng đoán và có thể không chính xác 100% cho các trường hợp đặc biệt."
echo "3. Nếu bạn muốn tự động chạy các lệnh 'flaggie' này, bạn cần sửa đổi script:"
echo "   - Tìm đến phần 'PHẦN QUAN TRỌNG' trong khối lệnh 'awk'."
echo "   - Bỏ comment (xóa #) ở dòng `system(sprintf(...))` để thực thi lệnh flaggie."
echo "   - Cân nhắc thêm các bước kiểm tra hoặc xác nhận trước khi thực thi tự động."
echo "4. Sau khi sử dụng 'flaggie' (nếu bạn quyết định chạy), các package bị ảnh hưởng có thể cần được biên dịch lại."
echo "   Hãy chạy: emerge --changed-use -av"
echo "   Hoặc để cập nhật toàn diện hơn: emerge -uDNav @world"
