variable "component" {
  default     = "vpc"
}

variable "aws_region" {
  default     = "eu-south-1"
}

variable "project" {
  default     = "devopsdemo"
}

variable "vpc_cidr" {
  default     = "10.0.0.0/24"
}

variable "public_subnets_cidr" {
  default     = ["10.0.0.0/26", "10.0.0.64/26"]
}

variable "private_subnets_cidr" {
  default     = ["10.0.0.128/26", "10.0.0.192/26"]
}