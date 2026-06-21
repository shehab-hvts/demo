param(
  [string]$Region = 'eu-north-1',
  [string]$RepositoryPath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'

$aws = 'C:\Program Files\Amazon\AWSCLIV2\aws.exe'
$gh = 'C:\Program Files\GitHub CLI\gh.exe'

function Invoke-AwsText {
  param([string[]]$Args)
  $result = & $aws @Args --output text 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "AWS CLI failed: aws $($Args -join ' ') --output text`n$($result -join [Environment]::NewLine)"
  }
  return ($result | Out-String).Trim()
}

function Invoke-AwsJson {
  param([string[]]$Args)
  $result = & $aws @Args --output json 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "AWS CLI failed: aws $($Args -join ' ') --output json`n$($result -join [Environment]::NewLine)"
  }
  return (($result | Out-String) | ConvertFrom-Json)
}

function Invoke-AwsVoid {
  param([string[]]$Args)
  $result = & $aws @Args 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "AWS CLI failed: aws $($Args -join ' ')`n$($result -join [Environment]::NewLine)"
  }
}

function Test-AwsCommand {
  param([string[]]$Args)
  & $aws @Args *> $null
  return ($LASTEXITCODE -eq 0)
}

function Ensure-Role {
  param(
    [string]$RoleName,
    [string]$TrustService,
    [string]$ManagedPolicyArn
  )

  if (-not (Test-AwsCommand @('iam', 'get-role', '--role-name', $RoleName))) {
    $trustPath = Join-Path $env:TEMP "$RoleName-trust.json"
    @{
      Version = '2012-10-17'
      Statement = @(@{
        Effect = 'Allow'
        Principal = @{ Service = $TrustService }
        Action = 'sts:AssumeRole'
      })
    } | ConvertTo-Json -Depth 5 | Set-Content -Path $trustPath -Encoding ascii

    Invoke-AwsVoid @('iam', 'create-role', '--role-name', $RoleName, '--assume-role-policy-document', "file://$trustPath")
  }

  Invoke-AwsVoid @('iam', 'attach-role-policy', '--role-name', $RoleName, '--policy-arn', $ManagedPolicyArn)
}

function Ensure-InstanceProfile {
  param(
    [string]$ProfileName,
    [string]$RoleName
  )

  if (-not (Test-AwsCommand @('iam', 'get-instance-profile', '--instance-profile-name', $ProfileName))) {
    Invoke-AwsVoid @('iam', 'create-instance-profile', '--instance-profile-name', $ProfileName)
  }

  $profile = Invoke-AwsJson @('iam', 'get-instance-profile', '--instance-profile-name', $ProfileName)
  $attachedRoleNames = @($profile.InstanceProfile.Roles | ForEach-Object { $_.RoleName })
  if ($attachedRoleNames -notcontains $RoleName) {
    Invoke-AwsVoid @('iam', 'add-role-to-instance-profile', '--instance-profile-name', $ProfileName, '--role-name', $RoleName)
  }
}

function Ensure-Cluster {
  param([string]$ClusterName)

  $describe = Invoke-AwsJson @('ecs', 'describe-clusters', '--clusters', $ClusterName, '--region', $Region)
  if (-not $describe.clusters -or $describe.clusters.Count -eq 0) {
    Invoke-AwsVoid @('ecs', 'create-cluster', '--cluster-name', $ClusterName, '--region', $Region)
  }
}

function Ensure-LogGroup {
  param([string]$LogGroupName)

  $exists = Test-AwsCommand @('logs', 'describe-log-groups', '--log-group-name-prefix', $LogGroupName, '--region', $Region)
  if ($exists) {
    $groups = Invoke-AwsJson @('logs', 'describe-log-groups', '--log-group-name-prefix', $LogGroupName, '--region', $Region)
    if (-not ($groups.logGroups | Where-Object { $_.logGroupName -eq $LogGroupName })) {
      Invoke-AwsVoid @('logs', 'create-log-group', '--log-group-name', $LogGroupName, '--region', $Region)
    }
  }
  Invoke-AwsVoid @('logs', 'put-retention-policy', '--log-group-name', $LogGroupName, '--retention-in-days', '30', '--region', $Region)
}

