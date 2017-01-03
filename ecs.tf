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
