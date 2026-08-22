variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "github_org" {
  description = "GitHub organization/user that owns the deploy repo."
  type        = string
}

variable "github_repo" {
  description = "Repository name (without org prefix) allowed to assume the CI/CD role."
  type        = string
}

variable "github_branch" {
  description = "Branch allowed to assume the CI/CD role via OIDC. Only this ref can deploy."
  type        = string
  default     = "main"
}

variable "environment" {
  description = "Logical environment this IAM layer is applied to, e.g. production or development."
  type        = string
}