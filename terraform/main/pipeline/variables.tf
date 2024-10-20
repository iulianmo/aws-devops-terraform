variable "component" {
  default     = "pipeline"
}

variable "aws_region" {
  default     = "eu-south-1"
}

variable "project" {
  default     = "devopsdemo"
}

variable "github-owner" {
  default     = "iulianmo"
}

variable "github-repo" {
  default     = "devopsdemo-devops"
}

variable "github-branch" {
  default     = "main"
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

data "terraform_remote_state" "ecs" {
  backend = "s3"
  config = {
    bucket         = "devopsdemo-tf"
    key            = "ecs/terraform.tfstate"
    region         = "eu-south-1"
    dynamodb_table = "devopsdemo-tf"
  }
}