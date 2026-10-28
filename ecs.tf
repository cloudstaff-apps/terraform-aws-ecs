resource "aws_ecs_cluster" "ecs" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = var.container_insights ? "enabled" : "disabled"
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "aws_ecs_cluster_capacity_providers" "ecs" {
  cluster_name = aws_ecs_cluster.ecs.name

  capacity_providers = compact([
    try(aws_ecs_capacity_provider.ecs_capacity_provider[0].name, ""),
    "FARGATE",
    "FARGATE_SPOT"
  ])

  # Tasks started without a launch type or strategy (RunTask) land on the EC2 capacity provider and
  # wait in PROVISIONING while managed scaling adds an instance, instead of failing with RESOURCE:MEMORY.
  dynamic "default_capacity_provider_strategy" {
    for_each = var.default_capacity_provider_strategy_enabled && !var.fargate_only ? [1] : []

    content {
      capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider[0].name
      weight            = 1
      base              = 0
    }
  }
}