function Get-OrCreateSecurityGroup {
  param(
    [string]$Name,
    [string]$Description,
    [string]$VpcId
  )

  $query = "SecurityGroups[0].GroupId"
  $groupId = Invoke-AwsText @('ec2', 'describe-security-groups', '--filters', "Name=group-name,Values=$Name", "Name=vpc-id,Values=$VpcId", '--region', $Region, '--query', $query)
  if (-not $groupId -or $groupId -eq 'None') {
    $groupId = Invoke-AwsText @('ec2', 'create-security-group', '--group-name', $Name, '--description', $Description, '--vpc-id', $VpcId, '--region', $Region, '--query', 'GroupId')
  }

  return $groupId
}

function Ensure-IngressCidr {
  param(
    [string]$GroupId,
    [string]$Port,
    [string]$Cidr
  )

  try {
    Invoke-AwsVoid @('ec2', 'authorize-security-group-ingress', '--group-id', $GroupId, '--protocol', 'tcp', '--port', $Port, '--cidr', $Cidr, '--region', $Region)
  } catch {
    if ($_.Exception.Message -notmatch 'InvalidPermission.Duplicate') { throw }
  }
}

function Ensure-IngressSourceGroup {
  param(
    [string]$GroupId,
    [string]$Port,
    [string]$SourceGroupId
  )

  try {
    Invoke-AwsVoid @('ec2', 'authorize-security-group-ingress', '--group-id', $GroupId, '--protocol', 'tcp', '--port', $Port, '--source-group', $SourceGroupId, '--region', $Region)
  } catch {
    if ($_.Exception.Message -notmatch 'InvalidPermission.Duplicate') { throw }
  }
}

function New-SecurePassword {
  $chars = ((48..57) + (65..90) + (97..122) + 33,35,36,37,42,64)
  return (-join (1..28 | ForEach-Object { [char]($chars | Get-Random) }))
}

Invoke-AwsVoid @('ecr', 'put-image-scanning-configuration', '--repository-name', 'todo-app', '--image-scanning-configuration', 'scanOnPush=true', '--region', $Region)

$accountId = Invoke-AwsText @('sts', 'get-caller-identity', '--query', 'Account')
$vpcId = Invoke-AwsText @('ec2', 'describe-vpcs', '--filters', 'Name=isDefault,Values=true', '--region', $Region, '--query', 'Vpcs[0].VpcId')
$subnetId = Invoke-AwsText @('ec2', 'describe-subnets', '--filters', "Name=vpc-id,Values=$vpcId", 'Name=default-for-az,Values=true', '--region', $Region, '--query', 'Subnets[0].SubnetId')

$appSecurityGroupId = Get-OrCreateSecurityGroup -Name 'todo-app-ec2-sg' -Description 'Security group for todo-app ECS host' -VpcId $vpcId
$dbSecurityGroupId = Get-OrCreateSecurityGroup -Name 'todo-db-sg' -Description 'Security group for todo-app PostgreSQL' -VpcId $vpcId
Ensure-IngressCidr -GroupId $appSecurityGroupId -Port '3001' -Cidr '0.0.0.0/0'
Ensure-IngressSourceGroup -GroupId $dbSecurityGroupId -Port '5432' -SourceGroupId $appSecurityGroupId

Ensure-Role -RoleName 'ecsInstanceRole' -TrustService 'ec2.amazonaws.com' -ManagedPolicyArn 'arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role'
Ensure-Role -RoleName 'ecsTaskExecutionRole' -TrustService 'ecs-tasks.amazonaws.com' -ManagedPolicyArn 'arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy'
Ensure-InstanceProfile -ProfileName 'ecsInstanceProfile' -RoleName 'ecsInstanceRole'
Ensure-Cluster -ClusterName 'prod-cluster'
Ensure-LogGroup -LogGroupName '/ecs/todo-app'

$dbDescribeOk = Test-AwsCommand @('rds', 'describe-db-instances', '--db-instance-identifier', 'todo-db', '--region', $Region)
$dbPassword = $null
if (-not $dbDescribeOk) {
  $dbPassword = New-SecurePassword
  Invoke-AwsVoid @(
    'rds', 'create-db-instance',
    '--db-instance-identifier', 'todo-db',
    '--db-name', 'todo_db',
    '--db-instance-class', 'db.t3.micro',
    '--engine', 'postgres',
    '--engine-version', '16.4',
    '--master-username', 'postgres',
    '--master-user-password', $dbPassword,
    '--allocated-storage', '20',
    '--storage-type', 'gp3',
    '--publicly-accessible', 'false',
    '--no-multi-az',
    '--storage-encrypted',
    '--vpc-security-group-ids', $dbSecurityGroupId,
    '--backup-retention-period', '7',
    '--enable-cloudwatch-logs-exports', 'postgresql',
    '--region', $Region
  )
}

