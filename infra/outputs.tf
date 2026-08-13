output "app_url" {
  description = "Open this in a browser"
  value       = "http://${aws_lb.main.dns_name}"
}

output "github_variables" {
  description = "Paste these into GitHub → Settings → Secrets and variables → Actions → Variables"
  value = {
    AWS_REGION       = var.region
    AWS_ROLE_ARN     = aws_iam_role.github_actions.arn
    ECR_REPOSITORY   = aws_ecr_repository.app.repository_url
    ECS_CLUSTER      = aws_ecs_cluster.main.name
    ECS_SERVICE      = aws_ecs_service.app.name
    ECS_TASK_FAMILY  = aws_ecs_task_definition.app.family
    APP_URL          = "http://${aws_lb.main.dns_name}"
  }
}
