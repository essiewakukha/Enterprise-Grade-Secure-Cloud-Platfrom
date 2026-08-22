resource "aws_sns_topic" "security_alerts" {
  name = "security-team-alerts"
}

resource "aws_sns_topic_subscription" "security_email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.security_alerts_email
}