variable "frontend_alb_name" {
  description = "Name of the internet-facing frontend ALB"
  type        = string
}

variable "backend_alb_name" {
  description = "Name of the internal backend ALB"
  type        = string
}

variable "frontend_alb_sg_id" {
  description = "Security group ID for the frontend ALB"
  type        = string
}

variable "backend_alb_sg_id" {
  description = "Security group ID for the backend ALB (internal)"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the internet-facing frontend ALB"
  type        = list(string)
}

variable "backend_subnet_ids" {
  description = "Private subnet IDs for the internal backend ALB"
  type        = list(string)
}

variable "frontend_tg_name" {
  description = "Frontend target group name"
  type        = string
}

variable "backend_tg_name" {
  description = "Backend target group name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS on the frontend ALB"
  type        = string
}
