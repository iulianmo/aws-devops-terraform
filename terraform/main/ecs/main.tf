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
    key            = "ecs/terraform.tfstate"
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

##### ECS #####

resource "aws_ecs_cluster" "main" {
  name = "${var.project}-cluster"
}

resource "aws_ecs_service" "main" {
  name            = var.project
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_capacity

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs.arn
    container_name   = var.project
    container_port   = var.ecs-port
  }
}

resource "aws_ecs_task_definition" "main" {
  family                   = var.project
  requires_compatibilities = ["EC2"]
  cpu                      = var.ecs-cpu
  memory                   = var.ecs-memory
  network_mode             = "host"
  execution_role_arn       = aws_iam_role.ecs.arn
  task_role_arn            = aws_iam_role.ecs.arn

  container_definitions = jsonencode([
    {
      "name": var.project,
      "image": var.image_uri,
      "essential": true,
      "secrets": [
        {
          "name": "PG_HOST",
          "valueFrom": aws_secretsmanager_secret.postgres.arn
        },
        {
          "name": "PG_PORT",
          "valueFrom": aws_secretsmanager_secret.postgres.arn
        },
        {
          "name": "PG_USER",
          "valueFrom": aws_secretsmanager_secret.postgres.arn
        },
        {
          "name": "PG_PASSWORD",
          "valueFrom": aws_secretsmanager_secret.postgres.arn
        },
        {
          "name": "PG_DB",
          "valueFrom": aws_secretsmanager_secret.postgres.arn
        }
      ],
      "portMappings": [
        {
          "containerPort": var.ecs-port,
          "hostPort": var.ecs-port,
          "protocol": "tcp"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-create-group": "true",
          "awslogs-group": aws_cloudwatch_log_group.main.name,
          "awslogs-region": var.aws_region,
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ])
}

resource "aws_cloudwatch_log_group" "main" {
  name = "/ecs/${var.project}"
}

resource "aws_iam_role" "ecs" {
  name = "${var.project}-ecs-role"
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "secrets" {
  name  = "${var.project}-secrets-manager-access-policy"
  role = aws_iam_role.ecs.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "${aws_secretsmanager_secret.postgres.arn}"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "ecs-instances" {
  name = "${var.project}-ecs-instances-role"
  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore", "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role", "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy", "arn:aws:iam::aws:policy/SecretsManagerReadWrite"]
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs-instances" {
  name = "${var.project}-ecs-instances-policy"
  role = aws_iam_role.ecs-instances.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codepipeline:StartPipelineExecution"
        ]
        Resource = [
          "*"
        ]
      }
    ]
  })
}


resource "aws_iam_instance_profile" "ecs-instances" {
  name = "${var.project}-instance-profile"
  role = aws_iam_role.ecs-instances.name
}

resource "aws_launch_template" "ecs-lt" {
  name_prefix   = "${var.project}-ecs-lt"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  vpc_security_group_ids = [ aws_security_group.ecs.id ]

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs-instances.name
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 30
      volume_type = "gp3"
      encrypted   = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project}-ecs"
    }
  }  
  
  user_data = base64encode(templatefile("${path.module}/user-data.tpl", {
    aws_region = var.aws_region
    ecs_cluster_name = aws_ecs_cluster.main.name
    postgres_secret_name = aws_secretsmanager_secret.postgres.name
  }))
}

resource "aws_autoscaling_group" "ecs-instances" {
  name = "${var.project}-ecs"
  vpc_zone_identifier = [for subnet in data.terraform_remote_state.vpc.outputs.private_subnet_ids : subnet]
  desired_capacity    = var.desired_capacity
  max_size            = 1
  min_size            = 0

  launch_template {
    id      = aws_launch_template.ecs-lt.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  } 
}

resource "aws_secretsmanager_secret" "postgres" {
  name = "${var.project}-postgres"
}



##### APPLIACTION LOAD BALANCER #####

resource "aws_lb_target_group" "ecs" {
  name        = "${var.project}-ecs-tg"
  port        = var.ecs-port
  protocol    = "HTTP"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id
  target_type = "instance"


  health_check {
    path                = "/actuator/health"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 10
    interval            = 30
    matcher             = "200"
  }
}

resource "aws_lb" "ecs" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.terraform_remote_state.vpc.outputs.public_subnet_ids
}

resource "aws_lb_listener" "ecs-listener" {
  load_balancer_arn = aws_lb.ecs.arn
  port              = var.alb-port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs.arn
  }
}



##### SECURITY GROUPS #####

resource "aws_security_group" "ecs" {
  name = "${var.project}-ecs-service-sg"
  vpc_id = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    from_port = var.ecs-port
    to_port = var.ecs-port
    protocol = "tcp"
    cidr_blocks = [data.terraform_remote_state.vpc.outputs.vpc_cidr]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name =  "${var.project}-ecs-service-sg"
  }
}

resource "aws_security_group" "ecs-instances" {
  name = "${var.project}-ecs-instance-sg"
  vpc_id = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    from_port = var.ecs-port
    to_port = var.ecs-port
    protocol = "tcp"
    cidr_blocks = [data.terraform_remote_state.vpc.outputs.vpc_cidr]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name =  "${var.project}-ecs-instance-sg"
  }
}

resource "aws_security_group" "alb" {
  name   = "${var.project}-alb-sg"
  vpc_id = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    from_port   = var.alb-port
    to_port     = var.alb-port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags = {
    Name =  "${var.project}-alb-sg"
  }
}