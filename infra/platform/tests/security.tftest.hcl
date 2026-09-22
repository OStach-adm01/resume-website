mock_provider "aws" {
  mock_data "aws_caller_identity" { defaults = { account_id = "123456789012" } }
  mock_data "aws_ssm_parameter" { defaults = { value = "ami-0123456789abcdef0" } }
  mock_data "aws_ec2_managed_prefix_list" { defaults = { id = "pl-0123456789abcdef0" } }
}
mock_provider "aws" { alias = "edge" }
mock_provider "cloudflare" {}
mock_provider "archive" {
  mock_data "archive_file" { defaults = { output_path = "/tmp/recruiter.zip", output_base64sha256 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" } }
}
mock_provider "random" {}
variables {
  domain_name          = "example.com"
  cloudflare_zone_id   = "00000000000000000000000000000000"
  alert_email          = "test@example.com"
  runtime_boundary_arn = "arn:aws:iam::123456789012:policy/resume-website-runtime-boundary"
  free_plan_expires_on = "2027-01-01"
}
override_resource {
  target = aws_acm_certificate.site
  values = {
    arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
    domain_validation_options = [
      { domain_name = "example.com", resource_record_name = "_test.example.com", resource_record_type = "CNAME", resource_record_value = "_test.acm-validations.aws" },
      { domain_name = "www.example.com", resource_record_name = "_www.example.com", resource_record_type = "CNAME", resource_record_value = "_www.acm-validations.aws" }
    ]
  }
}
run "security_contract" {
  command = plan
  assert {
    condition     = aws_s3_bucket_public_access_block.artifacts.block_public_acls && aws_s3_bucket_public_access_block.artifacts.block_public_policy && aws_s3_bucket_public_access_block.artifacts.ignore_public_acls && aws_s3_bucket_public_access_block.artifacts.restrict_public_buckets
    error_message = "Artifact storage must never be public."
  }
  assert {
    condition     = aws_instance.node.metadata_options[0].http_tokens == "required" && aws_instance.node.root_block_device[0].encrypted
    error_message = "The node requires IMDSv2 and encrypted disk."
  }
  assert {
    condition     = aws_dynamodb_table.recruiters.ttl[0].enabled && aws_dynamodb_table.recruiters.ttl[0].attribute_name == "expiresAt"
    error_message = "Recruiter records require automatic expiration."
  }
  assert {
    condition     = jsondecode(aws_api_gateway_model.request.schema).properties.recruiter.enum == [true]
    error_message = "Only affirmative recruiter requests may reach the integration."
  }
  assert {
    condition     = aws_api_gateway_request_validator.request.validate_request_body && contains(keys(aws_api_gateway_method.post.request_models), "$default")
    error_message = "All content types must pass body validation."
  }
  assert {
    condition     = aws_cloudwatch_log_group.lambda.retention_in_days == 7
    error_message = "Application logs must have bounded retention."
  }
}
