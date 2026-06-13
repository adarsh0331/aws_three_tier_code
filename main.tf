terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # ── Remote State ────────────────────────────────────────────────────────
  # Run scripts/bootstrap-tf-state.sh ONCE to create the S3 bucket and
  # DynamoDB lock table. The script prints the exact values to substitute.
  # After substituting ACCOUNT_ID below, run: terraform init -migrate-state
  #
  backend "s3" {
    bucket         = "bookstore-terraform-state-ACCOUNT_ID"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "bookstore"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ── Input Variables ────────────────────────────────────────────────────────

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "allowed_ssh_cidr" {
  description = "Your IP/32 for bastion SSH. Example: '1.2.3.4/32'. Never 0.0.0.0/0."
  type        = string
}

# ── Networking ─────────────────────────────────────────────────────────────

module "network" {
  source   = "./modules/network"
  vpc_cidr = "170.20.0.0/16"

  public_subnets = [
    { cidr = "170.20.1.0/24", az = "us-east-1a" },
    { cidr = "170.20.2.0/24", az = "us-east-1b" }
  ]

  private_subnets = [
    { cidr = "170.20.3.0/24", az = "us-east-1a" },  # [0] frontend instances
    { cidr = "170.20.4.0/24", az = "us-east-1b" },  # [1] frontend instances
    { cidr = "170.20.5.0/24", az = "us-east-1a" },  # [2] backend instances
    { cidr = "170.20.6.0/24", az = "us-east-1b" },  # [3] backend instances
    { cidr = "170.20.7.0/24", az = "us-east-1a" },  # [4] RDS
    { cidr = "170.20.8.0/24", az = "us-east-1b" },  # [5] RDS
  ]
}

output "vpc_id" {
  value = module.network.vpc_id
}

# ── Security Groups ────────────────────────────────────────────────────────

module "security_groups" {
  source           = "./modules/security"
  vpc_id           = module.network.vpc_id
  prefix           = "bookstore"
  allowed_ssh_cidr = var.allowed_ssh_cidr
}

output "alb_frontend_sg_id"      { value = module.security_groups.alb_frontend_sg_id }
output "backend_instance_sg_id"  { value = module.security_groups.backend_instance_sg_id }

# ── ACM Certificate ────────────────────────────────────────────────────────

module "acm" {
  source      = "./modules/acm"
  domain_name = "b17facebook.xyz"
  san_names   = ["*.b17facebook.xyz"]
}

# ── IAM Instance Profile (EC2 → Secrets Manager + SSM) ────────────────────

resource "aws_iam_role" "ec2_app_role" {
  name = "bookstore-ec2-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Secrets Manager: read DB credentials
resource "aws_iam_role_policy" "ec2_secrets" {
  name = "bookstore-ec2-secrets-policy"
  role = aws_iam_role.ec2_app_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = module.rds.master_user_secret_arn
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/bookstore/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "*"
        Condition = {
          StringLike = {
            "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_app" {
  name = "bookstore-ec2-instance-profile"
  role = aws_iam_role.ec2_app_role.name
}

# Store the RDS secret ARN in SSM so backend.sh can look it up at boot
resource "aws_ssm_parameter" "rds_secret_arn" {
  name  = "/bookstore/rds/secret-arn"
  type  = "String"
  value = module.rds.master_user_secret_arn

  depends_on = [module.rds]
}

# ── RDS ────────────────────────────────────────────────────────────────────

module "rds" {
  source               = "./modules/rds"
  db_identifier        = "bookstore-db"
  db_engine            = "mysql"
  db_engine_version    = "8.0"
  db_instance_class    = "db.t3.micro"
  db_allocated_storage = 25
  db_name              = "test"
  db_username          = "admin"
  db_security_group_id = module.security_groups.rds_sg_id
  db_subnet_ids        = [
    module.network.private_subnet_ids[4],
    module.network.private_subnet_ids[5],
  ]
  multi_az                = true
  backup_retention_period = 7
  deletion_protection     = true
}

output "rds_endpoint" {
  value = module.rds.rds_endpoint
}

output "rds_secret_arn" {
  value     = module.rds.master_user_secret_arn
  sensitive = true
}

# ── Load Balancers ─────────────────────────────────────────────────────────

module "alb" {
  source             = "./modules/load_balancers"
  frontend_alb_name  = "bookstore-frontend-alb"
  backend_alb_name   = "bookstore-backend-alb"
  frontend_alb_sg_id = module.security_groups.alb_frontend_sg_id
  backend_alb_sg_id  = module.security_groups.alb_backend_sg_id
  public_subnet_ids  = module.network.public_subnet_ids
  backend_subnet_ids = [
    module.network.private_subnet_ids[2],
    module.network.private_subnet_ids[3],
  ]
  frontend_tg_name    = "bookstore-frontend-tg"
  backend_tg_name     = "bookstore-backend-tg"
  vpc_id              = module.network.vpc_id
  acm_certificate_arn = module.acm.acm_certificate_arn
}

# ── Launch Templates ───────────────────────────────────────────────────────

module "launch_templates" {
  source                    = "./modules/launch_templates"
  frontend_lt_name          = "bookstore-frontend-lt"
  backend_lt_name           = "bookstore-backend-lt"
  key_name                  = "madhu"
  ami_id_frontend           = "ami-026ff2aed0f235b98"
  ami_id_backend            = "ami-0cf6e84dc7d56f9d1"
  instance_type             = "t3.micro"
  frontend_user_data        = "frontend.sh"
  backend_user_data         = "backend.sh"
  frontend_security_group_id = module.security_groups.frontend_instance_sg_id
  backend_security_group_id  = module.security_groups.backend_instance_sg_id
  instance_profile_arn       = aws_iam_instance_profile.ec2_app.arn
}

# ── Auto Scaling Groups ────────────────────────────────────────────────────

module "autoscaling" {
  source               = "./modules/asg"
  frontend_asg_name    = "bookstore-frontend-asg"
  backend_asg_name     = "bookstore-backend-asg"
  asg_min_size         = 2
  asg_max_size         = 4
  asg_desired_capacity = 2
  frontend_subnet_ids  = [
    module.network.private_subnet_ids[0],
    module.network.private_subnet_ids[1],
  ]
  backend_subnet_ids  = [
    module.network.private_subnet_ids[2],
    module.network.private_subnet_ids[3],
  ]
  frontend_tg_arn  = module.alb.frontend_tg_arn
  backend_tg_arn   = module.alb.backend_tg_arn
  frontend_lt_id   = module.launch_templates.frontend_lt_id
  backend_lt_id    = module.launch_templates.backend_lt_id
}

# ── Bastion ────────────────────────────────────────────────────────────────

module "bastion" {
  source            = "./modules/bastion"
  ami_id            = "ami-0c3389a4fa5bddaad"
  instance_type     = "t3.micro"
  key_name          = "madhu"
  public_subnet_id  = module.network.public_subnet_ids[0]
  security_group_id = module.security_groups.bastion_sg_id
}

output "bastion_ip" {
  value = module.bastion.bastion_public_ip
}

# ── Route 53 ───────────────────────────────────────────────────────────────

module "route53" {
  source             = "./modules/route53"
  vpc_id             = module.network.vpc_id
  rds_endpoint       = module.rds.rds_endpoint
  alb_dns_name       = module.alb.alb_backend_dns
  alb_front_dns_name = module.alb.alb_frontend_dns
}

# ── ECR ────────────────────────────────────────────────────────────────────

module "ecr" {
  source                = "./modules/ecr"
  prefix                = "bookstore"
  image_retention_count = 10
}

output "frontend_repo_url" { value = module.ecr.frontend_repo_url }
output "backend_repo_url"  { value = module.ecr.backend_repo_url }

# ── EKS ────────────────────────────────────────────────────────────────────

module "eks" {
  source          = "./modules/eks"
  cluster_name    = "bookstore-eks"
  cluster_version = "1.29"
  prefix          = "bookstore"
  vpc_id          = module.network.vpc_id

  # Reuse the four private subnets already allocated for frontend + backend EC2
  subnet_ids = [
    module.network.private_subnet_ids[0],
    module.network.private_subnet_ids[1],
    module.network.private_subnet_ids[2],
    module.network.private_subnet_ids[3],
  ]

  node_instance_type = "t3.medium"
  node_min_size      = 2
  node_max_size      = 4
  node_desired_size  = 2
}

output "eks_cluster_name"     { value = module.eks.cluster_name }
output "eks_cluster_endpoint" { value = module.eks.cluster_endpoint }
output "eks_oidc_provider_arn" { value = module.eks.oidc_provider_arn }
