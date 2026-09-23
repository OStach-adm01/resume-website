terraform {
  required_version = ">= 1.10, < 2.0"
  backend "s3" { use_lockfile = true }
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 6.0" }
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 5.0" }
    archive    = { source = "hashicorp/archive", version = "~> 2.7" }
    random     = { source = "hashicorp/random", version = "~> 3.7" }
  }
}
provider "aws" {
  region = var.region
  default_tags { tags = { Project = "resume-website", ManagedBy = "Terraform", Environment = "production" } }
}
provider "aws" {
  alias  = "edge"
  region = "us-east-1"
  default_tags { tags = { Project = "resume-website", ManagedBy = "Terraform" } }
}
provider "cloudflare" {}
variable "region" {
  type    = string
  default = "eu-central-1"
}
variable "domain_name" { type = string }
variable "cloudflare_zone_id" { type = string }
variable "alert_email" { type = string }
variable "runtime_boundary_arn" { type = string }
variable "resume_version" {
  type    = string
  default = ""
  validation {
    condition     = var.resume_version == "" || can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}$", var.resume_version))
    error_message = "Use a safe immutable resume version, or leave empty to disable downloads."
  }
}
variable "free_plan_expires_on" {
  type = string
  validation {
    condition     = can(formatdate("YYYY-MM-DD", "${var.free_plan_expires_on}T00:00:00Z"))
    error_message = "Set the actual Free Plan expiry date as YYYY-MM-DD."
  }
}
variable "k3s_version" {
  type    = string
  default = "v1.34.3+k3s1"
}
variable "helm_version" {
  type    = string
  default = "v3.19.0"
}
variable "lambda_concurrency" {
  type        = number
  default     = -1
  description = "Use -1 on new accounts with a concurrency quota below 105; use 5 once the quota permits reservations. API throttling is always enabled."
}
data "aws_caller_identity" "current" {}
locals {
  name        = "resume-website"
  account     = data.aws_caller_identity.current.account_id
  artifacts   = "${local.name}-${local.account}-artifacts"
  origin_name = "origin.${var.domain_name}"
}
