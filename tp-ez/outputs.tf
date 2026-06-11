output "admin_public_ip" {
  value = aws_instance.admin.public_ip
}

output "proxy_public_ip" {
  value = aws_instance.proxy.public_ip
}

output "web_private_ips" {
  value = aws_instance.web[*].private_ip
}

output "load_balancer_url" {
  value = "http://${aws_instance.proxy.public_ip}"
}
