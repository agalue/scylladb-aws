#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

set -e

# AWS Template Variables

node_id=${node_id}
use_scylladb=${use_scylladb}
scylladb_seed="${scylladb_seed}"
scylladb_rf="${scylladb_rf}"
scylladb_ip_addresses="${scylladb_ip_addresses}"
cache_max_entries="${cache_max_entries}"
write_threads="${write_threads}"
core_connections_per_host="${core_connections_per_host}"
max_connections_per_host="${max_connections_per_host}"
max_requests_per_connection="${max_requests_per_connection}"

ring_buffer_size="${ring_buffer_size}"
use_redis="${use_redis}"

ip_address=$(curl http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null)

echo "### Installing common packages..."

yum -y -q update
amazon-linux-extras install epel -y
yum -y -q install jq net-snmp net-snmp-utils git pytz dstat htop nmap-ncat tree redis telnet curl nmon

echo "### Configuring Hostname and Domain..."

hostnamectl set-hostname --static onms$node_id
echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99_hostname.cfg

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

echo "### Downloading and installing Cassandra (for nodetool and cqlsh)..."

cat <<EOF > /etc/yum.repos.d/cassandra.repo
[cassandra]
name=Apache Cassandra
baseurl=https://www.apache.org/dist/cassandra/redhat/311x/
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://www.apache.org/dist/cassandra/KEYS
EOF
yum install -y -q cassandra

echo "### Installing PostgreSQL 10..."

amazon-linux-extras install postgresql10 -y
yum install -y -q postgresql-server
/usr/bin/postgresql-setup --initdb --unit postgresql
sed -r -i "/^(local|host)/s/(peer|ident)/trust/g" /var/lib/pgsql/data/pg_hba.conf
systemctl enable postgresql
systemctl start postgresql

echo "### Installing Haveged..."

yum -y -q install haveged
systemctl enable haveged
systemctl start haveged

# Redis

if [[ "$use_redis" == "true" ]]; then
  echo "### Configuring Redis..."

  echo "vm.overcommit_memory=1" > /etc/sysctl.d/redis.conf
  sysctl -w vm.overcommit_memory=1
  redis_conf=/etc/redis.conf
  cp $redis_conf $redis_conf.bak
  sed -i -r "s/^bind .*/bind 0.0.0.0/" $redis_conf
  sed -i -r "s/^protected-mode .*/protected-mode no/" $redis_conf
  sed -i -r "s/^save /# save /" $redis_conf
  sed -i -r "s/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/" $redis_conf

  systemctl enable redis
  systemctl start redis
fi

echo "### Downloading and installing latest OpenJDK 11..."

amazon-linux-extras install java-openjdk11 -y
yum -y -q install java-11-openjdk-devel
yum -y -q install maven

echo "### Installing OpenNMS stable repository..."

sed -r -i '/name=Amazon Linux 2/a exclude=rrdtool-*' /etc/yum.repos.d/amzn2-core.repo
yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-stable-rhel7.noarch.rpm
rpm --import /etc/yum.repos.d/opennms-repo-stable-rhel7.gpg

echo "### Installing OpenNMS dependencies from the stable repository..."

yum install -y -q jicmp jicmp6 jrrd jrrd2 rrdtool 'perl(LWP)' 'perl(XML::Twig)'

echo "### Installing OpenNMS and Helm from the stable repository..."

yum install -y -q opennms-core opennms-webapp-jetty
yum install -y -q opennms-webapp-hawtio
yum install -y -q opennms-helm

echo "### Configuring OpenNMS..."

opennms_home=/opt/opennms
opennms_etc=$opennms_home/etc

# JVM Settings
# http://cloudurable.com/blog/cassandra_aws_system_memory_guidelines/index.html
# https://docs.datastax.com/en/dse/5.1/dse-admin/datastax_enterprise/operations/opsTuneJVM.html

jmxport=18980

num_of_cores=`cat /proc/cpuinfo | grep "^processor" | wc -l`
half_of_cores=`expr $num_of_cores / 2`

total_mem_in_mb=`free -m | awk '/:/ {print $2;exit}'`
mem_in_mb=`expr $total_mem_in_mb / 2`
if [ "$mem_in_mb" -gt "30720" ]; then
  mem_in_mb="30720"
fi

