resource "aws_launch_template" "frontend_lt" {
  name          = var.frontend_lt_name
  key_name      = var.key_name
  image_id      = var.ami_id_frontend
  instance_type = var.instance_type
  user_data     = base64encode(file("${path.module}/${var.frontend_user_data}"))

  iam_instance_profile {
    arn = var.instance_profile_arn
  }

  network_interfaces {
    associate_public_ip_address = false  # frontend is in private subnet behind ALB
    security_groups             = [var.frontend_security_group_id]
    delete_on_termination       = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2 enforced
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = var.frontend_lt_name, Tier = "frontend" }
  }
}

resource "aws_launch_template" "backend_lt" {
  name          = var.backend_lt_name
  key_name      = var.key_name
  image_id      = var.ami_id_backend
  instance_type = var.instance_type
  user_data     = base64encode(file("${path.module}/${var.backend_user_data}"))

  iam_instance_profile {
    arn = var.instance_profile_arn
  }

  network_interfaces {
    associate_public_ip_address = false  # backend stays fully private
    security_groups             = [var.backend_security_group_id]
    delete_on_termination       = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2 enforced
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = var.backend_lt_name, Tier = "backend" }
  }
}
