# Mesmo bucket e tabela de lock da raiz (ver ../backend.tf), com key própria: dashboard e
# monitores podem ser recriados sem tocar na VPC, no EKS ou na Lambda.
terraform {
  backend "s3" {
    bucket         = "techchallenger-fase1-terraform-state-859733682813"
    key            = "observability/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "techchallenger-fase1-terraform-lock-shared"
    encrypt        = true
  }
}
