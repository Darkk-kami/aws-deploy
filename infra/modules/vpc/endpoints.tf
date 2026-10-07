resource "terraform_data" "endpoint_checks" {
  input = true
  lifecycle {
    precondition {
      condition     = length(local.unsupported_endpoints) == 0
      error_message = "Unsupported entries in enabled_vpc_endpoints: ${join(", ", local.unsupported_endpoints)}."
    }
  }
}

resource "aws_security_group" "vpc_endpoints_sg" {
  name_prefix = "${local.name_prefix}-vpc-endpoints-sg-"
  description = "Allow VPC interface endpoint traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # No egress

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc-endpoints-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_endpoint" "interface_endpoints" {
  # exclude "gateway" endpoints like S3 and DynamoDB
  for_each = setsubtract(toset(var.enabled_vpc_endpoints), toset(["s3", "dynamodb"]))

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.app_subnets[*].id
  security_group_ids = [aws_security_group.vpc_endpoints_sg.id]

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${each.value}-endpoint"
  })
}

resource "aws_vpc_endpoint" "s3_endpoint" {
  count = contains(var.enabled_vpc_endpoints, "s3") ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = {
    Name = "${local.name_prefix}-s3-endpoint"
  }
}