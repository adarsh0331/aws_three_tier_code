# ── Security Groups (bare — rules added separately to avoid circular deps) ──

resource "aws_security_group" "alb_frontend" {
  name        = "${var.prefix}-alb-frontend-sg"
  description = "Internet-facing ALB: allow HTTP/HTTPS from anywhere"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.prefix}-alb-frontend-sg" }
}

resource "aws_security_group" "frontend_instance" {
  name        = "${var.prefix}-frontend-instance-sg"
  description = "Frontend EC2: allow traffic from frontend ALB only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.prefix}-frontend-instance-sg" }
}

resource "aws_security_group" "alb_backend" {
  name        = "${var.prefix}-alb-backend-sg"
  description = "Internal ALB: allow traffic from frontend instances only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.prefix}-alb-backend-sg" }
}

resource "aws_security_group" "backend_instance" {
  name        = "${var.prefix}-backend-instance-sg"
  description = "Backend EC2: allow traffic from backend ALB only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.prefix}-backend-instance-sg" }
}

resource "aws_security_group" "rds" {
  name        = "${var.prefix}-rds-sg"
  description = "RDS: allow MySQL from backend instances only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.prefix}-rds-sg" }
}

resource "aws_security_group" "bastion" {
  name        = "${var.prefix}-bastion-sg"
  description = "Bastion: allow SSH from trusted IP only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.prefix}-bastion-sg" }
}

# ── Ingress Rules ──────────────────────────────────────────────────────────

# Frontend ALB: HTTP from internet
resource "aws_security_group_rule" "alb_frontend_http_in" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb_frontend.id
  description       = "HTTP from internet"
}

# Frontend ALB: HTTPS from internet
resource "aws_security_group_rule" "alb_frontend_https_in" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb_frontend.id
  description       = "HTTPS from internet"
}

# Frontend instances: only from their ALB
resource "aws_security_group_rule" "frontend_instance_http_in" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_frontend.id
  security_group_id        = aws_security_group.frontend_instance.id
  description              = "HTTP from frontend ALB"
}

# Frontend instances: SSH from bastion only
resource "aws_security_group_rule" "frontend_instance_ssh_in" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.frontend_instance.id
  description              = "SSH from bastion"
}

# Backend ALB: only from frontend instances
resource "aws_security_group_rule" "alb_backend_http_in" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.frontend_instance.id
  security_group_id        = aws_security_group.alb_backend.id
  description              = "HTTP from frontend instances"
}

# Backend instances: only from their ALB
resource "aws_security_group_rule" "backend_instance_http_in" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_backend.id
  security_group_id        = aws_security_group.backend_instance.id
  description              = "HTTP from backend ALB"
}

# Backend instances: SSH from bastion only
resource "aws_security_group_rule" "backend_instance_ssh_in" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.backend_instance.id
  description              = "SSH from bastion"
}

# RDS: only from backend instances
resource "aws_security_group_rule" "rds_mysql_in" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.backend_instance.id
  security_group_id        = aws_security_group.rds.id
  description              = "MySQL from backend instances"
}

# Bastion: SSH from specified trusted CIDR only (NOT 0.0.0.0/0)
resource "aws_security_group_rule" "bastion_ssh_in" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.allowed_ssh_cidr]
  security_group_id = aws_security_group.bastion.id
  description       = "SSH from trusted IP only"
}

# ── Egress Rules (explicit allow-all per tier) ─────────────────────────────

resource "aws_security_group_rule" "alb_frontend_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb_frontend.id
}

resource "aws_security_group_rule" "frontend_instance_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.frontend_instance.id
}

resource "aws_security_group_rule" "alb_backend_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb_backend.id
}

# Backend egress: only to DB (3306) and AWS APIs (443) via NAT
resource "aws_security_group_rule" "backend_instance_egress_db" {
  type                     = "egress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds.id
  security_group_id        = aws_security_group.backend_instance.id
  description              = "MySQL to RDS"
}

resource "aws_security_group_rule" "backend_instance_egress_https" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.backend_instance.id
  description       = "HTTPS to AWS APIs (Secrets Manager) via NAT"
}

# RDS: no outbound needed
resource "aws_security_group_rule" "rds_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rds.id
}

resource "aws_security_group_rule" "bastion_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.bastion.id
}
