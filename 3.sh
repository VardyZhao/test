#!/bin/bash

# 提取 ERROR_CODE.md 中的错误码
extract_error_codes() {
    grep '^|\s*[0-9]' ERROR_CODE.md | awk -F '|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}'
}

# 检查是否有重复的错误码
check_duplicate_codes() {
    local codes=("$@")
    local duplicates=($(echo "${codes[@]}" | tr ' ' '\n' | sort | uniq -d))
    echo "${duplicates[@]}"
}

# 获取 git diff 中本次提交的改动
git_diff() {
    git diff --cached ERROR_CODE.md
}

# 从 diff 中提取新增和删除的错误码
extract_diff_codes() {
    local diff="$1"
    local symbol="$2"
    echo "$diff" | grep "^$symbol|\s*[0-9]" | awk -F '|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}'
}

# 从 Confluence 获取错误码
get_confluence_codes() {
    local response=$(curl -s --location 'https://thebidgroup.atlassian.net/wiki/api/v2/pages/3333423226?body-format=STORAGE' \
        --header 'Accept: application/json' \
        --header 'Authorization: Basic dmFyZHkuemhhb0BsaWZlYnl0ZS5pbzpBVEFUVDN4RmZHRjBaS0ROSHY5VGh5My1abzhfMDRLb1dIZ0tJMUdWRkpKMEJYRUx0Q1dqWERONXd6ckt3SDdUcUVnajRJbWhiV0pZSHhSb1pHZXJVZ1B4MGpmNWJNeGtwc1piUkNuSndDWVBRZG1BWEw5dHNmZ2tJelFBLTQ1UnRCdGd6bkoyMmY5M3ZvV044RldDazdOVjNxVVdHdzZ5ZWRzTk1qaVd1OTR6UzZubzdkb0ZNcnc9QzZFMThENEM=')

    echo "$response" | grep -o '<tr><td><p>[0-9]\+</p ></td>' | sed 's|<[^>]*>||g' | sort -u
}

# 主逻辑
main() {
    # 提取 ERROR_CODE.md 中的错误码
    error_codes_in_md=($(extract_error_codes))

    # 检查是否有重复的错误码
    duplicate_code=($(check_duplicate_codes "${error_codes_in_md[@]}"))
    if [ ${#duplicate_code[@]} -ne 0 ]; then
        echo "Error: Duplicate error codes found in ERROR_CODE.md: ${duplicate_code[@]}"
        exit 1
    fi

    # 获取 git diff 中的改动
    diff_output=$(git_diff)
    new_error_codes=($(extract_diff_codes "$diff_output" '+'))
    deleted_error_codes=($(extract_diff_codes "$diff_output" '-'))

    if [ ${#new_error_codes[@]} -ne 0 ] || [ ${#deleted_error_codes[@]} -ne 0 ]; then
        updated_codes=()
        new_codes=()
        deleted_codes=()

        for new_code in "${new_error_codes[@]}"; do
            if [[ " ${deleted_error_codes[@]} " =~ " $new_code " ]]; then
                updated_codes+=("$new_code")
            else
                new_codes+=("$new_code")
            fi
        done

        for deleted_code in "${deleted_error_codes[@]}"; do
            if [[ ! " ${updated_codes[@]} " =~ " $deleted_code " ]]; then
                deleted_codes+=("$deleted_code")
            fi
        done

        # 获取 Confluence 上的错误码
        confluence_codes=($(get_confluence_codes))
        echo "Confluence error codes: ${confluence_codes[@]}"

        # 检查新增的错误码是否已存在于 Confluence
        duplicate_confluence_codes=()
        for new_code in "${new_codes[@]}"; do
            if [[ " ${confluence_codes[@]} " =~ " $new_code " ]]; then
                duplicate_confluence_codes+=("$new_code")
            fi
        done

        if [ ${#duplicate_confluence_codes[@]} -ne 0 ]; then
            echo "Error: The error code already exists in Confluence: ${duplicate_confluence_codes[@]}"
            exit 1
        fi

        # 检查 Confluence 上是否有未同步的错误码
        unsynced_codes=()
        for confluence_code in "${confluence_codes[@]}"; do
            if [[ ! " ${error_codes_in_md[@]} " =~ " $confluence_code " && ! " ${deleted_codes[@]} " =~ " $confluence_code " ]]; then
                unsynced_codes+=("$confluence_code")
            fi
        done

        if [ ${#unsynced_codes[@]} -ne 0 ]; then
            echo "Error: Confluence has been updated. Please sync the error codes: ${unsynced_codes[@]}"
            exit 1
        fi
    fi

    echo "No issues found."
    exit 0
}

main