# Outputs for ECS Databricks Application

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.app.repository_url
}

output "load_balancer_dns" {
  description = "Load balancer DNS name"
  value       = aws_lb.main.dns_name
}

output "application_url" {
  description = "Application URL (HTTP via ALB - for direct access)"
  value       = "http://${aws_lb.main.dns_name}"
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.app.name
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.app.name
}

output "allowed_ips" {
  description = "Currently allowed IP addresses"
  value       = var.allowed_ips
}

# CodeBuild outputs
output "codebuild_project_name" {
  description = "Name of the CodeBuild project for Docker image builds"
  value       = aws_codebuild_project.app_build.name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild project"
  value       = aws_codebuild_project.app_build.arn
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.app.arn
}