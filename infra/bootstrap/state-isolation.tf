resource "aws_iam_role_policy" "protect_bootstrap" {
  for_each = aws_iam_role.github
  role     = each.value.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect   = "Deny"
    Action   = "s3:*"
    Resource = "${aws_s3_bucket.state.arn}/bootstrap/*"
  }] })
}
