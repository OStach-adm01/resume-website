output "site_url" { value = "https://${var.domain_name}" }
output "artifacts_bucket" { value = aws_s3_bucket.artifacts.id }
output "ecr_repository" { value = aws_ecr_repository.web.repository_url }
output "instance_id" { value = aws_instance.node.id }
output "distribution_id" { value = aws_cloudfront_distribution.site.id }
output "deploy_document" { value = aws_ssm_document.deploy.name }
output "free_plan_expires_on" { value = var.free_plan_expires_on }
