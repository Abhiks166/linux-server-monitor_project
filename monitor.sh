
#!/bin/bash
echo -e "============================================ \nLINUX SERVER MONITOR \n============================================  "
echo -e "\n\n"
load_1min=$(awk '{print $1}' /proc/loadavg)
mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
mem_avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
mem_used=$((mem_total-mem_avail))
mem_per=$((mem_used *100/mem_total))
disk_usage=$(df -h / | awk 'NR==2 {print $5}')
echo -e "Hostname        : $(hostname) \nUser        : $(whoami) \nDate        : $(date) \nSystem        :$(uname)\nLoad Avg        :$load_1min\nMemory percentage        :$mem_per\nDisk Usage        :$disk_usage"
echo -e "\n============================================ "

