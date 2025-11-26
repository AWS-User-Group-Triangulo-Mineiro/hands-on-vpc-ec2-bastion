terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.5.0"
}

provider "aws" {
  region = "us-east-1"
}

# -----------------------
# VPC
# -----------------------
resource "aws_vpc" "main" {
  cidr_block           = "172.16.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "demo-vpc-172-16"
  }
}

# -----------------------
# Internet Gateway
# -----------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "demo-igw"
  }
}

# -----------------------
# Subnets Públicas
# -----------------------
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "172.16.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "172.16.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-b"
  }
}

# -----------------------
# Subnets Privadas
# -----------------------
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "172.16.10.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "172.16.11.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "private-b"
  }
}

# -----------------------
# Route Table Pública
# -----------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table_association" "public_a_assoc" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b_assoc" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# -----------------------
# NAT Gateway (em subnet pública)
# -----------------------
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_a.id

  tags = {
    Name = "nat-gw"
  }

  depends_on = [aws_internet_gateway.igw]
}

# -----------------------
# Route Table Privada
# -----------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private-rt"
  }
}

resource "aws_route_table_association" "private_a_assoc" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b_assoc" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# -----------------------
# Security Groups
# -----------------------

# SG da EC2 pública (bastion / web)
resource "aws_security_group" "public_sg" {
  name        = "public-sg"
  description = "Allow SSH from your IP and HTTP from anywhere"
  vpc_id      = aws_vpc.main.id

  # SSH apenas do seu IP (trocar pelo seu)
  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["SEU.IP.AQUI/32"]
  }

  # HTTP opcional
  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "public-sg"
  }
}

# SG da EC2 privada (backend)
resource "aws_security_group" "private_sg" {
  name        = "private-sg"
  description = "Allow HTTP/SSH only from bastion"
  vpc_id      = aws_vpc.main.id

  # SSH só da EC2 pública (bastion)
  ingress {
    description      = "SSH from bastion"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    security_groups  = [aws_security_group.public_sg.id]
  }

  # HTTP só da EC2 pública (se quiser)
  ingress {
    description      = "HTTP from bastion"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    security_groups  = [aws_security_group.public_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "private-sg"
  }
}

# -----------------------
# EC2 Pública (Bastion / Web)
# -----------------------
# Trocar ami, instance_type e key_name
resource "aws_instance" "bastion" {
  ami                    = "ami-0fc5d935ebf8bc3bc" # EXEMPLO us-east-1 (Amazon Linux 2023) - confira na console
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.public_sg.id]
  key_name               = "demo-key" # precisa existir na conta

  tags = {
    Name = "bastion-public-ec2"
  }
}

# -----------------------
# EC2 Privada (Backend)
# -----------------------
resource "aws_instance" "backend" {
  ami                    = "ami-0fc5d935ebf8bc3bc" # mesmo AMI ou outro
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_a.id
  vpc_security_group_ids = [aws_security_group.private_sg.id]
  key_name               = "demo-key"

  tags = {
    Name = "backend-private-ec2"
  }
}

# -----------------------
# Outputs úteis
# -----------------------
output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "bastion_public_dns" {
  value = aws_instance.bastion.public_dns
}

output "backend_private_ip" {
  value = aws_instance.backend.private_ip
}
