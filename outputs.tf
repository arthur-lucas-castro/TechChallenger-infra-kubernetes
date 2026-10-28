output "vpc_id" {
  description = "ID da VPC criada."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas (nodes do EKS; consumidas também pelo RDS e pela Lambda)."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "IDs das subnets públicas (load balancer)."
  value       = module.vpc.public_subnets
}

output "eks_cluster_name" {
  description = "Nome do cluster EKS."
  value       = aws_eks_cluster.this.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint da API do cluster EKS. Necessário para configurar o kubectl."
  value       = aws_eks_cluster.this.endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "Certificate authority (base64) do cluster EKS, usado para configurar o kubectl."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "eks_cluster_security_group_id" {
  description = "ID do security group primário do cluster EKS, usado pelos nodes (consumido pelo repositório infra-database como origem permitida no SG do RDS)."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "ecr_repository_url" {
  description = "URL do repositório ECR, usada no docker build/push e no manifesto do Kubernetes."
  value       = aws_ecr_repository.app.repository_url
}

output "lab_role_arn" {
  description = "ARN da LabRole (AWS Academy Learner Lab), reaproveitada pelo control plane e pelo node group do EKS em vez de roles criadas pelo Terraform."
  value       = data.aws_iam_role.lab_role.arn
}

output "api_gateway_id" {
  description = "ID do API Gateway (HTTP API)."
  value       = aws_apigatewayv2_api.this.id
}

output "api_gateway_endpoint" {
  description = "URL pública do API Gateway, porta de entrada da API da oficina (stage $default, sem prefixo)."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "api_gateway_vpc_link_id" {
  description = "ID do VPC Link que liga o API Gateway ao NLB interno da API."
  value       = aws_apigatewayv2_vpc_link.eks.id
}

output "api_nlb_dns_name" {
  description = "DNS do NLB interno da API (só acessível de dentro da VPC)."
  value       = aws_lb.api.dns_name
}

output "api_node_port" {
  description = "NodePort que o Service da API precisa declarar no service.yaml do TechChallenger-Api."
  value       = var.api_node_port
}
