#!/bin/bash
#Date：2021-04-26

echo "查询非法呼叫的的IP"
#限制输入的值必须是20210101-21000101之间的数字
until [[ "$TIME" =~ ^[0-9]+$ ]] && [ "$TIME" -ge 20210101 ] && [ "$TIME" -le 21000101 ]; do
#设置默认值是20210425
read -rp "输入查询时间[20210101-21000101]: " -e -i 20210425 TIME
done
#TIME=20210425
echo "你输入的查询时间:$TIME"

#连接MySQL数据库
#本地连接输入127.0.0.1
Host=127.0.0.1
User=vos
PW=123456
 
# #本地连接
# mysql -u$User -p$PW <<EOF                  #开始SQL语句
    # use DATABASE_NAME;                     #选择数据库（选择模式）
    # SELECT * FROM TABLE_NAME;              #执行SQL语句
    # COMMIT;                                #对于更新表格的操作执行commit语句
# EOF #结束SQL语句

#远程连接
mysql -h$Host -u$User -p$PW <<EOF
    use vos3000;
    select distinct callerip from vos3000.e_cdr_$TIME where endreason = -9;
    COMMIT;
EOF