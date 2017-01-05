# ALB Target group. Referenced by the ECS service below for instance registration.
resource "aws_alb_target_group" "test" {
  name     = "digital-web-ecs-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${var.vpc_id}"
}

# ALB Resource.
resource "aws_alb" "main" {
name            = "digital-web-alb"
#security_groups = ["${aws_security_group.elb.id}","${aws_security_group.instances.id}"]
security_groups = ["${aws_security_group.elb.id}"]
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
