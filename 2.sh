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

  PYTHON_CMD=""
  PHP_CMD=""
  # 更新confluence，中文字符shell不好处理，要用python或者php
  if command -v py &> /dev/null; then
      PYTHON_CMD="py"
  elif command -v py3 &> /dev/null; then
      PYTHON_CMD="py3"
  elif command -v python3 &> /dev/null; then
      PYTHON_CMD="python3"
  elif command -v python &> /dev/null; then
      PYTHON_CMD="python"
  elif command -v php &> /dev/null; then
      PHP_CMD="php"
  elif command -v php7 &> /dev/null; then
      PHP_CMD="php7"
  elif command -v php8 &> /dev/null; then
      PHP_CMD="php8"
  else
      echo "Python or PHP is not installed on this system.Can't update Confluence document,Please update Confluence document manually"
      exit 1
  fi
  if [ -n "$PYTHON_CMD" ]; then
    $PYTHON_CMD -c '
import sys
import http.client
import json
import re

conflunce_data=json.loads(sys.argv[1])
version_number=conflunce_data["version"]["number"]+1
with open("ERROR_CODE.md", "r", encoding="utf-8") as file:
    lines=file.readlines()
table_lines=lines[2:]
table_data=[re.split(r"\s*\|\s*", line.strip())[1:-1] for line in table_lines if "|" in line]
html_content="<table data-table-width=\"1800\" data-layout=\"default\" ac:local-id=\"8cfa5e45-3eee-441b-9847-85c0fb3af991\"><tbody>"
for row in table_data:
    html_content+="<tr>"
    for cell in row:
        html_content+=f"<td><p>{cell.strip()}</p></td>"
    html_content+="</tr>"
html_content+="</tbody></table>"

payload = json.dumps({
    "id": "3333423226",
    "status": "current",
    "title": "Backend Error Code",
    "body": {
        "representation": "storage",
        "value": html_content
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
conn = http.client.HTTPSConnection("thebidgroup.atlassian.net")
conn.request("PUT", "/wiki/api/v2/pages/3333423226", body=payload, headers=headers)
response = conn.getresponse()
conn.close()
data = response.read()
if response.status == 200:
    print("Confluence content updated successfully.")
else:
    print(f"Failed to update Confluence content: {response.status}")
    exit(1)
' "$confluence_data"
  elif [ -n "$PHP_CMD" ]; then
    $PHP_CMD -r '
<?php
$confluence_data = json_decode($argv[1], true);
$version_number = $confluence_data["version"]["number"] + 1;
$table_data = [];
$lines = file("ERROR_CODE.md", FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
$table_lines = array_slice($lines, 2);
foreach ($table_lines as $line) {
    if (strpos($line, "|") !== false) {
        // 使用正则表达式来处理每一行并将其转为表格
        $row = preg_split("/\s*\|\s*/", trim($line));
        array_shift($row);
        array_pop($row);
        $table_data[] = $row;
    }
}
$html_content = "<table data-table-width=\"1800\" data-layout=\"default\" ac:local-id=\"8cfa5e45-3eee-441b-9847-85c0fb3af991\"><tbody>";
foreach ($table_data as $row) {
    $html_content .= "<tr>";
    foreach ($row as $cell) {
        $html_content .= ""<td><p> . htmlspecialchars($cell) . "</p></td>";
    }
    $html_content .= "</tr>";
}
$html_content .= "</tbody></table>";
$payload = json_encode([
    "id" => "3333423226",
    "status" => "current",
    "title" => "Backend Error Code",
    "body" => [
        "representation" => "storage",
        "value" => $html_content
    ],
    "version" => [
        "number" => $version_number,
        "message" => "Git commit with update doc",
    ]
]);
$headers = [
    "Content-Type: application/json",
    "Accept: application/json",
    "Authorization: Basic dmFyZHkuemhhb0BsaWZlYnl0ZS5pbzpBVEFUVDN4RmZHRjBaS0ROSHY5VGh5My1abzhfMDRLb1dIZ0tJMUdWRkpKMEJYRUx0Q1dqWERONXd6ckt3SDdUcUVnajRJbWhiV0pZSHhSb1pHZXJVZ1B4MGpmNWJNeGtwc1piUkNuSndDWVBRZG1BWEw5dHNmZ2tJelFBLTQ1UnRCdGd6bkoyMmY5M3ZvV044RldDazdOVjNxVVdHdzZ5ZWRzTk1qaVd1OTR6UzZubzdkb0ZNcnc9QzZFMThENEM="
];
$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, "https://thebidgroup.atlassian.net/wiki/api/v2/pages/3333423226");
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "PUT");
curl_setopt($ch, CURLOPT_POSTFIELDS, $payload);
curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
$response = curl_exec($ch);
$httpcode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);
if ($httpcode == 200) {
    echo "Confluence content updated successfully.\n";
} else {
    echo "Failed to update Confluence content: " . $httpcode . "\n";
    exit(1);
}
?>
' "$confluence_data"
  fi
fi


# 测试用例
# 1、本地删除，confluence也要删除
# 2、confluence比本地的code多，提示要先更新
# 3、本地新增，本地不允许重复
# 4、本地新增，confluence上面有，不允许提交
# 5、本地修改，更新confluence




