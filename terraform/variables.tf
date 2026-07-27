variable "name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "imap-scrub"
}

variable "schedule_expression" {
  description = "When to run the job (EventBridge Scheduler cron/rate expression)"
  type        = string
  default     = "cron(0 6 ? * SUN *)" # weekly, Sunday 06:00
}

variable "schedule_timezone" {
  description = "IANA timezone the schedule expression is evaluated in"
  type        = string
  default     = "UTC"
}

variable "image_tag" {
  description = "Tag of the image in ECR to run"
  type        = string
  default     = "latest"
}

variable "container_command" {
  description = "Arguments passed to imap-scrub before the config path. Default runs the configured actions; set to [] for a dry run."
  type        = list(string)
  default     = ["-y"]
}

variable "cpu" {
  description = "Fargate task CPU units"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task memory in MiB"
  type        = number
  default     = 512
}

variable "cpu_architecture" {
  description = "Fargate CPU architecture (X86_64 or ARM64). Must match the platform the image was built for."
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "vpc_id" {
  description = "VPC to run the task in. Defaults to the account's default VPC."
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnets to run the task in (must belong to vpc_id, and have a route to the internet). Defaults to the default VPC's subnets."
  type        = list(string)
  default     = []
}

variable "assign_public_ip" {
  description = "Assign a public IP to the task. Required for internet access from public subnets without a NAT gateway."
  type        = bool
  default     = true
}
