resource "aws_ecr_repository" "app" {
  name = var.ecr_repository_name

  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project     = var.cluster_name
    Environment = var.environment
    Terraform   = "true"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Manter apenas as últimas 2 imagens"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 2
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
