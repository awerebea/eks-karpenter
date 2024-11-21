resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "igw"
  }
}

resource "aws_subnet" "private-az1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = var.aws_az1

  tags = {
    Name                                        = "private-${var.aws_az1}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.project_name}" = "owned"
  }
}

resource "aws_subnet" "private-az2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = var.aws_az2

  tags = {
    Name                                        = "private-${var.aws_az2}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.project_name}" = "owned"
  }
}

resource "aws_subnet" "public-az1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.20.0/24"
  availability_zone       = var.aws_az1
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "public-${var.aws_az1}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.project_name}" = "owned"
  }
}

resource "aws_subnet" "public-az2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.21.0/24"
  availability_zone       = var.aws_az2
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "public-${var.aws_az2}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.project_name}" = "owned"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "nat"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public-az1.id

  tags = {
    Name = "nat"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public"
  }
}

resource "aws_route_table_association" "private-az1" {
  subnet_id      = aws_subnet.private-az1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private-az2" {
  subnet_id      = aws_subnet.private-az2.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "public-az1" {
  subnet_id      = aws_subnet.public-az1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public-az2" {
  subnet_id      = aws_subnet.public-az2.id
  route_table_id = aws_route_table.public.id
}
