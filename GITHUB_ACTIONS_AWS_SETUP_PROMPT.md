# Complete GitHub Actions + AWS CI/CD Setup Prompt

**Context:** Todo app repo (https://github.com/shehab-hvts/demo) ready for full CI/CD pipeline.  
**Objective:** Automate Docker build → ECR push → ECS deployment using GitHub Actions (no local Docker).  
**Credentials Available:** GitHub Classic Token + AWS Account Access.

---

## PREREQUISITES CHECKLIST

Before running this prompt:

- [ ] AWS Account with CLI configured: `aws sts get-caller-identity`
- [ ] GitHub Classic Token created (PAT with repo + write:packages scope)
- [ ] Local repo cloned: `d:\D Drive\E Drive\Semester 4.2\Jobs prep\HVTS\HVTS DRIVE\demo`
- [ ] Git config set: `git config user.name "..." && git config user.email "..."`
- [ ] Repo pushed to GitHub main branch at least once

---

## PART A: GITHUB SETUP (Skip Local Docker)

### A1. Store GitHub Token (One-time)

```bash
# Windows PowerShell
$token = "github_pat_YOUR_CLASSIC_TOKEN_HERE"
[System.Environment]::SetEnvironmentVariable("GITHUB_TOKEN", $token, "User")
refreshenv
echo $env:GITHUB_TOKEN
```

### A2. Create Workflow Directory

```bash
cd "d:\D Drive\E Drive\Semester 4.2\Jobs prep\HVTS\HVTS DRIVE\demo"
mkdir -p .github/workflows
```

### A3. Create Main Deployment Workflow

**File: `.github/workflows/deploy.yml`**

```yaml
name: Deploy to ECS

on:
  push:
    branches: [main]

env:
  AWS_REGION: us-east-1
  ECR_REPOSITORY: todo-app
  ECS_CLUSTER: prod-cluster
  ECS_SERVICE: todo-app-service
  ECS_TASK_DEFINITION: todo-app-task

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build, tag, and push image to ECR
        id: image
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker tag $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG $ECR_REGISTRY/$ECR_REPOSITORY:latest
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest
          echo "image=$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG" >> $GITHUB_OUTPUT

      - name: Update ECS task definition
        id: task-def
        uses: aws-actions/amazon-ecs-render-task-definition@v1
        with:
          task-definition: task-definition.json
          container-name: todo-app
          image: ${{ steps.image.outputs.image }}

      - name: Deploy to ECS
        uses: aws-actions/amazon-ecs-deploy-task-definition@v1
        with:
          task-definition: ${{ steps.task-def.outputs.task-definition }}
          service: ${{ env.ECS_SERVICE }}
          cluster: ${{ env.ECS_CLUSTER }}
          wait-for-service-stability: true

      - name: Notify deployment
        if: success()
        run: echo "✅ Deployment to ECS successful"

      - name: Notify failure
        if: failure()
        run: echo "❌ Deployment failed - check logs"
```

### A4. Create PR Check Workflow

**File: `.github/workflows/pr-check.yml`**

```yaml
name: PR Check

on:
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Node
        uses: actions/setup-node@v4
        with:
          node-version: '25'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: TypeScript check
        run: npm run build

      - name: Build Docker image
        run: docker build -t todo-app:test .

      - name: Docker image inspection
        run: docker images | grep todo-app
```

---

## PART B: TASK DEFINITION (ECS Configuration)

**File: `task-definition.json` (repo root)**

Replace `YOUR_AWS_ACCOUNT_ID` and `your-rds-endpoint.rds.amazonaws.com` with actual values.

```json
{
  "family": "todo-app-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["EC2"],
  "cpu": "512",
  "memory": "1024",
  "taskRoleArn": "arn:aws:iam::YOUR_AWS_ACCOUNT_ID:role/ecsTaskExecutionRole",
  "executionRoleArn": "arn:aws:iam::YOUR_AWS_ACCOUNT_ID:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "todo-app",
      "image": "{{IMAGE_URI}}",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 3001,
          "hostPort": 3001,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "NODE_ENV",
          "value": "production"
        },
        {
          "name": "DATABASE_URL",
          "value": "postgresql://postgres:DBPASSWORD@your-rds-endpoint.rds.amazonaws.com:5432/todo_db"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/todo-app",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
```

---

## PART C: AWS INFRASTRUCTURE SETUP

Run these commands in PowerShell (AWS CLI required).

### C1. Set Variables

```bash
$AWS_ACCOUNT_ID = aws sts get-caller-identity --query Account --output text
$AWS_REGION = "us-east-1"
$GITHUB_REPO = "shehab-hvts/demo"
$GITHUB_BRANCH = "main"

echo "Account: $AWS_ACCOUNT_ID"
echo "Region: $AWS_REGION"
```

### C2. Create ECR Repository

```bash
aws ecr create-repository `
  --repository-name todo-app `
  --region $AWS_REGION

# Get ECR URI
$ECR_URI = aws ecr describe-repositories `
  --repository-names todo-app `
  --region $AWS_REGION `
  --query 'repositories[0].repositoryUri' `
  --output text

echo "ECR URI: $ECR_URI"
```

### C3. Create IAM Role for GitHub Actions (OIDC)

```bash
# Step 1: Create trust policy file
$trust_policy = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$AWS_ACCOUNT_ID`:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:$GITHUB_REPO`:ref:refs/heads/$GITHUB_BRANCH"
        }
      }
    }
  ]
}
"@

$trust_policy | Out-File trust-policy.json -Encoding UTF8

# Step 2: Create IAM role
aws iam create-role `
  --role-name github-actions-ecs-deploy `
  --assume-role-policy-document file://trust-policy.json

echo "IAM Role created: github-actions-ecs-deploy"
```

### C4. Attach Policies to IAM Role

```bash
# ECR permissions
$ecr_policy = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    }
  ]
}
"@

$ecr_policy | Out-File ecr-policy.json -Encoding UTF8

aws iam put-role-policy `
  --role-name github-actions-ecs-deploy `
  --policy-name ecr-policy `
  --policy-document file://ecr-policy.json

# ECS permissions
$ecs_policy = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:DescribeServices",
        "ecs:DescribeTaskDefinition",
        "ecs:DescribeTasks",
        "ecs:ListTasks",
        "ecs:RegisterTaskDefinition",
        "ecs:UpdateService",
        "iam:PassRole"
      ],
      "Resource": "*"
    }
  ]
}
"@

