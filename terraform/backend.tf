terraform {
  backend "s3" {
    bucket = "anu-ci-cd-terraform-state-bucket"
    key    = "state/terraform.tfstate"
    region = "ap-south-1"
  }
}
