resource "aws_acm_certificate" "alb" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

output "acm_certificate_arn" {
  value = aws_acm_certificate.alb.arn
}

output "acm_domain_validation_options" {
  value = aws_acm_certificate.alb.domain_validation_options
}