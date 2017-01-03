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
