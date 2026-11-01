# O código é publicado pelo pipeline do TechChallenger-severless (ADR-002). O
# placeholder só existe para a função poder ser criada antes do primeiro deploy.
data "archive_file" "lambda_placeholder" {
  type        = "zip"
  output_path = "${path.module}/.terraform/lambda-placeholder.zip"

  source {
    filename = "index.js"
    content  = <<-EOT
      exports.handler = async () => ({
        statusCode: 503,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          code: 'SERVICO_INDISPONIVEL',
          message: 'Função ainda não publicada.',
        }),
      });
    EOT
  }
}

resource "aws_security_group" "lambda_auth" {
  name        = "${var.cluster_name}-lambda-auth"
  description = "Lambda de autenticacao: saida para o RDS e para o SSM via NAT"
  vpc_id      = module.vpc.vpc_id

  egress {
    description = "RDS PostgreSQL"
    from_port   = var.db_port
    to_port     = var.db_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "SSM Parameter Store, via NAT Gateway"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # A AWS leva até dezenas de minutos para liberar as ENIs de uma Lambda em VPC.
  timeouts {
    delete = "45m"
  }

  tags = {
    Project     = var.cluster_name
    Environment = var.environment
    Terraform   = "true"
  }
}

# Criado antes da função para o Terraform controlar a retenção. Sem isso, a Lambda
# criaria o log group sozinha, sem expiração e fora do state.
resource "aws_cloudwatch_log_group" "lambda_auth" {
  name              = "/aws/lambda/${var.cluster_name}-auth"
  retention_in_days = var.lambda_log_retention_days

  tags = {
    Project     = var.cluster_name
    Environment = var.environment
    Terraform   = "true"
  }
}

resource "aws_lambda_function" "auth" {
  function_name = "${var.cluster_name}-auth"
  description   = "Autenticação por CPF e por e-mail e senha, com refresh token"
  role          = data.aws_iam_role.lab_role.arn

  runtime       = var.lambda_runtime
  handler       = "index.handler"
  architectures = [var.lambda_architecture]
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout

  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256

  reserved_concurrent_executions = var.lambda_reserved_concurrency

  vpc_config {
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [aws_security_group.lambda_auth.id]
  }

  environment {
    variables = {
      JWT_SECRET_PARAM    = var.ssm_jwt_secret_param
      DB_PARAM_PREFIX     = var.ssm_db_param_prefix
      DB_PORT             = tostring(var.db_port)
      NODE_EXTRA_CA_CERTS = "/var/runtime/ca-cert.pem"
    }
  }

  # O código pertence ao pipeline do severless, então o Terraform não o sobrescreve.
  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  depends_on = [aws_cloudwatch_log_group.lambda_auth]

  tags = {
    Project     = var.cluster_name
    Environment = var.environment
    Terraform   = "true"
  }
}

resource "aws_apigatewayv2_integration" "lambda_auth" {
  api_id                 = aws_apigatewayv2_api.this.id
  description            = "Lambda de autenticação"
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.auth.invoke_arn
  payload_format_version = "2.0"
}

# Rotas públicas: é aqui que os tokens são obtidos. Por serem mais específicas, têm
# prioridade sobre ANY /{proxy+}.
locals {
  auth_route_keys = toset([
    "POST /auth",
    "POST /auth/login",
    "POST /auth/refresh",
    "POST /auth/logout",
  ])
}

resource "aws_apigatewayv2_route" "auth" {
  for_each = local.auth_route_keys

  api_id    = aws_apigatewayv2_api.this.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.lambda_auth.id}"
}

resource "aws_lambda_permission" "api_gateway_auth" {
  statement_id  = "AllowApiGatewayInvokeAuth"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/POST/auth*"
}
