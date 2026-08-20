############################################
# GitHub Actions OIDC Federation
############################################
# GitHub's OIDC token issuer is https://token.actions.githubusercontent.com.
# AWS validates the token's signature against GitHub's published JWKS and its
# thumbprint, then maps claims (repo, ref, actor) in the trust policy to grant
# temporary, auto-expiring credentials. No static AWS access keys are ever
# stored in GitHub -- eliminating long-lived-credential leakage as an attack
# vector entirely.

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # GitHub's current OIDC root CA thumbprint. AWS also now validates the token
  # signature directly, so this thumbprint mainly needs to remain non-empty
  # and current; re-verify against GitHub's docs if provider creation fails.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "github_oidc_trust" {
  statement {
    sid     = "AllowGitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Hard scope: only this exact repo AND this exact branch may assume the
    # role. Any other repo, fork, PR-triggered workflow, or branch is denied
    # at the trust-policy level -- this is what blocks Scenario 3 (CI/CD abuse).
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "github_actions_deploy" {
  name                 = "GitHubActionsDeployRole"
  assume_role_policy   = data.aws_iam_policy_document.github_oidc_trust.json
  max_session_duration = 1800 # 30 minutes -- temporary credentials only

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "ci-cd-oidc"
  }
}

# Deploy role is allowed to assume DevOpsEngineer (which carries the
# permission boundary) rather than being granted broad rights directly --
# defense in depth: two hops, both scoped, both temporary.
resource "aws_iam_role_policy" "github_deploy_assume_devops" {
  name = "AssumeDevOpsEngineer"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AssumeDevOpsEngineerRole"
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = aws_iam_role.devops_engineer.arn
    }]
  })
}

output "github_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}

output "github_actions_deploy_role_arn" {
  value = aws_iam_role.github_actions_deploy.arn
}

output "devops_engineer_role_arn" {
  value = aws_iam_role.devops_engineer.arn
}