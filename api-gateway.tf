resource "aws_apigatewayv2_api" "this" {
  name          = "${var.cluster_name}-gateway"
  protocol_type = "HTTP"
  description   = "Porta de entrada da API da oficina: rotas de autenticação (Lambda) e API no EKS (VPC Link)"

  tags = {
    Project     = var.cluster_name
    Environment = var.environment
    Terraform   = "true"
  }
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.cluster_name}-gateway"
  retention_in_days = var.api_gateway_log_retention_days

  tags = {
    Project     = var.cluster_name
    Environment = var.environment
    Terraform   = "true"
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    detailed_metrics_enabled = true
    throttling_rate_limit    = var.api_gateway_throttling_rate_limit
    throttling_burst_limit   = var.api_gateway_throttling_burst_limit
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId          = "$context.requestId"
      requestTime        = "$context.requestTime"
      ip                 = "$context.identity.sourceIp"
      httpMethod         = "$context.httpMethod"
      path               = "$context.path"
      routeKey           = "$context.routeKey"
      status             = "$context.status"
      responseLength     = "$context.responseLength"
      responseLatency    = "$context.responseLatency"
      integrationLatency = "$context.integration.latency"
      integrationStatus  = "$context.integration.status"
      integrationError   = "$context.integrationErrorMessage"
      authorizerError    = "$context.authorizer.error"
      userAgent          = "$context.identity.userAgent"
    })
  }

  tags = {
    Project     = var.cluster_name
    Environment = var.environment
    Terraform   = "true"
  }
}

resource "aws_security_group" "vpc_link" {
  name        = "${var.cluster_name}-apigw-vpc-link"
  description = "ENIs do VPC Link do API Gateway: saida apenas para o NLB interno da API"
  vpc_id      = module.vpc.vpc_id

  egress {
    description = "Listener do NLB interno da API"
    from_port   = var.api_listener_port
    to_port     = var.api_listener_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Project     = var.cluster_name
    Environment = var.environment
    Terraform   = "true"
  }
}

resource "aws_apigatewayv2_vpc_link" "eks" {
  name               = "${var.cluster_name}-eks"
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [aws_security_group.vpc_link.id]

  tags = {
    Project     = var.cluster_name
    Environment = var.environment
    Terraform   = "true"
  }
}

resource "aws_apigatewayv2_integration" "eks" {
  api_id             = aws_apigatewayv2_api.this.id
  description        = "API da oficina no EKS, via VPC Link + NLB interno"
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = aws_lb_listener.api.arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.eks.id

  # Mesmo id dos access logs do gateway, para correlacionar com os logs da API.
  request_parameters = {
    "overwrite:header.x-correlation-id" = "$context.requestId"
  }
}

# Sem authorizer por enquanto: o Lambda Authorizer e as rotas POST /auth* entram
# junto com a infraestrutura das Lambdas (ADR-002). Até lá a proteção das rotas
# é feita só pelo middleware JWT da API.
resource "aws_apigatewayv2_route" "eks_proxy" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.eks.id}"
}
