output "admin_public_ip" {
  value = aws_instance.admin.public_ip
}

output "web_public_ip" {
  value = aws_instance.web.public_ip
}

output "nat_gateway_ip" {
  value = aws_eip.nat.public_ip
}
