############################################
# S3 bucket for CloudTrail logs, created IN the Logging account
############################################

resource "aws_s3_bucket" "cloudtrail" {
  provider = aws.logging
  bucket   = "fintech-org-cloudtrail-logs-077489419337"
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  provider                = aws.logging
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  provider = aws.logging
  bucket   = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.cloudtrail.arn
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_bucket_policy" {
  provider = aws.logging

  # Lets CloudTrail check the bucket's ACL before it starts delivering logs
  statement {
    sid       = "AWSCloudTrailAclCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }

  # Lets CloudTrail actually write log files, scoped to a per-account path
  # (org trails deliver each member account's logs under its own account-ID
  # prefix) and only when the bucket-owner-full-control ACL is used
  statement {
    sid       = "AWSCloudTrailWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  provider = aws.logging
  bucket   = aws_s3_bucket.cloudtrail.id
  policy   = data.aws_iam_policy_document.cloudtrail_bucket_policy.json
}