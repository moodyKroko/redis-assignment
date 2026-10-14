aws_region     = "us-east-1"
aws_account_id = "352635535791"
project_name   = "redis-lab"

vpc_cidr = "10.20.0.0/16"

subnets = {
  a = {
    availability_zone = "us-east-1a"
    public_cidr       = "10.20.0.0/24"
    private_cidr      = "10.20.16.0/20"
  }

  b = {
    availability_zone = "us-east-1b"
    public_cidr       = "10.20.1.0/24"
    private_cidr      = "10.20.32.0/20"
  }
}

enable_nat_gateway = false
