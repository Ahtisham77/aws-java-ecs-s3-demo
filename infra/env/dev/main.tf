
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  project = "aws-java-ecs-s3-demo"
  env     = var.env
  region  = var.region

  name = "${local.project}-${local.env}"

  ecs_container_name = "backend"
  ecs_container_port = 8080
  backend_image = "${aws_ecr_repository.backend.repository_url}:latest"

  # VPC + subnetting
  vpc_cidr = "10.0.0.0/16"

  # first 2 AZs for dev
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # /20 sized public & private subnets
  public_subnets = [
    cidrsubnet(local.vpc_cidr, 4, 0),
    cidrsubnet(local.vpc_cidr, 4, 1),
  ]

  private_subnets = [
    cidrsubnet(local.vpc_cidr, 4, 2),
    cidrsubnet(local.vpc_cidr, 4, 3),
  ]

  tags = {
    Project = local.project
    Env     = local.env
  }
}



module "network" {
  source = "../../modules/aws-vpc"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  enable_nat_gateway       = true
  single_nat_gateway       = true 
  enable_dns_hostnames     = true
  enable_dns_support       = true
  map_public_ip_on_launch  = true

  tags = local.tags
}

resource "aws_security_group" "db" {
  name        = "${local.name}-db-sg"
  description = "Allow MySQL access from within VPC"
  vpc_id      = module.network.vpc_id

  # allow MySQL from inside the VPC CIDR
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [module.network.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}


resource "random_password" "db" {
  length  = 20
  special = true
}

module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.1"

  identifier = "${local.name}-db"

  engine               = "mysql"
  engine_version       = "8.0"
  family               = "mysql8.0"
  major_engine_version = "8.0"
  instance_class       = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 100

  db_name  = "appdb"
  username = "appuser"
  password = random_password.db.result
  port     = 3306


  create_db_subnet_group = true 
  subnet_ids             = module.network.private_subnets

  vpc_security_group_ids = [aws_security_group.db.id]

  publicly_accessible = false
  multi_az            = false

  maintenance_window = "Mon:00:00-Mon:03:00"
  backup_window      = "03:00-06:00"

  skip_final_snapshot = true
  deletion_protection = false

  tags = local.tags
}


module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name               = "${local.name}-alb"
  load_balancer_type = "application"

  vpc_id  = module.network.vpc_id
  subnets = module.network.public_subnets

  enable_deletion_protection = false

  # Security group - allow HTTP from the internet, egress back into VPC
  security_group_ingress_rules = {
    http_80 = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      description = "HTTP web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  security_group_egress_rules = {
    all_to_vpc = {
      ip_protocol = "-1"
      cidr_ipv4   = module.network.vpc_cidr_block
    }
  }

  # Simple HTTP listener that forwards to one target group
  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"

      forward = {
        target_group_key = "ecs_tg"
      }
    }
  }

  # Target group that ECS Fargate use
  target_groups = {
    ecs_tg = {
      backend_protocol = "HTTP"
      backend_port     = local.ecs_container_port
      target_type      = "ip"

      health_check = {
        enabled             = true
        interval            = 30
        path                = "/health"
        port                = "traffic-port"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        timeout             = 5
        protocol            = "HTTP"
        matcher             = "200-399"
      }

      # ECS will attach tasks to this TG, so nothing attached from ALB side
      create_attachment = false
    }
  }

  tags = local.tags
}

module "ecs_cluster" {
  source  = "terraform-aws-modules/ecs/aws//modules/cluster"
  version = "~> 5.0"

  cluster_name = "${local.name}-cluster"

  # Fargate capacity providers (same style as official example)
  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 1
        base   = 1
      }
    }
    FARGATE_SPOT = {
      default_capacity_provider_strategy = {
        weight = 1
      }
    }
  }

  tags = local.tags
}


resource "aws_ecr_repository" "backend" {
  name = "${local.name}-backend"

  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

# Execution role for ECS tasks (pull image, write logs, etc.)
resource "aws_iam_role" "ecs_execution" {
  name = "${local.name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name}"
  retention_in_days = 7
  tags              = local.tags
}

# Our own Fargate task definition – this is where port 8080 is defined
resource "aws_ecs_task_definition" "backend" {
  family                   = "${local.name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"

  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([
    {
      name      = local.ecs_container_name
      image     = "${aws_ecr_repository.backend.repository_url}:v1"
      essential = true

      portMappings = [
        {
          containerPort = local.ecs_container_port 
          hostPort      = local.ecs_container_port 
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = local.region
          awslogs-stream-prefix = "ecs"
        }
      }

      # DB wiring – I’ve renamed these to generic DB_* so it’s not “Spring-specific”
      environment = [
        {
          name  = "DB_URL"
          value = "jdbc:mysql://${module.db.db_instance_address}:${module.db.db_instance_port}/appdb"
        },
        {
          name  = "DB_USERNAME"
          value = "appuser"
        },
        {
          name  = "DB_PASSWORD"
          value = random_password.db.result
        }
      ]
    }
  ])

  tags = local.tags
}

module "ecs_service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.0"

  name        = "${local.name}-service"
  cluster_arn = module.ecs_cluster.arn

  # Use the task definition we manage above
  create_task_definition = false
  task_definition_arn    = aws_ecs_task_definition.backend.arn

  desired_count          = 2
  enable_execute_command = true

  # Run tasks in private subnets
  subnet_ids = module.network.private_subnets

  # Security group: ALB → ECS, plus outbound
  security_group_rules = {
    alb_ingress = {
      description              = "Allow ALB to reach ECS tasks"
      type                     = "ingress"
      from_port                = local.ecs_container_port
      to_port                  = local.ecs_container_port
      protocol                 = "tcp"
      source_security_group_id = module.alb.security_group_id
    }

    all_egress = {
      description = "Allow all outbound traffic"
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # Attach service to existing ALB target group
  load_balancer = {
    app = {
      target_group_arn = module.alb.target_groups["ecs_tg"].arn
      container_name   = local.ecs_container_name
      container_port   = local.ecs_container_port
    }
  }

  tags = local.tags
}


module "frontend_s3" {
  source      = "../../modules/aws-frontend-s3"
  bucket_name = "${local.name}-frontend"
  tags        = local.tags
}


