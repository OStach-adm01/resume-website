terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
provider "aws" { region = var.region }
variable "region" {
  type    = string
  default = "eu-central-1"
}
variable "github_repository" {
  type    = string
  default = "OStach-adm01/resume-website"
}
variable "github_owner_id" {
  description = "Immutable GitHub owner ID used in the OIDC subject."
  type        = string
  default     = "307522145"
  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "Set the numeric GitHub owner ID."
  }
}
variable "github_repository_id" {
  description = "Immutable GitHub repository ID used in the OIDC subject."
  type        = string
  default     = "1381486564"
  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "Set the numeric GitHub repository ID."
  }
}
variable "state_bucket_name" { type = string }
data "aws_caller_identity" "current" {}
locals {
  github_oidc_subject = "repo:${split("/", var.github_repository)[0]}@${var.github_owner_id}/${split("/", var.github_repository)[1]}@${var.github_repository_id}:environment:production"
  name                = "resume-website"
  account             = data.aws_caller_identity.current.account_id
  tags                = { Project = local.name, ManagedBy = "Terraform" }
}
resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name
  tags   = local.tags
  lifecycle { prevent_destroy = true }
}
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}
# SSE-S3 is intentional for this lab; a paid customer-managed KMS key is not required.
#trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Deny", Principal = "*", Action = "s3:*", Resource = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"], Condition = { Bool = { "aws:SecureTransport" = "false" } } }] })
}
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  tags           = local.tags
}
resource "aws_iam_role" "github" {
  for_each           = toset(["terraform", "publish", "deploy", "drift"])
  name               = "${local.name}-${each.key}"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Federated = aws_iam_openid_connect_provider.github.arn }, Action = "sts:AssumeRoleWithWebIdentity", Condition = { StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com", "token.actions.githubusercontent.com:sub" = local.github_oidc_subject } } }] })
  tags               = local.tags
}
resource "aws_iam_policy" "runtime_boundary" {
  name = "${local.name}-runtime-boundary"
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:ListBucket"], Resource = ["arn:aws:s3:::${local.name}-${local.account}-artifacts", "arn:aws:s3:::${local.name}-${local.account}-artifacts/*"] },
    { Effect = "Allow", Action = ["dynamodb:PutItem"], Resource = "arn:aws:dynamodb:${var.region}:${local.account}:table/${local.name}-recruiters" },
    { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "arn:aws:logs:*:${local.account}:log-group:/aws/lambda/${local.name}-recruiter:*" },
    { Effect = "Allow", Action = ["ssm:GetParameter"], Resource = "arn:aws:ssm:${var.region}:${local.account}:parameter/${local.name}/origin-token" },
    { Effect = "Allow", Action = ["ecr:GetAuthorizationToken", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability", "ssm:UpdateInstanceInformation", "ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"], Resource = "*" }
  ] })
}
resource "aws_iam_role_policy" "state" {
  for_each = toset(["terraform", "drift"])
  role     = aws_iam_role.github[each.key].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.state.arn },
    { Effect = "Allow", Action = each.key == "terraform" ? ["s3:GetObject", "s3:PutObject"] : ["s3:GetObject"], Resource = "${aws_s3_bucket.state.arn}/platform/terraform.tfstate" },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = "${aws_s3_bucket.state.arn}/platform/terraform.tfstate.tflock" }
  ] })
}
resource "aws_iam_role_policy_attachment" "drift" {
  role       = aws_iam_role.github["drift"].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
# Lifecycle operations span services. This account is dedicated to this lab.
# Runtime role boundaries prevent provisioning an administrator workload role.
resource "aws_iam_role_policy" "terraform" {
  role = aws_iam_role.github["terraform"].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["logs:DescribeLogGroups", "ssm:DescribeParameters"], Resource = "*" },
    { Effect = "Allow", Action = ["ec2:GetManagedPrefixListEntries"], Resource = "arn:aws:ec2:${var.region}:aws:prefix-list/*" },
    { Effect = "Allow", Action = ["ssm:DescribeDocumentPermission"], Resource = "arn:aws:ssm:${var.region}:${local.account}:document/${local.name}-deploy" },
    { Effect = "Allow", Action = ["s3:GetAccelerateConfiguration", "s3:GetReplicationConfiguration"], Resource = "arn:aws:s3:::${local.name}-${local.account}-artifacts" },
    { Effect = "Allow", Action = ["ec2:Describe*", "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute", "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute", "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway", "ec2:AttachInternetGateway", "ec2:DetachInternetGateway", "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable", "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress", "ec2:RunInstances", "ec2:TerminateInstances", "ec2:StopInstances", "ec2:StartInstances", "ec2:ModifyInstanceAttribute", "ec2:ModifyInstanceMetadataOptions", "ec2:AllocateAddress", "ec2:ReleaseAddress", "ec2:AssociateAddress", "ec2:DisassociateAddress", "ec2:CreateTags", "ec2:DeleteTags", "ec2:DescribeInstanceCreditSpecifications", "ec2:ModifyInstanceCreditSpecification"], Resource = "*" },
    { Effect = "Allow", Action = ["s3:CreateBucket", "s3:DeleteBucket", "s3:GetBucket*", "s3:ListBucket", "s3:GetEncryptionConfiguration", "s3:PutEncryptionConfiguration", "s3:GetLifecycleConfiguration", "s3:PutLifecycleConfiguration", "s3:PutBucketVersioning", "s3:PutBucketPublicAccessBlock", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:PutBucketTagging"], Resource = "arn:aws:s3:::${local.name}-${local.account}-artifacts" },
    { Effect = "Allow", Action = ["ecr:*"], Resource = "arn:aws:ecr:${var.region}:${local.account}:repository/${local.name}" },
    { Effect = "Allow", Action = ["lambda:*"], Resource = "arn:aws:lambda:${var.region}:${local.account}:function:${local.name}-recruiter" },
    { Effect = "Allow", Action = ["dynamodb:*"], Resource = "arn:aws:dynamodb:${var.region}:${local.account}:table/${local.name}-recruiters" },
    { Effect = "Allow", Action = ["cloudfront:*", "acm:*", "apigateway:*", "cloudwatch:*", "budgets:*"], Resource = "*" },
    { Effect = "Allow", Action = ["logs:*"], Resource = "arn:aws:logs:*:${local.account}:log-group:/aws/lambda/${local.name}-recruiter*" },
    { Effect = "Allow", Action = ["sns:*"], Resource = "arn:aws:sns:*:${local.account}:${local.name}-alerts" },
    { Effect = "Allow", Action = ["ssm:GetParameter"], Resource = "arn:aws:ssm:${var.region}::parameter/aws/service/ami-amazon-linux-latest/*" },
    { Effect = "Allow", Action = ["ssm:PutParameter", "ssm:GetParameter", "ssm:DeleteParameter", "ssm:AddTagsToResource", "ssm:RemoveTagsFromResource", "ssm:ListTagsForResource"], Resource = "arn:aws:ssm:${var.region}:${local.account}:parameter/${local.name}/*" },
    { Effect = "Allow", Action = ["ssm:CreateDocument", "ssm:UpdateDocument", "ssm:UpdateDocumentDefaultVersion", "ssm:DeleteDocument", "ssm:GetDocument", "ssm:DescribeDocument", "ssm:AddTagsToResource", "ssm:RemoveTagsFromResource", "ssm:ListTagsForResource"], Resource = "arn:aws:ssm:${var.region}:${local.account}:document/${local.name}-deploy" },
    { Effect = "Allow", Action = ["iam:CreateRole"], Resource = "arn:aws:iam::${local.account}:role/${local.name}/*", Condition = { StringEquals = { "iam:PermissionsBoundary" = aws_iam_policy.runtime_boundary.arn } } },
    { Effect = "Allow", Action = ["iam:GetRole", "iam:DeleteRole", "iam:UpdateAssumeRolePolicy", "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole", "iam:TagRole", "iam:UntagRole"], Resource = "arn:aws:iam::${local.account}:role/${local.name}/*" },
    { Effect = "Allow", Action = ["iam:PassRole"], Resource = "arn:aws:iam::${local.account}:role/${local.name}/*", Condition = { StringEquals = { "iam:PassedToService" = ["lambda.amazonaws.com", "ec2.amazonaws.com"] } } },
    { Effect = "Allow", Action = ["iam:CreateInstanceProfile", "iam:GetInstanceProfile", "iam:DeleteInstanceProfile", "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile", "iam:UntagInstanceProfile"], Resource = "arn:aws:iam::${local.account}:instance-profile/${local.name}/*" }
  ] })
}
resource "aws_iam_role_policy" "publish" {
  role = aws_iam_role.github["publish"].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:ListBucket"], Resource = "arn:aws:s3:::${local.name}-${local.account}-artifacts" },
    { Effect = "Allow", Action = ["s3:PutObject", "s3:GetObject"], Resource = "arn:aws:s3:::${local.name}-${local.account}-artifacts/*" },
    { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
    { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:DescribeImages"], Resource = "arn:aws:ecr:${var.region}:${local.account}:repository/${local.name}" }
  ] })
}
resource "aws_iam_role_policy" "deploy" {
  role = aws_iam_role.github["deploy"].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["ssm:SendCommand"], Resource = "arn:aws:ssm:${var.region}:${local.account}:document/${local.name}-deploy" },
    { Effect = "Allow", Action = ["ssm:SendCommand"], Resource = "arn:aws:ec2:${var.region}:${local.account}:instance/*", Condition = { StringEquals = { "ssm:resourceTag/Project" = local.name } } },
    { Effect = "Allow", Action = ["ssm:GetCommandInvocation", "ec2:DescribeInstances"], Resource = "*" },
    { Effect = "Allow", Action = ["cloudfront:ListDistributions", "cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"], Resource = "*" }
  ] })
}
output "state_bucket" { value = aws_s3_bucket.state.id }
output "roles" { value = { for key, role in aws_iam_role.github : key => role.arn } }
output "runtime_boundary_arn" { value = aws_iam_policy.runtime_boundary.arn }
