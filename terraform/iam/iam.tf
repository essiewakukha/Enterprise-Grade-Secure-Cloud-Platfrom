############################################
# Permission Boundary Policy
############################################

resource "aws_iam_policy" "devops_boundary" {
  name        = "DevOpsEngineerPermissionBoundary"
  description = "Maximum permissions ceiling for the DevOpsEngineer role. Blocks destructive S3 actions and IAM privilege escalation regardless of the role's attached policies."
  policy      = file("${path.module}/policies/permission-boundary-devops.json")
}

############################################
# DevOpsEngineer role
############################################
# Trust policy is added in Piece 5 below (it needs to reference the OIDC
# deploy role, which doesn't exist yet at this point in the file) -- for now
# this creates the role with a placeholder trust that we'll immediately
# replace once oidc.tf exists.

resource "aws_iam_role" "devops_engineer" {
  name                 = "DevOpsEngineer"
  permissions_boundary = aws_iam_policy.devops_boundary.arn
  max_session_duration = 3600

      assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowAssumeByOIDCDeployRole"
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = aws_iam_role.github_actions_deploy.arn }
    }]
  })
  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Working permissions granted to DevOpsEngineer -- still capped by the
# boundary above no matter how broad this attached policy is.
resource "aws_iam_role_policy_attachment" "devops_poweruser" {
  role       = aws_iam_role.devops_engineer.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}