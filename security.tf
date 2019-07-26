# @author: Alejandro Galue <agalue@opennms.org>

resource "aws_security_group" "common" {
  name        = "terraform-opennms-common-sq"
  description = "Allow basic protocols"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 161
    to_port     = 161
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = aws_vpc.default.id

  tags = {
    Name        = "Terraform Common SG"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_security_group" "scylladb" {
  name        = "terraform-opennms-scylladb-sg"
  description = "Allow ScyllaDB connections."

  ingress {
    from_port   = 7199
    to_port     = 7599
    protocol    = "tcp"
    description = "JMX"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 7000
    to_port     = 7020
    protocol    = "tcp"
    description = "Intra Node"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 9042
    to_port     = 9442
    protocol    = "tcp"
    description = "CQL Native"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 9160
    to_port     = 9560
    protocol    = "tcp"
    description = "Thrift"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    description = "Prometheus"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 9180
    to_port     = 9180
    protocol    = "tcp"
    description = "Prometheus"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = aws_vpc.default.id

  tags = {
    Name        = "Terraform ScyllaDB SG"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_security_group" "opennms" {
  name        = "terraform-opennms-sg"
  description = "Allow OpenNMS connections."

  ingress {
    from_port   = 8101
    to_port     = 8101
    protocol    = "tcp"
    description = "Karaf Shell"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8980
    to_port     = 8980
    protocol    = "tcp"
    description = "ONMS WebUI"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 18980
    to_port     = 18980
    protocol    = "tcp"
    description = "ONMS JMX"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    description = "Grafana"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = aws_vpc.default.id

  tags = {
    Name        = "Terraform OpenNMS Core SG"
    Environment = "Test"
    Department  = "Support"
  }
}

