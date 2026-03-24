output "alb_id" {
  description = "The ID of the ALB"
  value       = aws_lb.this.id
}

output "alb_arn" {
  description = "The ARN of the ALB"
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "The ARN suffix of the ALB (used for CloudWatch metrics)"
  value       = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  description = "The DNS name of the ALB"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "The canonical hosted zone ID of the ALB (for Route53 alias records)"
  value       = aws_lb.this.zone_id
}

output "security_group_id" {
  description = "The ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "http_listener_arn" {
  description = "The ARN of the HTTP listener"
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "The ARN of the HTTPS listener (empty if no certificate is configured)"
  value       = local.use_https ? aws_lb_listener.https[0].arn : ""
}

output "target_group_arns" {
  description = "Map of target group name to ARN"
  value       = { for k, v in aws_lb_target_group.this : k => v.arn }
}

output "target_group_arn_suffixes" {
  description = "Map of target group name to ARN suffix (for CloudWatch metrics)"
  value       = { for k, v in aws_lb_target_group.this : k => v.arn_suffix }
}
