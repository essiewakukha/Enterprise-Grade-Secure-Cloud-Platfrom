# Enterprise-Grade Secure Cloud Platform

A multi-account, zero-trust AWS foundation built for a Central Bank of Kenya–regulated
fintech migrating core production workloads to the cloud. Six infrastructure layers,
deployed and proven in a real AWS account — not a simulation.

**Repo:** [github.com/essiewakukha/Enterprise-Grade-Secure-Cloud-Platfrom](https://github.com/essiewakukha/Enterprise-Grade-Secure-Cloud-Platfrom)

---

## What this is

Six Terraform layers, applied independently against a live multi-account AWS
Organization, covering governance, identity, detection & response, continuous
compliance, and application security — each with real evidence captured, not just
code that "should work."

| Layer | Covers |
|---|---|
| `terraform/org` | AWS Organizations, OUs, Service Control Policy, org-wide CloudTrail |
| `terraform/iam` | Permission boundary, `DevOpsEngineer` role, GitHub OIDC federation |
| `terraform/incident-response` | GuardDuty → EventBridge → Step Functions → Lambda → SNS + S3 |
| `terraform/compliance` | AWS Config, auto-remediation, Security Hub, Inspector |
| `terraform/appsec` | ALB, WAF, sample app, ACM |
| `terraform/encryption` | Customer-managed KMS key, ACM certificate |

## Account structure

```
AWS Organization (Management: 207567786898)
├── Security OU
│   ├── Logging account (077489419337)
│   └── Security tooling account (747705454475)
├── Production OU
│   └── Production account (353362989916)  ← everything below lives here
└── Development OU
    └── Development account (889580843213)
```

---

## What's proven, and how

Every claim below was verified against real AWS output during a live build session —
not assumed from the Terraform code alone.

### 1. Governance — SCPs override even admin-level IAM

A Service Control Policy on the Production OU denies `ec2:TerminateInstances` and
`cloudtrail:StopLogging`/`DeleteTrail`/`UpdateTrail` for every principal in the
account, including `OrganizationAccountAccessRole` (full `AdministratorAccess`).

**Proof:** launched a real EC2 instance, assumed the admin role, attempted
`ec2:TerminateInstances` against the running instance. Result:

```
An error occurred (UnauthorizedOperation) when calling the TerminateInstances
operation: ... with an explicit deny in a service control policy:
arn:aws:organizations::207567786898:policy/o-7t7a99koq2/service_control_policy/p-o0ws4v62
```

The SCP was independently re-verified after an unrelated `terraform destroy`
incident partially tore down and rebuilt this layer mid-session — confirmed still
attached and enforcing (`p-o0ws4v62`) after recovery.

### 2. Identity — permission boundaries cap even PowerUserAccess

The `DevOpsEngineer` role has `PowerUserAccess` attached but is capped by a
permission boundary that explicitly denies destructive S3 actions
(`DeleteObject`, `DeleteBucket`, `PutBucketPolicy`, etc.) and IAM privilege
escalation paths.

**Proof:** assumed `DevOpsEngineer`, attempted `s3:DeleteObject` on a real test
bucket. Result:

```
An error occurred (AccessDenied) when calling the DeleteObject operation: ...
with an explicit deny in a permissions boundary:
arn:aws:iam::353362989916:policy/DevOpsEngineerPermissionBoundary
```

Same result for `DeleteBucket` — confirmed the boundary blocks uniformly, not
just on one action.

GitHub OIDC federation (provider + `GitHubActionsDeployRole`, trust policy scoped
to `essiewakukha/Enterprise-Grade-Secure-Cloud-Platfrom:ref:refs/heads/main`) is
deployed and IAM-verified. A live GitHub Actions run hit an unresolved
`AssumeRoleWithWebIdentity` denial despite a correct trust policy and matching
branch/repo — logged as an open item, see Known Limitations.

### 3. Detection & response — the full pipeline, proven twice

`GuardDuty → EventBridge → Step Functions → Lambda → SNS + S3`, fully automated,
zero manual intervention required once a finding lands.

**Proof, happy path (manual, real instance):** started a Step Functions execution
with a real running EC2 instance ID. Result: `SUCCEEDED` in ~3 seconds — finding
logged to S3, instance tagged `SecurityStatus=Quarantined` and moved to a
network-isolated security group (no inbound/outbound), SNS notification delivered
with the full audit trail embedded.

**Proof, automatic trigger (real GuardDuty sample finding):**
`guardduty create-sample-findings` → EventBridge → Step Functions fired
**without any manual `start-execution` call** — confirmed by the execution's
auto-generated name (`16d34f10-...`) rather than a human-chosen one. This
particular finding referenced a synthetic, non-existent instance ID
(`i-99999999`, GuardDuty's sample-finding convention) — the isolation step
correctly failed, was caught by the state machine's error handling, and the
security team was still notified with the failure reason attached. This is the
resilience design working as intended: a downstream failure degrades gracefully
rather than silently dropping a high-severity finding.

### 4. Continuous compliance — Config, remediation, Security Hub

Two Config rules deployed, both with SSM auto-remediation attached:

- `s3-bucket-server-side-encryption-enabled` → `AWS-EnableS3BucketEncryption`
- `s3-bucket-public-read-prohibited` → `AWS-DisableS3BucketPublicReadWrite`

**Notable finding:** AWS changed S3's platform defaults in January 2023 — every
new bucket now gets default encryption (`AES256`) applied automatically, with no
way to opt out via the API. This makes the spec's literal test ("deploy an
unencrypted bucket, watch it auto-remediate") structurally impossible to trigger
today. Verified directly: deleting a bucket's encryption config via
`delete-bucket-encryption` shows it reapplied **instantly**, faster than Config's
evaluation cycle could ever run — this is AWS's own platform default, not our
remediation. The remediation configuration itself was independently confirmed
correctly wired via `describe-remediation-configurations` (correct SSM document,
correct IAM role, `automatic: true`).

The second rule (public-read prohibition) is genuinely triggerable and was
exercised: a test bucket's policy was set to public, Config evaluation was
triggered, and the rule correctly reported the change — full remediation
execution logging hit an unrelated S3 permissions quirk on that specific test
artifact during verification, documented as a known limitation below.

Security Hub is enabled with the AWS Foundational Security Best Practices
standard (`StandardsStatus: READY`, independently confirmed via
`get-enabled-standards`), Inspector is enabled for EC2/ECR, and an EventBridge
rule forwards HIGH/CRITICAL Security Hub findings to the same SNS topic used by
the incident-response pipeline.

### 5. Application security — WAF proven against real attacks

A sample app runs behind an ALB protected by a WAFv2 Web ACL:
`AWSManagedRulesCommonRuleSet`, `AWSManagedRulesSQLiRuleSet`, and a rate-based
rule (100 requests / 5 minutes / IP).

**Proof — all three attack types tested against the live ALB:**

| Test | Result |
|---|---|
| SQL injection (`?id=1' OR '1'='1`) | `HTTP 403` |
| XSS (`?q=<script>alert(1)</script>`) | `HTTP 403` |
| Rate limit (120 rapid requests) | `HTTP 200` × 117, then `HTTP 403` × 3, transition at request 118 |

Along the way, a real deployment bug was found and fixed: the original AMI
(`ami-0c02fb55956c7d316`, Amazon Linux 2) was paired with `dnf`-based user data,
but AL2 requires `yum` — this silently prevented `httpd` from installing,
causing the ALB target to fail health checks (`502 Bad Gateway`). Fixed by
switching to `yum` and refreshing to a current AL2 AMI; confirmed via target
health check transitioning to `healthy`.

### 6. Encryption

A customer-managed KMS key (`fintech-platform-cmk`) with automatic annual
rotation enabled, administered by a named IAM user rather than relying solely on
root account access — a deliberate choice to avoid a single point of failure
while keeping the root account as a documented safety net (see key policy).

---

## Known limitations (honest, not hidden)

Real infrastructure work surfaces real constraints. These are documented rather
than glossed over:

1. **HTTPS listener is disabled.** ACM will not attach a `PENDING_VALIDATION`
   certificate to an ALB listener — confirmed directly
   (`UnsupportedCertificate` error). Our certificate uses a placeholder domain
   with no real DNS control, so it can never complete validation. The HTTP
   listener currently forwards directly to the app rather than redirecting to
   HTTPS (to avoid breaking availability). **Remediation path:** register a real
   domain (~$12/year), complete ACM's DNS validation, restore the commented-out
   HTTPS listener in `terraform/appsec/app.tf`, and revert the HTTP listener to
   a 301 redirect.

2. **The literal "unencrypted S3 bucket" auto-remediation test cannot be
   performed** on any AWS account created after January 2023, due to AWS's own
   platform-level default encryption. The remediation mechanism itself is
   deployed and independently verified as correctly configured.

3. **GitHub Actions OIDC workflow returned `AccessDenied`** on a live run
   despite a trust policy that appears correct in every dimension checked
   (exact repo/org match, exact branch match, correct role ARN, correct
   audience). The AWS-side infrastructure (OIDC provider, trust policy,
   `GitHubActionsDeployRole`) is deployed and confirmed correct via direct IAM
   inspection. This is logged as an open debugging item rather than a design
   flaw — the same trust-policy pattern is standard and well-documented; the
   root cause here wasn't isolated within the session.

4. **Root-email aliasing** (Gmail `+` addressing) was used to provision the four
   member accounts, appropriate for a single-owner lab/portfolio environment.
   Production deployment would use dedicated, monitored group mailboxes per
   account for proper separation of duties.

---

## A real incident, mid-build: partial destroy failure

Worth documenting because it's a genuine, transferable lesson. A `terraform
destroy` was run against the `org` layer late in the build. AWS Organizations
does not allow member accounts to be removed via API unless they have full
standalone billing/contact prerequisites configured — which fresh
Terraform-created accounts never have. The destroy **partially succeeded**: it
tore down CloudTrail, the KMS key, the SCP, and the S3 bucket policy (all of
which have no such restriction) before halting on the account-removal step,
leaving Terraform state and real AWS state out of sync.

Recovery: a careful `terraform plan` review confirmed the four accounts and
three OUs were untouched — only the CloudTrail pipeline had been torn down — and
a subsequent `terraform apply` cleanly rebuilt exactly what was missing, nothing
more.

**Takeaway for the report:** `terraform destroy` on any layer containing
`aws_organizations_account` resources should never be run in production. If
partial teardown is genuinely needed, target specific resources with
`-target` rather than a full destroy.

---

## Repo structure

```
terraform/
  org/              AWS Organizations, OUs, SCP, org-wide CloudTrail
  iam/              Permission boundary, DevOpsEngineer role, GitHub OIDC
  incident-response/  GuardDuty, EventBridge, Step Functions, Lambda, SNS, S3
  compliance/       AWS Config, auto-remediation, Security Hub, Inspector
  appsec/           ALB, WAF, sample app, ACM certificate
  encryption/       Customer-managed KMS key
lambda/
  validate-finding/   Validates + logs GuardDuty findings to S3
  isolate-instance/   Tags + quarantines an EC2 instance via SG swap
.github/workflows/
  deploy.yml                    CI/CD pipeline using OIDC (infra deployed, live run unresolved)
  deploy-unauthorized-test.yml  Proves unauthorized branches are denied by OIDC trust policy
```

## Prerequisites to reproduce

- An AWS account (Management account for a fresh Organization, or an existing
  Organization's management account)
- Four unique email addresses for member account creation (or `+` aliasing on
  Gmail)
- An IAM user to serve as KMS key administrator
- Terraform >= 1.6.0, AWS CLI v2
- A real domain, if you want working HTTPS end-to-end (optional — everything
  else functions without it)

Each layer has its own `terraform.tfvars.example` — copy to `terraform.tfvars`
and fill in real values before running `terraform init && terraform plan`.