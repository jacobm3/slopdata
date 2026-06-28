variable "project_id" {
  type        = string
  description = "GCP project to deploy the demo resources into."
}

variable "region" {
  type        = string
  description = "Region for all resources."
  default     = "us-central1"
}

variable "prefix" {
  type        = string
  description = "Short prefix on every resource name. Lower-case, digits, hyphens."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.prefix))
    error_message = "prefix must be 2-21 chars, lower-case letters/digits/hyphens, starting with a letter."
  }
}

variable "enable_cloudsql" {
  type        = bool
  description = "Create a Cloud SQL (Postgres) instance and load customer data."
  default     = true
}

variable "retention_days" {
  type        = number
  description = "Auto-delete bucket objects after this many days (0 = never)."
  default     = 365
}