# JVM Configuration with an advanced tuning for G1GC based on the chosen EC2 instance type
cat <<EOF > $opennms_etc/opennms.conf
START_TIMEOUT=0
JAVA_HEAP_SIZE=$mem_in_mb
MAXIMUM_FILE_DESCRIPTORS=204800

ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Djava.net.preferIPv4Stack=true"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Xlog:gc:/opt/opennms/logs/gc.log"

ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+UseStringDeduplication"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+UseG1GC"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:G1RSetUpdatingPauseTimePercent=5"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:MaxGCPauseMillis=500"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:InitiatingHeapOccupancyPercent=70"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:ParallelGCThreads=$half_of_cores"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:ConcGCThreads=$half_of_cores"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+ParallelRefProcEnabled"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+AlwaysPreTouch"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+UseTLAB"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+ResizeTLAB"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:-UseBiasedLocking"

# Configure Remote JMX
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.port=$jmxport"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.rmi.port=$jmxport"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.local.only=false"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.ssl=false"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.authenticate=true"

# Listen on all interfaces
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dopennms.poller.server.serverHost=0.0.0.0"

# Accept remote RMI connections on this interface
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Djava.rmi.server.hostname=$ip_address"
EOF

# JMX Groups
cat <<EOF > $opennms_etc/jmxremote.access
admin readwrite
jmx   readonly
EOF

# External ScyllaDB
# For 16 Cores, over 32GB of RAM, and a minimum of 16GB of ONMS Heap size on the OpenNMS server.
# IMPORTANT:
# - The ring_buffer_size, cache.max_entries, and writer_threads depends on the running environment.
#   They should be consistent with the settings to be used with the metrics:stress tool.
newts_cfg=$opennms_etc/opennms.properties.d/newts.properties
cat <<EOF > $newts_cfg
# Basic Settings
org.opennms.timeseries.strategy=newts
org.opennms.newts.config.hostname=$scylladb_seed
org.opennms.newts.config.keyspace=newts
org.opennms.newts.config.port=9042
# Production settings based required for the expected results from the metrics stress tool
org.opennms.newts.config.ring_buffer_size=$ring_buffer_size
org.opennms.newts.config.cache.max_entries=$cache_max_entries
org.opennms.newts.config.cache.priming.enable=true
org.opennms.newts.config.cache.priming.block_ms=-1
# Performance settings
org.opennms.newts.config.writer_threads=$${writer_threads-$num_of_cores}
org.opennms.newts.config.core-connections-per-host=$core_connections_per_host
org.opennms.newts.config.max-connections-per-host=$max_connections_per_host
org.opennms.newts.config.max-requests-per-connection=$max_requests_per_connection
# For collecting data every 30 seconds from OpenNMS and Cassandra
org.opennms.newts.query.minimum_step=30000
org.opennms.newts.query.heartbeat=450000
EOF

if [[ "$use_redis" == "true" ]]; then
  cat <<EOF >> $newts_cfg
org.opennms.newts.config.cache.strategy=org.opennms.netmgt.newts.support.RedisResourceMetadataCache
org.opennms.newts.config.cache.redis_hostname=127.0.0.1
org.opennms.newts.config.cache.redis_port=6379
EOF
fi

# This is the production ready configuration for the Newts keyspace, using NetworkTopologyStrategy and TimeWindowCompactionStrategy
# It is always a good idea to start with NetworkTopologyStrategy, even if a Multi-DC environment won't be used.
newts_cql=$opennms_etc/newts.cql
cat <<EOF > $newts_cql
CREATE KEYSPACE newts WITH replication = {'class' : 'SimpleStrategy', 'replication_factor' : $scylladb_rf };

CREATE TABLE newts.samples (
  context text,
  partition int,
  resource text,
  collected_at timestamp,
  metric_name text,
  value blob,
  attributes map<text, text>,
  PRIMARY KEY((context, partition, resource), collected_at, metric_name)
) WITH compaction = {
  'compaction_window_size': '7',
  'compaction_window_unit': 'DAYS',
  'expired_sstable_check_frequency_seconds': '86400',
  'class': 'TimeWindowCompactionStrategy'
} AND gc_grace_seconds = 604800
  AND read_repair_chance = 0;

CREATE TABLE newts.terms (
  context text,
  field text,
  value text,
  resource text,
  PRIMARY KEY((context, field, value), resource)
);

CREATE TABLE newts.resource_attributes (
  context text,
  resource text,
  attribute text,
  value text,
  PRIMARY KEY((context, resource), attribute)
);

CREATE TABLE newts.resource_metrics (
  context text,
  resource text,
  metric_name text,
  PRIMARY KEY((context, resource), metric_name)
);
EOF

