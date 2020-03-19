#!/bin/bash
DATE=date +%Y.%m-%d-%H - %M - %S
METHOD=$1
BRANCH=$2
GROUP_LIST=$3

fuction ip_list(){
  if [[ ${GROUP_LIST} == "GROUP1" ]];then
      Server_IP="192.168.134.190"
	  echo ${Server_IP}
	  ssh  root@192.168.134.182 ""echo disable server linux-web-80-master/192.168.134.190" |socat stdio /run/haproxy/admin.sock"
	  ssh  root@192.168.134.183 ""echo disable server linux-web-80-master/192.168.134.190" |socat stdio /run/haproxy/admin.sock"
  elif [[ ${GROUP_LIST} == "GROUP2" ]];then
      Server_IP="192.168.134.190 192.168.134.191"
	  echo ${Server_IP}
      ssh  root@192.168.134.182 ""echo enable server linux-web-80-master/192.168.134.190" |socat stdio /run/haproxy/admin.sock"
	  ssh  root@192.168.134.183 ""echo enable server linux-web-80-master/192.168.134.190" |socat stdio /run/haproxy/admin.sock"
  elif [[ ${GROUP_LIST} == "GROUP3" ]];then
      Server_IP="192.168.134.190 192.168.134.191 192.168.134.192"
	  echo ${Server_IP}
  fi
}
fuction clone_code(){
   cd /data/git/lunx39/ && rm -rf web1
   git clone -b ${BRANCH} git@192.168.134.183/linux39/web1.git
   echo "代码clone完成"
}
fuction scanner_code(){
  cd /data/git/lunx39/web1 && /usr/local/sonar-scanner/bin/sonar-scanner
  echo "代码扫描完成"
}

fuction code_maven(){               #编译
  echo "mvn clean package -Dmaven.test.skip=true"
  echo "代码编译完成"
}

fuction make_zip(){                 #压缩
  cd /data/git/lunx39/web1 && zip -r code.zip ./
  echo "代码打包成功"  
}

function down_node(){
   for node in ${Server_IP};do
     ssh root@192.168.134.183 "echo "disable server linux-web-80-master/${node}" | socat stdio /run/haproxy/admin.sock"
     echo "${node} 从负载均衡192.168.134.183下线成功"
	 ssh root@192.168.134.182 "echo "disable server linux-web-80-master/${node}" | socat stdio /run/haproxy/admin.sock"
     echo "${node} 从负载均衡192.168.134.182下线成功"
   done
} 
function stop_tomcat() {
  for node in ${Server_IP}; do
  ssh www@${node} "/etc/init.d/tomcat stop "
  done
}

function  scp_zipfile() {
  for node in $(Server_IP);do
    scp /data/git/lunx39/web1/code.zip www@${node}:/data/tomcat/webapps/code-${DATE}.zip 
	ssh www@${node} "unzip /data/tomcat/webapps/code-$${DATE}.zip -d /data/tomcat/webapps/code-${DATE} && rm -rf /data/tomcat/webapps/myapp && ln -sv /data/tomcat/webapps/code-${DATE} /data/tomcat/webapps/myapp"
  done	
}
function start_tomcat() {
  for node in ${Server_IP}; do
  ssh www@${node} "/etc/init.d/tomcat start "
  done
}
function web_test() {
  for node in ${Server_IP};do
    sleep 5
	NUM=`curl -s -I -m 10 -o /dev/null -w %{http_code} http://${node}:8080/myapp/web1/index.html`
	if [[ ${NUM} -eq 200]];then
	   echo "${node} 测试通过，即将添加到负载"
	   add_node ${node}
	else
	   echo "${node} 测试失败，请检测该服务器是否成功启动tomcat"
	fi
  done
} 
function add_node() {
 node=$1
   echo ${node},"---->"
   if [[ ${GROUP_LIST} == "GROUP2" ]];then
   ssh  root@192.168.134.182 ""echo enable server linux-web-80-master/192.168.134.190" |socat stdio /run/haproxy/admin.sock"
   ssh  root@192.168.134.183 ""echo enable server linux-web-80-master/192.168.134.190" |socat stdio /run/haproxy/admin.sock"
   fi
   if [[ ${node} == "192.168.134.190" ]];then
      echo "192.168.134.190 部署完毕，请测试代码"
   else
     ssh  root@192.168.134.182 ""echo enable server linux-web-80-master/${node}" |socat stdio /run/haproxy/admin.sock"
     ssh  root@192.168.134.183 ""echo enable server linux-web-80-master/${node}" |socat stdio /run/haproxy/admin.sock" 
   fi
}

function rollback_last_version(){
  for node in ${Server_IP};do
    NOW_VERSION=` ssh www@${node} ""/bin/ls -l -rt  /data/tomcat/webapps/myapp/ | awk -F "->" '{print $2}' | tail -n1""`
    NOW_VERSION=` basename ${NOW_VERSION}`
    echo $NOW_VERSION, "NOW_VERSION"
    NAME=`ssh www@${node}  ""ls -l -rt /data/tomcat/webapps/myapp/ | grep -B 1 ${NOW_VERSION} |head -n1 |awk '{print $9}' ""`
    ssh www@${node} " rm -rf /data/tomcat/webapps/myapp/ && ln -vs  /data/tomcat/tomcat_app/${NAME} /data/tomcat/webapps/myapp/"
  done
}

function delete_history_version() {
  for node in ${Server_IP};do
    NUM= ssh www@${node} ""/bin/ls -l -d -rt /data/tomcat/tomcat_app/code-* | wc -l ""
	echo $NUM
	  if [ ${NUM} -gt 10 ];then
	     NAME= ssh www@${node} ""/bin/ls -l -d -rt /data/tomcat/tomcat_app/code-* | head -n1 | awk  '{print $9}'""
	     ssh www@${node} "rm -rf ${NAME}"
	     echo "${node} 删除历史版本${NAME}成功！"
	  fi
  done
}
main(){
   case $1 in
   deploy)
      IP_list;
	  clone_code;
	  scanner_code;
	  make_zip;
	  down_node;
	  stop_tomcat;
	  scp_zipfile;
	  start_tomcat;
	  web_test;
	  ;;
   rollback_last_version)
      IP_list;
	  down_node;
	  stop_tomcat;
	  rollback_last_version;
	  start_tomcat;
	  web_test;
	  ;;
   esac	
}

main $1 $2 $3
