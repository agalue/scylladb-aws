# @author: Alejandro Galue <agalue@opennms.org>

provider "aws" {
  region = var.aws_region
}

data "aws_ami" "scylla" {
  owners      = ["797456418907"]
  most_recent = true
  name_regex  = "^ScyllaDB 4\\.4\\.*"
}

data "aws_ami" "amazon_linux_2" {
  owners      = ["amazon"]
  most_recent = true
  name_regex  = "^amzn2-ami-hvm.*"
}

# The template to use when initializing a ScyllaDB instance based on their documentation
data "template_file" "scylladb" {
  template = file("scylladb.tpl")

  vars = {
    cluster_name = var.settings.scylladb_cluster_name
    seed         = var.scylladb_ip_addresses[0]
    post_config  = base64encode(file("scylladb-init.sh"))
  }
}

resource "aws_instance" "scylladb" {
  count         = var.settings.use_scylladb ? length(var.scylladb_ip_addresses) : 0
  ami           = data.aws_ami.scylla.id
  instance_type = var.settings.scylladb_instance_type
  subnet_id     = aws_subnet.public.id
  key_name      = var.aws_key_name
  private_ip    = var.scylladb_ip_addresses[count.index]
  user_data     = data.template_file.scylladb.rendered

  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.common.id,
    aws_security_group.scylladb.id,
  ]

  tags = {
    Name        = "Terraform ScyllaDB Server ${count.index + 1}"
    Environment = "Test"
    Department  = "Support"
  }
}

data "template_file" "cassandra" {
  count    = var.settings.use_scylladb ? 0 : length(var.scylladb_ip_addresses)
  template = file("cassandra.tpl")

  vars = {
    node_id               = count.index + 1
    cluster_name          = var.settings.scylladb_cluster_name
    seed_name             = var.scylladb_ip_addresses[0]
    compaction_throughput = var.settings.compaction_throughput
  }
}

resource "aws_instance" "cassandra" {
  count         = var.settings.use_scylladb ? 0 : length(var.scylladb_ip_addresses)
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = var.settings.cassandra_instance_type
  subnet_id     = aws_subnet.public.id
  key_name      = var.aws_key_name
  private_ip    = var.scylladb_ip_addresses[count.index]
  user_data     = data.template_file.cassandra.*.rendered[count.index]

  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.common.id,
    aws_security_group.scylladb.id,
  ]

  tags = {
    Name        = "Terraform Cassandra Server ${count.index + 1}"
    Environment = "Test"
    Department  = "Support"
  }
}

# The template to install and configure OpenNMS
data "template_file" "opennms" {
  count    = length(var.opennms_ip_addresses)
  template = file("opennms.tpl")

  vars = {
    node_id                     = count.index + 1
    use_scylladb                = var.settings.use_scylladb
    scylladb_ip_addresses       = join(" ", var.scylladb_ip_addresses)
    scylladb_seed               = var.scylladb_ip_addresses[0]
    scylladb_rf                 = var.settings.scylladb_replication_factor
    cache_max_entries           = var.settings.newts_cache_max_entries
    ring_buffer_size            = var.settings.newts_ring_buffer_size
    write_threads               = var.settings.newts_write_threads
    core_connections_per_host   = var.settings.newts_core_connections_per_host
    max_connections_per_host    = var.settings.newts_max_connections_per_host
    max_requests_per_connection = var.settings.newts_max_requests_per_connection
    use_redis                   = var.settings.newts_use_redis
  }
}

resource "aws_instance" "opennms" {
  count         = length(var.opennms_ip_addresses)
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = var.settings.opennms_instance_type
  subnet_id     = aws_subnet.public.id
  key_name      = var.aws_key_name
  private_ip    = var.opennms_ip_addresses[count.index]
  user_data     = data.template_file.opennms.*.rendered[count.index]

  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.common.id,
    aws_security_group.opennms.id,
  ]

  tags = {
    Name        = "Terraform OpenNMS Server ${count.index + 1}"
    Environment = "Test"
    Department  = "Support"
  }
}

output "scylladb" {
  value = join(", ", aws_instance.scylladb.*.public_ip)
}

output "cassandra" {
  value = join(", ", aws_instance.cassandra.*.public_ip)
}

output "onmscore" {
  value = join(", ", aws_instance.opennms.*.public_ip)
}
