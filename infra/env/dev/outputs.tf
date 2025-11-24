output "vpc_id" {
  description = "VPC ID for dev"
  value       = module.network.vpc_id
}

output "public_subnets" {
  description = "Public subnet IDs for dev"
  value       = module.network.public_subnets
}

output "private_subnets" {
  description = "Private subnet IDs for dev"
  value       = module.network.private_subnets
}
output "db_endpoint" {
  value = module.db.db_instance_endpoint
}

output "db_port" {
  value = module.db.db_instance_port
}

output "db_name" {
  value = module.db.db_instance_name
}

output "db_username" {
  value     = module.db.db_instance_username
  sensitive = true
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = module.alb.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB"
  value       = module.alb.zone_id
}

output "ecs_cluster_name" {
  description = "Name of ECS cluster"
  value       = module.ecs_cluster.name
}

output "ecs_cluster_arn" {
  description = "ARN of ECS cluster"
  value       = module.ecs_cluster.arn
}

output "ecs_cluster_id" {
  description = "ID of ECS cluster"
  value       = module.ecs_cluster.id
}
