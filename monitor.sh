#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$SCRIPT_DIR/config/monitor.conf" ]; then
	echo "Error: config/monitor.conf not found"
	exit 1
fi

source "$SCRIPT_DIR/config/monitor.conf"

ALERT_LOG="$SCRIPT_DIR/logs/alerts.log"

ALERT_STATE="$SCRIPT_DIR/state/alerts.state"

show_help(){
    echo "Linux Server Monitor"
    echo
    echo "Usage:"
    echo "  ./monitor.sh                 Run monitoring"
    echo "  ./monitor.sh --status       Show current system status"
    echo "  ./monitor.sh --errors       Show WARNING and CRITICAL events"
    echo "  ./monitor.sh --errors LEVEL Show events for a specific severity"
    echo "  ./monitor.sh --help         Show this help message"
    echo
    echo "Valid severity levels:"
    echo "  WARNING"
    echo "  CRITICAL"
}

show_errors(){
    if [ ! -f "$SCRIPT_DIR/logs/monitor.log" ]; then
        echo "No log file found."
        return 0
    fi

    level=$1

    if [ -n "$level" ] && [ "$level" != "WARNING" ] && [ "$level" != "CRITICAL" ]; then
        echo "Invalid severity: $level"
        echo "Valid values: WARNING, CRITICAL"
        return 1
    fi

    if [ -z "$level" ]; then
        grep -E '\| WARNING \||\| CRITICAL \|' "$SCRIPT_DIR/logs/monitor.log"
    else
        grep -E "\| $level \|" "$SCRIPT_DIR/logs/monitor.log"
    fi
}


get_cpu_usage(){
    cpu1=$(head -n 1 /proc/stat)
    sleep 1
    cpu2=$(head -n 1 /proc/stat)

    total1=$(echo "$cpu1" | awk '{sum=0; for(i=2;i<=NF;i++) sum+=$i; print sum}')
    idle1=$(echo "$cpu1" | awk '{print $5+$6}')

    total2=$(echo "$cpu2" | awk '{sum=0; for(i=2;i<=NF;i++) sum+=$i; print sum}')
    idle2=$(echo "$cpu2" | awk '{print $5+$6}')

    total_delta=$((total2 - total1))
    idle_delta=$((idle2 - idle1))

    cpu_usage=$(( (total_delta - idle_delta) * 100 / total_delta ))

    echo "$cpu_usage"
}



show_status(){
    echo "============================================"
    echo "LINUX SERVER STATUS"
    echo "============================================"

    echo
    echo "Hostname : $(hostname)"
    echo "Uptime   : $(uptime -p)"
    load_avg=$(awk '{print $1}' /proc/loadavg)
    cpu_usage=$(get_cpu_usage)

    echo "Load Avg : $load_avg"
    echo "CPU      : $cpu_usage%"
    mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    mem_avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
    mem_used=$((mem_total - mem_avail))
    mem_per=$((mem_used * 100 / mem_total))

    disk_usage=$(df -h / | awk 'NR==2 {print $5}')

    echo "Memory   : $mem_per%"
    echo "Disk     : $disk_usage"

    process_count=$(ps -e --no-headers | wc -l)

    top_process=$(ps -eo pid,comm,%cpu --sort=-%cpu | head -n 2 | tail -n 1)
    top_process_name=$(echo "$top_process" | awk '{print $2}')
    top_process_cpu=$(echo "$top_process" | awk '{print $3}')

    echo "Processes: $process_count"
    echo "Top Process: $top_process_name ($top_process_cpu%)"



    echo
    echo "Services"
    echo "--------------------------------------------"

    for i in "${SERVICES[@]}"; do
        if ! systemctl cat "$i" >/dev/null 2>&1; then
            echo "$i : NOT FOUND"
            continue
        fi

        status=$(systemctl is-active "$i")

        if [ "$status" = "active" ]; then
            echo "$i : active"
        else
            echo "$i : $status"
        fi
    done

    echo "============================================"
}


