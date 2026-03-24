variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
}

variable "environment" {
  description = "The deployment environment (dev, test, prod)"
  type        = string
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway for all private subnets (cost saving for dev)"
  type        = bool
  default     = false
}

variable "availability_zones" {
  description = "List of availability zones to use (defaults to 3)"
  type        = list(string)
  default     = []
}
