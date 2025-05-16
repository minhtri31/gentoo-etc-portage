#!/bin/bash

# Script này phân tích lỗi emerge gần nhất và tự động thêm USE flag phù hợp bằng flaggie

LOG="/var/log/emerge.log"
TMP="/tmp/emerge_use_fix.txt"

# Lọc các dòng lỗi USE flag
grep -E "required by|USE=" $LOG | tail -n 50 > $TMP

# Tìm tên package và USE flag
PACKAGE=$(grep -oP "(?<=).*?(?=)" $TMP | head -n 1 | awk '{print $1}')
USEFLAGS=$(grep "USE=" $TMP | head -n 1 | sed -e 's/.*USE="//' -e 's/".*//')

if [[ -z "$PACKAGE" || -z "$USEFLAGS" ]]; then
    echo "Không tìm được thông tin USE flags từ emerge.log. Thử chạy emerge lỗi lại."
    exit 1
fi

echo "Thêm USE flags cho $PACKAGE: $USEFLAGS"
flaggie $PACKAGE $USEFLAGS

echo "Xong. Bây giờ bạn có thể thử emerge lại."
