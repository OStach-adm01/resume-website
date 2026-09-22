# Alerts contain operational metric names only. A CMK would add cost and key-policy complexity.
#trivy:ignore:AWS-0095
resource "aws_sns_topic" "alerts" { name = "${local.name}-alerts" }
resource "aws_sns_topic_subscription" "alerts" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
# Same operational-only notification scope as the regional topic above.
#trivy:ignore:AWS-0095
resource "aws_sns_topic" "edge_alerts" {
  provider = aws.edge
  name     = "${local.name}-alerts"
}
resource "aws_sns_topic_subscription" "edge_alerts" {
  provider  = aws.edge
  topic_arn = aws_sns_topic.edge_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
resource "aws_cloudwatch_metric_alarm" "node" {
  alarm_name          = "${local.name}-node-failed"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 2
  period              = 60
  statistic           = "Maximum"
  dimensions          = { InstanceId = aws_instance.node.id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "missing"
}
resource "aws_cloudwatch_metric_alarm" "lambda" {
  for_each            = toset(["Errors", "Throttles"])
  alarm_name          = "${local.name}-lambda-${lower(each.key)}"
  namespace           = "AWS/Lambda"
  metric_name         = each.key
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 1
  period              = 300
  statistic           = "Sum"
  dimensions          = { FunctionName = aws_lambda_function.recruiter.function_name }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}
resource "aws_cloudwatch_metric_alarm" "database" {
  alarm_name          = "${local.name}-database-throttles"
  namespace           = "AWS/DynamoDB"
  metric_name         = "WriteThrottleEvents"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 1
  period              = 300
  statistic           = "Sum"
  dimensions          = { TableName = aws_dynamodb_table.recruiters.name }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}
resource "aws_cloudwatch_metric_alarm" "edge" {
  provider            = aws.edge
  alarm_name          = "${local.name}-edge-errors"
  namespace           = "AWS/CloudFront"
  metric_name         = "5xxErrorRate"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 5
  evaluation_periods  = 2
  period              = 300
  statistic           = "Average"
  dimensions          = { DistributionId = aws_cloudfront_distribution.site.id, Region = "Global" }
  alarm_actions       = [aws_sns_topic.edge_alerts.arn]
  treat_missing_data  = "notBreaching"
}
resource "aws_budgets_budget" "monthly" {
  name         = "${local.name}-monthly"
  budget_type  = "COST"
  limit_amount = "20"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  cost_types {
    include_credit = false
    include_refund = false
  }
  dynamic "notification" {
    for_each = toset(["5", "10", "20"])
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = tonumber(notification.value)
      threshold_type             = "ABSOLUTE_VALUE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.alert_email]
    }
  }
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 20
    threshold_type             = "ABSOLUTE_VALUE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
