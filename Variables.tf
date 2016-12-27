variable "aws_access_key" {
  description = "The AWS access key id credential"
}

variable "aws_secret_key" {
  description = "The AWS secret access key credential"
}

#variable "aws_account" {
#  description = "The AWS Account we are building infrastructure in."
#}

variable "aws_region" {
  description = "The AWS Region we are building infrastructure in."
}

variable "vpc_id" {
  description = "The vpc id in the account"
}

variable "asg_min" {
  description = "Min numbers of servers in ASG"
}

variable "asg_max" {
  description = "Max numbers of servers in ASG"
  default     = "4"
}

variable "asg_desired" {
  description = "Desired numbers of servers in ASG"
  default     = "1"
}

variable "subnet_ids" {
  type = "map"
  description = "Mapping of subnet ids per vpc"
  #default = {
  #  vpc-5088c834 = "subnet-a5dc198f,subnet-b6b32c8b"
  #}
}

variable "ami_id" {
  description = "AMI to be used for provisioning instances"
}

variable "instance_type" {
  description = "Instance type"
}

variable "my_ip" {
  description = "My IP address"
}
