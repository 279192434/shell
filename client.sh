#!/bin/bash
Client_CaName=client-$1.254
if [ -z $Client_CaName ];then
	echo "输入参数: client-参数.254"
	echo "例 增加106网段: bash client.sh 106"
	exit 0
fi

cp /etc/apt/sources.list /etc/apt/sources.list.bak
cat>/etc/apt/sources.list<<EOF
#阿里云源 
deb http://mirrors.aliyun.com/ubuntu/ disco main restricted universe multiverse 
deb-src http://mirrors.aliyun.com/ubuntu/ disco main restricted universe multiverse 
deb http://mirrors.aliyun.com/ubuntu/ disco-security main restricted universe multiverse 
deb-src http://mirrors.aliyun.com/ubuntu/ disco-security main restricted universe multiverse 
deb http://mirrors.aliyun.com/ubuntu/ disco-updates main restricted universe multiverse 
deb-src http://mirrors.aliyun.com/ubuntu/ disco-updates main restricted universe multiverse 
deb http://mirrors.aliyun.com/ubuntu/ disco-backports main restricted universe multiverse 
deb-src http://mirrors.aliyun.com/ubuntu/ disco-backports main restricted universe multiverse 
deb http://mirrors.aliyun.com/ubuntu/ disco-proposed main restricted universe multiverse 
deb-src http://mirrors.aliyun.com/ubuntu/ disco-proposed main restricted universe multiverse 
#中科大源 
deb https://mirrors.ustc.edu.cn/ubuntu/ disco main restricted universe multiverse 
deb-src https://mirrors.ustc.edu.cn/ubuntu/ disco main restricted universe multiverse 
deb https://mirrors.ustc.edu.cn/ubuntu/ disco-updates main restricted universe multiverse 
deb-src https://mirrors.ustc.edu.cn/ubuntu/ disco-updates main restricted universe multiverse 
deb https://mirrors.ustc.edu.cn/ubuntu/ disco-backports main restricted universe multiverse 
deb-src https://mirrors.ustc.edu.cn/ubuntu/ disco-backports main restricted universe multiverse 
deb https://mirrors.ustc.edu.cn/ubuntu/ disco-security main restricted universe multiverse 
deb-src https://mirrors.ustc.edu.cn/ubuntu/ disco-security main restricted universe multiverse 
deb https://mirrors.ustc.edu.cn/ubuntu/ disco-proposed main restricted universe multiverse 
deb-src https://mirrors.ustc.edu.cn/ubuntu/ disco-proposed main restricted universe multiverse 
#163源 
deb http://mirrors.163.com/ubuntu/ disco main restricted universe multiverse 
deb http://mirrors.163.com/ubuntu/ disco-security main restricted universe multiverse 
deb http://mirrors.163.com/ubuntu/ disco-updates main restricted universe multiverse 
deb http://mirrors.163.com/ubuntu/ disco-proposed main restricted universe multiverse 
deb http://mirrors.163.com/ubuntu/ disco-backports main restricted universe multiverse 
deb-src http://mirrors.163.com/ubuntu/ disco main restricted universe multiverse 
deb-src http://mirrors.163.com/ubuntu/ disco-security main restricted universe multiverse 
deb-src http://mirrors.163.com/ubuntu/ disco-updates main restricted universe multiverse 
deb-src http://mirrors.163.com/ubuntu/ disco-proposed main restricted universe multiverse 
deb-src http://mirrors.163.com/ubuntu/ disco-backports main restricted universe multiverse 
#清华源 
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ disco main restricted universe multiverse 
deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ disco main restricted universe multiverse 
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ disco-updates main restricted universe multiverse 
deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ disco-updates main restricted universe multiverse 
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ disco-backports main restricted universe multiverse 
deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ disco-backports main restricted universe multiverse 
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ disco-security main restricted universe multiverse 
deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ disco-security main restricted universe multiverse 
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ disco-proposed main restricted universe multiverse 
deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ disco-proposed main restricted universe multiverse
EOF

apt update
if [ $? -eq 0 ];then
   apt install openvpn vim net-tools nload openssh-server -y
else
   echo "update error...."
   exit 0
fi

cat>/etc/fier.ini<<EOF
*nat
:PREROUTING ACCEPT [352459:18660587]
:INPUT ACCEPT [3100:490459]
:OUTPUT ACCEPT [1785:107063]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -j MASQUERADE
COMMIT
EOF

cat>/root/start.sh<<EOF
#!/bin/bash
coname=$Client_CaName
openvpn --daemon --cd /root --config \$coname
EOF

cat>/root/check.sh<<EOF
#!/bin/bash
echo "nameserver 8.8.4.4" > /etc/resolv.conf
echo "nameserver 114.114.114.114" >> /etc/resolv.conf
echo "nameserver 9.9.9.9" >> /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf
Bin=/root/start.sh
NetName=\$(ifconfig|grep enp|awk -F ':' '{print \$1}')
IP=\$(hostname -I|awk '{print \$1}'|awk -F \. '{print \$1"."\$2"."\$3"."0}')
route add -net \$IP netmask 255.255.255.0 dev \$NetName
while true;do
ret=\$(ps -ef |grep openvpn|grep -v grep |awk '{print \$2}')
if [ "\$ret" == "" ];then
	bash \$Bin	
else
     	route_sum=\$(route -n|wc -l)
        ping -c 5 10.8.0.1&&ping_sum=888||ping_sum=0
        if [[ \$route_sum -gt 5 && \$ping_sum -eq 0 ]];then
	   ifconfig \$NetName down && ifconfig \$NetName up
	   IP=\$(hostname -I|awk '{print $1}'|awk -F \. '{print \$1"."\$2"."\$3"."0}')
           route add -net  \$IP netmask 255.255.255.0 dev \$NetName
           kill -9 \$ret&&bash \$Bin
        fi

fi  
sleep 10
done
EOF

chmod +x /root/start.sh /root/check.sh
ln -fs /lib/systemd/system/rc-local.service /etc/systemd/system/rc-local.service

cat>/etc/rc.local<<EOF
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.
echo "看到这行字，说明添加自启动脚本成功。" > /usr/local/test.log
iptables-restore < /etc/fier.ini
bash /root/check.sh &
exit 0
EOF

echo 1 > /proc/sys/net/ipv4/ip_forward
chmod +x /etc/rc.local

cat >>/etc/sysctl.conf<<EOF
net.ipv4.ip_forward = 1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
#cat /etc/sysctl.conf|grep 'net.ipv4.ip_forward'
#if [ $? -ne 0 ];then
#cat >>/etc/sysctl.conf<<EOF
#net.ipv4.ip_forward = 1
#net.core.default_qdisc=fq
#net.ipv4.tcp_congestion_control=bbr
#EOF
#fi
sysctl -p