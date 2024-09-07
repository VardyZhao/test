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

# 文件有变化，需要检查是否有重复的错误码
if [ -n "$deleted_error_codes" ] || [ -n "$new_error_codes" ]; then
  # git diff 如果是修改，会同时存在一个-，一个+，可以不用检查confluence
  # 如果是新增，只会有一个+，这个就要检查confluence
  # 如果是删除，只会有一个-，不需要检查confluence
  updated_codes=""
  new_codes=""
  deleted_codes=""
  for new_item in $new_error_codes; do
    flag=0
    for deleted_item in $deleted_error_codes; do
      if [ "$new_item" -eq "$deleted_item" ]; then
        flag=1
        break
      fi
    done
    if [ $flag -eq 1 ]; then
      updated_codes="$updated_codes $new_item"
    else
      new_codes="$new_codes $new_item"
    fi
  done
  for remove_item in $deleted_error_codes; do
    if ! echo "$updated_codes" | grep -qw "$remove_item"; then
      deleted_codes="$deleted_codes $remove_item"
    fi
  done

  # 检查conflunce和ERROR_CODE的差异
  confluence_data=$(curl -s --location 'https://thebidgroup.atlassian.net/wiki/api/v2/pages/3333423226?body-format=STORAGE' \
       --header 'Accept: application/json' \
       --header 'Authorization: Basic dmFyZHkuemhhb0BsaWZlYnl0ZS5pbzpBVEFUVDN4RmZHRjBaS0ROSHY5VGh5My1abzhfMDRLb1dIZ0tJMUdWRkpKMEJYRUx0Q1dqWERONXd6ckt3SDdUcUVnajRJbWhiV0pZSHhSb1pHZXJVZ1B4MGpmNWJNeGtwc1piUkNuSndDWVBRZG1BWEw5dHNmZ2tJelFBLTQ1UnRCdGd6bkoyMmY5M3ZvV044RldDazdOVjNxVVdHdzZ5ZWRzTk1qaVd1OTR6UzZubzdkb0ZNcnc9QzZFMThENEM=' \
  )
  confluence_codes=$(echo "$confluence_data" | grep -oP '<tr><td><p>\K[0-9]+' | sort -u)
  duplicate_confluence_codes=()
  for insert_code in $new_codes; do
    if echo "$confluence_codes" | grep -qw "$insert_code"; then
      duplicate_confluence_codes+=("$insert_code")
    fi
  done
#  if [ -n "$duplicate_confluence_codes" ]; then
#    echo "Error: The error code already exists in Confluence: $duplicate_confluence_codes"
#    exit 1
#  fi

  # 检查confluence上面的错误码是否比本地的多，如果是，则不允许提交且给出先同步的提示
  duplicate_codes=()
  for remote_code in $confluence_codes; do
    if ! echo "$error_codes_in_md" | grep -qw "$remote_code" && \
       ! echo "$deleted_codes" | grep -qw "$remote_code"; then
      duplicate_codes+=("$remote_code")
    fi
  done

  if [ -n "$duplicate_codes" ]; then
    echo "Error: Confluence has been updated to the latest version. Please sync the error codes from Confluence to your local environment first: $duplicate_codes"
    exit 1
  fi
fi

echo $duplicate_codes
echo "===="
echo $confluence_codes
echo "===="
echo $deleted_codes





