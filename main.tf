# @author: Alejandro Galue <agalue@opennms.org>

provider "aws" {
  region = var.aws_region
}

# The template to use when initializing a ScyllaDB instance based on their documentation
data "template_file" "scylladb" {
  template = file("${path.module}/scylladb.tpl")

  vars = {
    cluster_name = var.settings["scylladb_cluster_name"]
    total_nodes  = length(var.scylladb_ip_addresses)
    seed         = element(var.scylladb_ip_addresses, 0)
  }
}

# Custom provider to fix Scylla JMX access, and install the SNMP agent.
resource "null_resource" "scylladb" {
  count = var.settings.use_scylladb ? length(aws_instance.scylladb.*.ami) : 0
  triggers = {
    cluster_instance_ids = element(aws_instance.scylladb.*.id, count.index)
  }

  connection {
    host        = element(aws_instance.scylladb.*.public_ip, count.index)
    type        = "ssh"
    user        = var.settings["scylladb_ec2_user"]
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
  ami           = var.settings["scylladb_ami_id"]
  instance_type = var.settings["scylladb_instance_type"]
  subnet_id     = aws_subnet.public.id
  key_name      = var.aws_key_name
  private_ip    = element(var.scylladb_ip_addresses, count.index)
  user_data     = data.template_file.scylladb.rendered

  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.common.id,
    aws_security_group.scylladb.id,
  ]

  connection {
    host        = coalesce(self.public_ip, self.private_ip)
    type        = "ssh"
    user        = var.settings["scylladb_ec2_user"]
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
  template = file("${path.module}/cassandra.tpl")

  vars = {
    node_id      = count.index + 1
    cluster_name = var.settings["scylladb_cluster_name"]
    seed_name    = element(var.scylladb_ip_addresses, 0)
  }
}

resource "aws_instance" "cassandra" {
  count         = var.settings.use_scylladb ? 0 : length(var.scylladb_ip_addresses)
  ami           = var.settings["cassandra_ami_id"]
  instance_type = var.settings["cassandra_instance_type"]
  subnet_id     = aws_subnet.public.id
  key_name      = var.aws_key_name
  private_ip    = element(var.scylladb_ip_addresses, count.index)
  user_data     = element(data.template_file.cassandra.*.rendered, count.index)

  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.common.id,
    aws_security_group.scylladb.id,
  ]

  connection {
    host        = coalesce(self.public_ip, self.private_ip)
    type        = "ssh"
    user        = var.settings["cassandra_ec2_user"]
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
  template = file("${path.module}/opennms.tpl")

  vars = {
    use_scylladb          = var.settings.use_scylladb
    scylladb_ip_addresses = join(" ", var.scylladb_ip_addresses)
    scylladb_seed         = element(var.scylladb_ip_addresses, 0)
    scylladb_rf           = var.settings["scylladb_replication_factor"]
    cache_max_entries     = var.settings["opennms_cache_max_entries"]
    ring_buffer_size      = var.settings["opennms_ring_buffer_size"]
    connections_per_host  = var.settings["opennms_connections_per_host"]
    use_redis             = var.settings["opennms_use_redis"]
  }
}

resource "aws_instance" "opennms" {
  ami           = var.settings["opennms_ami_id"]
  instance_type = var.settings["opennms_instance_type"]
  subnet_id     = aws_subnet.public.id
  key_name      = var.aws_key_name
  private_ip    = var.settings["opennms_ip_address"]
  user_data     = data.template_file.opennms.rendered

  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.common.id,
    aws_security_group.opennms.id,
  ]

  connection {
    host        = coalesce(self.public_ip, self.private_ip)
    type        = "ssh"
    user        = var.settings["opennms_ec2_user"]
    private_key = file(var.aws_private_key)
  }

  tags = {
    Name        = "Terraform OpenNMS Server"
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
  value = aws_instance.opennms.public_ip
}
