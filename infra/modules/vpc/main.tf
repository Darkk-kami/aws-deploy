resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  count  = var.enable_igw ? 1 : 0
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# Substituting for VPC endpoints as our use case only requires ecr pulls
# resource "aws_subnet" "nat_subnets" {
#   count             = var.public_subnets_no
#   vpc_id            = data.aws_vpc.main_vpc.id
#   cidr_block        = ["10.100.14.0/28", "10.100.15.0/28"][count.index]
#   availability_zone = local.az_list[count.index % length(local.az_list)]

#   tags = merge(var.tags, {
#     Name = "app-nat-subnnet-${local.az_list[count.index]}"
#     }
#   )
# }

# resource "aws_eip" "main_nat_eip" {
#   count = var.nat_gw_no
# }

# resource "aws_nat_gateway" "main_nat_gw" {
#   count         = var.nat_gw_no
#   subnet_id     = aws_subnet.nat_subnets[count.index].id
#   allocation_id = aws_eip.main_nat_eip[count.index].id
# }



######################
# Subnets
resource "aws_subnet" "lb_subnets" {
  count                   = length(var.lb_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.lb_subnet_cidrs[count.index]
  availability_zone       = local.public_azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name       = "${local.name_prefix}-lb-subnet-${local.public_azs[count.index]}" # e.g. prod-app-lb-subnet-eu-west-2a
    SubnetType = "public"
  })

}

resource "aws_subnet" "app_subnets" {
  count             = length(var.app_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.app_subnet_cidrs[count.index]
  availability_zone = local.private_azs[count.index]

  tags = merge(var.tags, {
    Name       = "${local.name_prefix}-app-subnet-${local.private_azs[count.index]}" # e.g. prod-app-subnet-eu-west-2a
    SubnetType = "private"
  })
}

######################
# Route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-rt-public"
  })
}

resource "aws_route" "public_internet" {
  count                  = var.enable_igw ? 1 : 0
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main[0].id
}


resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-rt-private"
  })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.lb_subnets)
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.lb_subnets[count.index].id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.app_subnets)
  route_table_id = aws_route_table.private.id
  subnet_id      = aws_subnet.app_subnets[count.index].id
}