resource "aws_lb" "api" {
  name               = "${var.cluster_name}-api"
  internal           = true
  load_balancer_type = "network"
  subnets            = module.vpc.private_subnets

  enable_cross_zone_load_balancing = true

  tags = {
    Project     = var.cluster_name
    Environment = var.environment
    Terraform   = "true"
  }
}

resource "aws_lb_target_group" "api" {
  name                 = "${var.cluster_name}-api"
  port                 = var.api_node_port
  protocol             = "TCP"
  target_type          = "instance"
  vpc_id               = module.vpc.vpc_id
  deregistration_delay = 30

  health_check {
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = var.api_health_check_path
    matcher             = "200-399"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Project     = var.cluster_name
    Environment = var.environment
    Terraform   = "true"
  }
}

resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.api.arn
  port              = var.api_listener_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  tags = {
    Project     = var.cluster_name
    Environment = var.environment
    Terraform   = "true"
  }
}

# Registra os nodes do EKS no target group: todo node que o ASG do node group
# criar (inclusive pelo scaling) entra automaticamente no NLB.
resource "aws_autoscaling_attachment" "api" {
  autoscaling_group_name = aws_eks_node_group.default.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.api.arn
}

# NLB sem security group preserva o IP de origem em targets do tipo instance:
# os nodes recebem tráfego dos ENIs do VPC Link e dos health checks do NLB,
# todos dentro da VPC.
resource "aws_vpc_security_group_ingress_rule" "nodes_api_node_port" {
  security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description       = "NodePort da API a partir do NLB interno e do VPC Link do API Gateway"
  cidr_ipv4         = var.vpc_cidr
  from_port         = var.api_node_port
  to_port           = var.api_node_port
  ip_protocol       = "tcp"
}
