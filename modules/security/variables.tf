variable "vpc_id" {
  description = "VPC ID where security groups are created"
  type        = string
}

variable "prefix" {
  description = "Prefix applied to all resource names"
  type        = string
  default     = "bookstore"
}

variable "allowed_ssh_cidr" {
  description = "Your office/home IP in CIDR notation for bastion SSH access. Never use 0.0.0.0/0."
  type        = string
}
