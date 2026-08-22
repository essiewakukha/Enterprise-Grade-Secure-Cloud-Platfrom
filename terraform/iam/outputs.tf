output "devops_engineer_role_arn" {
  value = aws_iam_role.devops_engineer.arn
}

output "github_actions_deploy_role_arn" {
  value = aws_iam_role.github_actions_deploy.arn
}

output "github_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}