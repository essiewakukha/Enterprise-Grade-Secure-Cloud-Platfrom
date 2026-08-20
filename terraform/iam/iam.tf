############################################
# Permission Boundary
############################################
# A permission boundary is a MAXIMUM permission ceiling. The role's own
# identity policy still grants the actual permissions; the boundary can only
# take permissions away, never add them. This is what differentiates it from
# an SCP: SCPs govern every principal in an OU/account org-wide and are set
# by the organization's management account, while a boundary is attached to
# ONE IAM principal and can be set by any account admin with iam:PutRolePermissionsBoundary.

resource "aws_iam_policy" "devops_boundary" {
  name        = "DevOpsEngineerPermissionBoundary"
  description = "Maximum permissions ceiling for the DevOpsEngineer role. Blocks destructive S3 actions and IAM privilege escalation regardless of the role's attached policies."
  policy      = file("${path.module}/policies/permission-boundary-devops.json")
}

data "aws_iam_policy_document" "devops_trust" {
  statement {
    sid     = "AllowAssumeByOIDCDeployRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.github_actions_deploy.arn]
    }
  }
}

resource "aws_iam_role" "devops_engineer" {
  name                 = "DevOpsEngineer"
  assume_role_policy   = data.aws_iam_policy_document.devops_trust.json
  permissions_boundary = aws_iam_policy.devops_boundary.arn
  max_session_duration = 3600

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Working permissions granted to DevOpsEngineer (still capped by the boundary above)
resource "aws_iam_role_policy_attachment" "devops_poweruser" {
  role       = aws_iam_role.devops_engineer.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

############################################
# Proof artifact: attempting a boundary-denied action
############################################
# Run this after apply to generate the "proof of blocked action" deliverable:
#   aws sts assume-role --role-arn <devops_engineer_role_arn> --role-session-name boundary-test
#   aws s3api delete-object --bucket <any-bucket> --key <any-key> --profile boundary-test
# Expected result: AccessDenied - explicit deny via permissions boundary,
# even if an attached policy (e.g. PowerUserAccess) would otherwise allow it.