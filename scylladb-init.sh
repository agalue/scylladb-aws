#!/bin/sh

yum -y -q install net-snmp net-snmp-utils
cat <<EOF > /etc/snmp/snmpd.conf
rocommunity public default
syslocation AWS
syscontact Account Manager
dontLogTCPWrappersConnects yes
disk /
EOF
systemctl enable snmpd
systemctl start snmpd

ip_address=$(curl http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null)
env_default=/etc/sysconfig/scylla-jmx
sed -r -i "/SCYLLA_JMX_ADDR/s/^\#//" $env_default
sed -r -i "/SCYLLA_JMX_ADDR/s/=.*/=$ip_address/" $env_default
sed -r -i "/SCYLLA_JMX_REMOTE/s/^\#//" $env_default
systemctl restart scylla-jmx --no-block