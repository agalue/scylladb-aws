#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

# AWS Template Variables

node_id="${node_id}"
cluster_name="${cluster_name}"
seed_name="${seed_name}"
compaction_throughput="${compaction_throughput}"

mount_point=/var/lib/cassandra
device_name=nvme0n1
device=/dev/$device_name
conf_file=/etc/cassandra/conf/cassandra.yaml
env_file=/etc/cassandra/conf/cassandra-env.sh
jvm_file=/etc/cassandra/conf/jvm.options
ip_address=$(curl http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null)

echo "### IO Tuning..."

echo 1 > /sys/block/$device_name/queue/nomerges
echo 8 > /sys/block/$device_name/queue/read_ahead_kb
# The following might not work on i3 instances.
echo deadline > /sys/block/$device_name/queue/scheduler

echo "### Installing common packages..."

yum -y -q update
amazon-linux-extras install epel -y
yum -y -q install jq net-snmp net-snmp-utils git pytz dstat htop nmap-ncat tree redis telnet curl nmon

echo "### Configuring Hostname and Domain..."

hostnamectl set-hostname --static cassandra$node_id
echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99_hostname.cfg

echo "### Waiting on device $device..."
while [ ! -e $device ]; do
  printf '.'
  sleep 10
done

echo "### Configuring Kernel..."

sed -i 's/^\(.*swap\)/#\1/' /etc/fstab

sysctl_app=/etc/sysctl.d/application.conf
cat <<EOF > $sysctl_app
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_probes=3
net.ipv4.tcp_keepalive_intvl=10

net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=16777216
net.core.wmem_default=16777216
net.core.optmem_max=40960
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216

net.ipv4.tcp_window_scaling=1
net.core.netdev_max_backlog=2500
net.core.somaxconn=65000

vm.swappiness=1
vm.zone_reclaim_mode=0
vm.max_map_count=1048575
EOF
sysctl -p $sysctl_app

echo "### Disable THP..."

cat <<EOF > /etc/systemd/system/disable-thp.service
[Unit]
Description=Disable Transparent Huge Pages (THP)

[Service]
Type=simple
ExecStart=/bin/sh -c "echo 'never' > /sys/kernel/mm/transparent_hugepage/enabled && echo 'never' > /sys/kernel/mm/transparent_hugepage/defrag"

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable disable-thp
systemctl start disable-thp

echo "### Configuring Net-SNMP..."

snmp_cfg=/etc/snmp/snmpd.conf
cp $snmp_cfg $snmp_cfg.original
cat <<EOF > $snmp_cfg
rocommunity public default
syslocation AWS
syscontact Account Manager
dontLogTCPWrappersConnects yes
disk /
EOF
systemctl enable snmpd
systemctl start snmpd

echo "### Downloading and installing latest OpenJDK 8..."

yum install -y -q java-1.8.0-openjdk-devel java-1.8.0-openjdk-headles

echo "### Downloading and installing Cassandra..."

cat <<EOF > /etc/yum.repos.d/cassandra.repo
[cassandra]
name=Apache Cassandra
baseurl=https://www.apache.org/dist/cassandra/redhat/311x/
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://www.apache.org/dist/cassandra/KEYS
EOF
yum install -y -q cassandra cassandra-tools

echo "### Creating partition on $device..."

(
echo o
echo n
echo p
echo 1
echo
echo
echo w
) | fdisk $device
mkfs.xfs -f $device

echo "### Mounting partition..."

mv $mount_point $mount_point.bak
mkdir -p $mount_point
mount -t xfs $device $mount_point
echo "$device $mount_point xfs defaults,noatime 0 0" >> /etc/fstab
mv $mount_point.bak/* $mount_point/
rmdir $mount_point.bak

echo "### Configure Main Cassandra Settings..."

sed -r -i "/cluster_name/s/Test Cluster/$cluster_name/" $conf_file
sed -r -i "/seeds/s/127.0.0.1/$seed_name/" $conf_file
sed -r -i "/listen_address/s/localhost/$ip_address/" $conf_file
sed -r -i "/rpc_address/s/localhost/$ip_address/" $conf_file
sed -r -i "/compaction_throughput_mb_per_sec/s/16/$compaction_throughput" $conf_file

echo "### Apply Cassandra Tuning..."

num_of_cores=`cat /proc/cpuinfo | grep "^processor" | wc -l`
sed -r -i "s|^[# ]*?concurrent_compactors: .*|concurrent_compactors: $num_of_cores|" $conf_file
sed -r -i "s|^[# ]*?commitlog_total_space_in_mb: .*|commitlog_total_space_in_mb: 2048|" $conf_file

echo "### Enable external JMX Access..."

sed -r -i "/rmi.server.hostname/s/^\#//" $env_file
sed -r -i "/rmi.server.hostname/s/.public name./$ip_address/" $env_file
sed -r -i "/jmxremote.access/s/#//" $env_file
sed -r -i "/LOCAL_JMX=/s/yes/no/" $env_file

echo "### Configure Heap Size..."

total_mem_in_mb=`free -m | awk '/:/ {print $2;exit}'`
mem_in_mb=`expr $total_mem_in_mb / 2`
if [ "$mem_in_mb" -gt "30720" ]; then
  mem_in_mb="30720"
fi
sed -r -i "s/#-Xms4G/-Xms$${mem_in_mb}m/" $jvm_file
sed -r -i "s/#-Xmx4G/-Xmx$${mem_in_mb}m/" $jvm_file

echo "### Disable CMSGC..."

ToDisable=(UseParNewGC UseConcMarkSweepGC CMSParallelRemarkEnabled SurvivorRatio MaxTenuringThreshold CMSInitiatingOccupancyFraction UseCMSInitiatingOccupancyOnly CMSWaitDuration CMSParallelInitialMarkEnabled CMSEdenChunksRecordAlways CMSClassUnloadingEnabled)
for entry in "${ToDisable[@]}"; do
  sed -r -i "/$entry/s/-XX/#-XX/" $jvm_file
done

echo "### Enable G1GC..."

ToEnable=(UseG1GC G1RSetUpdatingPauseTimePercent MaxGCPauseMillis InitiatingHeapOccupancyPercent ParallelGCThreads)
for entry in "${ToEnable[@]}"; do
  sed -r -i "/$entry/s/#-XX/-XX/" $jvm_file
done

echo "### Configuring JMX access..."

jmx_passwd=/etc/cassandra/jmxremote.password
jmx_access=/etc/cassandra/jmxremote.access

cat <<EOF > $jmx_passwd
monitorRole QED
controlRole R&D
cassandra cassandra
EOF
chmod 0400 $jmx_passwd
chown cassandra:cassandra $jmx_passwd

cat <<EOF > $jmx_access
monitorRole   readonly
cassandra     readwrite
controlRole   readwrite \
              create javax.management.monitor.*,javax.management.timer.* \
              unregister
EOF
chmod 0400 $jmx_access
chown cassandra:cassandra $jmx_access

echo "### Awaiting for Seed..."

start_delay=$((60*($node_id-1)))
if [[ $start_delay != 0 ]]; then
  until echo -n > /dev/tcp/$seed_name/9042; do
    echo "### $seed_name is unavailable - sleeping"
    sleep 5
  done
  echo "### Waiting $start_delay seconds prior starting Cassandra..."
  sleep $start_delay
fi

echo "### Enabling and starting Cassandra..."

systemctl enable cassandra
systemctl start cassandra