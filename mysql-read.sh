#!/bin/bash
#Date：2021-04-26

#获取当前日期：年月日
TIME=`date +%Y%m%d`

# echo "阻止非法呼叫的的IP"
# #限制输入的值必须是20210101-21000101之间的数字
# until [[ "$TIME" =~ ^[0-9]+$ ]] && [ "$TIME" -ge 20210101 ] && [ "$TIME" -le 21000101 ]; do
# #设置默认值是20210425
# read -rp "输入日期[20210101-21000101]: " -e -i 20210427 TIME
# done
# #TIME=20210425
# echo "你输入的日期:$TIME"

#连接MySQL数据库
# #远程连接使用
# Host=localhost
# User=vos
# PW=123456
 
# #本地连接
# mysql -u$User -p$PW <<EOF                  #开始SQL语句
    # use DATABASE_NAME;                     #选择数据库（选择模式）
    # SELECT * FROM TABLE_NAME;              #执行SQL语句
    # COMMIT;                                #对于更新表格的操作执行commit语句
# EOF #结束SQL语句

#把查询到的内容输入到mysql.txt文本
#远程连接
#mysql -h$Host -u$User -p$PW -N <<EOF>>mysql.txt
#本地连接，不加-N默认是取表头的，这里只查询数据里面的ip地址。
mysql -N <<EOF>mysql.txt
    use vos3000;
    select distinct callerip from vos3000.e_cdr_$TIME where endreason = -9;
    COMMIT;
EOF
# 去重查询vos3000数据库下e_cdr_20210424表中的callerip列并且还要endreason列中的数据等于-9的数据
# select distinct callerip from vos3000.e_cdr_20210424 where endreason = -9;

for ip in $(cat mysql.txt)
do
{
#在防火墙添加阻止ip的规则
/sbin/iptables -I INPUT -s $ip -j DROP
}&
done
wait
#保存防火墙设置
service iptables save
#重启防火墙使之生效
service iptables restart
echo "防火墙添加非法ip完成"

#删除重复的防火墙规则
cat /etc/sysconfig/iptables | sed  -n "G; s/\n/&&/;/^\(.*\n\).*\n\1/d; s/\n//;h;P" > /tmp/iptables
iptables-restore < /tmp/iptables
rm -f /tmp/iptables
/etc/init.d/iptables save
iptables-save > /etc/sysconfig/iptables

#保存防火墙设置
service iptables save
#重启防火墙使之生效
service iptables restart
echo "防火墙规则去重完成"


#查看防火墙规则
#cat /etc/sysconfig/iptables
iptables -L INPUT -n --line-numbers
