terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Data source 
data "aws_availability_zones" "available" {
  state = "available"
}

# Data source : AMI Amazon Linux 2023
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# VPC 
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "vpc-tp-ez" }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "igw-tp-ez" }
}

# Subnet public (Admin + Proxy) 
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = { Name = "subnet-public" }
}

# Subnets privés 
resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 2}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "subnet-private-${count.index + 1}" }
}

# EIP + NAT Gateway 
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags          = { Name = "nat-gw-tp-ez" }
  depends_on    = [aws_internet_gateway.igw]
}

#  Route table publique 
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "rt-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Route table privée (via NAT) 
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "rt-private" }
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Clé SSH Admin (unique) 
resource "tls_private_key" "admin_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "admin" {
  key_name   = "tp-ez-admin-key"
  public_key = tls_private_key.admin_key.public_key_openssh
}

resource "local_file" "admin_key_pem" {
  content         = tls_private_key.admin_key.private_key_pem
  filename        = "${path.module}/admin_key.pem"
  file_permission = "0600"
}

# Clé SSH commune (web + proxy) 
resource "tls_private_key" "common_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "common" {
  key_name   = "tp-ez-common-key"
  public_key = tls_private_key.common_key.public_key_openssh
}

resource "local_file" "common_key_pem" {
  content         = tls_private_key.common_key.private_key_pem
  filename        = "${path.module}/common_key.pem"
  file_permission = "0600"
}

#  Security Groups 

resource "aws_security_group" "admin" {
  name   = "admin-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH depuis Internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "admin-sg" }
}

resource "aws_security_group" "proxy" {
  name   = "proxy-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP depuis Internet"
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.admin.id]
    description     = "SSH depuis Admin"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "proxy-sg" }
}

resource "aws_security_group" "web" {
  name   = "web-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.proxy.id]
    description     = "HTTP depuis Reverse Proxy uniquement"
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.admin.id]
    description     = "SSH depuis Admin uniquement"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "web-sg" }
}

# Instance Admin 
resource "aws_instance" "admin" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  key_name               = aws_key_pair.admin.key_name
  vpc_security_group_ids = [aws_security_group.admin.id]

  # Dépose la clé commune sur l'admin pour accéder aux autres machines
  user_data = <<-EOF
    #!/bin/bash
    mkdir -p /home/ec2-user/.ssh
    echo "${tls_private_key.common_key.private_key_pem}" > /home/ec2-user/.ssh/common_key.pem
    chmod 600 /home/ec2-user/.ssh/common_key.pem
    chown ec2-user:ec2-user /home/ec2-user/.ssh/common_key.pem
  EOF

  tags = { Name = "admin-machine" }
}

# Instances Web Server 
resource "aws_instance" "web" {
  count                  = 3
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[count.index].id
  key_name               = aws_key_pair.common.key_name
  vpc_security_group_ids = [aws_security_group.web.id]

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>Bonjour ! Je suis le serveur Web : $(hostname)</h1><p>IP : $(hostname -I)</p>" > /var/www/html/index.html
  EOF

  tags = { Name = "web-server-${count.index + 1}" }
}

# Instance Reverse Proxy 
resource "aws_instance" "proxy" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  key_name               = aws_key_pair.common.key_name
  vpc_security_group_ids = [aws_security_group.proxy.id]

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y nginx

    cat <<'EOT' > /etc/nginx/conf.d/proxy.conf
    upstream backend {
      server ${aws_instance.web[0].private_ip};
      server ${aws_instance.web[1].private_ip};
      server ${aws_instance.web[2].private_ip};
    }
    server {
      listen 80;
      location / {
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
      }
    }
    EOT

    systemctl start nginx
    systemctl enable nginx
  EOF

  tags       = { Name = "reverse-proxy" }
  depends_on = [aws_instance.web]
}