if [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

if [ "$1" = "--errors" ]; then
	show_errors "$2"
	exit $?
fi

if [ "$1" = "--status" ]; then
    show_status
    exit 0
fi



echo -e "============================================ \nLINUX SERVER MONITOR \n============================================  "
echo -e "\n \n"

log_event(){
    level="$1"
    shift

    mkdir -p "$SCRIPT_DIR/logs"
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "$timestamp | $level | $*" >> "$SCRIPT_DIR/logs/monitor.log"
}


send_alert(){
    level="$1"
    shift
    message="$*"

    mkdir -p "$(dirname "$ALERT_LOG")"
    mkdir -p "$(dirname "$ALERT_STATE")"

    now=$(date +%s)
    alert_key=$(printf '%s' "$level|$message" | sha256sum | awk '{print $1}')

    last_sent=$(awk -F '|' -v key="$alert_key" '$1 == key {print $2}' "$ALERT_STATE" 2>/dev/null)

    if [ -n "$last_sent" ] && [ "$((now - last_sent))" -lt "$ALERT_COOLDOWN" ]; then
        return 0
    fi

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if ! echo "$timestamp | $level | $message" >> "$ALERT_LOG"; then
        echo "ERROR: Failed to write alert to $ALERT_LOG" >&2
        return 1
    fi

    grep -v "^$alert_key|" "$ALERT_STATE" 2>/dev/null > "$ALERT_STATE.tmp" || true
    echo "$alert_key|$now" >> "$ALERT_STATE.tmp"
    mv "$ALERT_STATE.tmp" "$ALERT_STATE"
    send_webhook "$level" "$message"
}

send_webhook(){
    local level="$1"
    local message="$2"

    if [ "$WEBHOOK_ENABLED" != "true" ] || [ -z "$WEBHOOK_URL" ]; then
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "WARNING: curl is unavailable; webhook not sent" >&2
        return 0
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "WARNING: jq is unavailable; webhook not sent" >&2
        return 0
    fi

    if ! curl --silent --fail \
        --connect-timeout 5 --max-time 10 \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg level "$level" --arg message "$message" \
        '{level: $level, message: $message}')" \
        "$WEBHOOK_URL" >/dev/null; then
        echo "WARNING: Webhook delivery failed" >&2
    fi

    return 0
}

get_failure_count(){
    service="$1"

    if grep -q "^$service|" "$SCRIPT_DIR/state/recovery.state"; then
        grep "^$service|" "$SCRIPT_DIR/state/recovery.state" | cut -d'|' -f2
    else
        echo "0"
    fi
}

set_failure_count(){
	service="$1"
	count="$2"

	if grep -q "^$service|" "$SCRIPT_DIR/state/recovery.state"; then
		sed -i "s/^$service|.*/$service|$count/" "$SCRIPT_DIR/state/recovery.state"
	else
		echo "$service|$count" >> "$SCRIPT_DIR/state/recovery.state"
	fi

}

restart_attempt(){
    service="$1"
    fail_count=$(get_failure_count "$service")

    if [ "$fail_count" -ge "$MAX_CONSECUTIVE_FAILURES" ]; then
        echo "Recovery limit exceeded for service : $service"
        log_event CRITICAL "SERVICE $service recovery_limit_reached failures=$fail_count"
        send_alert CRITICAL "SERVICE $service recovery_limit_reached failures=$fail_count"
	return 1
    fi

    attempt=1

    while [ "$attempt" -le "$MAX_RESTART_ATTEMPTS" ]; do

        echo "Recovery attempt $attempt/$MAX_RESTART_ATTEMPTS for $service"

        sudo systemctl restart "$service"
        result=$?

        if [ "$result" -eq 0 ]; then
            new_status=$(systemctl is-active "$service")

            if [ "$new_status" = "active" ]; then
                echo "Recovery successful"
                log_event INFO "SERVICE $service recovered"
                set_failure_count "$service" 0
                return 0
            fi
        fi

        echo "Recovery attempt $attempt failed"
        log_event WARNING "SERVICE $service recovery_attempt_failed attempt=$attempt code=$result"

        attempt=$((attempt + 1))

        if [ "$attempt" -le "$MAX_RESTART_ATTEMPTS" ]; then
            sleep "$RECOVERY_DELAY"
        fi

    done

    fail_count=$((fail_count + 1))
    set_failure_count "$service" "$fail_count"

    echo "Recovery failed after $MAX_RESTART_ATTEMPTS attempts"
    log_event CRITICAL "SERVICE $service recovery_failed attempts=$MAX_RESTART_ATTEMPTS consecutive_failures=$fail_count"
    send_alert CRITICAL "SERVICE $service recovery_failed attempts=$MAX_RESTART_ATTEMPTS consecutive_failures=$fail_count"
    return 1
}

