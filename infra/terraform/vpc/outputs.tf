output "vpc_id" {
  description = "ID of the lab VPC."
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "IPv4 range of the lab VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs in stable key order."
  value = [
    for key in sort(keys(var.subnets)) :
    aws_subnet.public[key].id
  ]
}

output "private_subnet_ids" {
  description = "Private subnet IDs in stable key order."
  value = [
    for key in sort(keys(var.subnets)) :
    aws_subnet.private[key].id
  ]
}

output "availability_zones" {
  description = "Availability Zones used by this configuration."
  value = [
    for key in sort(keys(var.subnets)) :
    var.subnets[key].availability_zone
  ]
}

output "nat_gateway_id" {
  description = "NAT gateway ID, or null when disabled."
  value       = one(aws_nat_gateway.main[*].id)
}