$ecs_policy | Out-File ecs-policy.json -Encoding UTF8

aws iam put-role-policy `
  --role-name github-actions-ecs-deploy `
  --policy-name ecs-policy `
  --policy-document file://ecs-policy.json

echo "Policies attached"
```

### C5. Create RDS PostgreSQL

```bash
aws rds create-db-instance `
  --db-instance-identifier todo-db `
  --db-instance-class db.t3.micro `
  --engine postgres `
  --master-username postgres `
  --master-user-password "TodoApp2024Secure!" `
  --allocated-storage 20 `
  --storage-type gp2 `
  --publicly-accessible false `
  --multi-az false `
  --region $AWS_REGION

echo "RDS instance creating... (wait 10 minutes)"

# Get endpoint (run after it's available)
$RDS_ENDPOINT = aws rds describe-db-instances `
  --db-instance-identifier todo-db `
  --region $AWS_REGION `
  --query 'DBInstances[0].Endpoint.Address' `
  --output text

echo "RDS Endpoint: $RDS_ENDPOINT"
```

### C6. Create ECS Cluster

```bash
aws ecs create-cluster `
  --cluster-name prod-cluster `
  --region $AWS_REGION

echo "ECS Cluster created: prod-cluster"
```

### C7. Create IAM Instance Profile for EC2 (ECS Instances)

```bash
# Create role
aws iam create-role `
  --role-name ecsInstanceRole `
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }'

# Attach policy
aws iam attach-role-policy `
  --role-name ecsInstanceRole `
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role

# Create instance profile
aws iam create-instance-profile --instance-profile-name ecsInstanceProfile

aws iam add-role-to-instance-profile `
  --instance-profile-name ecsInstanceProfile `
  --role-name ecsInstanceRole

echo "EC2 instance profile created"
```

### C8. Create ECS Task Execution Role

```bash
aws iam create-role `
  --role-name ecsTaskExecutionRole `
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "ecs-tasks.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }'

aws iam attach-role-policy `
  --role-name ecsTaskExecutionRole `
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

echo "ECS task execution role created"
```