load_1min=$(awk '{print $1}' /proc/loadavg)
mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
mem_avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
mem_used=$((mem_total-mem_avail))
mem_per=$((mem_used *100/mem_total))

if [ "$mem_per" -ge "$RAM_THRESHOLD" ]; then
	echo "Warning ! : Memory usage high"
	#log_event RESOURCE "Memory HIGH" "$mem_per
	log_event WARNING "RESOURCE memory high usage=${mem_per}%"
fi

disk_usage=$(df -h / | awk 'NR==2 {print $5}')

disk_percent=$(echo "$disk_usage" | tr -d '%')

if [ "$disk_percent" -ge "$DISK_THRESHOLD" ]; then
    echo "WARNING: Disk usage is high"
    #log_event RESOURCE "disk" "high" "$disk_percent%"
    log_event WARNING "RESOURCE disk high usage=${disk_percent}%"
fi

cpu_usage=$(get_cpu_usage)

if [ "$cpu_usage" -ge "$CPU_THRESHOLD" ]; then
    echo "Warning ! : CPU usage high"
    #log_event RESOURCE "CPU" "HIGH" "$cpu_usage%"
    log_event WARNING "RESOURCE CPU high usage=${cpu_usage}%"
fi


echo -e "Hostname        : $(hostname) \nUser        : $(whoami) \nDate        : $(date) \nSystem        :$(uname)\nLoad Avg        :$load_1min\nCpu usage       :$(get_cpu_usage) %\nMemory Usage        :$mem_per%\nDisk Usage        :$disk_usage"
echo -e "Uptime       :$(uptime -p)"
process_count=$(ps -e --no-header | wc -l)
echo -e "Running Processes       :$process_count"
processes=$(ps -eo pid,comm,%cpu --sort=-%cpu)
top_process=$(echo "$processes" |awk 'NR==2')
top_process_pid=$(echo "$top_process" | awk '{print $1}')
top_process_name=$(echo "$top_process" | awk '{print $2}')
top_process_cpu_usage=$(echo "$top_process" | awk '{print $3}')
echo -e "\nTop Process Pid       :$top_process_pid\nTop Process Name       :$top_process_name\nTop Process Cpu Usage       :$top_process_cpu_usage"
echo -e "\n\n"
echo -e "\n Service monitoring"
# The below is system monitoring related loop

#The service array or list is loaded from config file which is sourced at top of script

for i in "${SERVICES[@]}"; do

	if ! systemctl cat "$i" >/dev/null 2>&1; then
		echo "$i : Service does not exist"
		log_event WARNING "SERVICE $i not_found"
		continue
	fi

        status=$(systemctl is-active $i)
	if [ "$status" = "active" ]; then
		echo "$i : healthy"
	else
		echo "$i : Issue(check logs)"
		echo "Status: $(systemctl is-active $i)"
		# log_event SERVICE "$i" problem "$status"
		log_event WARNING "SERVICE $i problem $status"

		if [ "$AUTO_RECOVER" = true ]; then
			echo "Attempting recovery"
			if restart_attempt "$i"; then
				echo "$i : Recovery successful"

			else
				echo "$i : Recovery failed"
			fi
		else
			echo "Automatic recovery disabled"
			#log_event SERVICE "$i" recovery_disabled
			log_event INFO "SERVICE $i recovery_disabled"
		fi
	fi
done


echo -e "\n============================================ "



