Invoke-AwsVoid @('rds', 'wait', 'db-instance-available', '--db-instance-identifier', 'todo-db', '--region', $Region)

$dbEndpoint = Invoke-AwsText @('rds', 'describe-db-instances', '--db-instance-identifier', 'todo-db', '--region', $Region, '--query', 'DBInstances[0].Endpoint.Address')

$parameterName = '/todo-app/prod/database-url'
$parameterArn = $null
$parameterDescribe = Invoke-AwsJson @('ssm', 'describe-parameters', '--parameter-filters', "Key=Name,Values=$parameterName", '--region', $Region)
if ($parameterDescribe.Parameters.Count -gt 0) {
  $parameterArn = $parameterDescribe.Parameters[0].ARN
} elseif ($dbPassword) {
  $databaseUrl = "postgresql://postgres:$dbPassword@$dbEndpoint:5432/todo_db"
  Invoke-AwsVoid @('ssm', 'put-parameter', '--name', $parameterName, '--type', 'SecureString', '--value', $databaseUrl, '--overwrite', '--region', $Region)
  $parameterDescribe = Invoke-AwsJson @('ssm', 'describe-parameters', '--parameter-filters', "Key=Name,Values=$parameterName", '--region', $Region)
  $parameterArn = $parameterDescribe.Parameters[0].ARN
} else {
  throw 'DATABASE_URL parameter is missing and the RDS password is not available to recreate it safely.'
}

Push-Location $RepositoryPath
try {
  Invoke-Expression "& '$gh' secret set AWS_DATABASE_URL_PARAMETER_ARN --body '$parameterArn'" | Out-Null
} finally {
  Pop-Location
}

$amiId = Invoke-AwsText @('ssm', 'get-parameter', '--name', '/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id', '--region', $Region, '--query', 'Parameter.Value')
$instanceId = Invoke-AwsText @('ec2', 'describe-instances', '--filters', 'Name=tag:Name,Values=todo-ecs-host', 'Name=instance-state-name,Values=pending,running,stopping,stopped', '--region', $Region, '--query', 'Reservations[0].Instances[0].InstanceId')
if (-not $instanceId -or $instanceId -eq 'None') {
  $userDataPath = Join-Path $env:TEMP 'todo-ecs-user-data.sh'
  @"
#!/bin/bash
echo ECS_CLUSTER=prod-cluster >> /etc/ecs/ecs.config
"@ | Set-Content -Path $userDataPath -Encoding ascii

  $instanceId = Invoke-AwsText @(
    'ec2', 'run-instances',
    '--image-id', $amiId,
    '--instance-type', 't3.micro',
    '--iam-instance-profile', 'Name=ecsInstanceProfile',
    '--security-group-ids', $appSecurityGroupId,
    '--subnet-id', $subnetId,
    '--monitoring', 'Enabled=true',
    '--user-data', "file://$userDataPath",
    '--tag-specifications', 'ResourceType=instance,Tags=[{Key=Name,Value=todo-ecs-host}]',
    '--region', $Region,
    '--query', 'Instances[0].InstanceId'
  )
}

Invoke-AwsVoid @('ec2', 'wait', 'instance-running', '--instance-ids', $instanceId, '--region', $Region)
$publicIp = Invoke-AwsText @('ec2', 'describe-instances', '--instance-ids', $instanceId, '--region', $Region, '--query', 'Reservations[0].Instances[0].PublicIpAddress')
$containerInstances = Invoke-AwsJson @('ecs', 'list-container-instances', '--cluster', 'prod-cluster', '--region', $Region)

[pscustomobject]@{
  AccountId = $accountId
  VpcId = $vpcId
  SubnetId = $subnetId
  AppSecurityGroupId = $appSecurityGroupId
  DbSecurityGroupId = $dbSecurityGroupId
  DbEndpoint = $dbEndpoint
  DatabaseUrlParameterArn = $parameterArn
  InstanceId = $instanceId
  InstancePublicIp = $publicIp
  ContainerInstanceCount = @($containerInstances.containerInstanceArns).Count
} | ConvertTo-Json -Depth 4