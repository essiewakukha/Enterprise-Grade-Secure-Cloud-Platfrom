variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_id" {
  description = "VPC to deploy the sample app and ALB into."
  type        = string
}

variable "public_subnet_ids" {
  description = "At least two public subnets in different AZs, required by the ALB."
  type        = list(string)
}

variable "ami_id" {
  description = "AMI for the sample web app instance."
  type        = string
}
variable "domain_name" {
  description = "Domain for the ALB's ACM cert. Placeholder until a real domain is available; HTTPS listener will deploy but the cert stays PENDING_VALIDATION until DNS validation is completed."
  type        = string
  default     = "app.example-placeholder.com"
}