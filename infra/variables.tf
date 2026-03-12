variable "environment" {
  description = "Deployment environment (prod or dev)"
  type        = string

  validation {
    condition     = contains(["prod", "dev"], var.environment)
    error_message = "Environment must be 'prod' or 'dev'."
  }
}

variable "aws_region" {
  description = "Primary AWS region for infrastructure"
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Root domain name (without any subdomain prefix)"
  type        = string
  default     = "ihatetimezones.com"
}

# -----------------------------------------------------------------------------
# Locals — derived values used throughout the config
# -----------------------------------------------------------------------------

locals {
  is_prod = var.environment == "prod"

  # prod: "ihatetimezones.com", dev: "dev.ihatetimezones.com"
  site_domain = local.is_prod ? var.domain_name : "${var.environment}.${var.domain_name}"

  bucket_name = "ihatetimezones-${var.environment}-site"

  # prod needs www alias for the redirect; dev does not
  cloudfront_aliases = local.is_prod ? [
    local.site_domain,
    "www.${var.domain_name}"
  ] : [local.site_domain]

  # prod ACM cert covers both apex and www; dev only covers the subdomain
  acm_sans = local.is_prod ? ["www.${var.domain_name}"] : []

  # API
  api_name   = "ihatetimezones-${var.environment}-api"
  api_domain = local.is_prod ? "api.${var.domain_name}" : "api.${var.environment}.${var.domain_name}"
  cors_origins = local.is_prod ? [
    "https://ihatetimezones.com",
    "https://www.ihatetimezones.com"
  ] : ["https://dev.ihatetimezones.com"]
  from_email = "no-reply@${var.domain_name}"
}
