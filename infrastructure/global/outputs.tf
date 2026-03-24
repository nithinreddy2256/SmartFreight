output "ecr_repository_urls" {
  description = "Map of service name to ECR repository URL"
  value       = { for k, v in module.ecr : k => v.repository_url }
}

output "ecr_repository_arns" {
  description = "Map of service name to ECR repository ARN"
  value       = { for k, v in module.ecr : k => v.repository_arn }
}

output "public_hosted_zone_id" {
  description = "The Route53 public hosted zone ID"
  value       = aws_route53_zone.public.zone_id
}

output "public_hosted_zone_name_servers" {
  description = "The Route53 public hosted zone name servers (update your domain registrar)"
  value       = aws_route53_zone.public.name_servers
}

output "private_hosted_zone_id" {
  description = "The Route53 private hosted zone ID"
  value       = aws_route53_zone.private.zone_id
}

output "cicd_ecr_push_role_arn" {
  description = "The ARN of the IAM role for CI/CD ECR push access"
  value       = aws_iam_role.cicd_ecr_push.arn
}
