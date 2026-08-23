############################################
# Security groups
############################################

resource "aws_security_group" "alb" {
  name   = "sample-app-alb-sg"
  vpc_id = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS (reserved for future use once ACM cert is validated)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "app" {
  name   = "sample-app-instance-sg"
  vpc_id = var.vpc_id

  ingress {
    description     = "From ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

############################################
# ALB
############################################

resource "aws_lb" "app" {
  name               = "sample-app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_target_group" "app" {
  name     = "sample-app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

############################################
# HTTP listener
############################################
# NOTE: This forwards directly to the app rather than redirecting to HTTPS.
# A redirect-to-HTTPS listener is the correct production pattern (see the
# commented-out HTTPS listener below), but redirecting to a listener that
# doesn't exist would make the app completely unreachable. Once a real
# domain is available and the ACM certificate validates, restore this to a
# 301 redirect and uncomment the HTTPS listener.

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

############################################
# HTTPS listener -- DISABLED, requires a validated ACM certificate
############################################
# ACM will not attach a PENDING_VALIDATION certificate to an ALB listener.
# Confirmed via direct testing: attempting to create this listener returned
# "UnsupportedCertificate: The certificate ... must have a fully-qualified
# domain name, a supported signature, and a supported key size." Our
# certificate (acm.tf) uses a placeholder domain with no real DNS control,
# so it can never complete DNS validation.
#
# See executive report, Section 6 (Recommendations), for the documented
# limitation and remediation path: register a real domain, complete ACM's
# DNS validation, then restore this listener and revert the HTTP listener
# above back to a 301 redirect.
#
# resource "aws_lb_listener" "https" {
#   load_balancer_arn = aws_lb.app.arn
#   port              = 443
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
#   certificate_arn   = aws_acm_certificate.alb.arn
#
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.app.arn
#   }
# }

############################################
# Sample EC2 instance
############################################

resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = "t2.micro"
  subnet_id              = var.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = <<-EOF
    #!/bin/bash
    yum install -y httpd
    echo "<h1>Fintech Sample App - Secure Platform Demo</h1>" > /var/www/html/index.html
    systemctl enable --now httpd
  EOF

  tags = { Name = "sample-app-instance" }
}

resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app.id
  port              = 80
}

output "alb_dns_name" {
  value = aws_lb.app.dns_name
}