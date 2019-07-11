# @author: Alejandro Galue <agalue@opennms.org>

variable "aws_region" {
  description = "EC2 Region for the VPC. For testing purposes only, please use your own."
  default     = "us-west-2"
}

variable "aws_key_name" {
  description = "AWS Key Name, to access EC2 instances through SSH. For testing purposes only, please use your own."
  default     = "agalue"
}

variable "aws_private_key" {
  description = "AWS Private Key Full Path. For testing purposes only, please use your own."
  default     = "/Users/agalue/.ssh/agalue.private.aws.us-west-2.pem"
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
  description = "ScyllaDB IP Addresses. This also determines the size of the cluster."
  type        = list(string)

  default = [
    "172.17.1.21",
    "172.17.1.22",
    "172.17.1.23",
    "172.17.1.24",
    "172.17.1.25",
    "172.17.1.26",
  ]
}

variable "settings" {
  description = "Common settings"
  type        = map(string)

  default = {
    scylladb_ami_id             = "ami-0adede0719979b158" # ScyllaDB Custom AMI for us-west-2
    scylladb_instance_type      = "i3.xlarge"             #  4 Cores,  32 GB of RAM
#   scylladb_instance_type      = "i3.8xlarge"            # 32 Cores, 244 GB of RAM (careful with the AWS limits)
    scylladb_ec2_user           = "centos"
    scylladb_cluster_name       = "OpenNMS-Cluster"
    scylladb_replication_factor = 2                       # It should be consistent with the cluster size. Check scylladb_ip_addresses
    opennms_ami_id              = "ami-082b5a644766e0e6f" # Amazon Linux 2 for us-west-2
    opennms_instance_type       = "c5.9xlarge"
    opennms_ec2_user            = "ec2-user"
    opennms_ip_address          = "172.17.1.100"
    opennms_cache_max_entries   = 2000000 # for 50000 samples per second
    opennms_ring_buffer_size    = 8388608 # for 50000 samples per second (with 4194304 dropped metrics are expected while filling up the resource cache)
  }
}

