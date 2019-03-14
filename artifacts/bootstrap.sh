#!/bin/bash

: ${HADOOP_PREFIX:=/usr/local/hadoop}

. $HADOOP_PREFIX/etc/hadoop/hadoop-env.sh

# Directory to find config artifacts
CONFIG_DIR="/tmp/hadoop-config"

# Copy config files from volume mount

for f in slaves core-site.xml hdfs-site.xml mapred-site.xml yarn-site.xml; do
  if [[ -e ${CONFIG_DIR}/$f ]]; then
    cp ${CONFIG_DIR}/$f $HADOOP_PREFIX/etc/hadoop/$f
  else
    echo "ERROR: Could not find $f in $CONFIG_DIR"
    exit 1
  fi
done

# installing libraries if any - (resource urls added comma separated to the ACP system variable)
cd $HADOOP_PREFIX/share/hadoop/common ; for cp in ${ACP//,/ }; do  echo == $cp; curl -LO $cp ; done; cd -


sed -i '/<\/configuration>/d' $HADOOP_PREFIX/etc/hadoop/mapred-site.xml
cat >> $HADOOP_PREFIX/etc/hadoop/mapred-site.xml <<- EOM
    <property>
    <name>mapreduce.reduce.memory.mb</name>
    <value>3000</value>
    <description>每个Reduce任务的物理内存限制</description>
  </property>
EOM
echo '</configuration>' >> $HADOOP_PREFIX/etc/hadoop/mapred-site.xml



if [[ "${HOSTNAME}" =~ "hdfs-nn" ]]; then
  mkdir -p /root/hdfs/namenode
  $HADOOP_PREFIX/bin/hdfs namenode -format -force -nonInteractive
  sed -i s/hdfs-nn/0.0.0.0/ /usr/local/hadoop/etc/hadoop/core-site.xml
  $HADOOP_PREFIX/sbin/hadoop-daemon.sh start namenode
fi

if [[ "${HOSTNAME}" =~ "hadoop-client" ]]; then
    echo "hadoop-client start put"
    hdfs dfs -ls /input
    if [[ $? != 0 ]]; then
       hdfs dfs -mkdir /input
    fi
    wget data-loader:8102/oneGtext.txt -O /root/tmp/oneGtext.txt
    hdfs dfs -put /root/tmp/oneGtext.txt /input/ &
    echo "hadoop-client put ok"
fi 

if [[ "${HOSTNAME}" =~ "hdfs-dn" ]]; then
  mkdir -p /root/hdfs/datanode
  #  wait up to 30 seconds for namenode
  count=0 && while [[ $count -lt 15 && -z `curl -sf http://hdfs-nn:50070` ]]; do echo "Waiting for hdfs-nn" ; ((count=count+1)) ; sleep 2; done
  [[ $count -eq 15 ]] && echo "Timeout waiting for hdfs-nn, exiting." && exit 1
  $HADOOP_PREFIX/sbin/hadoop-daemon.sh start datanode

fi

#sed -i '/<\/configuration>/d' $HADOOP_PREFIX/etc/hadoop/yarn-site.xml
if [[ "${HOSTNAME}" =~ "yarn-rm" ]]; then
  sed -i s/yarn-rm/0.0.0.0/ $HADOOP_PREFIX/etc/hadoop/yarn-site.xml
  cp ${CONFIG_DIR}/start-yarn-rm.sh $HADOOP_PREFIX/sbin/
  cd $HADOOP_PREFIX/sbin
  chmod +x start-yarn-rm.sh
  ./start-yarn-rm.sh
fi

# yarn.nodemanager.vmem-pmem-ratio
# change "yarn-nm" to "hdfs-dn"
if [[ "${HOSTNAME}" =~ "hdfs-dn" ]]; then
  sed -i '/<\/configuration>/d' $HADOOP_PREFIX/etc/hadoop/yarn-site.xml
  cat >> $HADOOP_PREFIX/etc/hadoop/yarn-site.xml <<- EOM
  <property>
    <name>yarn.nodemanager.resource.memory-mb</name>
    <value>4096</value>
  </property>

  <property>
    <name>yarn.nodemanager.resource.cpu-vcores</name>
    <value>${MY_CPU_LIMIT:-4}</value>
  </property>
  <property>
    <name>yarn.nodemanager.vmem-pmem-ratio</name>
    <value>5</value>
  </property>
EOM
  echo '</configuration>' >> $HADOOP_PREFIX/etc/hadoop/yarn-site.xml
  cp ${CONFIG_DIR}/start-yarn-nm.sh $HADOOP_PREFIX/sbin/
  cd $HADOOP_PREFIX/sbin
  chmod +x start-yarn-nm.sh

  #  wait up to 30 seconds for resourcemanager
  count=0 && while [[ $count -lt 15 && -z `curl -sf http://yarn-rm:8088/ws/v1/cluster/info` ]]; do echo "Waiting for yarn-rm" ; ((count=count+1)) ; sleep 2; done
  [[ $count -eq 15 ]] && echo "Timeout waiting for hdfs-nn, exiting." && exit 1

  ./start-yarn-nm.sh
fi

if [[ $1 == "-d" ]]; then
  until find ${HADOOP_PREFIX}/logs -mmin -1 | egrep -q '.*'; echo "`date`: Waiting for logs..." ; do sleep 2 ; done
  tail -F ${HADOOP_PREFIX}/logs/* &
  while true; do sleep 1000; done
fi

if [[ $1 == "-bash" ]]; then
  /bin/bash
fi
