provider "aws" {
  region = var.region
}

# ── VPC ──────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  tags = { Name = "vpc-tp12" }
}

# ── Internet Gateway ──────────────────────────────────────────────
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "igw-tp12" }
}

# ── Subnets ───────────────────────────────────────────────────────

# Admin subnet
resource "aws_subnet" "admin" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "subnet-admin" }
}

# Public subnets (reverse proxy) — 3 AZ différentes
resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${10 + count.index}.0/24"
  availability_zone       = "us-east-1${["a", "b", "c"][count.index]}"
  map_public_ip_on_launch = true
  tags = { Name = "subnet-public-${count.index + 1}" }
}

# Private subnets (web servers) — 3 AZ différentes
resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${2 + count.index}.0/24"
  availability_zone = "us-east-1${["a", "b", "c"][count.index]}"
  tags = { Name = "subnet-private-${count.index + 1}" }
}

# ── EIP + NAT Gateway (dans subnet admin) ─────────────────────────
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.admin.id
  tags          = { Name = "nat-gw-tp12" }
  depends_on    = [aws_internet_gateway.igw]
}

# ── Route table publique (admin + public subnets) ─────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "rt-public" }
}

resource "aws_route_table_association" "admin" {
  subnet_id      = aws_subnet.admin.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── Route table privée (via NAT) ──────────────────────────────────
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

# ── Security Groups ───────────────────────────────────────────────

resource "aws_security_group" "admin" {
  name   = "admin-sg"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/24"]
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
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/24"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "web-sg" }
}

# ── Instance Admin ────────────────────────────────────────────────
resource "aws_instance" "admin" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.admin.id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.admin.id]
  tags = { Name = "instance-admin" }
}

# ── Instances Reverse Proxy (3) ───────────────────────────────────
resource "aws_instance" "proxy" {
  count                  = 3
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[count.index].id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.proxy.id]
  user_data              = <<-EOF
    #!/bin/bash
    yum update -y
    amazon-linux-extras install nginx1 -y
    systemctl start nginx
    systemctl enable nginx
  EOF
  tags = { Name = "instance-proxy-${count.index + 1}" }
}

# ── Instances Web Server (3) ──────────────────────────────────────
resource "aws_instance" "web" {
  count                  = 3
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[count.index].id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.web.id]
  user_data              = <<-EOF
    #!/bin/bash
    yum update -y
    amazon-linux-extras install nginx1 -y
    systemctl start nginx
    systemctl enable nginx
  EOF
  tags = { Name = "instance-web-${count.index + 1}" }
}

# ── Application Load Balancer ─────────────────────────────────────
resource "aws_lb" "alb" {
  name               = "alb-tp12"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.proxy.id]
  subnets            = aws_subnet.public[*].id
  tags = { Name = "alb-tp12" }
}

resource "aws_lb_target_group" "web" {
  name     = "tg-web"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }
  tags = { Name = "tg-web" }
}

resource "aws_lb_target_group_attachment" "web" {
  count            = 3
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.proxy[count.index].id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
