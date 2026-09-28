
#!/bin/bash
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





load_1min=$(awk '{print $1}' /proc/loadavg)
mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
mem_avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
mem_used=$((mem_total-mem_avail))
mem_per=$((mem_used *100/mem_total))
disk_usage=$(df -h / | awk 'NR==2 {print $5}')
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

services=("cron" "rsyslog" "systemd-journald")

for i in "${services[@]}"; do
        status=$(systemctl is-active $i)
	if [ "$status" = "active" ]; then
		echo "$i : healthy"
	else
		echo -e "$i : Issue in the service\n Status:$(systemctl status $i)"
	fi
done


echo -e "\n============================================ "



























