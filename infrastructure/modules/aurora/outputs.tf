output "cluster_id" {
  description = "The ID of the Aurora cluster"
  value       = aws_rds_cluster.this.id
}

output "cluster_arn" {
  description = "The ARN of the Aurora cluster"
  value       = aws_rds_cluster.this.arn
}

output "cluster_identifier" {
  description = "The identifier of the Aurora cluster"
  value       = aws_rds_cluster.this.cluster_identifier
}

output "cluster_endpoint" {
  description = "The writer endpoint of the Aurora cluster"
  value       = aws_rds_cluster.this.endpoint
}

output "cluster_reader_endpoint" {
  description = "The reader endpoint of the Aurora cluster"
  value       = aws_rds_cluster.this.reader_endpoint
}

output "cluster_port" {
  description = "The port of the Aurora cluster"
  value       = aws_rds_cluster.this.port
}

output "database_name" {
  description = "The name of the initial database"
  value       = aws_rds_cluster.this.database_name
}

output "security_group_id" {
  description = "The ID of the Aurora security group"
  value       = aws_security_group.aurora.id
}

output "subnet_group_name" {
  description = "The name of the DB subnet group"
  value       = aws_db_subnet_group.this.name
}

output "master_credentials_secret_arn" {
  description = "The ARN of the Secrets Manager secret containing master credentials"
  value       = aws_secretsmanager_secret.master_credentials.arn
}

output "master_credentials_secret_name" {
  description = "The name of the Secrets Manager secret containing master credentials"
  value       = aws_secretsmanager_secret.master_credentials.name
}

output "instance_ids" {
  description = "List of Aurora instance IDs"
  value       = aws_rds_cluster_instance.this[*].id
}
