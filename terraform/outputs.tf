output "ecr_repository_url" {
  description = "Push the image here"
  value       = aws_ecr_repository.this.repository_url
}

output "config_secret_name" {
  description = "Secrets Manager secret that must hold the imap-scrub YAML config"
  value       = aws_secretsmanager_secret.config.name
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.this.name
}

output "run_now_command" {
  description = "AWS CLI command to trigger a one-off run outside the schedule"
  value = join(" ", [
    "aws ecs run-task",
    "--cluster ${aws_ecs_cluster.this.name}",
    "--launch-type FARGATE",
    "--task-definition ${aws_ecs_task_definition.this.family}",
    "--network-configuration '${jsonencode({
      awsvpcConfiguration = {
        subnets        = local.subnet_ids
        securityGroups = [aws_security_group.task.id]
        assignPublicIp = var.assign_public_ip ? "ENABLED" : "DISABLED"
      }
    })}'",
  ])
}
