# Troubleshooting Backstage AWS Deployment

## Common Issues and Solutions

### 1. ECS Task Fails to Start

**Symptoms**: Task shows `PENDING` or `STOPPED` status

**Possible Causes & Solutions**:

- **Image not found**: Ensure Docker image is pushed to ECR
  ```bash
  aws ecr describe-images --repository-name backstage-demo --region us-east-2
  ```

- **Insufficient permissions**: Check ECS task execution role has ECR pull permissions
  ```bash
  aws iam list-attached-role-policies --role-name backstage-ecs-execution-role
  ```

- **Secrets not accessible**: Verify Secrets Manager secrets exist
  ```bash
  aws secretsmanager list-secrets --region us-east-2
  ```

**Check logs**:
```bash
aws logs tail /ecs/backstage-demo --follow --region us-east-2
```

### 2. Database Connection Issues

**Symptoms**: Application logs show database connection errors

**Possible Causes & Solutions**:

- **Security group blocking**: Ensure ECS security group allows outbound to RDS
- **Wrong credentials**: Check database password in Secrets Manager
- **Database not ready**: Wait for RDS instance to be available
  ```bash
  aws rds describe-db-instances --db-instance-identifier backstage-demo-db --region us-east-2 --query 'DBInstances[0].DBInstanceStatus'
  ```

**Test connection**:
```bash
# From ECS task (if accessible)
psql -h <rds-endpoint> -U backstage -d backstage
```

### 3. Application Health Check Fails

**Symptoms**: ALB shows unhealthy targets

**Possible Causes & Solutions**:

- **Wrong health check path**: Ensure `/api/healthcheck` endpoint exists
- **Application not starting**: Check application logs for startup errors
- **Port mismatch**: Verify container port 7007 is exposed

**Check target health**:
```bash
aws elbv2 describe-target-health --target-group-arn <target-group-arn> --region us-east-2
```

### 4. High Resource Usage

**Symptoms**: Tasks consuming high CPU/memory

**Possible Causes & Solutions**:

- **Insufficient resources**: Increase task CPU/memory allocation
- **Memory leaks**: Monitor application memory usage
- **High load**: Implement auto-scaling

**Check metrics**:
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ClusterName,Value=backstage-demo-cluster Name=ServiceName,Value=backstage-demo-service \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 300 \
  --statistics Average \
  --region us-east-2
```

### 5. GitHub Integration Issues

**Symptoms**: Catalog not loading GitHub repositories

**Possible Causes & Solutions**:

- **Invalid token**: Update GitHub token in Secrets Manager
- **Token permissions**: Ensure token has `repo` scope
- **Rate limiting**: Check GitHub API rate limits

**Test token**:
```bash
curl -H "Authorization: token YOUR_TOKEN" https://api.github.com/user
```

### 6. SSL/Certificate Issues

**Symptoms**: HTTPS not working or certificate errors

**Possible Causes & Solutions**:

- **Certificate not validated**: Check ACM certificate status
  ```bash
  aws acm describe-certificate --certificate-arn <cert-arn> --region us-east-2
  ```

- **DNS not configured**: Verify Route 53 records
- **ALB listener misconfigured**: Check HTTPS listener configuration

### 7. Terraform State Issues

**Symptoms**: Terraform commands fail with state errors

**Solutions**:

- **State file corrupted**: Check state file integrity
- **Concurrent modifications**: Ensure only one person runs Terraform at a time
- **State lock**: Manually unlock if needed
  ```bash
  terraform force-unlock <lock-id>
  ```

## Debugging Commands

### Check ECS Service Status
```bash
aws ecs describe-services \
  --cluster backstage-demo-cluster \
  --services backstage-demo-service \
  --region us-east-2
```

### Check Task Status
```bash
aws ecs list-tasks \
  --cluster backstage-demo-cluster \
  --family backstage-demo \
  --region us-east-2
```

### View Application Logs
```bash
aws logs tail /ecs/backstage-demo \
  --follow \
  --region us-east-2
```

### Check Database Status
```bash
aws rds describe-db-instances \
  --db-instance-identifier backstage-demo-db \
  --region us-east-2 \
  --query 'DBInstances[0].[DBInstanceStatus,Endpoint]'
```

### Check Load Balancer
```bash
aws elbv2 describe-load-balancers \
  --names backstage-demo-alb \
  --region us-east-2
```

## Performance Optimization

### Database Tuning
- Monitor slow queries
- Adjust RDS instance size based on load
- Enable RDS Performance Insights

### Application Optimization
- Enable gzip compression in ALB
- Implement caching for static assets
- Monitor memory usage and adjust task size

### Cost Optimization
- Use reserved instances for steady workloads
- Implement auto-scaling to reduce over-provisioning
- Monitor and optimize data transfer costs

## Getting Help

1. Check AWS documentation for service-specific issues
2. Review Backstage community forums
3. Check GitHub issues for similar problems
4. Contact AWS support for infrastructure issues