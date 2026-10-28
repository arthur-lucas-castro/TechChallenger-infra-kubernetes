# O nome de bucket S3 é global: o sufixo com o ID da conta evita colisão com
# nomes de contas anteriores do Learner Lab que a AWS ainda não liberou.
data "aws_caller_identity" "current" {}

locals {
  state_bucket_name = "${var.project_name}-terraform-state-${data.aws_caller_identity.current.account_id}"
}

# O bucket é criado pela CLI, e não por aws_s3_bucket: o provider lê a
# configuração de Object Lock a cada refresh, e a SCP do Learner Lab nega
# s3:GetBucketObjectLockConfiguration. Sem destroy de propósito: o bucket guarda
# o state de todos os repositórios.
resource "terraform_data" "terraform_state_bucket" {
  input = local.state_bucket_name

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      aws s3api head-bucket --bucket "${local.state_bucket_name}" 2>/dev/null || aws s3api create-bucket --bucket "${local.state_bucket_name}" --region "${var.aws_region}"
    EOT
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = terraform_data.terraform_state_bucket.output

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = terraform_data.terraform_state_bucket.output

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = terraform_data.terraform_state_bucket.output

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_lock" {
  name         = "${var.project_name}-terraform-lock-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
