
#!/bin/bash
echo -e "============================================ \nLINUX SERVER MONITOR \n============================================  "
echo -e "\n\n"
echo -e "Hostname        : $(hostname) \nUser            : $(whoami) \nDate            : $(date) \nSystem          : $(uname)"
load_avg_1Min=$(cat /proc/loadavg | awk '{print $1}')
echo -e "\n Load avg       : $load_avg_1Min"
echo -e "\n============================================ "

