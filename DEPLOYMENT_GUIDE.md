# Backstage Demo AWS Deployment Guide

This guide provides step-by-step instructions for deploying the Backstage Demo application on AWS using Terraform and Docker.

## Prerequisites

1. **AWS Account**: Ensure you have an AWS account with appropriate permissions
2. **AWS CLI**: Install and configure AWS CLI with your credentials
   ```bash
   aws configure
   ```
3. **Terraform**: Install Terraform (>= 1.0)
   ```bash
   # Download from https://www.terraform.io/downloads
   ```
4. **Docker**: Install Docker for building container images
5. **GitHub Token**: Create a Personal Access Token with repo permissions for Backstage integrations

## Architecture Overview

The deployment creates:
- VPC with public/private subnets
- ECS Fargate cluster running the Backstage container
- RDS PostgreSQL database
- Application Load Balancer
- CloudWatch logging
- Secrets Manager for sensitive data

## Step 1: Clone and Prepare the Repository

```bash
git clone https://github.com/rupesh9999/demo-master.git
cd demo-master
```

## Step 2: Configure Application for AWS

### Update Database Configuration

Edit `app-config.yaml` to use PostgreSQL instead of SQLite:

```yaml
backend:
  database:
    client: pg
    connection:
      host: ${POSTGRES_HOST}
      port: ${POSTGRES_PORT}
      user: ${POSTGRES_USER}
      password: ${POSTGRES_PASSWORD}
      database: ${POSTGRES_DB}
```

### Create Production Config

Create `app-config.production.yaml`:

```yaml
app:
  baseUrl: https://your-domain.com  # Replace with your ALB DNS or custom domain
  support:
    url: https://github.com/backstage/backstage/issues

backend:
  baseUrl: https://your-domain.com  # Replace with your ALB DNS or custom domain
  cors:
    origin: https://your-domain.com  # Replace with your ALB DNS or custom domain

auth:
  environment: production
  providers:
    github:
      production:
        clientId: ${GITHUB_CLIENT_ID}
        clientSecret: ${GITHUB_CLIENT_SECRET}

# Add other production-specific configurations
```

## Step 3: Configure Terraform

1. Navigate to the terraform directory:
   ```bash
   cd terraform
   ```

2. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

3. Edit `terraform.tfvars` with your values:
   ```hcl
   github_token = "your-actual-github-token"
   # domain_name = "backstage.yourdomain.com"  # Optional
   ```

## Step 4: Build and Push Docker Image

1. Authenticate Docker with ECR:
   ```bash
   aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-2.amazonaws.com
   ```

2. Build the Docker image:
   ```bash
   docker build -t backstage-demo .
   ```

3. Tag the image for ECR:
   ```bash
   docker tag backstage-demo:latest $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-2.amazonaws.com/backstage-demo:latest
   ```

4. Push to ECR:
   ```bash
   docker push $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-2.amazonaws.com/backstage-demo:latest
   ```

## Step 5: Deploy Infrastructure with Terraform

1. Initialize Terraform:
   ```bash
   terraform init
   ```

2. Plan the deployment:
   ```bash
   terraform plan
   ```

3. Apply the changes:
   ```bash
   terraform apply
   ```

   Type `yes` when prompted to confirm.

## Step 6: Configure Secrets (Optional but Recommended)

After deployment, update the GitHub token secret:

```bash
aws secretsmanager update-secret \
  --secret-id backstage/github-token \
  --secret-string "your-actual-github-token"
```

## Step 7: Access Your Application

After deployment completes, Terraform will output the ALB DNS name. Access your Backstage instance at:

```
http://<alb-dns-name>
```

## Step 8: Set Up Custom Domain (Optional)

If you want a custom domain:

1. Update `terraform.tfvars` with your domain:
   ```hcl
   domain_name = "backstage.yourdomain.com"
   ```

2. Add Route 53 and ACM resources to `main.tf` (example):

   ```hcl
   # Add to main.tf
   data "aws_route53_zone" "selected" {
     name = var.domain_name
   }

   resource "aws_acm_certificate" "cert" {
     domain_name       = var.domain_name
     validation_method = "DNS"

     tags = {
       Name = "backstage-cert"
     }
   }

   resource "aws_route53_record" "cert_validation" {
     for_each = {
       for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
         name   = dvo.resource_record_name
         record = dvo.resource_record_value
         type   = dvo.resource_record_type
       }
     }

     allow_overwrite = true
     name            = each.value.name
     records         = [each.value.record]
     ttl             = 60
     type            = each.value.type
     zone_id         = data.aws_route53_zone.selected.zone_id
   }

   resource "aws_acm_certificate_validation" "cert" {
     certificate_arn         = aws_acm_certificate.cert.arn
     validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
   }

   resource "aws_route53_record" "backstage" {
     zone_id = data.aws_route53_zone.selected.zone_id
     name    = var.domain_name
     type    = "A"

     alias {
       name                   = aws_lb.backstage_alb.dns_name
       zone_id                = aws_lb.backstage_alb.zone_id
       evaluate_target_health = true
     }
   }

   # Update ALB listener to use HTTPS
   resource "aws_lb_listener" "backstage_https" {
     load_balancer_arn = aws_lb.backstage_alb.arn
     port              = "443"
     protocol          = "HTTPS"
     ssl_policy        = "ELBSecurityPolicy-2016-08"
     certificate_arn   = aws_acm_certificate.cert.arn

     default_action {
       type             = "forward"
       target_group_arn = aws_lb_target_group.backstage_tg.arn
     }
   }
   ```

3. Run `terraform apply` again.

## Monitoring and Troubleshooting

### Check Application Logs

```bash
aws logs tail /ecs/backstage-demo --follow --region us-east-2
```

### Check ECS Service Status

```bash
aws ecs describe-services --cluster backstage-demo-cluster --services backstage-demo-service --region us-east-2
```

### Check Database Connection

```bash
aws rds describe-db-instances --db-instance-identifier backstage-demo-db --region us-east-2
```

### Common Issues

1. **Container fails to start**: Check CloudWatch logs for application errors
2. **Database connection fails**: Verify security groups and subnet configurations
3. **Health check fails**: Ensure the `/api/healthcheck` endpoint is accessible

## Cost Estimation

- **ECS Fargate**: ~$0.04/hour for t3.medium (1 vCPU, 2 GB RAM)
- **RDS PostgreSQL**: ~$0.018/hour for db.t3.micro
- **ALB**: ~$0.022/hour
- **Data Transfer**: ~$0.09/GB

Total estimated monthly cost: ~$100-150 for light usage.

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

## Next Steps

- Configure CI/CD pipeline for automated deployments
- Set up monitoring with CloudWatch alarms
- Configure backup strategies for RDS
- Implement auto-scaling based on load
- Add WAF for additional security