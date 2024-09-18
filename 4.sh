#!/bin/bash

error_code_file=ERROR_CODE.md
page_id="3333423226"

# 提取 ERROR_CODE.md
error_codes_in_md=$(grep '^|\s*[0-9]' "$error_code_file" | awk -F '|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')

# 检查是否有重复的错误码
duplicate_code=$(echo "$error_codes_in_md" | sort | uniq -d)
if [ -n "$duplicate_code" ]; then
    echo "Error: Duplicate error codes found in ERROR_CODE.md: $duplicate_code"
    exit 1
fi

echo "start: "$(date +'%Y-%m-%d %H:%M:%S')

# 通过git diff获取本次提交的改动
new_error_codes=$(git diff --cached "$error_code_file" | grep -E '^\+\s*\|\s*[0-9xX]+' | awk -F '|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
deleted_error_codes=$(git diff --cached "$error_code_file" | grep -E '^\-\s*\|\s*[0-9xX]+' | awk -F '|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
updated_error_codes=$(git diff --cached --ignore-all-space -U0 "$error_code_file" | awk '
  /^-/ {
    old = $0;
    split(old, parts, "|");
    if (length(parts) >= 3) {
      old_code = trim(parts[2]);
      old_desc = trim(parts[3]);
      if (index(old_code, "-") == 0) {
        old_entries[old_code] = old_desc;
      }
    }
  }
  /^\+/ {
    new = $0;
    split(new, parts, "|");
    if (length(parts) >= 3) {
      new_code = trim(parts[2]);
      new_desc = trim(parts[3]);
      if (index(new_code, "-") == 0) {
        new_entries[new_code] = new_desc;
        if (old_entries[new_code] && old_entries[new_code] != new_desc) {
          print new_code;
        }
      }
    }
  }

  function trim(str) {
    gsub(/^[ \t]+|[ \t]+$/, "", str);
    return str;
  }
')

echo "获取改动: "$(date +'%Y-%m-%d %H:%M:%S')

# 文件有变化，需要检查是否有重复的错误码
if [ -n "$deleted_error_codes" ] || [ -n "$new_error_codes" ]; then
  # git diff 如果是修改，会同时存在一个-，一个+，可以不用检查confluence
  # 如果是新增，只会有一个+，这个就要检查confluence
  # 如果是删除，只会有一个-，不需要检查confluence
  updated_codes=""
  new_codes=()
  deleted_codes=""
  for new_item in $new_error_codes; do
    flag=0
    for deleted_item in $deleted_error_codes; do
    if [ "$new_item" == "$deleted_item" ]; then
        flag=1
        break
    fi
    done
    if [ $flag -eq 1 ]; then
      updated_codes="$updated_codes $new_item"
    else
      new_codes+=("$new_item")
    fi
  done
  for remove_item in $deleted_error_codes; do
    if ! echo "$updated_codes" | grep -qw "$remove_item"; then
      deleted_codes="$deleted_codes $remove_item"
    fi
  done

  echo "检查本地差异: "$(date +'%Y-%m-%d %H:%M:%S')

  # 检查conflunce和ERROR_CODE的差异
  confluence_data=$(curl -s --location 'https://thebidgroup.atlassian.net/wiki/api/v2/pages/'$page_id'?body-format=STORAGE' \
      --header 'Accept: application/json' \
      --header 'Authorization: Basic dmFyZHkuemhhb0BsaWZlYnl0ZS5pbzpBVEFUVDN4RmZHRjBaS0ROSHY5VGh5My1abzhfMDRLb1dIZ0tJMUdWRkpKMEJYRUx0Q1dqWERONXd6ckt3SDdUcUVnajRJbWhiV0pZSHhSb1pHZXJVZ1B4MGpmNWJNeGtwc1piUkNuSndDWVBRZG1BWEw5dHNmZ2tJelFBLTQ1UnRCdGd6bkoyMmY5M3ZvV044RldDazdOVjNxVVdHdzZ5ZWRzTk1qaVd1OTR6UzZubzdkb0ZNcnc9QzZFMThENEM=' \
  )
  confluence_codes=($(echo "$confluence_data" | grep -o '<tr><td><p>[0-9xX]\{1,\}</p></td>' | sed 's|<[^>]*>||g' | sed 's/^[ \t]*//;s/[ \t]*$//'))
  duplicate_confluence_codes=()
  for insert_code in ${new_codes[@]}; do
      for code in "${confluence_codes[@]}"; do
          if [[ "$code" == "$insert_code" ]]; then
              duplicate_confluence_codes+=("$insert_code")
              break
          fi
      done
  done
  if [ ${#duplicate_confluence_codes[@]} -gt 0 ]; then
      echo "Error: The error code already exists in Confluence: ${duplicate_confluence_codes[*]}"
      exit 1
  fi
  echo "检查confluence差异: "$(date +'%Y-%m-%d %H:%M:%S')

  # 无法匹配右边描述是空的情况，右边空的要加上占位符“-”
  table_content=$(echo "$confluence_data" | grep -o "<table[^>]*>.*</table>")
  exec 3>&1 4>&2
  perl_output=$(echo "$table_content" | perl -e '
    use strict;
    use warnings;

    my ($wait_delete, $wait_update) = @ARGV;
    my @del_codes = split(" ", $wait_delete);
    my @update_codes = split(" ", $wait_update);
    my $table_content = do { local $/; <STDIN> };

    while ($table_content =~ /<tr><td><p>([^<]*)<\/p><\/td><td><p>([^<]*)<\/p><\/td><\/tr>/g) {
      my $code = $1;
      my $desc = $2;

      # 去除空白字符
      $code =~ s/^\s+|\s+$//g;

      # 判断是否需要删除
      my $delete_flag = 0;
      foreach my $del_code (@del_codes) {
        if ($code eq $del_code) {
          $delete_flag = 1;
          last;
        }
      }

      # 判断有没有更新，筛选掉本次更新的
      my $update_flag = 0;
      foreach my $update_code (@update_codes) {
        if ($code eq $update_code) {
            $update_flag = 1;
            last;
        }
      }

      # 如果不需要删除，分别输出 code 和 desc，使用制表符分隔
      if ($delete_flag == 0 && $update_flag == 0) {
        print "$code\t$desc\n";
      }
    }
  ' "$deleted_codes" "$updated_error_codes")
  conf_array=()
  conf_html_array=()
  conf_code_array=()
  while IFS= read -r entry; do
      IFS=$'\t' read -r code desc <<< "$entry"
      desc=${desc}
      conf_array+=("| $code | $desc |")
      conf_html_array+=("<tr><td><p>$code</p></td><td><p>$desc</p></td></tr>")
      conf_code_array+=("$code")
  done <<< "$perl_output"

  echo "读取confluence数据: "$(date +'%Y-%m-%d %H:%M:%S')

  md_array=()
  md_html_array=()
  md_code_array=()
  count=0
  while IFS= read -r line || [[ -n $line ]];  do
    count=$((count+1))
    [[ $count -lt 4 ]] && continue

    # 跳过空行
    [[ -z "$line" ]] && continue

    IFS='|' read -r -a array <<< "$line"

    code="${array[1]//[[:space:]]/}"
    description="${array[2]}"

    # 如果在deleted_codes，跳过
    del_flag=0
    for del in "${deleted_codes[@]}"; do
      if [[ "$del" == "$code" ]]; then
        del_flag=1
        break
      fi
    done
    if [[ "$del_flag" == 1 ]]; then
      continue
    fi
    # 不在本次更新内容里，跳过
    update_flag=0
    new_flag=0
    for update in ${updated_error_codes[@]}; do
      if [[ "$update" == "$code" ]]; then
        update_flag=1
        break
      fi
    done
    for new in ${new_codes[@]}; do
      if [[ "$new" == "$code" ]]; then
        new_flag=1
        break
      fi
    done
    if [[ "$update_flag" == 1 ]] || [[ "$new_flag" == 1 ]] ; then
      md_array+=("| $code | $description |")
      md_html_array+=("<tr><td><p>$code</p></td><td><p>$description</p></td></tr>")
      md_code_array+=("$code")
    fi
  done < "$error_code_file"

  echo "读取md数据: "$(date +'%Y-%m-%d %H:%M:%S')

  new_markdown_file="tmp_new_md"
  echo "## 异常code表
| Code  | Description                                 |
|-------|---------------------------------------------|" >> "$new_markdown_file"
  table_html='<table data-table-width=\"1800\" data-layout=\"align-start\" ac:local-id=\"f8055d4b-ca9c-494e-a150-e2ce3fda4628\"><tbody><tr><th><p><strong>Code</strong></p></th><th><p><strong>Description</strong></p></th></tr>'
  conf_i=0
  md_i=0
  x_code_num=""
  while true; do
    if [[ $conf_i -ge ${#conf_code_array[@]} ]] && [[ $md_i -ge ${#md_code_array[@]} ]]; then
      break
    fi

    conf_code=${conf_code_array[conf_i]}
    md_code=${md_code_array[md_i]}

    if [[ -z "$conf_code" ]] && [[ -z "$md_code" ]]; then
      break
    fi

    if [[ -z "$conf_code" ]]; then
      echo ${md_array[md_i]} >> "$new_markdown_file"
      table_html=$table_html${md_html_array[md_i]}
      md_i=$((md_i+1))
    elif [[ -z "$md_code" ]]; then
      echo ${conf_array[conf_i]} >> "$new_markdown_file"
      table_html=$table_html${conf_html_array[conf_i]}
      conf_i=$((conf_i+1))
    elif [[ "$conf_code" == "$md_code" ]]; then
      echo ${md_array[md_i]} >> "$new_markdown_file"
      table_html=$table_html${md_html_array[md_i]}
      conf_i=$((conf_i+1))
      md_i=$((md_i+1))
    elif [[ "$conf_code" == *"x"* ]]; then
      # 如果有x把x替换成0，再比对大小，所以要求后续有几位就加几个x
      x_code_num=$(echo "$conf_code" | sed 's/x/0/g')
      tmp_md_code=$md_code
      if [[ "$md_code" == *"x"* ]]; then
        tmp_md_code=$(echo "$md_code" | sed 's/x/0/g')
      fi
      if [[ "$tmp_md_code" -lt "$x_code_num" ]]; then
        echo ${md_array[md_i]} >> "$new_markdown_file"
        table_html=$table_html${md_html_array[md_i]}
        md_i=$((md_i+1))
      else
        echo ${conf_array[conf_i]} >> "$new_markdown_file"
        table_html=$table_html${conf_html_array[conf_i]}
        conf_i=$((conf_i+1))
        x_code_num=""
      fi
    elif [[ "$md_code" == *"x"* ]]; then
      # 如果有x把x替换成0，再比对大小，所以要求后续有几位就加几个x
      x_code_num=$(echo "$md_code" | sed 's/x/0/g')
      tmp_conf_code=$conf_code
      if [[ "$conf_code" == *"x"* ]]; then
        tmp_conf_code=$(echo "$conf_code" | sed 's/x/0/g')
      fi
      if [[ "$tmp_conf_code" -lt "$x_code_num" ]]; then
        echo ${conf_array[conf_i]} >> "$new_markdown_file"
        table_html=$table_html${conf_html_array[conf_i]}
        conf_i=$((conf_i+1))
      else
        echo ${md_array[md_i]} >> "$new_markdown_file"
        table_html=$table_html${md_html_array[md_i]}
        md_i=$((md_i+1))
        x_code_num=""
      fi
    elif [[ "$conf_code" -lt "$md_code" ]]; then
      echo ${conf_array[conf_i]} >> "$new_markdown_file"
      table_html=$table_html${conf_html_array[conf_i]}
      conf_i=$((conf_i+1))
    elif [[ "$md_code" -lt "$conf_code" ]]; then
      echo ${md_array[md_i]} >> "$new_markdown_file"
      table_html=$table_html${md_html_array[md_i]}
      md_i=$((md_i+1))
    fi
  done
  table_html=$table_html"</tbody></table><p />"

  echo "组装临时md: "$(date +'%Y-%m-%d %H:%M:%S')

  exit 1

  version_number=$(echo "$confluence_data" | grep -o '"number":[0-9]*' | awk -F: '{print $2}')
  new_version_number=$((version_number + 1))
  echo '{
       "id": "'$page_id'",
       "status": "current",
       "title": "Backend Error Code",
       "body": {
           "representation": "storage",
           "value": "'$table_html'"
       },
       "version": {
           "number": '$new_version_number',
           "message": "Git commit with update doc"
       }
   }' > tmp_params.json 
  response=$(curl -s -X PUT 'https://thebidgroup.atlassian.net/wiki/api/v2/pages/'$page_id \
  --header 'Content-Type: application/json' \
  --header 'Accept: application/json' \
  --header 'Authorization: Basic dmFyZHkuemhhb0BsaWZlYnl0ZS5pbzpBVEFUVDN4RmZHRjBaS0ROSHY5VGh5My1abzhfMDRLb1dIZ0tJMUdWRkpKMEJYRUx0Q1dqWERONXd6ckt3SDdUcUVnajRJbWhiV0pZSHhSb1pHZXJVZ1B4MGpmNWJNeGtwc1piUkNuSndDWVBRZG1BWEw5dHNmZ2tJelFBLTQ1UnRCdGd6bkoyMmY5M3ZvV044RldDazdOVjNxVVdHdzZ5ZWRzTk1qaVd1OTR6UzZubzdkb0ZNcnc9QzZFMThENEM=' \
  --data-binary @tmp_params.json)
  rm -f tmp_params.json

  status=$(echo "$response" | sed -n 's/.*"status":\s*\([0-9]\+\).*/\1/p')
  if [[ -n "$status" ]]; then
    echo $response
    echo "Request failed with status code: $status"
    rm -f "$new_markdown_file"
    exit 1
  else
    cat "$new_markdown_file" > "$error_code_file"
    git add $error_code_file
    echo "Succeed to update ERROR_CODE.md and CONFLUENCE"
    rm -f "$new_markdown_file"
  fi
fi
