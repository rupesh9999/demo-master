terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

# VPC and Networking
resource "aws_vpc" "backstage_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "backstage-vpc"
  }
}

resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.backstage_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "backstage-public-1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.backstage_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = true

  tags = {
    Name = "backstage-public-2"
  }
}

resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.backstage_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-2a"

  tags = {
    Name = "backstage-private-1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.backstage_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-2b"

  tags = {
    Name = "backstage-private-2"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.backstage_vpc.id

  tags = {
    Name = "backstage-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.backstage_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "backstage-public-rt"
  }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "backstage-nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet_1.id

  tags = {
    Name = "backstage-nat"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.backstage_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "backstage-private-rt"
  }
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_rt.id
}

# Security Groups
resource "aws_security_group" "alb_sg" {
  name   = "backstage-alb-sg"
  vpc_id = aws_vpc.backstage_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "backstage-alb-sg"
  }
}

resource "aws_security_group" "ecs_sg" {
  name   = "backstage-ecs-sg"
  vpc_id = aws_vpc.backstage_vpc.id

  ingress {
    from_port   = 7007
    to_port     = 7007
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow direct access from internet
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "backstage-ecs-sg"
  }
}

resource "aws_security_group" "rds_sg" {
  name   = "backstage-rds-sg"
  vpc_id = aws_vpc.backstage_vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  tags = {
    Name = "backstage-rds-sg"
  }
}

# RDS PostgreSQL
resource "aws_db_subnet_group" "backstage_db_subnet" {
  name       = "backstage-db-subnet"
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]

  tags = {
    Name = "backstage-db-subnet"
  }
}

resource "aws_db_instance" "backstage_db" {
  identifier             = "backstage-demo-db"
  engine                 = "postgres"
  engine_version         = "13.18"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "backstage"
  username               = "backstage"
  password               = random_password.db_password.result
  db_subnet_group_name   = aws_db_subnet_group.backstage_db_subnet.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
  publicly_accessible    = false

  tags = {
    Name = "backstage-demo-db"
  }
}

resource "random_password" "db_password" {
  length  = 16
  special = true
}

# ECR Repository
resource "aws_ecr_repository" "backstage_repo" {
  name                 = "backstage-demo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "backstage-demo"
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "backstage_cluster" {
  name = "backstage-demo-cluster"

  tags = {
    Name = "backstage-demo-cluster"
  }
}

# IAM Roles
resource "aws_iam_role" "ecs_execution_role" {
  name = "backstage-ecs-execution-role"

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

  tags = {
    Name = "backstage-ecs-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Custom policy for Secrets Manager access
resource "aws_iam_role_policy" "ecs_execution_secrets_policy" {
  name = "backstage-ecs-execution-secrets-policy"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.db_password.arn,
          aws_secretsmanager_secret.github_token.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task_role" {
  name = "backstage-ecs-task-role"

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

  tags = {
    Name = "backstage-ecs-task-role"
  }
}

# Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name = "backstage/db-password"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}

resource "aws_secretsmanager_secret" "github_token" {
  name = "backstage/github-token"
}

resource "aws_secretsmanager_secret_version" "github_token" {
  secret_id     = aws_secretsmanager_secret.github_token.id
  secret_string = var.github_token
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "backstage_logs" {
  name              = "/ecs/backstage-demo"
  retention_in_days = 30

  tags = {
    Name = "backstage-demo-logs"
  }
}

# ALB - Commented out due to account limitations
# resource "aws_lb" "backstage_alb" {
#   name               = "backstage-demo-alb"
#   internal           = false
#   load_balancer_type = "application"
#   security_groups    = [aws_security_group.alb_sg.id]
#   subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]

#   tags = {
#     Name = "backstage-demo-alb"
#   }
# }

# resource "aws_lb_target_group" "backstage_tg" {
#   name        = "backstage-demo-tg"
#   port        = 7007
#   protocol    = "HTTP"
#   vpc_id      = aws_vpc.backstage_vpc.id
#   target_type = "ip"

#   health_check {
#     path                = "/api/healthcheck"
#     healthy_threshold   = 2
#     unhealthy_threshold = 10
#     timeout             = 60
#     interval            = 300
#     matcher             = "200"
#   }

#   tags = {
#     Name = "backstage-demo-tg"
#   }
# }

# resource "aws_lb_listener" "backstage_listener" {
#   load_balancer_arn = aws_lb.backstage_alb.arn
#   port              = "80"
#   protocol          = "HTTP"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.backstage_tg.arn
#   }
# }

# ECS Task Definition
resource "aws_ecs_task_definition" "backstage_task" {
  family                   = "backstage-demo"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "backstage"
      image = "${aws_ecr_repository.backstage_repo.repository_url}:latest"
      portMappings = [
        {
          containerPort = 7007
          hostPort      = 7007
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        },
        {
          name  = "POSTGRES_HOST"
          value = aws_db_instance.backstage_db.address
        },
        {
          name  = "POSTGRES_PORT"
          value = "5432"
        },
        {
          name  = "POSTGRES_USER"
          value = aws_db_instance.backstage_db.username
        },
        {
          name  = "POSTGRES_DB"
          value = aws_db_instance.backstage_db.db_name
        },
        {
          name  = "ENVIRONMENT_CONFIG"
          value = "production"
        }
      ]
      secrets = [
        {
          name      = "POSTGRES_PASSWORD"
          valueFrom = aws_secretsmanager_secret.db_password.arn
        },
        {
          name      = "GITHUB_TOKEN"
          valueFrom = aws_secretsmanager_secret.github_token.arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backstage_logs.name
          "awslogs-region"        = "us-east-2"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Name = "backstage-demo-task"
  }
}

# ECS Service - Modified to use public IP instead of ALB
resource "aws_ecs_service" "backstage_service" {
  name            = "backstage-demo-service"
  cluster         = aws_ecs_cluster.backstage_cluster.id
  task_definition = aws_ecs_task_definition.backstage_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_subnet_1.id]  # Use public subnet
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true  # Enable public IP
  }

  # Remove load_balancer block since we're not using ALB

  tags = {
    Name = "backstage-demo-service"
  }
}

# Outputs
output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.backstage_repo.repository_url
}

output "database_endpoint" {
  description = "Database endpoint"
  value       = aws_db_instance.backstage_db.endpoint
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.backstage_cluster.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.backstage_service.name
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.backstage_vpc.id
}