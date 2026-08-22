############################################
# GitHub Actions OIDC Provider
############################################
# Registers GitHub's OIDC issuer as a trusted identity provider in this AWS
# account. AWS validates tokens from GitHub against this registration --
# without it, GitHub's tokens mean nothing to AWS.

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # GitHub's OIDC root CA thumbprint. AWS also validates the token signature
  # directly, so this mainly needs to be present and roughly current.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

############################################
# Trust policy: ONLY this repo, ONLY this branch, ONLY as sts.amazonaws.com
############################################

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

    # This is the line that blocks Scenario 3 (CI/CD abuse from an
    # unauthorized branch/fork): the sub claim must match EXACTLY.
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
  max_session_duration = 3600 # 60 minutes -- temporary credentials only

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "ci-cd-oidc"
  }
}

############################################
# GitHubActionsDeployRole can ONLY do one thing: assume DevOpsEngineer
############################################
# Two-hop design: the OIDC role itself has no direct AWS permissions at all
# -- it exists purely to prove "this really is a GitHub Actions run from the
# right repo/branch," then hands off to DevOpsEngineer (which carries the
# actual permission boundary from Piece 3/4).

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