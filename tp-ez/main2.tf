# main2.tf — Suppression complète d'un VPC via AWS CLI
variable "vpc_id" {
  description = "ID du VPC à supprimer (injecté par Jenkins)"
  type        = string
}

variable "region" {
  default = "us-east-1"
}
