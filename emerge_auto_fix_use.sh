#!/bin/bash

# Kiểm tra gói được cung cấp
if [ -z "$1" ]; then
  echo "Usage: $0 <package>"
  exit 1
fi

PACKAGE="$1"
TMPLOG="/tmp/emerge_output.log"

# Chạy emerge và ghi lại lỗi
emerge -pv "$PACKAGE" 2>&1 | tee "$TMPLOG"

# Tìm dòng USE flags từ output
USELINE=$(grep -E "^
