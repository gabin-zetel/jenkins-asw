output "admin_public_ip" {
  value = aws_instance.admin.public_ip
}

output "proxy_public_ips" {
  value = aws_instance.proxy[*].public_ip
}

output "alb_dns_name" {
  value = aws_lb.alb.dns_name
}

output "nat_gateway_ip" {
  value = aws_eip.nat.public_ip
}
