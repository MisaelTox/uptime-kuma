provider "aws" {
  region = var.region
}

# --- REDES ---
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0" # Es buena práctica fijar la versión

  name = "uptime_kuma_vpc"
  cidr = "10.1.0.0/16"

  azs            = ["${var.region}a", "${var.region}b"]
  public_subnets = ["10.1.1.0/24", "10.1.2.0/24"]

  # ESTO ES LO QUE FALTA PARA QUE LA IP FUNCIONE:
  create_igw         = true
  enable_nat_gateway = false # No lo necesitas para esto y cuesta dinero
}

# --- ALMACENAMIENTO (EFS) ---
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

# --- SEGURIDAD ---
resource "aws_security_group" "kuma_sg" {
  name   = "kuma_sg"
  vpc_id = module.vpc.vpc_id

  # Regla para la web
  ingress {
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NUEVA REGLA: Permite que el contenedor hable con el disco EFS
  ingress {
    from_port = 2049
    to_port   = 2049
    protocol  = "tcp"
    self      = true # Esto permite que los recursos con este mismo SG se hablen entre sí
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- NOTIFICACIONES (SNS) ---
resource "aws_sns_topic" "alerts" {
  name = "kuma-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.user_email
}

# --- CÓMPUTO (ECS FARGATE) ---
resource "aws_ecs_cluster" "kuma_cluster" {
  name = "kuma_cluster"
}

resource "aws_ecs_task_definition" "kuma_task" {
  family                   = "kuma-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256" # Más pequeño = más barato
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_role.arn

  container_definitions = jsonencode([{
    name  = "uptime-kuma"
    image = "louislam/uptime-kuma:1"
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
  name            = "kuma_service"
  cluster         = aws_ecs_cluster.kuma_cluster.id
  task_definition = aws_ecs_task_definition.kuma_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  health_check_grace_period_seconds = 300 # Le damos 5 minutos para arrancar

  network_configuration {
    subnets          = module.vpc.public_subnets
    security_groups  = [aws_security_group.kuma_sg.id]
    assign_public_ip = true
  }
}

# --- MONITOREO (ALERTA DE CPU) ---
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

# (Roles IAM abreviados, usa los mismos que en el de Minecraft)
resource "aws_iam_role" "ecs_role" {
  name = "kuma_ecs_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
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