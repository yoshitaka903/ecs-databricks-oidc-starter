# Variables for ECS Databricks Application

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "app_name" {
  description = "Application name"
  type        = string
  default     = "ecs-databricks-app"
}

# セキュリティ設定
variable "allowed_ips" {
  description = "Allowed IP addresses for ALB access (list of CIDR blocks)"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for ip in var.allowed_ips : can(cidrhost(ip, 0))
    ])
    error_message = "All allowed_ips values must be valid CIDR blocks."
  }
}

# Databricks設定
variable "databricks_host" {
  description = "Databricks workspace URL"
  type        = string
  validation {
    condition     = can(regex("^https://.*\\.(cloud\\.databricks\\.com|azuredatabricks\\.net)$", var.databricks_host))
    error_message = "The databricks_host must be a valid Databricks workspace URL (AWS or Azure)."
  }
}

variable "databricks_client_id" {
  description = "Databricks OAuth Client ID"
  type        = string
}

variable "databricks_client_secret" {
  description = "Databricks OAuth Client Secret"
  type        = string
  sensitive   = true
}

variable "databricks_endpoint" {
  description = "Databricks Serving Endpoint name"
  type        = string
  default     = "databricks-claude-sonnet-4"
}

variable "oauth_redirect_uri" {
  description = "OAuth Redirect URI for authentication"
  type        = string
  default     = "https://your-app-name.loca.lt/oauth/callback"
}

# ネットワーク設定
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "The vpc_cidr must be a valid CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  validation {
    condition = alltrue([
      for cidr in var.public_subnet_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All public_subnet_cidrs values must be valid CIDR blocks."
  }
}

variable "availability_zones" {
  description = "Availability zones for subnets (if empty, uses data source)"
  type        = list(string)
  default     = []
}

# ECS設定
variable "ecs_cpu" {
  description = "ECS task CPU (256, 512, 1024, 2048)"
  type        = string
  default     = "256"
  validation {
    condition     = contains(["256", "512", "1024", "2048"], var.ecs_cpu)
    error_message = "ECS CPU must be one of: 256, 512, 1024, 2048."
  }
}

variable "ecs_memory" {
  description = "ECS task memory (MB)"
  type        = string
  default     = "512"
  validation {
    condition     = can(tonumber(var.ecs_memory)) && tonumber(var.ecs_memory) >= 512 && tonumber(var.ecs_memory) <= 30720
    error_message = "ECS memory must be between 512 and 30720 MB."
  }
}

variable "ecs_desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 1
}

# ログ設定
variable "log_retention_days" {
  description = "CloudWatch log retention period (days)"
  type        = number
  default     = 7
}

# タグ設定
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "ECS-Databricks-Integration"
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}