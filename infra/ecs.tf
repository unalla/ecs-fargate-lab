resource "aws_ecs_cluster" "main" {
  name = var.project

  setting {
    name  = "containerInsights"
    value = "disabled" # keeps CloudWatch inside the free tier for a lab
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project}"
  retention_in_days = 7
}

# Terraform registers revision 1 so the service has something to start from.
# After that, the pipeline registers new revisions — see the lifecycle block
# on the service below.
resource "aws_ecs_task_definition" "app" {
  family                   = var.project
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "app"
    image     = "public.ecr.aws/docker/library/nginx:alpine" # placeholder; CI replaces this
    essential = true
    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "app"
      }
    }
  }])

  lifecycle {
    ignore_changes = [container_definitions]
  }
}

resource "aws_ecs_service" "app" {
  name            = var.project
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = true # no NAT Gateway; see network.tf
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = 8080
  }

  # Rolling deployment: bring up new tasks alongside the old ones, never
  # drop below full capacity.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # If the new revision fails health checks, ECS abandons the deployment and
  # restores the previous task definition without anyone being paged.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  health_check_grace_period_seconds = 30
  wait_for_steady_state             = false

  depends_on = [aws_lb_listener.http]

  # The pipeline owns the image after bootstrap. Without this, every
  # `terraform apply` would drag production back to revision 1.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}
