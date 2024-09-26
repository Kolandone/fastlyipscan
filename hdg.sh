#!/bin/bash


ip_to_decimal() {
    local ip="$1"
    local a b c d
    IFS=. read -r a b c d <<< "$ip"
    echo "$((a * 256**3 + b * 256**2 + c * 256 + d))"
}


decimal_to_ip() {
    local dec="$1"
    local a=$((dec / 256**3 % 256))
    local b=$((dec / 256**2 % 256))
    local c=$((dec / 256 % 256))
    local d=$((dec % 256))
    echo "$a.$b.$c.$d"
}


measure_latency() {
    local ip=$1
    local latency=$(ping -c 1 -W 1 "$ip" | grep 'time=' | awk -F'time=' '{ print $2 }' | cut -d' ' -f1)
    if [ -z "$latency" ]; then
        latency="N/A"
    fi
    printf "%s %s\n" "$ip" "$latency"
}


generate_ips_in_cidr() {
    local cidr="$1"
    local limit="$2" 
    local base_ip=$(echo "$cidr" | cut -d'/' -f1)
    local prefix=$(echo "$cidr" | cut -d'/' -f2)
    local ip_dec=$(ip_to_decimal "$base_ip")
    local range_size=$((2 ** (32 - prefix)))
    local ips=()

    
    for ((i=0; i<limit; i++)); do
        local random_offset=$((RANDOM % range_size))
        ips+=("$(decimal_to_ip $((ip_dec + random_offset)))")
    done

    echo "${ips[@]}"
}


check_and_install() {
    if ! command -v $1 &> /dev/null; then
        echo "$1 not found, installing..."
        pkg install -y $2
    else
        echo "$1 is already installed."
    fi
}


check_and_install ping inetutils
check_and_install awk coreutils
check_and_install grep grep
check_and_install cut coreutils
check_and_install curl curl
check_and_install bc bc


IP_RANGES=(
    "23.235.32.0/20" "43.249.72.0/22" "103.244.50.0/24" "103.245.222.0/23"
    "103.245.224.0/24" "104.156.80.0/20" "140.248.64.0/18" "140.248.128.0/17"
    "146.75.0.0/17" "151.101.0.0/16" "157.52.64.0/18" "167.82.0.0/17"
    "167.82.128.0/20" "167.82.160.0/20" "167.82.224.0/20" "172.111.64.0/18"
    "185.31.16.0/22" "199.27.72.0/21" "199.232.0.0/16"
)


show_progress() {
    local current=$1
    local total=$2
    local percent=$(( 100 * current / total ))
    local progress=$(( current * 50 / total ))
    local green=$(( progress ))
    local red=$(( 50 - progress ))

    printf "\r["
    printf "\e[42m%${green}s\e[0m" | tr ' ' '='
    printf "\e[41m%${red}s\e[0m" | tr ' ' '='
    printf "] %d%%" "$percent"
}


LIMIT=50


SELECTED_IP_RANGES=($(shuf -e "${IP_RANGES[@]}" -n 5))
echo "Selected IP Ranges: ${SELECTED_IP_RANGES[@]}"

SELECTED_IPS=()
for range in "${SELECTED_IP_RANGES[@]}"; do
    ips=($(generate_ips_in_cidr "$range" "$LIMIT"))
    SELECTED_IPS+=("${ips[@]}")
done


SHUFFLED_IPS=($(shuf -e "${SELECTED_IPS[@]}" -n 100))


display_table_ipv4() {
    printf "+-----------------------+------------+\n"
    printf "| IP                    | Latency(ms) |\n"
    printf "+-----------------------+------------+\n"
    echo "$1" | while read -r ip latency; do
        if [ "$latency" == "N/A" ]; then
            continue
        fi
        printf "| %-21s | %-10s |\n" "$ip" "$latency"
    done
    printf "+-----------------------+------------+\n"
}


valid_ips=()
total_ips=${#SHUFFLED_IPS[@]}
processed_ips=0

while [[ ${#valid_ips[@]} -lt 10 ]]; do
    
    ping_results=$(printf "%s\n" "${SHUFFLED_IPS[@]}" | xargs -I {} -P 10 bash -c '
    measure_latency() {
        local ip="$1"
        local latency=$(ping -c 1 -W 1 "$ip" | grep "time=" | awk -F"time=" "{ print \$2 }" | cut -d" " -f1)
        if [ -z "$latency" ]; then
            latency="N/A"
        fi
        printf "%s %s\n" "$ip" "$latency"
    }
    measure_latency "$@"
    ' _ {})

    
    valid_ips=($(echo "$ping_results" | grep -v "N/A" | awk '{print $1}'))

    processed_ips=$((${#valid_ips[@]} + ${#SHUFFLED_IPS[@]} - $total_ips))
    show_progress $processed_ips $total_ips

    
    if [[ ${#valid_ips[@]} -lt 10 ]]; then
        echo -e "\nNot enough valid IPs found. Selecting more IP ranges..."
        additional_ips=($(generate_ips_in_cidr "$range" "$LIMIT"))
        SHUFFLED_IPS=($(shuf -e "${additional_ips[@]}" -n 100))
        total_ips=${#SHUFFLED_IPS[@]}
        processed_ips=0
    fi
done


clear
echo -e "\e[1;32mDisplaying top IPs with valid latency...\e[0m"
display_table_ipv4 "$ping_results"

comma_separated_ips=$(IFS=,; echo "${valid_ips[*]}")
echo -e "\e[1;33mDisplaying all valid IPs:\e[0m"
echo "$comma_separated_ips"

