#!/bin/bash

# 将 Markdown 表格转换为 HTML 表格 (只转换表内容，不转换表头)
convert_to_html() {
  awk '
  BEGIN { in_table = 0 }
  /^\| Code \| CN \| EN \|/ { in_table = 0 }
  /^\|/ {
    split($0, fields, "|")
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", fields[2])
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", fields[3])
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", fields[4])
    if (fields[2] ~ /^-/) { next }
    print "<tr><td><p>" fields[2] "</p></td><td><p>" fields[3] "</p></td><td><p>" fields[4] "</p></td></tr>"
  }
  '
}

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
  confluence_codes=$(echo "$confluence_data" | grep -o '<tr><td><p>[0-9]\+</p></td>' | sed 's|<[^>]*>||g' | sort -u)
  duplicate_confluence_codes=()
  for insert_code in $new_codes; do
    if echo "$confluence_codes" | grep -qw "$insert_code"; then
      duplicate_confluence_codes+=("$insert_code")
    fi
  done
  if [ -n "$duplicate_confluence_codes" ]; then
    echo "Error: The error code already exists in Confluence: $duplicate_confluence_codes"
    exit 1
  fi

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

  # 把本地的ERROR_CODE.md更新到conflunce上面
  html_table=$(echo "$error_code_table" | convert_to_html)
	version_number=$(echo "$confluence_data" | grep -o '"number":[0-9]*' | awk -F: '{print $2}')
	new_version_number=$((version_number + 1))
	current_html_content=$(echo "$confluence_data" | grep -oP '{"representation":"storage","value":"\K.*?(?=")"}},' | sed 's/...,$//')
	updated_html=$(replace_table_content "$current_html_content" "$html_table")
	python -c '
import sys
import requests
import json

content=sys.argv[1].replace("\"\"", "\"\"")
content=content.replace("\\\"", "\"")
version_number=sys.argv[2]
url = "https://thebidgroup.atlassian.net/wiki/api/v2/pages/3333423226"
payload = json.dumps({
    "id": "3333423226",
    "status": "current",
    "title": "Backend Error Code",
    "body": {
        "representation": "storage",
        "value": content
    },
    "version": {
        "number": version_number,
        "message": "Git commit with update doc"
    }
})
headers = {
    "Content-Type": "application/json",
    "Accept": "application/json",
    "Authorization": "Basic dmFyZHkuemhhb0BsaWZlYnl0ZS5pbzpBVEFUVDN4RmZHRjBaS0ROSHY5VGh5My1abzhfMDRLb1dIZ0tJMUdWRkpKMEJYRUx0Q1dqWERONXd6ckt3SDdUcUVnajRJbWhiV0pZSHhSb1pHZXJVZ1B4MGpmNWJNeGtwc1piUkNuSndDWVBRZG1BWEw5dHNmZ2tJelFBLTQ1UnRCdGd6bkoyMmY5M3ZvV044RldDazdOVjNxVVdHdzZ5ZWRzTk1qaVd1OTR6UzZubzdkb0ZNcnc9QzZFMThENEM="
}

response = requests.request("PUT", url, headers=headers, data=payload)
print(payload)
if response.status_code == 200:
    print("Confluence content updated successfully.")
else:
    print(f"Failed to update Confluence content: {response.status_code}")
    sys.exit(1)
	' "$updated_html" "$new_version_number"
fi

echo $duplicate_codes
echo "===="
echo $confluence_codes
echo "===="
echo $deleted_codes
echo "===="
echo $new_codes