### C9. Create CloudWatch Log Group

```bash
aws logs create-log-group `
  --log-group-name /ecs/todo-app `
  --region $AWS_REGION

aws logs put-retention-policy `
  --log-group-name /ecs/todo-app `
  --retention-in-days 7

echo "CloudWatch log group created"
```

### C10. Create Launch Template for EC2

```bash
$user_data_base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(@"
#!/bin/bash
echo "ECS_CLUSTER=prod-cluster" >> /etc/ecs/ecs.config
systemctl restart ecs
"@))

aws ec2 create-launch-template `
  --launch-template-name ecs-instance-template `
  --version-description "ECS instance template for todo-app" `
  --launch-template-data @{
    ImageId="ami-0c02fb670d2a540c1"
    InstanceType="t3.small"
    IamInstanceProfile=@{
      Arn="arn:aws:iam::$AWS_ACCOUNT_ID`:instance-profile/ecsInstanceProfile"
    }
    UserData=$user_data_base64
  } | ConvertTo-Json | aws ec2 create-launch-template --cli-input-json file:/dev/stdin

echo "Launch template created"
```

### C11. Create Auto Scaling Group

```bash
# Get VPC and subnet info
$VPC_ID = aws ec2 describe-vpcs `
  --filters "Name=isDefault,Values=true" `
  --query 'Vpcs[0].VpcId' `
  --output text

$SUBNETS = aws ec2 describe-subnets `
  --filters "Name=vpc-id,Values=$VPC_ID" `
  --query 'Subnets[0:2].SubnetId' `
  --output text

echo "VPC: $VPC_ID"
echo "Subnets: $SUBNETS"

# Create ASG
aws autoscaling create-auto-scaling-group `
  --auto-scaling-group-name ecs-asg `
  --launch-template "LaunchTemplateName=ecs-instance-template,Version=1" `
  --min-size 2 `
  --max-size 10 `
  --desired-capacity 2 `
  --vpc-zone-identifier "$SUBNETS"

echo "Auto Scaling Group created: ecs-asg"
```

### C12. Create Application Load Balancer

```bash
# Get default VPC subnets
$SUBNETS = aws ec2 describe-subnets `
  --filters "Name=vpc-id,Values=$VPC_ID" `
  --query 'Subnets[0:2].SubnetId' `
  --output text

aws elbv2 create-load-balancer `
  --name todo-alb `
  --subnets $SUBNETS `
  --scheme internet-facing `
  --type application

$ALB_ARN = aws elbv2 describe-load-balancers `
  --names todo-alb `
  --query 'LoadBalancers[0].LoadBalancerArn' `
  --output text

echo "ALB created: $ALB_ARN"
```

### C13. Create Target Group

```bash
aws elbv2 create-target-group `
  --name todo-targets `
  --protocol HTTP `
  --port 3001 `
  --vpc-id $VPC_ID `
  --health-check-protocol HTTP `
  --health-check-path / `
  --health-check-interval-seconds 30 `
  --health-check-timeout-seconds 5 `
  --healthy-threshold-count 2 `
  --unhealthy-threshold-count 3

$TARGET_GROUP_ARN = aws elbv2 describe-target-groups `
  --names todo-targets `
  --query 'TargetGroups[0].TargetGroupArn' `
  --output text

echo "Target Group created: $TARGET_GROUP_ARN"
```

### C14. Register ALB Listener

```bash
aws elbv2 create-listener `
  --load-balancer-arn $ALB_ARN `
  --protocol HTTP `
  --port 80 `
  --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN

echo "ALB listener registered"
```

### C15. Register ECS Task Definition

```bash
# Update task-definition.json with RDS endpoint
(Get-Content task-definition.json) -replace "your-rds-endpoint.rds.amazonaws.com", $RDS_ENDPOINT | Set-Content task-definition.json

aws ecs register-task-definition `
  --cli-input-json file://task-definition.json

echo "Task definition registered"
```

### C16. Create ECS Service

```bash
aws ecs create-service `
  --cluster prod-cluster `
  --service-name todo-app-service `
  --task-definition todo-app-task:1 `
  --desired-count 2 `
  --launch-type EC2 `
  --load-balancers targetGroupArn=$TARGET_GROUP_ARN,containerName=todo-app,containerPort=3001

