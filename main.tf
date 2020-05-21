# @author: Alejandro Galue <agalue@opennms.org>

provider "aws" {
  region = var.aws_region
}

# The template to use when initializing a ScyllaDB instance based on their documentation
data "template_file" "scylladb" {
  template = file("scylladb.tpl")

  vars = {
    cluster_name = var.settings.scylladb_cluster_name
    total_nodes  = length(var.scylladb_ip_addresses)
    seed         = var.scylladb_ip_addresses[0]
  }
}

# Custom provider to fix Scylla JMX access, and install the SNMP agent.
resource "null_resource" "scylladb" {
  count = var.settings.use_scylladb ? length(aws_instance.scylladb.*.ami) : 0
  triggers = {
    cluster_instance_ids = element(aws_instance.scylladb.*.id, count.index)
  }

  connection {
    host        = aws_instance.scylladb.*.public_ip[count.index]
    type        = "ssh"
    user        = var.settings.scylladb_ec2_user
    private_key = file(var.aws_private_key)
  }

  provisioner "file" {
    source      = "./scylladb-init.sh"
    destination = "/tmp/scylladb-init.sh"
  }

  provisioner "remote-exec" {
    inline = ["sudo sh /tmp/scylladb-init.sh"]
  }
}

resource "aws_instance" "scylladb" {
  count         = var.settings.use_scylladb ? length(var.scylladb_ip_addresses) : 0
  ami           = var.settings.scylladb_ami_id
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

  connection {
    host        = coalesce(self.public_ip, self.private_ip)
    type        = "ssh"
    user        = var.settings.scylladb_ec2_user
    private_key = file(var.aws_private_key)
  }

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
  ami           = var.settings.cassandra_ami_id
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

  connection {
    host        = coalesce(self.public_ip, self.private_ip)
    type        = "ssh"
    user        = var.settings.cassandra_ec2_user
    private_key = file(var.aws_private_key)
  }

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
  ami           = var.settings.opennms_ami_id
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

  connection {
    host        = coalesce(self.public_ip, self.private_ip)
    type        = "ssh"
    user        = var.settings.opennms_ec2_user
    private_key = file(var.aws_private_key)
  }

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
