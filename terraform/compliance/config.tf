############################################
# AWS Config: recorder + delivery + managed rule + auto-remediation
############################################

resource "aws_iam_role" "config" {
  name = "aws-config-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config_managed" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_iam_role_policy" "config_s3_delivery" {
  name = "config-s3-delivery"
  role = aws_iam_role.config.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetBucketAcl"]
      Resource = ["arn:aws:s3:::${var.config_bucket_name}", "arn:aws:s3:::${var.config_bucket_name}/*"]
    }]
  })
}

resource "aws_config_configuration_recorder" "this" {
  name     = "org-config-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = "org-config-delivery"
  s3_bucket_name = var.config_bucket_name
  depends_on     = [aws_config_configuration_recorder.this]
}

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.this]
}

# --- Required Config rule: S3 SSE enforcement ---

resource "aws_config_config_rule" "s3_encryption" {
  name = "s3-bucket-server-side-encryption-enabled"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.this]
}

############################################
# Auto-remediation: apply default SSE to any bucket Config finds non-compliant
############################################

resource "aws_iam_role" "remediation" {
  name = "config-remediation-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "remediation" {
  name = "config-remediation-policy"
  role = aws_iam_role.remediation.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutEncryptionConfiguration",
        "s3:GetEncryptionConfiguration",
        "s3:GetBucketLocation"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_config_remediation_configuration" "s3_encryption" {
  config_rule_name = aws_config_config_rule.s3_encryption.name
  target_type      = "SSM_DOCUMENT"
  target_id        = "AWS-EnableS3BucketEncryption"
  target_version   = "1"

  parameter {
    name           = "AutomationAssumeRole"
    static_value   = aws_iam_role.remediation.arn
  }
  parameter {
    name           = "BucketName"
    resource_value = "RESOURCE_ID"
  }
  parameter {
    name         = "SSEAlgorithm"
    static_value = "aws:kms"
  }

  automatic                 = true
  maximum_automatic_attempts = 3

  retry_attempt_seconds = 60

  execution_controls {
    ssm_controls {
      concurrent_execution_rate_percentage = 25
      error_percentage                     = 10
    }
  }
}

# Deliverable proof steps (Scenario 1):
#   1. aws s3api create-bucket --bucket fintech-test-unencrypted-<rand> --region af-south-1
#   2. Wait for the next Config evaluation cycle (or trigger manually via
#      aws configservice start-config-rules-evaluation --config-rule-names s3-bucket-server-side-encryption-enabled)
#   3. Security Hub will surface a NON_COMPLIANT finding for the bucket
#   4. AWS_EnableS3BucketEncryption SSM automation runs automatically and applies aws:kms SSE
#   5. Next evaluation cycle flips the resource back to COMPLIANT and the Security Hub finding auto-resolves