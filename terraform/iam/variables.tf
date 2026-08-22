variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "github_org" {
  description = "Your GitHub username or organization that owns the deploy repo."
  type        = string
}

variable "github_repo" {
  description = "Repository name (without the org/user prefix) allowed to assume the CI/CD role."
  type        = string
}

variable "github_branch" {
  description = "Branch allowed to assume the CI/CD role via OIDC."
  type        = string
  default     = "main"
}

variable "environment" {
  type    = string
  default = "production"
}