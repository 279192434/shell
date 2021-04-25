#!/bin/bash

#结束check,openvpn进程,运行start脚本
kill -9 $(ps -ef | grep "check" | grep -v "grep" | awk '{print $2}')
kill -9 $(ps -ef | grep "openvpn" | grep -v "grep" | awk '{print $2}')
bash /root/start.sh