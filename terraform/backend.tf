terraform {
  backend "s3" {
    bucket       = "misaeltox-uptime-kuma-tfstate"
    key          = "uptime-kuma/terraform.tfstate"
    region       = "eu-north-1"
    use_lockfile = true
    encrypt      = true
  }
}