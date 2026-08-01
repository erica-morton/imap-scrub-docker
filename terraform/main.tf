data "aws_region" "current" {}

# --- Networking: default VPC unless overridden -------------------------------

data "aws_vpc" "default" {
  count   = var.vpc_id == null ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = length(var.subnet_ids) == 0 ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

locals {
  vpc_id     = var.vpc_id != null ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
}

resource "aws_security_group" "task" {
  name        = "${var.name}-task"
  description = "Egress-only security group for the ${var.name} task"
  vpc_id      = local.vpc_id

  lifecycle {
    precondition {
      condition     = !(length(var.subnet_ids) > 0 && var.vpc_id == null)
      error_message = "When subnet_ids is set, vpc_id must be set too — the security group must live in the same VPC as the subnets."
    }
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

# --- Image registry ----------------------------------------------------------

resource "aws_ecr_repository" "this" {
  name         = var.name
  force_delete = true
}

resource "aws_ecr_lifecycle_policy" "keep_last_5" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the 5 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

# --- Config secret -----------------------------------------------------------

# The value (the full imap-scrub YAML config, including the IMAP password) is
# deliberately not managed by Terraform. Set it with:
#   aws secretsmanager put-secret-value \
#     --secret-id <name>/config --secret-string file://imap-scrub.yml
resource "aws_secretsmanager_secret" "config" {
  name        = "${var.name}/config"
  description = "imap-scrub YAML configuration (contains the IMAP password)"
}

# --- Logs --------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
}

# --- ECS cluster & task ------------------------------------------------------

resource "aws_ecs_cluster" "this" {
  name = var.name
}

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "read_config_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.config.arn]
  }
}

resource "aws_iam_role_policy" "execution_read_secret" {
  name   = "read-config-secret"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.read_config_secret.json
}

# imap-scrub needs no AWS API access at runtime
resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([{
    name      = var.name
    image     = "${aws_ecr_repository.this.repository_url}:${var.image_tag}"
    essential = true
    command   = var.container_command

    secrets = [{
      name      = "IMAP_SCRUB_CONFIG"
      valueFrom = aws_secretsmanager_secret.config.arn
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.this.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = var.name
      }
    }
  }])
}

# --- Failure alerts ----------------------------------------------------------

locals {
  alert_count = var.alert_email == null ? 0 : 1
}

resource "aws_sns_topic" "alerts" {
  count = local.alert_count
  name  = "${var.name}-alerts"
}

resource "aws_sns_topic_subscription" "alert_email" {
  count     = local.alert_count
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

data "aws_iam_policy_document" "alerts_topic" {
  count = local.alert_count

  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts[0].arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.task_failed[0].arn]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  count  = local.alert_count
  arn    = aws_sns_topic.alerts[0].arn
  policy = data.aws_iam_policy_document.alerts_topic[0].json
}

# Fires for any task in the cluster that stops unsuccessfully — a container
# exiting non-zero (bad credentials, IMAP server down) or the task never
# starting (missing secret value, unpullable image).
resource "aws_cloudwatch_event_rule" "task_failed" {
  count       = local.alert_count
  name        = "${var.name}-task-failed"
  description = "${var.name} run finished unsuccessfully"

  event_pattern = jsonencode({
    source      = ["aws.ecs"]
    detail-type = ["ECS Task State Change"]
    detail = {
      clusterArn = [aws_ecs_cluster.this.arn]
      lastStatus = ["STOPPED"]
      "$or" = [
        { stopCode = ["TaskFailedToStart"] },
        { containers = { exitCode = [{ anything-but = 0 }] } }
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "task_failed_sns" {
  count = local.alert_count
  rule  = aws_cloudwatch_event_rule.task_failed[0].name
  arn   = aws_sns_topic.alerts[0].arn

  input_transformer {
    input_paths = {
      time     = "$.time"
      stopCode = "$.detail.stopCode"
      reason   = "$.detail.stoppedReason"
      exitCode = "$.detail.containers[0].exitCode"
    }

    input_template = <<-EOT
      "imap-scrub run FAILED at <time> (stopCode: <stopCode>, exit code: <exitCode>): <reason>. Inspect with: aws logs tail ${aws_cloudwatch_log_group.this.name} --since 1d"
    EOT
  }
}

# --- Weekly schedule ---------------------------------------------------------

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${var.name}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

data "aws_iam_policy_document" "scheduler_run_task" {
  statement {
    actions   = ["ecs:RunTask"]
    resources = ["${aws_ecs_task_definition.this.arn_without_revision}:*"]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.this.arn]
    }
  }

  statement {
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.execution.arn, aws_iam_role.task.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "scheduler_run_task" {
  name   = "run-task"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler_run_task.json
}

resource "aws_scheduler_schedule" "this" {
  name                         = var.name
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.schedule_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_ecs_cluster.this.arn
    role_arn = aws_iam_role.scheduler.arn

    ecs_parameters {
      task_definition_arn = aws_ecs_task_definition.this.arn
      launch_type         = "FARGATE"

      network_configuration {
        subnets          = local.subnet_ids
        security_groups  = [aws_security_group.task.id]
        assign_public_ip = var.assign_public_ip
      }
    }

    retry_policy {
      maximum_retry_attempts = 2
    }
  }
}
