#!/bin/bash

# DNS服务器的IP地址
DNS_SERVER="10.246.128.120"

# 需要解析的域名前缀列表
DOMAINS=("shui" "mizu" "climate" "energy" "water" "land" "carbon" "moisture" "rainfall" "PREP-NexT" "prep-next-printer")
DOMAIN_ROOT="prepnext.nus.edu.sg"

# hosts文件路径
HOSTS_FILE="/etc/hosts"

# 脚本创建条目的标识
START_MARKER=">>>>>> Start of entries added by prep-next_hosts.sh"
END_MARKER="<<<<<< End of entries added by prep-next_hosts.sh"

# 检查dig命令是否存在
if ! command -v dig &>/dev/null; then
    echo "dig command not found, please install dig with 'apt-get install dnsutils' or equivalent"
    exit 1
fi

# 检查是否能够访问指定的DNS服务器
if ! nc -z "$DNS_SERVER" 53 &>/dev/null; then
    echo "Cannot connect to the DNS server at $DNS_SERVER. Please make sure you are in the Campus Network to run this script."
    exit 1
fi

# 检查sudo权限
SUDO=''
if [ "$(id -u)" != "0" ]; then
    SUDO='sudo'
fi

# 检查当前操作系统，为sed命令设置相应的参数
if [[ "$(uname)" == "Darwin" ]]; then
    SED_I_OPTION=(-i '') # macOS 需要空字符串作为后缀
else
    SED_I_OPTION=(-i)    # Linux 不需要后缀
fi

# 提取由脚本管理的当前条目
CURRENT_ENTRIES=$(awk "/$START_MARKER/,/$END_MARKER/ { if (!/$START_MARKER/ && !/$END_MARKER/) print }" $HOSTS_FILE)
# echo "$CURRENT_ENTRIES"

# 标志变量，用于跟踪是否有变化
has_changes=false

# 函数：检查和提示条目变更
check_and_prompt_changes() {
    local ip=$1
    local fqdn=$2
    local hostname=$3
    local entry="$ip $fqdn $hostname"
    local existing_entry=$(echo "$CURRENT_ENTRIES" | grep -m 1 $fqdn || true)
    local existing_ip=$(echo "$existing_entry" | awk '{print $1}')

    if [[ "$existing_ip" != "$ip" ]]; then
        if [[ -n "$existing_ip" ]]; then
            echo "$fqdn has been updated to $ip"
            has_changes=true
        else
            echo "Adding new entry for $fqdn with IP $ip"
            has_changes=true
        fi
    fi
}

# 函数：移除过时的条目并提示变更
remove_obsolete_entries_and_prompt() {
    local domains=("$@")
    # 如果当前条目为空，不执行任何操作
    if [ -z "$CURRENT_ENTRIES" ]; then
        return
    fi
    while IFS= read -r line; do
        local is_obsolete=true
        local fqdn=$(echo "$line" | awk '{print $2}')
        for domain in "${domains[@]}"; do
            local expected_fqdn="${domain}.${DOMAIN_ROOT}"
            if [[ "$fqdn" == "$expected_fqdn" ]]; then
                is_obsolete=false
                break
            fi
        done
        if [[ "$is_obsolete" == true ]]; then
            echo "A domain $fqdn has been removed from the list."
            has_changes=true
        fi
    done <<< "$CURRENT_ENTRIES"
}

# 检查和提示将要移除的条目
remove_obsolete_entries_and_prompt "${DOMAINS[@]}"

# 检查和提示将要增加或更新的条目
for DOMAIN in "${DOMAINS[@]}"; do
    FULL_DOMAIN="${DOMAIN}.${DOMAIN_ROOT}"
    IP=$(dig +short @"$DNS_SERVER" "$FULL_DOMAIN" A)
    if [[ -n "$IP" ]]; then
        check_and_prompt_changes "$IP" "$FULL_DOMAIN" "$DOMAIN"
    else
        echo "Failed to resolve $FULL_DOMAIN"
    fi
done

# 如果检测到变更，则询问用户是否要应用这些变更
if [[ "$has_changes" == true ]]; then
    read -p "Would you like to update $HOSTS_FILE? [y/N]." response
    if [[ $response =~ ^[Yy]$ ]]; then
        # 接受变更，清除并重新添加条目
        echo "The password may be needed to update $HOSTS_FILE"
        $SUDO sed "${SED_I_OPTION[@]}" "/$START_MARKER/,/$END_MARKER/d" "$HOSTS_FILE"
        echo "$START_MARKER" | $SUDO tee -a "$HOSTS_FILE"
        for DOMAIN in "${DOMAINS[@]}"; do
            FULL_DOMAIN="${DOMAIN}.${DOMAIN_ROOT}"
            IP=$(dig +short @"$DNS_SERVER" "$FULL_DOMAIN" A)
            if [[ -n "$IP" ]]; then
                echo -e "$IP\t$FULL_DOMAIN\t$DOMAIN" | $SUDO tee -a "$HOSTS_FILE"
            fi
        done
        echo "$END_MARKER" | $SUDO tee -a "$HOSTS_FILE"
        echo "The $HOSTS_FILE has been updated."
    else
        echo "No changes were made to $HOSTS_FILE."
    fi
else
    echo "No changes detected. $HOSTS_FILE is up-to-date."
fi