echo "ECS service created: todo-app-service"
```

---

## PART D: GITHUB SECRETS CONFIGURATION

### D1. Get IAM Role ARN

```bash
$ROLE_ARN = aws iam get-role `
  --role-name github-actions-ecs-deploy `
  --query 'Role.Arn' `
  --output text

echo "Role ARN: $ROLE_ARN"
```

### D2. Add Secrets to GitHub

Go to: **https://github.com/shehab-hvts/demo/settings/secrets/actions**

Create these secrets:
- **Name:** `AWS_ROLE_ARN` | **Value:** `$ROLE_ARN` (from above)
- **Name:** `AWS_REGION` | **Value:** `us-east-1`

Or use GitHub CLI:

```bash
# Install GitHub CLI if needed: choco install gh
gh auth login

gh secret set AWS_ROLE_ARN --body "$ROLE_ARN"
gh secret set AWS_REGION --body "us-east-1"
```

---

## PART E: COMMIT AND DEPLOY

### E1. Push Files to GitHub

```bash
cd "d:\D Drive\E Drive\Semester 4.2\Jobs prep\HVTS\HVTS DRIVE\demo"

git add .github/ task-definition.json

git commit -m "Part 3: GitHub Actions CI/CD + AWS integration

- Added deploy.yml workflow (GitHub Actions)
- Added pr-check.yml for PR validation
- Added task-definition.json for ECS
- Configured OIDC auth with AWS
- Ready for auto-deployment on push"

git push origin main
```

### E2. Verify GitHub Actions Run

```
Open: https://github.com/shehab-hvts/demo/actions
Expected flow:
  1. Build Docker image ✅
  2. Push to ECR ✅
  3. Register task definition ✅
  4. Deploy to ECS ✅
  5. Wait for service stability ✅
```

---

## PART F: VERIFICATION CHECKLIST

Run these commands to verify everything is working:

```bash
# 1. Check ECR has image
aws ecr describe-images --repository-name todo-app --region us-east-1

# 2. Check ECS cluster
aws ecs describe-clusters --clusters prod-cluster --region us-east-1

# 3. Check ECS service
aws ecs describe-services --cluster prod-cluster --services todo-app-service --region us-east-1

# 4. Check EC2 instances launched
aws ec2 describe-instances --filters "Name=tag:aws:autoscaling:groupName,Values=ecs-asg" --region us-east-1

# 5. Check ALB DNS
aws elbv2 describe-load-balancers --names todo-alb --query 'LoadBalancers[0].DNSName' --output text

# 6. Get ALB DNS and test
$ALB_DNS = aws elbv2 describe-load-balancers --names todo-alb --query 'LoadBalancers[0].DNSName' --output text
curl -v "http://$ALB_DNS/"
```

---

## TROUBLESHOOTING

| Issue | Solution |
|-------|----------|
| **GitHub Actions fails: "role not found"** | Check AWS_ROLE_ARN secret is correct |
| **ECS tasks stuck in PENDING** | Check EC2 instances in ASG are running & healthy |
| **ALB returns 502 Bad Gateway** | Wait 5 min for ECS tasks to fully start |
| **RDS connection timeout** | Check security groups allow inbound 5432 from EC2 |
| **ECR image push fails** | Verify IAM role has ecr:PutImage permission |

---

## COST BREAKDOWN (Monthly)

| Resource | Cost | Notes |
|----------|------|-------|
| 2x t3.small EC2 (ASG) | $15-30 | Can scale to 10 |
| RDS t3.micro | $15-20 | Single AZ |
| ALB | $16 | Fixed cost |
| Data transfer | $5-10 | Varies by traffic |
| **Total** | **~$50-75/month** | vs $200+ for Fargate |

---

## NEXT STEPS AFTER DEPLOYMENT

1. ✅ App is live at `http://ALB_DNS_NAME`
2. ✅ Push to main branch → auto-deploys in 3-5 min
3. ⏭️ Add monitoring: CloudWatch alarms, X-Ray tracing
4. ⏭️ Add auto-scaling: Target CPU 70%, scale 2-10 instances
5. ⏭️ Set up custom domain: Route53 + ACM certificate

---

**Status:** Ready to execute. Run Part C-E in sequence.
