variable "frontend_lt_name" {
  type = string
}

variable "backend_lt_name" {
  type = string
}

variable "key_name" {
  description = "EC2 key pair name for SSH (bastion access)"
  type        = string
}

variable "ami_id_frontend" {
  type = string
}

variable "ami_id_backend" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "frontend_user_data" {
  description = "User data script filename for frontend instances"
  type        = string
}

variable "backend_user_data" {
  description = "User data script filename for backend instances"
  type        = string
}

variable "frontend_security_group_id" {
  description = "SG for frontend EC2 instances"
  type        = string
}

variable "backend_security_group_id" {
  description = "SG for backend EC2 instances"
  type        = string
}

variable "instance_profile_arn" {
  description = "IAM instance profile ARN granting EC2 access to Secrets Manager + SSM"
  type        = string
}
