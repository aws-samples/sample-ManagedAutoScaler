---
name: Security Issue
about: Report a security vulnerability (use only for non-sensitive issues)
title: '[SECURITY] '
labels: 'security'
assignees: ''

---

## ⚠️ IMPORTANT SECURITY NOTICE ⚠️

**For sensitive security vulnerabilities, please DO NOT create a public issue.**

Instead, please report security vulnerabilities privately by:
- **Email**: [security@yourorganization.com] (replace with actual security contact)
- **Subject**: "SECURITY: Aurora AutoScaler Vulnerability Report"

See our [Security Policy](../../SECURITY.md) for detailed reporting instructions.

---

## Public Security Issue
**Use this template only for non-sensitive security improvements or questions.**

## Issue Type
- [ ] Security configuration question
- [ ] Security best practices inquiry
- [ ] Non-sensitive security improvement suggestion
- [ ] Security documentation issue

## Description
A clear description of the security-related issue or question.

## Environment
**AWS Region:** 
**Deployment Type:** (Production/Staging/Development)
**Security Features Enabled:**
- [ ] Security hardening
- [ ] CloudTrail logging
- [ ] Access Analyzer
- [ ] KMS encryption
- [ ] VPC integration

## Current Configuration
```hcl
# Relevant terraform.tfvars settings
enable_security_hardening = true
enable_cloudtrail = true
# ... other security settings
```

## Security Concern
**What security aspect are you concerned about?**
- [ ] IAM permissions
- [ ] Network security
- [ ] Data encryption
- [ ] Audit logging
- [ ] Access controls
- [ ] Compliance requirements

## Proposed Improvement
**How could security be improved?**

## Compliance Requirements
**Are there specific compliance frameworks you need to meet?**
- [ ] SOC 2
- [ ] PCI DSS
- [ ] HIPAA
- [ ] GDPR
- [ ] Other: ___________

## Additional Context
Any additional information about your security requirements or concerns.

## Checklist
- [ ] This is NOT a sensitive security vulnerability
- [ ] I have reviewed the Security Policy
- [ ] I have checked existing security documentation
- [ ] This relates to configuration or best practices