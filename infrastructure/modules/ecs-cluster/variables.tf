variable "cluster_name" {
  description = "The name of the ECS cluster"
  type        = string
}

variable "environment" {
  description = "The deployment environment (dev, test, prod)"
  type        = string
}
