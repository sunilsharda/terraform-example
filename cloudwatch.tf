# --- CloudWatch Logs

resource "aws_cloudwatch_log_group" "ecs" {
  name = "digital-web-group/ecs-agent"
}

resource "aws_cloudwatch_log_group" "web" {
  name = "digital-web-group/digital-web"
}
