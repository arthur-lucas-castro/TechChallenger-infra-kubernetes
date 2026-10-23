output "state_bucket_name" {
  description = "Nome do bucket S3 a ser usado no bloco backend \"s3\" (chave 'bucket')."
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "ARN do bucket S3 criado para armazenar o state."
  value       = aws_s3_bucket.terraform_state.arn
}

output "lock_table_name" {
  description = "Nome da tabela DynamoDB a ser usada no bloco backend \"s3\" (chave 'dynamodb_table')."
  value       = aws_dynamodb_table.terraform_lock.name
}

output "aws_region" {
  description = "Região AWS a ser usada no bloco backend \"s3\" (chave 'region')."
  value       = var.aws_region
}
