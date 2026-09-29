
#!/bin/bash

if [ ! -f config/monitor.conf ]; then
	echo "Error: config/monitor.conf not found"
	exit 1
fi

source config/monitor.conf

echo -e "============================================ \nLINUX SERVER MONITOR \n============================================  "
echo -e "\n\n"

get_cpu_usage(){
	cpu1=$(head -n 1 /proc/stat)
	sleep 1
	
	cpu2=$(head -n 1 /proc/stat)
	total1=$(echo "$cpu1" | awk '
	{sum=0;
       	for(i=2;i<=9;i++) sum+=$i;
	print sum}')

	idle_total1=$(echo "$cpu1" | awk '{print $5+$6}')

	total2=$(echo "$cpu2" | awk '
	{sum =0;
	for(i=2;i<=9;i++) sum+=$i
	print sum}')

	 idle_total2=$(echo "$cpu2" | awk '{print $5+$6}')

	 total_delta=$((total2-total1))
	 idle_delta=$((idle_total2-idle_total1))

	 cpu_usage=$(( (total_delta-idle_delta)*100/total_delta ))

	 echo "$cpu_usage"
}



log_event(){
	mkdir -p logs
	timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    	echo "$timestamp | $*" >> logs/monitor.log
}

restart_attempt(){
	sudo systemctl restart $1
	result=$?
	if [ "$result" -eq 0 ]; then
		echo -e "\nRestarted successfully Code :0"
		echo -e "Status - $1 :$(systemctl is-active $1)\nChecking status again 		       to validate "
		new_status=$(systemctl is-active "$1")
		if [ "$new_status" = "active" ]; then
    			echo "Recovery successful"
			log_event SERVICE "$1" recovered active
		else
    			echo "Recovery failed"
			log_event SERVICE "$1" recovery_failed "$result"
		fi
	else
		echo -e "Recovery failed\nCode : $result"
		log_event SERVICE "$1" recovery_failed "$result"
	fi

}

load_1min=$(awk '{print $1}' /proc/loadavg)
mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
mem_avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
mem_used=$((mem_total-mem_avail))
mem_per=$((mem_used *100/mem_total))

if [ "$mem_per" -ge "$RAM_THRESHOLD" ]; then
	echo "Warning ! : Memory usage high"
	log_event RESOURCE "Memory HIGH" "$mem_per"
fi

disk_usage=$(df -h / | awk 'NR==2 {print $5}')

disk_percent=$(echo "$disk_usage" | tr -d '%')

if [ "$disk_percent" -ge "$DISK_THRESHOLD" ]; then
    echo "WARNING: Disk usage is high"
    log_event RESOURCE "disk" "high" "$disk_percent%"
fi

cpu_usage=$(get_cpu_usage)

if [ "$cpu_usage" -ge "$CPU_THRESHOLD" ]; then
    echo "Warning ! : CPU usage high"
    log_event RESOURCE "CPU" "HIGH" "$cpu_usage%"
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
		log_event SERVICE "$i" not found
		continue
	fi

        status=$(systemctl is-active $i)
	if [ "$status" = "active" ]; then
		echo "$i : healthy"
	else
		echo "$i : Issue(check logs)"
		echo "Status: $(systemctl is-active $i)"
		log_event SERVICE "$i" problem "$status"
	       	echo "Attempting recovery"
		restart_attempt $i	
	fi
done


echo -e "\n============================================ "



























