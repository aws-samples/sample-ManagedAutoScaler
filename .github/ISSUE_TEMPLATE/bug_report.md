---
name: Bug report
about: Create a report to help us improve the Aurora AutoScaler
title: '[BUG] '
labels: 'bug'
assignees: ''

---

## Bug Description
A clear and concise description of what the bug is.

## Environment Information
**AWS Region:** (e.g., us-east-1, eu-central-1)
**Aurora Version:** (e.g., PostgreSQL 13.7, 14.6)
**Terraform Version:** (e.g., 1.5.0)
**Python Version:** (e.g., 3.13.0)

## Configuration
**Instance Types:** (e.g., db.r5.large, db.r6g.large)
**Availability Zones:** (e.g., us-east-1a, us-east-1b)
**CPU Threshold:** (e.g., 10.0%)
**Lookback Minutes:** (e.g., 5)

## Steps to Reproduce
1. Go to '...'
2. Run command '...'
3. See error

## Expected Behavior
A clear and concise description of what you expected to happen.

## Actual Behavior
A clear and concise description of what actually happened.

## Error Messages
```
Paste any error messages, stack traces, or log output here
```

## CloudWatch Logs
If applicable, include relevant CloudWatch log entries:
- `/aws/lambda/aurora-autoscale-up`
- `/aws/lambda/aurora-downscale`

## Terraform Output
If the issue is deployment-related, include:
```hcl
# terraform plan or apply output
```

## Screenshots
If applicable, add screenshots to help explain your problem.

## Additional Context
Add any other context about the problem here:
- Recent changes to infrastructure
- Network configuration details
- Security group settings
- Any workarounds you've tried

## Checklist
- [ ] I have searched existing issues to avoid duplicates
- [ ] I have included all relevant configuration details
- [ ] I have included error messages and logs
- [ ] I have tested with the latest version
- [ ] I have followed the troubleshooting guide in the README

## Impact Assessment
- **Severity:** (Critical/High/Medium/Low)
- **Affected Components:** (Scale-up/Scale-down/Notifications/Deployment)
- **Business Impact:** (Production down/Performance degraded/Development blocked/etc.)

## Possible Solution
If you have ideas on how to fix the issue, please describe them here.