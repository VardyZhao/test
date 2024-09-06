#!/bin/bash

# 提取 ERROR_CODE.md
error_codes_in_md=$(grep '^|\s*[0-9]' ERROR_CODE.md | awk -F '|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')

# 检查是否有重复的错误码
duplicate_code=$(echo "$error_codes_in_md" | sort | uniq -d)
if [ -n "$duplicate_code" ]; then
    echo "Error: Duplicate error codes found in ERROR_CODE.md: $duplicate_code"
    exit 1
fi



# 通过git diff获取本次提交的改动
new_error_codes=$(git diff --cached ERROR_CODE.md | grep '^+|\s*[0-9]' | awk -F '|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
deleted_error_codes=$(git diff --cached ERROR_CODE.md | grep '^-|\s*[0-9]' | awk -F '|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')


echo $new_error_codes
echo $deleted_error_codes
exit 1

# Step 4: 如果没有删除的错误码，且有新增的错误码，表示是新增
if [ -z "$deleted_error_codes" ] && [ -n "$new_error_codes" ]; then
    echo "Detected new error codes: $new_error_codes"

    # Step 5: 请求 Confluence 接口，获取所有已有的错误码
    confluence_codes=$(curl -s --location 'https://thebidgroup.atlassian.net/wiki/api/v2/pages/3333423226?body-format=STORAGE' \
           --header 'Accept: application/json' \
           --header 'Authorization: Basic dmFyZHkuemhhb0BsaWZlYnl0ZS5pbzpBVEFUVDN4RmZHRjBaS0ROSHY5VGh5My1abzhfMDRLb1dIZ0tJMUdWRkpKMEJYRUx0Q1dqWERONXd6ckt3SDdUcUVnajRJbWhiV0pZSHhSb1pHZXJVZ1B4MGpmNWJNeGtwc1piUkNuSndDWVBRZG1BWEw5dHNmZ2tJelFBLTQ1UnRCdGd6bkoyMmY5M3ZvV044RldDazdOVjNxVVdHdzZ5ZWRzTk1qaVd1OTR6UzZubzdkb0ZNcnc9QzZFMThENEM=' \
          | grep -oP '(?<=<td><p>)[0-9]+(?=</p></td>)' | sort)

    # Step 6: 检查本次新增的错误码是否已存在于 Confluence
    for code in $new_error_codes; do
        if echo "$confluence_codes" | grep -q "$code"; then
            echo "Error: The error code $code already exists in Confluence: $code"
            exit 1
        fi
    done
fi

echo "No issues found. Proceeding with commit."


