ERROR_CODE_FILE="ERROR_CODE.md"

# 1. 检查 README.md 是否有重复错误码
check_duplicate_error_codes() {
	error_codes=$(awk '
	/\| [0-9]+ \|/ {
		split($0, fields, "|")
		gsub(/[[:space:]]+/, "", fields[2])
		print fields[2]
	}' "$ERROR_CODE_FILE")

	duplicate_codes=$(echo "$error_codes" | sort | uniq -d)

	if [ -n "$duplicate_codes" ]; then
		echo "Error: Duplicate error codes found: $duplicate_codes"
		exit 1
	fi
}

# 2. 获取本次提交新增的错误码
get_new_error_codes() {
	git diff --cached "$ERROR_CODE_FILE" | grep '^+' | awk '
	/^\+[[:space:]]*\|[[:space:]]*[0-9]+[[:space:]]*\|/ {
		split($0, fields, "|")
		gsub(/[[:space:]]+/, "", fields[2])
		print fields[2]
	}'
}

# 3. 获取本次提交删除的错误码
get_deleted_error_codes() {
	git diff --cached "$ERROR_CODE_FILE" | grep '^-' | awk '
	/^-[[:space:]]*\|[[:space:]]*[0-9]+[[:space:]]*\|/ {
		split($0, fields, "|")
		gsub(/[[:space:]]+/, "", fields[2])
		print fields[2]
	}'
}

# 提取 Confluence 中已有的错误码
get_confluence_error_codes() {
    curl -s --location 'https://thebidgroup.atlassian.net/wiki/api/v2/pages/3333423226?body-format=STORAGE' \
    --header 'Accept: application/json' \
    --header 'Authorization: Basic dmFyZHkuemhhb0BsaWZlYnl0ZS5pbzpBVEFUVDN4RmZHRjBaS0ROSHY5VGh5My1abzhfMDRLb1dIZ0tJMUdWRkpKMEJYRUx0Q1dqWERONXd6ckt3SDdUcUVnajRJbWhiV0pZSHhSb1pHZXJVZ1B4MGpmNWJNeGtwc1piUkNuSndDWVBRZG1BWEw5dHNmZ2tJelFBLTQ1UnRCdGd6bkoyMmY5M3ZvV044RldDazdOVjNxVVdHdzZ5ZWRzTk1qaVd1OTR6UzZubzdkb0ZNcnc9QzZFMThENEM='
}

# 提取 README.md 中的错误码表格内容
extract_error_code_table() {
  awk '
  BEGIN { in_table = 0 }
  /^## 异常code表/ { in_table = 1; next }
  /^## / { in_table = 0 }
  in_table { print }
  ' "$ERROR_CODE_FILE"
}

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

# 替换 Confluence 文档中表格的内容
replace_table_content() {
  local html_content="$1"
  local new_table_content="$2"

  echo "$html_content" | awk -v new_content="$new_table_content" '
  BEGIN { FS = "</tbody>"; OFS = "</tbody>" }
  {
    if (match($0, /<tbody>.*<\/tbody>/)) {
      pre_body = substr($0, 1, RSTART - 1)
      post_body = substr($0, RSTART + RLENGTH)
      print pre_body "<tbody>" new_content "</tbody>" post_body
    } else {
      print $0
    }
  }' | sed 's|<tr><td><p>Code</p></td><td><p>CN</p></td><td><p>EN</p></td></tr>|<tr><th><p>Code</p></th><th><p>CN</p></th><th><p>EN</p></th></tr>|g'
}

# 校验ERROR_CODE.md有没有重复的code
check_duplicate_error_codes

# 获取新增和删除的错误码
new_error_codes=$(get_new_error_codes)
deleted_error_codes=$(get_deleted_error_codes)

echo $new_error_codes # 101 102 103
echo $deleted_error_codes # 101 102
common_codes=$(awk 'BEGIN{RS=" ";ORS="\n"} {seen[$0]++} END{for(code in seen) if(seen[code]>1) print code}' <(echo "$new_error_codes $deleted_error_codes"))

# 输出相同的错误码
if [ -n "$common_codes" ]; then
    echo "以下错误码同时出现在新增和删除列表中: $common_codes"
else
    echo "没有相同的错误码。"
fi
exit 1

# 检查新增的code在confluence上面存不存在
if [ -n "$new_error_codes" ]; then
	confluence_data=$(get_confluence_error_codes)
	confluence_codes=$(echo "$confluence_data" | grep -oP '<td><p>\K[0-9]+' | sort -u)

	# 检查是否有新增的错误码已经存在于 Confluence
	duplicates_in_confluence=""
	for code in $new_error_codes; do
		if echo "$confluence_codes" | grep -q "^$code$"; then
		duplicates_in_confluence="$duplicates_in_confluence $code"
		fi
	done

	if [ -n "$duplicates_in_confluence" ]; then
		echo "Error: The following newly added error codes already exist in Confluence: $duplicates_in_confluence"
		exit 1
	fi
fi

# 更新 Confluence
if [ -n "$deleted_error_codes" ] || [ -n "$new_error_codes" ]; then
	error_code_table=$(extract_error_code_table)
	if [ -z "$error_code_table" ]; then
		echo "Error: No error code table found in README.md"
		exit 1
	fi

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



