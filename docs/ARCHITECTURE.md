# Backstage AWS Architecture

## High-Level Architecture

```
Internet
    ↓
[Route 53] (Optional - Custom Domain)
    ↓
[CloudFront] (Optional - CDN)
    ↓
[Application Load Balancer]
    ↓
[ECS Fargate Tasks - Backstage App]
    ↙        ↘
[RDS PostgreSQL]    [Secrets Manager]
    ↑
[CloudWatch Logs/Metrics]
```

## Detailed Component Diagram

### Networking Layer
- **VPC**: Isolated network environment in us-east-2
- **Public Subnets**: ALB and NAT Gateway
- **Private Subnets**: ECS tasks and RDS database
- **Internet Gateway**: Public internet access
- **NAT Gateway**: Private subnet internet access for updates

### Compute Layer
- **ECS Cluster**: Container orchestration service
- **Fargate Tasks**: Serverless container execution
- **Task Definition**: Backstage container configuration
- **Service**: Maintains desired task count with auto-healing

### Data Layer
- **RDS PostgreSQL**: Managed relational database
- **Secrets Manager**: Secure storage for database credentials and API tokens
- **CloudWatch Logs**: Centralized logging

### Security Layer
- **Security Groups**: Network-level access control
- **IAM Roles**: Least-privilege access for ECS tasks
- **ACM Certificates**: SSL/TLS encryption (for custom domains)

## Data Flow

1. **User Request**: HTTP/HTTPS request hits ALB
2. **Load Balancing**: ALB routes traffic to healthy ECS tasks
3. **Application Processing**: Backstage container processes request
4. **Database Queries**: Application connects to RDS via private subnet
5. **External APIs**: Application calls GitHub APIs using stored tokens
6. **Logging**: All logs sent to CloudWatch for monitoring

## Scalability Considerations

- **Horizontal Scaling**: ECS service can scale based on CPU/memory metrics
- **Database Scaling**: RDS can be scaled vertically or use read replicas
- **Load Balancing**: ALB distributes traffic across multiple tasks
- **Caching**: Consider Redis/ElastiCache for session/data caching

## Security Best Practices

- Database in private subnet, no public access
- Secrets stored in AWS Secrets Manager, not in code
- SSL/TLS encryption for all communications
- Minimal IAM permissions for tasks
- Security groups restrict access to necessary ports only
- Regular security updates via ECR image scanning

## Monitoring Points

- **Application Metrics**: Built-in OpenTelemetry support
- **Infrastructure Metrics**: CloudWatch metrics for ECS/RDS/ALB
- **Logs**: Centralized logging in CloudWatch Logs
- **Health Checks**: ALB health checks for container health
- **Alerts**: CloudWatch alarms for critical metrics