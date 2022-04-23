locals {
  tags = {
    ModificationDate = timestamp()
    # Console | Terraform | Ansible | Packer
    Builder = "Terraform"
    # Client Infos
    Applictation = var.application
    Project      = var.project
    Environment  = local.environment[var.environment]
  }
  environment = {
    dev = "Development"
    prd = "Production"
    hml = "Homolog"
  }
  # name_pattern = format("%s-%s-%s", var.project, var.environment, local.resource)
  capacity_provider = var.capacity_provider
  image_name        = lower(format("%s-%s-%s", var.project, var.environment, var.service.name))
  image_full_name   = format("%s:%s", aws_ecr_repository.repository.repository_url, var.image_tag)
  target_group_name = format("%s-%s-%s", var.project, var.environment, "tg-${var.service.name}")
   #[for i in [var.service.name] : format("/aws/ecs/%s/%s/%s", var.project, var.environment, regex(".*-([a-z]{1,})",i))] // TODO - change this into a array
  log_group_names  = format("/aws/ecs/%s/%s/%s", var.project, var.environment, var.service.name)
  task_family_name = format("%s-%s-%s", var.project, var.environment, "task-${var.service.name}")
  cluster_name     = var.cluster_name
  docker_registry =format("%s.dkr.ecr.%s.amazonaws.com", data.aws_caller_identity.current.account_id, var.region)
}

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

### Images Definition

/* ECR - Repository for each service */
resource "aws_ecr_repository" "repository" {
  image_tag_mutability = "IMMUTABLE"
  name                 = local.image_name

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository_policy" "reg_power_user" {
  repository = aws_ecr_repository.repository.name
  policy     = data.aws_iam_policy_document.reg_power_user.json
}

resource "aws_ecr_lifecycle_policy" "ecr_lifecycl_policy" {
  repository = aws_ecr_repository.repository.name
  policy = jsonencode(
    {
      rules = [
        {
          action = {
            type = "expire"
          }
          selection = {
            countType   = "imageCountMoreThan"
            countNumber = 10
            tagStatus   = "any"
          }
          description  = "Keep last 10 images"
          rulePriority = 1
        }
      ]
    }
  )
}

resource "docker_image" "this" {
  name = aws_ecr_repository.repository.repository_url
  build {
    path = var.path_to_dockerfile
    tag  = [ 
      aws_ecr_repository.repository.name
    ]
    build_arg = {
      TEST : "NEW TEST ARG"
    }
    label = {
      author : "Feliep F Rocha"
      maintainer: "Felipe F Rocha"
      vendor: "Usodus Systems"
    }
  }
}

resource "null_resource" "push_docker_images" {
  provisioner "local-exec" {
    command = <<-EOT
      echo ${data.aws_ecr_authorization_token.token.password} | docker login --username AWS --password-stdin ${local.docker_registry}
      docker push ${aws_ecr_repository.repository.repository_url}:${var.image_tag}
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [
    docker_image.this,
  ]

  triggers = {
    docker_images = docker_image.this.repo_digest
  }
}

### Service Definition

resource "aws_lb_target_group" "tg" {
  name     = local.target_group_name
  port     = var.service.container_definition.containerPort
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  # target_type          = var.service.type
  deregistration_delay = 60

  health_check {
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = max(var.service.health.retries - 3, 2)
    unhealthy_threshold = var.service.health.retries
    interval            = var.service.health.interval
    timeout             = var.service.health.timeout
    path                = "/${var.health_path}"
  }
  depends_on = [data.aws_lb.load_balancer]
}

resource "aws_lb_listener" "lb" {
  load_balancer_arn = data.aws_lb.load_balancer.arn
  port              = var.service.container_definition.containerPort
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_lb_target_group.tg.arn
    type             = "forward"
  }
}

resource "aws_cloudwatch_log_group" "microservice" {
  # for_each = local.log_group_names
  # name     = each.value
  name =local.log_group_names
}

resource "aws_autoscaling_attachment" "asg_attachment_bar" {
  autoscaling_group_name = data.aws_autoscaling_group.asg.name
  lb_target_group_arn   = aws_lb_target_group.tg.arn
}

