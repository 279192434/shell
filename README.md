<br />更新centos7阿里源
<br />yum install -y wget
<br />wget https://raw.githubusercontent.com/279192434/linux/main/yum-centos7.sh && chmod 777 yum-centos7.sh && bash yum-centos7.sh
<br />重新安装系统脚本
<br />yum install -y xz openssl gawk file glibc-common wget screen && screen -S os
<br />wget --no-check-certificate -O AutoReinstall.sh https://raw.githubusercontent.com/279192434/shell/main/AutoReinstall.sh && chmod a+x AutoReinstall.sh && bash AutoReinstall.sh
