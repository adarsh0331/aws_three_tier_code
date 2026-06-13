output "alb_frontend_sg_id" {
  description = "SG for internet-facing frontend ALB"
  value       = aws_security_group.alb_frontend.id
}

output "frontend_instance_sg_id" {
  description = "SG for frontend EC2 instances"
  value       = aws_security_group.frontend_instance.id
}

output "alb_backend_sg_id" {
  description = "SG for internal backend ALB"
  value       = aws_security_group.alb_backend.id
}

output "backend_instance_sg_id" {
  description = "SG for backend EC2 instances"
  value       = aws_security_group.backend_instance.id
}

output "rds_sg_id" {
  description = "SG for RDS — only MySQL from backend instances"
  value       = aws_security_group.rds.id
}

output "bastion_sg_id" {
  description = "SG for bastion host"
  value       = aws_security_group.bastion.id
}
