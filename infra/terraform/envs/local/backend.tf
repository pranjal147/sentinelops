# Local backend — state stored alongside the environment files.
# TODO Day 13: migrate to S3 backend for the AWS environment:
#   backend "s3" {
#     bucket         = "sentinelops-tfstate"
#     key            = "envs/aws/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "sentinelops-tflock"
#     encrypt        = true
#   }
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
