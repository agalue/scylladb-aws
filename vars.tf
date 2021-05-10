# @author: Alejandro Galue <agalue@opennms.org>

variable "aws_region" {
  description = "EC2 Region for the VPC (change it accordingly)"
  default     = "us-east-2"
}

variable "aws_key_name" {
  description = "AWS Key Name, to access EC2 instances through SSH (change it accordingly)"
  default     = "agalue"
}

variable "vpc_cidr" {
  description = "CIDR for the whole VPC"
  default     = "172.17.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet"
  default     = "172.17.1.0/24"
}

variable "scylladb_ip_addresses" {
  description = "ScyllaDB/Cassandra IP Addresses. This also determines the size of the cluster."
  type        = list(string)

  default = [
    "172.17.1.21",
    "172.17.1.22",
    "172.17.1.23",
#    "172.17.1.24",
#    "172.17.1.25",
#    "172.17.1.26",
#    "172.17.1.27",
#    "172.17.1.28",
  ]
}

variable "opennms_ip_addresses" {
  description = "OpenNMS IP Addresses."
  type        = list(string)

  default = [
    "172.17.1.100",
#    "172.17.1.101",
  ]
}

// Careful with the AWS limits when choosing larger i3 instances
// i3.2xlarge :  8 Cores,  64 GB of RAM
// i3.4xlarge : 16 Cores, 122 GB of RAM
// i3.8xlarge : 32 Cores, 244 GB of RAM
variable "settings" {
  description = "Common settings"
  type        = map(string)

  default = {
    use_scylladb                      = true         # Set this to true to use Scylla instead of Cassandra
    scylladb_instance_type            = "i3.2xlarge"
    scylladb_ec2_user                 = "centos"
    scylladb_cluster_name             = "OpenNMS"
    scylladb_replication_factor       = 2            # It should be consistent with the cluster size. Check scylladb_ip_addresses
    cassandra_instance_type           = "i3.2xlarge" # 8 Cores, 64 GB of RAM
    compaction_throughput             = 900
    opennms_instance_type             = "c5.9xlarge" # 36 Cores, 72GB of RAM
    newts_use_redis                   = false
    newts_write_threads               = 36           # A multiple of the number of cores of the OpenNMS server
    newts_cache_max_entries           = 2000000      # Not used when Redis is enabled
    newts_ring_buffer_size            = 4194304      # Has to be a power of 2 (not enough when Redis is enabled)
    newts_core_connections_per_host   = 24           # Has to be 2 or 3 times the number of cores on a given ScyllaDB node
    newts_max_connections_per_host    = 24           # Has to be 2 or 3 times the number of cores on a given ScyllaDB node
    newts_max_requests_per_connection = 8192
  }
}
