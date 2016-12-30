#-- Configure the AWS Provider
provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "${var.aws_region}"
}

#--- Set up the Autoscaling group for the instances, with the associated
#--- Launch config and subnet id's across the availability zones
resource "aws_autoscaling_group" "digital-web" {
  name                 = "digital-web-asg"
  min_size             = "${var.asg_min}"
  max_size             = "${var.asg_max}"
  desired_capacity     = "${var.asg_desired}"
  launch_configuration = "${aws_launch_configuration.digital-web.name}"
  vpc_zone_identifier = ["${split(",", lookup(var.subnet_ids, var.vpc_id))}"]
}

#--- Source the config settings for the ECS instances.
#--- Required to register the instances with the correct ECS cluster etc
data "template_file" "ecs_config" {
  template = "${file("${path.module}/config/ecs-config.yml")}"

  vars {
    ecs_cluster_name   = "${aws_ecs_cluster.digital-web.name}"
    ecs_log_level      = "info"
    ecs_agent_version  = "latest"
    ecs_log_group_name = "${aws_cloudwatch_log_group.ecs.name}"
  }
}

#--- Security group for the EC2 instances. SSH and HTTP
resource "aws_security_group" "instances" {
  name        = "Instances Group"
  description = "Used for the EC2 instances"
  vpc_id      = "${var.vpc_id}"

  # SSH access from private ips. This is Temporary and should only be used while testing.
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}"]
  }

  # HTTP access from the VPC
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    self = true #Allow access from sources using the same security group as THIS
  }

  # outbound internet access. Needed for ECS agent to communicate outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#--- Lanuch Config using "Instances" SG and "ecs_config" User Data.
resource "aws_launch_configuration" "digital-web" {
  security_groups = ["${aws_security_group.instances.id}"]

  name                        = "digital-web-launch-configs"
  key_name                    = "personal"
  image_id                    = "${var.ami_id}"
  instance_type               = "${var.instance_type}"
  iam_instance_profile        = "${aws_iam_instance_profile.digital-web.name}"
  user_data                   = "${data.template_file.ecs_config.rendered}"
  associate_public_ip_address = false

  lifecycle {
    create_before_destroy = true
  }
}


#--- ECS Section

#--- Cluster
resource "aws_ecs_cluster" "digital-web" {
  name = "digital_web_ecs_cluster"
}

#--- Source the Task Definition
data "template_file" "task_definition" {
  template = "${file("${path.module}/task-definitions/digital-web-task-def.json")}"

  vars {
    log_group_region = "${var.aws_region}"
    log_group_name   = "${aws_cloudwatch_log_group.web.name}"
  }
}

#Provision Task definition
resource "aws_ecs_task_definition" "digital-web" {
  family                = "digital-web_td"
  container_definitions = "${data.template_file.task_definition.rendered}"
  # -- The Docker networking mode to use for the containers in the task.
  # --- The valid values are none, bridge, and host
  network_mode          = "host"
}

#--- IAM Section

# IAM role for ECS service
resource "aws_iam_role" "ecs_service" {
  name = "digital-web_ecs_role"

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

# IAM Policy attached to the IAM role for ECS Service
resource "aws_iam_role_policy" "ecs_service" {
  name = "digital-web_ecs_policy"
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

# IAM Instance Profile for EC2 instances
resource "aws_iam_instance_profile" "digital-web" {
  name  = "digital-web-instance-profile"
  roles = ["${aws_iam_role.web_instance.name}"]
}

# IAM Role for EC2 instances
resource "aws_iam_role" "web_instance" {
  name = "digital-web-instance-role"

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
    }
  ]
}
EOF
}

# IAM role policy attached to IAM role for EC2 instances.
# Without this the EC2 instances do not get registered with ECS cluster
resource "aws_iam_role_policy" "web_instance" {
  name = "digital-web_instance_policy"
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

# ALB Target group. Referenced by the ECS service below for instance registration.
resource "aws_alb_target_group" "test" {
  name     = "digital-web-ecs-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${var.vpc_id}"
}

# ECS Service - effectively a task that is expected to run until an error occurs
# or a user terminates it. (typically a webserver/appserver or a database)
resource "aws_ecs_service" "digital-web" {
  name            = "digital-web-ecs-service"
  cluster         = "${aws_ecs_cluster.digital-web.id}"
  task_definition = "${aws_ecs_task_definition.digital-web.arn}"
  desired_count   = 2
  # --- iam_role is required if you are using an lb with your service. (allows the Amazon ECS
  # --- container agent to make calls to your load balancer on your behalf.)
  iam_role        = "${aws_iam_role.ecs_service.name}"

  load_balancer {
    target_group_arn = "${aws_alb_target_group.test.id}"
    container_name   = "nginx"
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

# A security group for the ELB so it is accessible via the web
resource "aws_security_group" "elb" {
  name        = "digital-web_elb"
  description = "Used in the terraform"
  vpc_id      = "${var.vpc_id}"

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ALB Resource.
resource "aws_alb" "main" {
name            = "digital-web-alb"
security_groups = ["${aws_security_group.elb.id}","${aws_security_group.instances.id}"]
subnets = ["subnet-a5dc198f","subnet-b6b32c8b"]

# --- If true, the ALB will be internal
internal        = false

# --- mandatory fields... for billing.
tags {
    Name        = "Digital Web ECS ALB",
    AuthorEmail = "SunilSharda@gmail.com"
    }

}

#--- ALB Listener
# Multiple will be needed when running more than 1 container on a host and if each
# container needs to be accessible via the ALB.
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
