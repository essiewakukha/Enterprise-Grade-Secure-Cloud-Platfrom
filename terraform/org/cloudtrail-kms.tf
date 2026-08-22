############################################
# KMS key for CloudTrail logs, created IN the Logging account
############################################

data "aws_iam_policy_document" "cloudtrail_kms" {
  provider = aws.logging

  statement {
    sid       = "EnableLoggingAccountRootAccess"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::077489419337:root"]
    }
  }

  statement {
    sid    = "AllowCloudTrailToEncryptLogs"
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "cloudtrail" {
  provider                = aws.logging
  description              = "Encrypts org-wide CloudTrail logs in the Logging account"
  deletion_window_in_days  = 30
  enable_key_rotation      = true
  policy                   = data.aws_iam_policy_document.cloudtrail_kms.json
}

resource "aws_kms_alias" "cloudtrail" {
  provider      = aws.logging
  name          = "alias/org-cloudtrail-key"
  target_key_id = aws_kms_key.cloudtrail.key_id
}