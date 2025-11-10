variable "environment" {
  description = "Environment name"
  type        = string
  default     = "demo"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "backstage"
}

variable "github_token" {
  description = "GitHub personal access token for Backstage integrations"
  type        = string
  sensitive   = true
}