# AWS Todo Deployment Report

## Deployment Summary

- Date: 2026-06-21
- Region requested: `eu-north-1` (Stockholm)
- AWS account: `340010512290`
- Budget ceiling currently approved: `$5.00/month`
- Status: `PENDING - secure auth setup required before deployment`

No AWS resources were created.

## Why Deployment Was Stopped

The original instruction set required an immediate stop if the estimated monthly cost exceeded `$1.00/month`.

You later approved a `$5.00/month` budget.

With the ALB removed, the cost picture changes materially.

Verified AWS VPC pricing shows public IPv4 addresses are billed per hour.

For a simple EC2-hosted ECS service that is reachable from the internet, at least one public IPv4 address is typically required.

AWS currently lists:

- Hourly charge for in-use public IPv4 address: `$0.005/hour`

That alone is approximately:

`0.005 * 24 * 30 = $3.60/month`

That means the revised no-ALB architecture is not compatible with a `$1.00/month` ceiling if the application must be publicly reachable over IPv4.

Under the revised `$5.00/month` ceiling, this can fit only if the AWS account is still eligible for EC2 and RDS free tier usage.

There is a second hard blocker in the current environment:

- AWS CLI was not initially installed
- AWS CLI is now installed locally
- No AWS credentials are configured for this machine
- `aws sts get-caller-identity` currently fails with `NoCredentials`

There is also a GitHub management blocker:

- GitHub CLI is installed locally
- No authenticated GitHub CLI session exists yet
- Repository secrets cannot be created until GitHub authentication is completed

## Verified Cost Analysis

### Requested Architecture

- EC2 `t3.micro`: potentially free-tier eligible, but only if the account still qualifies
- RDS `db.t3.micro`: potentially free-tier eligible, but only if the account still qualifies
- ECR storage: low cost, typically cents per month
- CloudWatch Logs: can remain within free tier at low volume
- Public IPv4 for internet reachability: not within `$1.00/month`

### Estimated Monthly Cost With `$5` Cap

- EC2 `t3.micro`: `$0` if free tier applies
- RDS `db.t3.micro`: `$0` if free tier applies
- Public IPv4: about `$3.60/month`
- ECR storage: about `$0.01/month`
- Data transfer and logs at low usage: small variable amount

Estimated total while free tier applies: about `$3.61+` per month

### Blocking Cost Item

- Public IPv4 base cost estimate: about `$3.60/month` for one in-use address

### Additional Risk Items

- Additional public IPv4 addresses would increase cost linearly
- Free tier is not guaranteed without confirming account age and plan eligibility
- RDS and EC2 cease being effectively free once free tier eligibility ends, which would likely push this architecture above `$5/month`

## Security And Privacy Findings

### Verified Safety Controls Applied In This Session

- No AWS resources were provisioned
- No AWS credentials were requested or printed
- No secrets were committed to the repository
- The plaintext password that was already present in the repository was removed from the ECS task definition template

### Security Issue In The Requested Steps

The provided variable `RDS_PASSWORD` is a plaintext secret. Using that value directly in CLI commands, task definitions, workflow files, or repository content would violate your own security requirement of no hardcoded secrets.

That secret was not written into any new project file by this session.

### Required Secure Approach

- Store database credentials in SSM Parameter Store as a `SecureString` to avoid the monthly cost of Secrets Manager
- Reference the full `DATABASE_URL` at runtime through ECS task secret injection
- Keep GitHub Actions AWS credentials in GitHub Secrets or OIDC-based federation
- Keep RDS non-public and restrict security groups to required traffic only

## Infrastructure Execution Status

### Phase 0: Security Baseline

- Partial review completed
- Secure secret handling requirement identified
- No resources created

### Phase 1: AWS Infrastructure

- Not executed
- Reason: AWS credentials are unavailable and free-tier eligibility is unverified

### Phase 2: Task Definition

- Prepared securely in repository template form only
- Plaintext database URL removed
- Region corrected to `eu-north-1`

### Phase 3: GitHub Actions Setup

- Secure deployment workflow template prepared in repository
- Reason not executed: repository secrets and GitHub authentication are not configured

### Phase 4: ECS Service

- Not executed
- Reason: deployment aborted before infrastructure creation

## Resource Inventory

No AWS resources were created, so there are no live values for:

- ECR repository URI
- RDS endpoint
- EC2 instance ID
- ECS cluster ARN
- ECS service ARN
- ALB DNS name

## What Was Fixed

The main planning error in the original runbook was the assumption that the deployment could stay below `$1.00/month` once internet reachability costs were included.

With your revised `$5.00/month` ceiling, the design can be acceptable only while EC2 and RDS remain free-tier eligible.

The repository also contained an unsafe ECS task definition with a plaintext `DATABASE_URL`. That has been corrected to use ECS secret injection with a parameter ARN placeholder.

A secure GitHub Actions deployment workflow has also been added, using GitHub Secrets instead of hardcoded AWS credentials.

## Recommended Under-Budget Alternative

To stay below `$5/month`, keep the footprint to one EC2 instance, one small RDS instance only while free tier applies, one public IPv4 address, and minimal image/log storage.

The practical low-cost alternative is:

1. Use a single `t3.micro` or `t4g.micro` instance only if you have confirmed free-tier eligibility.
2. Run the app with Docker directly on EC2.
3. Use a local Docker volume or SQLite instead of RDS if data durability requirements allow it.
4. Keep the instance private and access it through AWS Systems Manager Session Manager or a VPN.
5. Use GitHub Actions to deploy through SSM instead of exposing a public IPv4 address.

If the account is no longer free-tier eligible for EC2 or RDS, stop and re-estimate before provisioning.

## If You Want A Secure AWS Path Anyway

If you want the ECS plus RDS architecture, the next safe step is to approve a higher budget cap first.

If you want me to execute the deployment from this machine, these prerequisites still must be completed first:

- Configure AWS CLI credentials locally
- Authenticate GitHub CLI locally
- Add repository secrets securely without writing them to files

## Monitoring And Cost Control Guidance

If you later proceed on AWS, set these before provisioning:

- AWS Budgets alert at `$1`, `$5`, and `$20`
- Cost Explorer enabled
- CloudWatch log retention explicitly set
- ECR lifecycle policy to expire old images
- Periodic review of public IPv4 usage

## Final Result

- Deployment executed: `No`
- Budget policy respected: `Yes, conditionally under free tier and current $5 cap`
- Security policy respected: `Yes`
- Data privacy policy respected: `Yes`
- Local AWS CLI installed: `Yes`
- Local AWS credentials available: `No`
- Local GitHub CLI installed: `Yes`
- Local GitHub authentication available: `No`

## References

- AWS VPC pricing: https://aws.amazon.com/vpc/pricing/
- GitHub repository: https://github.com/shehab-hvts/demo