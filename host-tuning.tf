# Opt-in host tuning. With the defaults (no agent config, disk monitoring off) the rendered user data
# is the same as before, so existing launch templates do not change.

locals {
  userdata_ecs_agent_config = length(var.ecs_agent_config) == 0 ? "" : join("\n", concat(
    ["echo \"### ECS AGENT CONFIG\""],
    [for k, v in var.ecs_agent_config : "echo \"${k}=${v}\" >> /etc/ecs/ecs.config"],
  ))

  # CloudWatch agent: root-disk used_percent per instance, plus an aggregate per ASG for the alarm.
  userdata_disk_monitoring = !var.enable_disk_monitoring ? "" : <<-EOT
    echo "### CLOUDWATCH AGENT (root disk)"
    yum install -y amazon-cloudwatch-agent
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWA'
    {
      "agent": { "metrics_collection_interval": 60 },
      "metrics": {
        "namespace": "CWAgent",
        "append_dimensions": { "AutoScalingGroupName": "$${aws:AutoScalingGroupName}", "InstanceId": "$${aws:InstanceId}" },
        "aggregation_dimensions": [["AutoScalingGroupName"]],
        "metrics_collected": {
          "disk": { "measurement": ["used_percent"], "resources": ["/"], "drop_device": true }
        }
      }
    }
    CWA
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
  EOT
}

resource "aws_iam_role_policy_attachment" "ecs_cloudwatch_agent" {
  count      = !var.fargate_only && var.enable_disk_monitoring ? 1 : 0
  role       = aws_iam_role.ecs[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_cloudwatch_metric_alarm" "asg_disk_used" {
  count = !var.fargate_only && var.enable_disk_monitoring ? 1 : 0

  alarm_name          = "${try(data.aws_iam_account_alias.current[0].account_alias, var.alarm_prefix)}-ecs-${var.name}-asg-disk-used"
  alarm_description   = "Root disk of an ECS host in ecs-${var.name} is at or above ${var.alarm_disk_used_threshold}%. Per-host values: CWAgent disk_used_percent by InstanceId."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "disk_used_percent"
  namespace           = "CWAgent"
  period              = 300
  statistic           = "Maximum"
  threshold           = var.alarm_disk_used_threshold
  alarm_actions       = var.alarm_sns_topics
  ok_actions          = var.alarm_sns_topics
  treat_missing_data  = "missing"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.ecs[0].name
  }
}
