##### TERRAFORM #####

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "devopsdemo-tf"
    key            = "pipeline/terraform.tfstate"
    region         = "eu-south-1"
    dynamodb_table = "devopsdemo-tf"
    encrypt        = true
  }
}

provider "aws" {
  shared_config_files = ["~/.aws/config"]
  profile = "iulian-mocanu"
  region = var.aws_region

  default_tags {
    tags = {
      Project = var.project
      IaC = "terraform"
    }
  }
}


#######################


##### CODEBUILD #####

resource "aws_codebuild_project" "main" {
  name          = "${var.project}-build"
  build_timeout = 30
  service_role  = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  cache {
    type  = "LOCAL"
    modes = ["LOCAL_DOCKER_LAYER_CACHE"]
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:6.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false

    environment_variable {
      name  = "DOCKER_CREDENTIALS_SECRET_NAME"
      value = aws_secretsmanager_secret.dockerhub.name
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "log-group"
      stream_name = "log-stream"
    }
  }

  source {
    type            = "CODEPIPELINE"
    git_clone_depth = 1
    buildspec = file("buildspec.yml")
  }
}



##### CODEPIPELINE #####


resource "aws_codepipeline" "main" {
  name = "${var.project}-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.id
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category          = "Source"
      owner             = "ThirdParty"
      provider           = "GitHub"
      input_artifacts    = []
      output_artifacts   = ["source_output"]
      version             = "1"

      configuration = {
        Owner                = var.github-owner
        Repo                 = var.github-repo
        Branch               = var.github-branch
        OAuthToken           = data.aws_secretsmanager_secret_version.github-token.secret_string
        PollForSourceChanges = "false"
      }
    }
  }

  stage {
    name = "Test-Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.main.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category         = "Deploy"
      owner            = "AWS"
      provider          = "ECS"
      input_artifacts   = ["build_output"]
      output_artifacts  = []
      version            = "1"

      # configuration = {
      #   ClusterName = data.terraform_remote_state.ecs.outputs.ecs_cluster
      #   ServiceName = data.terraform_remote_state.ecs.outputs.ecs_service
      # }
    }
  }
}

resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.project}-artifacts"
}

resource "aws_secretsmanager_secret" "dockerhub" {
  name = "${var.project}-dockerhub"
}

resource "aws_secretsmanager_secret" "github" {
  name = "${var.project}-github"
}

data "aws_secretsmanager_secret_version" "github-token" {
  secret_id = aws_secretsmanager_secret.github.id
}



##### IAM #####

resource "aws_iam_role" "codebuild" {
  name = "${var.project}-codebuild-role"
  managed_policy_arns = ["arn:aws:iam::aws:policy/AWSCodeBuildAdminAccess", "arn:aws:iam::aws:policy/SecretsManagerReadWrite"]
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${var.project}-codebuild-policy"
  role = aws_iam_role.codebuild.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          "${aws_s3_bucket.artifacts.arn}",
          "${aws_s3_bucket.artifacts.arn}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
        ]
        Resource = [
          "*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "codepipeline" {
  name = "${var.project}-codepipeline-role" 
  managed_policy_arns = ["arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess", "arn:aws:iam::aws:policy/AmazonECS_FullAccess"]
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "codepipeline" {
  name = "${var.project}-codepipeline-policy"
  role = aws_iam_role.codepipeline.name

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObjectAcl",
          "s3:PutObject",
        ],
        "Resource": [
          "${aws_s3_bucket.artifacts.arn}",
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      },
      {
        "Effect": "Allow",
        "Action": [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ],
        "Resource": "${aws_codebuild_project.main.arn}"
      },
      {
        "Effect": "Allow",
        "Action": [
          "ecs:*",
        ],
        "Resource": "*"
      }
    ]
  })
}