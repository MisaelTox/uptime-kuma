provider "aws" {
  region = var.region
}

# --- Networking ---
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0" # Pinning version is recommended

  name = "uptime_kuma_vpc"
  cidr = "10.1.0.0/16"

  azs            = ["${var.region}a", "${var.region}b"]
  public_subnets = ["10.1.1.0/24", "10.1.2.0/24"]

  # Required for public IP assignment
  create_igw         = true
  enable_nat_gateway = false # NAT Gateway not needed here, saves cost
}

# --- Storage (EFS) ---
resource "aws_efs_file_system" "kuma_data" {
  creation_token = "kuma-data"
  tags           = { Name = "UptimeKumaData" }
}

resource "aws_efs_mount_target" "kuma_mount" {
  count           = 2
  file_system_id  = aws_efs_file_system.kuma_data.id
  subnet_id       = module.vpc.public_subnets[count.index]
  security_groups = [aws_security_group.kuma_sg.id]
}

# --- Security ---
resource "aws_security_group" "kuma_sg" {
  name   = "kuma_sg"
  vpc_id = module.vpc.vpc_id

  # Allow web traffic
  ingress {
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow EFS communication within the security group
  ingress {
    from_port = 2049
    to_port   = 2049
    protocol  = "tcp"
    self      = true # Allows resources sharing this SG to communicate
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- Notifications (SNS) ---
resource "aws_sns_topic" "alerts" {
  name = "kuma-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.user_email
}

# --- Compute (ECS Fargate) ---
resource "aws_ecs_cluster" "kuma_cluster" {
  name = "kuma_cluster"
}

resource "aws_ecs_task_definition" "kuma_task" {
  family                   = "kuma-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256" # Smaller = cheaper
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_role.arn

  container_definitions = jsonencode([{
    name         = "uptime-kuma"
    image        = "louislam/uptime-kuma:1"
    portMappings = [{ containerPort = 3001, hostPort = 3001 }]
    mountPoints  = [{ containerPath = "/app/data", sourceVolume = "kuma-storage" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/kuma"
        awslogs-region        = var.region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])

  volume {
    name = "kuma-storage"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.kuma_data.id
    }
  }
}

resource "aws_ecs_service" "kuma_service" {
  name                              = "kuma_service"
  cluster                           = aws_ecs_cluster.kuma_cluster.id
  task_definition                   = aws_ecs_task_definition.kuma_task.arn
  desired_count                     = 1
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 300 # Allow 5 minutes for the container to start

  network_configuration {
    subnets          = module.vpc.public_subnets
    security_groups  = [aws_security_group.kuma_sg.id]
    assign_public_ip = true
  }
}

# --- Monitoring (CPU Alert) ---
resource "aws_cloudwatch_metric_alarm" "cpu_alarm" {
  alarm_name          = "Kuma-High-CPU"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = {
    ClusterName = aws_ecs_cluster.kuma_cluster.name
    ServiceName = aws_ecs_service.kuma_service.name
  }
}

# IAM Roles for ECS task execution
resource "aws_iam_role" "ecs_role" {
  name = "kuma_ecs_role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_policy" {
  role       = aws_iam_role.ecs_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_cloudwatch_log_group" "kuma_logs" {
  name = "/ecs/kuma"
}

# ECR Repository for Uptime Kuma Docker image
resource "aws_ecr_repository" "uptime_kuma" {
  name                 = "uptime-kuma"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project     = "uptime-kuma"
    ManagedBy   = "terraform"
    Environment = "production"
  }
}