resource "aws_ecs_task_definition" "api_task_def" {
  family             = local.task_family_name
  task_role_arn      = var.task_role_arn == "" ? aws_iam_role.task_role.arn : var.task_role_arn
  execution_role_arn = var.execution_role_arn == "" ? aws_iam_role.execution_role.arn : var.execution_role_arn

  requires_compatibilities = ["EC2"]
  cpu                      = tostring(1 * var.service.cpu)
  memory                   = tostring(1 * var.service.memory)
  container_definitions = jsonencode([
    {
      name              = "${var.service.name}"
      image             = local.image_full_name
      cpu               = "${var.service.cpu}"
      memoryReservation = "${var.service.memory}"
      memory            = "${var.service.memory}"
      portMappings      = ["${var.service.container_definition}"]
      essential         = true
      environment       = var.environment_variables
      healthCheck = {
        command = [
          "CMD-SHELL",
          "curl -f http://localhost:${var.service.container_definition.containerPort}/${var.health_path} || exit 1"
        ]
        retries     = "${var.service.health.retries}"
        timeout     = "${var.service.health.timeout}"
        interval    = "${var.service.health.interval}"
        startPeriod = "${var.service.health.startPeriod}"
      }
      mountPoints = var.mount_points
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-region        = "${var.region}"
          awslogs-group         = aws_cloudwatch_log_group.microservice.name
          awslogs-stream-prefix = "service/${var.service.name}"
        }
      }
    }
  ])
  dynamic "volume" {
    for_each = var.task_volumes
    content {
      name = volume.value.name
      dynamic "efs_volume_configuration" {
        for_each = volume.value.efs_repo
        content {
          file_system_id = efs_volume_configuration.value.efs_config.file_system_id
          root_directory = efs_volume_configuration.value.efs_config.root_directory
        }
      }
    }
  }
}

/* service containers */
resource "aws_ecs_service" "ec2_service" {
  name            = var.service.name
  cluster         = data.aws_ecs_cluster.cluster.arn
  task_definition = aws_ecs_task_definition.api_task_def.arn

  desired_count = var.desired_count

  ordered_placement_strategy {
    type  = "binpack"
    field = "memory"
  }

  deployment_controller {
    type = "ECS"
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  capacity_provider_strategy {
    capacity_provider = local.capacity_provider
    base              = 1
    weight            = 1
  }

  enable_ecs_managed_tags           = true
  health_check_grace_period_seconds = 60

  scheduling_strategy = "REPLICA"

  load_balancer {
    container_name   = var.service.name
    container_port   = var.service.container_definition.containerPort
    target_group_arn = aws_lb_target_group.tg.arn
  }

  depends_on = [
    aws_ecs_task_definition.api_task_def,
    aws_lb_target_group.tg,
    aws_lb_listener.lb
  ]

}


resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = var.maximum_tasks
  min_capacity       = var.environment == "prod" ? var.minimum_tasks : 1
  resource_id        = "service/${local.cluster_name}/${var.service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  depends_on = [
    aws_ecs_service.ec2_service
  ]
}

resource "aws_appautoscaling_policy" "ecs_memory_policy" {
  name               = "memory-scale-${var.service.name}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 75
    scale_in_cooldown  = 120
    scale_out_cooldown = 60
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "ecs_cpu_policy" {
  name               = "cpu-scale-${var.service.name}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 75
    scale_in_cooldown  = 120
    scale_out_cooldown = 30
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "ecs_request_policy" {
  name               = "request-scale-${var.service.name}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 2000
    scale_in_cooldown  = 120
    scale_out_cooldown = 30
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = join("/", [regex(".*(app.*)", data.aws_lb.load_balancer.arn)[0], aws_lb_target_group.tg.arn_suffix])
    }
  }
}

resource "aws_iam_role" "task_role" {
  name               = "service_task_role"
  assume_role_policy = data.aws_iam_policy_document.assume_task_role.json
  inline_policy {
    name = "task_role_service_policy"
    policy = data.aws_iam_policy_document.task_role.json
  }
}

resource "aws_iam_role" "execution_role" {
  name               = "service_execution_role"
  assume_role_policy = data.aws_iam_policy_document.assume_execution_role.json
  inline_policy {
    name = "service_role_execution_policy"
    policy = data.aws_iam_policy_document.execution_role.json
  }
}