sed -r -i 's/cassandra-username/cassandra/g' $opennms_etc/poller-configuration.xml
sed -r -i 's/cassandra-password/cassandra/g' $opennms_etc/poller-configuration.xml
sed -r -i 's/cassandra-username/cassandra/g' $opennms_etc/collectd-configuration.xml
sed -r -i 's/cassandra-password/cassandra/g' $opennms_etc/collectd-configuration.xml

# To poll and collect statistics from OpenNMS and the ScyllaDB nodes every 30 seconds
# This is not intended for production, it is here to be able to see how the solution behaves while running the metrics:stress tool.
sed -r -i 's/interval="300000"/interval="30000"/g' $opennms_etc/collectd-configuration.xml 
sed -r -i 's/interval="300000" user/interval="30000" user/g' $opennms_etc/poller-configuration.xml 
sed -r -i 's/step="300"/step="30"/g' $opennms_etc/poller-configuration.xml 
files=(`ls -l $opennms_etc/*datacollection-config.xml | awk '{print $9}'`)
for f in "$${files[@]}"; do
  if [ -f $f ]; then
    sed -r -i 's/step="300"/step="30"/g' $f
  fi
done

echo "### Running OpenNMS install script..."

$opennms_home/bin/runjava -S /usr/java/latest/bin/java
$opennms_home/bin/install -dis

echo "### Waiting for Cassandra..."

until nodetool -h $scylladb_seed -u cassandra -pw cassandra status | grep $scylladb_seed | grep -q "UN";
do
  sleep 10
done

echo "### Creating Newts keyspace..."

if [ "$node_id" == "1" ]; then
  cqlsh -f $newts_cql $scylladb_seed
fi

echo "### Creating Requisition..."

mkdir -p $opennms_etc/imports/pending/
requisition=$opennms_etc/imports/pending/AWS.xml
cat <<EOF > $requisition
<model-import xmlns="http://xmlns.opennms.org/xsd/config/model-import" date-stamp="2019-07-01T00:00:00.000Z" foreign-source="AWS">
   <node foreign-id="opennms-server" node-label="opennms-server">
      <interface ip-addr="$ip_address" status="1" snmp-primary="P"/>
      <interface ip-addr="127.0.0.1" status="1" snmp-primary="N">
         <monitored-service service-name="OpenNMS-JVM"/>
      </interface>
   </node>
EOF
if [ "$node_id" == "1" ]; then
  IFS=' ' read -r -a array <<< "$scylladb_ip_addresses"
  for index in "$${!array[@]}"; do
    cat <<EOF >> $requisition
    <node foreign-id="cassandra$index" node-label="cassandra$index">
        <interface ip-addr="$${array[index]}" status="1" snmp-primary="P">
          <monitored-service service-name="JMX-Cassandra"/>
          <monitored-service service-name="JMX-Cassandra-Newts"/>
        </interface>
    </node>
EOF
  done
fi
cat <<EOF >> $requisition
</model-import>
EOF

mkdir -p $opennms_etc/foreign-sources/pending/
cat <<EOF > $opennms_etc/foreign-sources/pending/AWS.xml
<foreign-source xmlns="http://xmlns.opennms.org/xsd/config/foreign-source" name="AWS" date-stamp="2019-07-01T00:00:00.000Z">
   <scan-interval>1d</scan-interval>
   <detectors>
      <detector name="ICMP" class="org.opennms.netmgt.provision.detector.icmp.IcmpDetector"/>
      <detector name="SNMP" class="org.opennms.netmgt.provision.detector.snmp.SnmpDetector"/>
   </detectors>
   <policies/>
</foreign-source>
EOF

echo "### Starting OpenNMS..."

systemctl enable opennms
systemctl start opennms

echo "### Waiting for OpenNMS to be ready..."

until printf "" 2>>/dev/null >>/dev/tcp/$ip_address/8980; do printf '.'; sleep 1; done

echo "### Import Test Requisition..."

$opennms_home/bin/provision.pl requisition import AWS

if [[ "$use_scylladb" == "true" ]]; then
  echo "### Downloading & Starting Scylla Monitoring..."

  yum -y -q install docker
  systemctl enable docker
  systemctl start docker

  yum install -y git python-pip
  pip install --upgrade pip
  pip install pyyaml

  smon_ver=2.4
  wget https://github.com/scylladb/scylla-grafana-monitoring/archive/scylla-monitoring-$smon_ver.tar.gz
  tar -xvf scylla-monitoring-$smon_ver.tar.gz
  cd scylla-monitoring-scylla-monitoring-$smon_ver
  ./genconfig.py -d prometheus -sn $scylladb_ip_addresses
  ./start-all.sh
fi
