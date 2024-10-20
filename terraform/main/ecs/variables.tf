variable "component" {
  default     = "ecs"
}

variable "aws_region" {
  default     = "eu-south-1"
}

variable "project" {
  default     = "devopsdemo"
}

variable "image_uri" {
  default     = "docker.io/iulianmo/devopsdemo:latest"
}

variable "ecs-port" {
  default     = 8080
}

variable "alb-port" {
  default     = 80
}

variable "ecs-cpu" {
  default     = "512"
}

variable "ecs-memory" {
  default     = "1024"
}

variable "ami_id" {
  default     = "ami-03d4af54ef9165da7"
}

variable "instance_type" {
  default     = "t3.medium"
}

variable "key_name" {
  default     = "devopsdemo-ecs-instances"
}

variable "desired_capacity" {
  default     = 1
}

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket         = "devopsdemo-tf"
    key            = "vpc/terraform.tfstate"
    region         = "eu-south-1"
    dynamodb_table = "devopsdemo-tf"
  }
}