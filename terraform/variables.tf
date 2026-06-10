variable "region" {
  default = "us-east-1"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "key_name" {
  default = "vockey"
}

variable "ami_id" {
  default = "ami-0c02fb55956c7d316"
}
