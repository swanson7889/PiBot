#!/usr/bin/
line=$(head -n 1 /etc/network/interfaces)
echo before: $line
cp /home/pi/Desktop/PiBotRemoteFiles/interfaces_backup /etc/network/interfaces
line=$(head -n 1 /etc/network/interfaces)
echo after: $line
