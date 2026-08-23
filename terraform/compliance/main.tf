############################################
# IAM role for AWS Config itself
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

############################################
# Config recorder + delivery channel
############################################

resource "aws_config_configuration_recorder" "this" {
  name     = "production-config-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = "production-config-delivery"
  s3_bucket_name = aws_s3_bucket.config.bucket
  depends_on     = [aws_config_configuration_recorder.this]
}

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.this]
}

############################################
# Required Config rule: S3 SSE enforcement
############################################

resource "aws_config_config_rule" "s3_encryption" {
  name = "s3-bucket-server-side-encryption-enabled"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.this]
}

############################################
# Auto-remediation: apply default SSE to any non-compliant bucket
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
    name         = "AutomationAssumeRole"
    static_value = aws_iam_role.remediation.arn
  }
  parameter {
    name           = "BucketName"
    resource_value = "RESOURCE_ID"
  }
  parameter {
    name         = "SSEAlgorithm"
    static_value = "AES256"
  }

  automatic                  = true
  maximum_automatic_attempts = 3
  retry_attempt_seconds      = 60

  execution_controls {
    ssm_controls {
      concurrent_execution_rate_percentage = 25
      error_percentage                     = 10
    }
  }
}
############################################
# Second Config rule: S3 public-read prohibition (genuinely triggerable)
############################################

resource "aws_config_config_rule" "s3_public_read_prohibited" {
  name = "s3-bucket-public-read-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_iam_role" "remediation_public_access" {
  name = "config-remediation-public-access-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "remediation_public_access" {
  name = "config-remediation-public-access-policy"
  role = aws_iam_role.remediation_public_access.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutBucketPublicAccessBlock",
        "s3:GetBucketPublicAccessBlock",
        "s3:PutBucketAcl",
        "s3:GetBucketAcl",
        "s3:GetBucketPolicy",
        "s3:PutBucketPolicy",
        "s3:GetBucketPolicyStatus"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_config_remediation_configuration" "s3_public_read" {
  config_rule_name = aws_config_config_rule.s3_public_read_prohibited.name
  target_type      = "SSM_DOCUMENT"
  target_id        = "AWS-DisableS3BucketPublicReadWrite"
  target_version   = "1"

  parameter {
    name         = "AutomationAssumeRole"
    static_value = aws_iam_role.remediation_public_access.arn
  }
  parameter {
    name           = "S3BucketName"
    resource_value = "RESOURCE_ID"
  }

  automatic                  = true
  maximum_automatic_attempts = 3
  retry_attempt_seconds      = 60
}