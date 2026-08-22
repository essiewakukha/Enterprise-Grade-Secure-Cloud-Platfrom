variable "domain_name" {
  description = "Public domain for the ACM certificate. Placeholder for now -- swap in a real domain before applying, or ACM's DNS validation will never complete."
  type        = string
  default     = "app.example-placeholder.com"
}