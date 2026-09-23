mock_provider "aws" {
  mock_data "aws_caller_identity" { defaults = { account_id = "123456789012" } }
}
variables {
  state_bucket_name = "resume-website-123456789012-state"
}
override_resource {
  target = aws_iam_openid_connect_provider.github
  values = { arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" }
}
override_resource {
  target = aws_s3_bucket.state
  values = { arn = "arn:aws:s3:::resume-website-123456789012-state" }
}
override_resource {
  target = aws_iam_policy.runtime_boundary
  values = { arn = "arn:aws:iam::123456789012:policy/resume-website-runtime-boundary" }
}
run "github_identity_and_state_boundaries" {
  command = apply
  assert {
    condition     = alltrue([for role in aws_iam_role.github : jsondecode(role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:OStach-adm01@307522145/resume-website@1381486564:environment:production"])
    error_message = "Every role must require the exact production environment subject."
  }
  assert {
    condition     = length(aws_iam_role_policy.terraform.policy) + length(aws_iam_role_policy.state["terraform"].policy) + length(aws_iam_role_policy.protect_bootstrap["terraform"].policy) < 10240
    error_message = "Combined Terraform role inline policies exceed the AWS limit."
  }
  assert {
    condition     = alltrue([for policy in aws_iam_role_policy.protect_bootstrap : jsondecode(policy.policy).Statement[0].Effect == "Deny"])
    error_message = "Every CI role must be denied access to bootstrap state."
  }
}
