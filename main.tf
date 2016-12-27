provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "${var.aws_region}"
}

# --- network informaiton
data "aws_availability_zones" "available" {}

data "aws_vpc" "selected" {
  id = "${var.vpc_id}"
}

#--- compute
resource "aws_autoscaling_group" "digital-web" {
  name                 = "digital-web-asg"
  min_size             = "${var.asg_min}"
  max_size             = "${var.asg_max}"
  desired_capacity     = "${var.asg_desired}"
  launch_configuration = "${aws_launch_configuration.digital-web.name}"
  vpc_zone_identifier = ["subnet-a5dc198f","subnet-b6b32c8b"]
}

data "template_file" "cloud_config" {
  template = "${file("${path.module}/config/cloud-config.yml")}"

  vars {
    #aws_region         = "${var.aws_region}"
    ecs_cluster_name   = "${aws_ecs_cluster.digital-web.name}"
    ecs_log_level      = "info"
    ecs_agent_version  = "latest"
    ecs_log_group_name = "${aws_cloudwatch_log_group.ecs.name}"
  }
}

resource "aws_launch_configuration" "digital-web" {
  #security_groups = [
   #"${split(",", lookup(var.security_group_ids, var.vpc_id))}",
  #]

  name                        = "digital-web-launch-configs"
  key_name                    = "personal"
  image_id                    = "ami-6df8fe7a"
  instance_type               = "t2.micro"
  iam_instance_profile        = "${aws_iam_instance_profile.digital-web.name}"
  user_data                   = "${data.template_file.cloud_config.rendered}"
  associate_public_ip_address = false

  lifecycle {
    create_before_destroy = true
  }
}

# --- ECS
resource "aws_ecs_cluster" "digital-web" {
  name = "digital_web_alb_ecs_cluster"
}

resource "aws_ecs_task_definition" "digital-web" {
  family                = "digital-web_td"
  container_definitions = "${file("task-definitions/digital-web-task-def.json")}"
  # -- The Docker networking mode to use for the containers in the task.
  # --- The valid values are none, bridge, and host
  network_mode          = "host"
}

# --- ALB
resource "aws_alb_target_group" "test" {
  name     = "digital-web-ecs-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${var.vpc_id}"
}

# --- IAM
resource "aws_iam_role" "ecs_service" {
  name = "digital-web_alb_ecs_role"

  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ecs_service" {
  name = "digital-web_alb_ecs_policy"
  role = "${aws_iam_role.ecs_service.name}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:Describe*",
        "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
        "elasticloadbalancing:RegisterTargets"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "digital-web" {
  name  = "digital-web-alb-ecs-instance-profile"
  roles = ["${aws_iam_role.web_instance.name}"]
}

resource "aws_iam_role" "web_instance" {
  name = "digital-web-alb-ecs-instance-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    },
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }

  ]
}
EOF
}

#Attach instances to a policy to allow for specific permissions. Without this the EC2 instances do not get registered with ECS cluster
resource "aws_iam_role_policy" "web_instance" {
  name = "digital-web_alb_instance_policy"
  role = "${aws_iam_role.web_instance.name}"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "ecs:CreateCluster",
          "ecs:DeregisterContainerInstance",
          "ecs:DiscoverPollEndpoint",
          "ecs:Poll",
          "ecs:RegisterContainerInstance",
          "ecs:StartTelemetrySession",
          "ecs:Submit*",
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource": "*"
      }
    ]
  }
EOF
}

# --- aws_ecs_service - effectively a task that is expected to run until and error occurs
# --- of a user terminates it. (typically a webserver or a databse)
resource "aws_ecs_service" "digital-web" {
  name            = "digital-web-ecs-service"
  cluster         = "${aws_ecs_cluster.digital-web.id}"
  task_definition = "${aws_ecs_task_definition.digital-web.arn}"
  desired_count   = 2
  # --- iam_role is required if you are using an lb with your service. (allows you Amazon ECS
  # --- container agent to make calls to your load balancer on your behalf.)
  iam_role        = "${aws_iam_role.ecs_service.name}"

  load_balancer {
    target_group_arn = "${aws_alb_target_group.test.id}"
    container_name   = "digital-web"
    container_port   = "80"
  }



 # --- To prevent a race condition during service deletion, make sure to set depends_on to the
 # --- related aws_iam_role_policy; otherwise, the policy may be destroyed too soon and the ECS
 # --- service will then get stuck in the DRAINING state.
 depends_on = [
   "aws_iam_role_policy.ecs_service",
   "aws_alb_listener.front_end",
 ]
}

resource "aws_alb" "main" {
name            = "digital-web-alb-ecs"
#subnets         = ["${split(",", lookup(var.subnet_ids, var.vpc_id))}"]
#security_groups = ["${split(",", lookup(var.security_group_ids, var.vpc_id))}"]
subnets = ["subnet-a5dc198f","subnet-b6b32c8b"]

# --- If true, the ALB will be internal
internal        = false

# --- mandatory fields... for billing.
tags {
    Name        = "Digital Web ECS ALB",
    AuthorEmail = "SunilSharda@gmail.com"
    }

}

resource "aws_alb_listener" "front_end" {
  load_balancer_arn = "${aws_alb.main.id}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.test.id}"
    type             = "forward"
  }
}

# --- CloudWatch Logs

resource "aws_cloudwatch_log_group" "ecs" {
  name = "digital-web-group/ecs-agent"
}

resource "aws_cloudwatch_log_group" "web" {
  name = "digital-web-group/digital-web"
}
