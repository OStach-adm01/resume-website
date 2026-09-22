resource "aws_vpc" "main" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
}
resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.42.1.0/24"
}
resource "aws_internet_gateway" "main" { vpc_id = aws_vpc.main.id }
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
data "aws_ec2_managed_prefix_list" "cloudfront" { name = "com.amazonaws.global.cloudfront.origin-facing" }
# Package, registry, and AWS endpoints have changing IPs; only ports 80/443 are open outbound.
#trivy:ignore:AWS-0104
resource "aws_security_group" "node" {
  name        = "${local.name}-node"
  description = "Only CloudFront can reach the website; management uses outbound SSM"
  vpc_id      = aws_vpc.main.id
  ingress {
    description     = "CloudFront origin traffic"
    from_port       = 30080
    to_port         = 30080
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }
  egress {
    description = "HTTPS for AWS APIs, image registries, and package downloads"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "HTTP for operating system package repositories"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "random_password" "origin" {
  length  = 48
  special = false
}
resource "aws_ssm_parameter" "origin" {
  name  = "/${local.name}/origin-token"
  type  = "SecureString"
  value = random_password.origin.result
}
data "aws_ssm_parameter" "ami" { name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64" }
resource "aws_iam_role" "node" {
  name                 = "${local.name}-node"
  path                 = "/${local.name}/"
  permissions_boundary = var.runtime_boundary_arn
  assume_role_policy   = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy" "node" {
  role = aws_iam_role.node.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion"], Resource = "${aws_s3_bucket.artifacts.arn}/*" },
    { Effect = "Allow", Action = "s3:ListBucket", Resource = aws_s3_bucket.artifacts.arn },
    { Effect = "Allow", Action = "ssm:GetParameter", Resource = aws_ssm_parameter.origin.arn },
    { Effect = "Allow", Action = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"], Resource = aws_ecr_repository.web.arn },
    { Effect = "Allow", Action = ["ecr:GetAuthorizationToken", "ssm:UpdateInstanceInformation", "ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"], Resource = "*" }
  ] })
}
resource "aws_iam_instance_profile" "node" {
  name = "${local.name}-node"
  path = "/${local.name}/"
  role = aws_iam_role.node.name
}
resource "aws_instance" "node" {
  ami                         = data.aws_ssm_parameter.ami.value
  instance_type               = "t4g.small"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.node.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.node.name
  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    k3s_version   = var.k3s_version, helm_version = var.helm_version,
    region        = var.region, account = local.account,
    deploy_script = base64encode(file("${path.module}/../../scripts/node-deploy.sh"))
  })
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }
  root_block_device {
    volume_size = 16
    volume_type = "gp3"
    encrypted   = true
  }
  credit_specification { cpu_credits = "standard" }
  tags       = { Name = "${local.name}-k3s", FreePlanExpiresOn = var.free_plan_expires_on }
  depends_on = [aws_route_table_association.public, aws_iam_role_policy.node]
}
resource "aws_eip" "node" {
  domain   = "vpc"
  instance = aws_instance.node.id
}
resource "aws_ssm_document" "deploy" {
  name            = "${local.name}-deploy"
  document_type   = "Command"
  document_format = "JSON"
  content = jsonencode({ schemaVersion = "2.2", description = "Deploy a published immutable resume release", parameters = {
    Release = { type = "String", allowedPattern = "^[a-f0-9]{40}$", interpolationType = "ENV_VAR" }
  }, mainSteps = [{ action = "aws:runShellScript", name = "deploy", inputs = { timeoutSeconds = "1200", runCommand = ["/usr/local/bin/resume-deploy \"$SSM_Release\""] } }] })
}
