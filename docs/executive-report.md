# Enterprise-Grade Secure Cloud Platform
### Executive & Technical Report


---

## 1. Executive Summary

This report documents the design, deployment, and — critically — the **live
testing** of a multi-account, zero-trust AWS foundation for a fictional
Central Bank of Kenya–regulated fintech migrating core production services to
AWS. Unlike a purely theoretical design exercise, every control described
here was deployed into a real AWS Organization and exercised against real,
adversarial test conditions: security controls were attacked with genuinely
privileged credentials to confirm they hold, and the automated
incident-response pipeline was triggered both manually and by an actual
GuardDuty finding to confirm it fires without human intervention.

The platform spans six independently deployable layers — governance,
identity, detection & response, continuous compliance, application security,
and encryption — organized as separate Terraform root modules against a real
AWS Organization with four member accounts.

This report is written in the spirit of an honest engineering postmortem
rather than a marketing summary: it documents what was proven, what was
found to no longer apply due to platform changes since the reference material
was written, and what remains unresolved.

---

## 2. Architecture Overview

### 2.1 Account structure

A multi-account strategy was used rather than a single-account, tag-based
isolation model, on the standard reasoning that accounts are the strongest
isolation boundary AWS offers — no shared IAM namespace, no shared VPC, no
shared KMS key policy between accounts unless explicitly granted.

```
AWS Organization (Management: 207567786898)
├── Security OU
│   ├── Logging account (077489419337)
│   └── Security tooling account (747705454475)
├── Production OU  — SCP-governed
│   └── Production account (353362989916)
└── Development OU
    └── Development account (889580843213)
```

All workload infrastructure (identity roles, GuardDuty, Step Functions, Config,
Security Hub, WAF, the sample application) was deployed into the Production
account, reached from the Management account via the auto-provisioned
`OrganizationAccountAccessRole` — the same cross-account assumption pattern
used throughout the build for anything needing to operate inside a member
account.

### 2.2 Identity flow

No human or CI/CD system holds a permanent AWS access key in this design.
Human access during the build used short-lived `sts assume-role` sessions.
CI/CD access is designed around GitHub's OIDC identity provider: a
`GitHubActionsDeployRole` whose trust policy matches only
`repo:essiewakukha/Enterprise-Grade-Secure-Cloud-Platfrom:ref:refs/heads/main`,
which is permitted to assume `DevOpsEngineer` — a role capped by a permission
boundary regardless of which working policy (`PowerUserAccess`) is attached to
it for day-to-day usability.

The AWS-side half of this design — the OIDC provider, the scoped trust
policy, and the deploy role — is deployed and was independently confirmed
correct via `aws iam get-role`. A live GitHub Actions run, however, returned
`AccessDenied` on `AssumeRoleWithWebIdentity` despite every checkable
condition matching. This is documented in Section 7 as an open item rather
than resolved.

### 2.3 Detection and automated response

GuardDuty is the sole trigger for automated remediation (Config and Security
Hub feed monitoring and alerting, not live response, to avoid two systems
racing to act on the same resource). An EventBridge rule filters for findings
with `severity >= 7` and invokes a Step Functions state machine — chosen over
direct Lambda chaining specifically for its `Retry`/`Catch` semantics and
per-execution audit trail. The isolation Lambda tags and quarantines a
compromised instance into a security group with no inbound/outbound rules,
rather than terminating it — both because forensic preservation is the
correct instinct and because the Production SCP would block termination
regardless.

This pipeline was proven twice, deliberately capturing two different
behaviors:

- **Manual execution, real instance:** completed `SUCCEEDED` in ~3 seconds —
  finding validated and logged to S3, instance tagged
  `SecurityStatus=Quarantined` and moved into the isolation security group,
  SNS notified with the full result embedded.
- **Automatic trigger, GuardDuty sample finding:** fired without any manual
  intervention (confirmed by the auto-generated execution name rather than a
  human-chosen one). The sample finding referenced GuardDuty's synthetic,
  non-existent instance ID convention (`i-99999999`) — `IsolateInstance`
  correctly failed with `InvalidInstanceID.NotFound`, was caught, and the
  security team was still notified with the failure embedded in the alert.
  The execution still reported `SUCCEEDED`, correctly reflecting that the
  *workflow* completed as designed even though one downstream action failed —
  a meaningfully different and more useful proof than the happy path alone.

### 2.4 Continuous compliance

Two AWS Config rules were deployed, each with SSM Automation remediation
attached with `automatic = true`:
`s3-bucket-server-side-encryption-enabled` and
`s3-bucket-public-read-prohibited`. Security Hub runs the AWS Foundational
Security Best Practices standard (confirmed `READY` via
`get-enabled-standards`), Inspector is enabled for EC2/ECR, and an
EventBridge rule forwards HIGH/CRITICAL Security Hub findings to the same SNS
topic used by the incident-response pipeline, giving the security team one
inbox rather than several.

A significant, unplanned finding emerged while testing this layer: AWS's
January 2023 change to apply default S3 encryption at bucket creation makes
the spec's literal remediation test — create an unencrypted bucket, watch
Config fix it — structurally impossible to reproduce today. This was
confirmed directly (see Section 6) rather than assumed, and the remediation
mechanism's correctness was instead independently verified via
`describe-remediation-configurations`.

### 2.5 Application security and encryption

The sample application sits behind an ALB with a regional WAFv2 Web ACL:
`AWSManagedRulesCommonRuleSet`, `AWSManagedRulesSQLiRuleSet`, and a
rate-based rule capping any single IP to 100 requests per 5 minutes, with
logging through Kinesis Firehose into CloudWatch Logs and an S3 archive. All
three protections were tested against the live endpoint and blocked the
corresponding attack (detailed results in Section 6).

The HTTPS listener is present in the Terraform configuration but currently
disabled (commented out) — ACM will not attach a `PENDING_VALIDATION`
certificate to an ALB listener, confirmed directly via a failed apply
(`UnsupportedCertificate`), and the certificate's placeholder domain has no
real DNS control to complete validation. The HTTP listener currently forwards
directly to the target group rather than redirecting to a non-functional
HTTPS listener, to preserve availability. A customer-managed KMS key with
automatic rotation was deployed and used for the CloudTrail and Step
Functions findings pipeline's data; wiring it uniformly across every S3
bucket in the platform was deferred and remains outstanding (Section 7).

---

## 3. Why These Services Were Chosen

Each major service decision below was a choice among real alternatives, not
the only option available — the reasoning is what an exam or a design review
would actually probe.

**AWS Organizations + SCPs, over a single-account/tag-based model.** Tags and
IAM conditions can approximate isolation but remain bypassable by anyone with
sufficient IAM permissions in the same account. A separate account has no
shared IAM namespace, VPC, or KMS key policy unless explicitly granted — the
isolation is structural, not policy-based. Proven concretely: the Production
SCP blocked `ec2:TerminateInstances` even from a role with full
`AdministratorAccess`, something no IAM policy alone could guarantee, since an
admin can always edit or delete an IAM policy that constrains them.

**Step Functions, over direct Lambda-to-Lambda invocation.** Chained Lambdas
have no built-in retry/catch semantics and no per-execution audit trail — a
transient failure in a chain either crashes silently or requires bespoke
error-handling code in every function. Step Functions centralizes that logic
once, in the state machine definition, and was observed doing exactly this:
a downstream Lambda failure (isolating a synthetic, non-existent GuardDuty
sample-finding instance) was caught and routed to notification rather than
lost, with the overall execution still reporting a clean, auditable
`SUCCEEDED`.

**GuardDuty as the sole automated-response trigger, not Config or Security
Hub.** Multiple services independently reacting to the same resource creates
race conditions and duplicate remediation attempts. GuardDuty was chosen
specifically because it's purpose-built for active threat detection (network
behavior, credential compromise indicators) rather than static configuration
drift, which is Config and Security Hub's domain — those two feed the same
alerting channel but do not trigger the isolation pipeline.

**Regional WAF on the ALB, not CloudFront.** CloudFront's value is edge
caching and global distribution; this deployment is a single-region service
with dynamic, largely uncacheable content, so a CDN layer adds latency and
cost with no security or performance benefit. Attaching WAF directly to the
ALB was validated by running real SQLi, XSS, and rate-limit attacks against
the live endpoint — all three were blocked, confirming the regional
attachment point is sufficient for this workload's actual traffic pattern.

**AWS Config + SSM Automation, over a custom remediation Lambda.** Config's
rule/remediation pairing is declarative and comes with AWS-maintained SSM
documents (`AWS-EnableS3BucketEncryption`,
`AWS-DisableS3BucketPublicReadWrite`) already tested against edge cases a
hand-rolled Lambda would need to reimplement. The trade-off, discovered
directly during testing, is that Config's evaluation cycle is not
instantaneous — auto-remediation happens on a polling cadence, not
synchronously with the triggering change, which matters for anyone assuming
"automatic" means "immediate."

**A customer-managed KMS key, over relying solely on AWS-managed keys.** A
CMK gives the organization control over key policy (who can administer versus
who can merely use it for encrypt/decrypt) and produces an auditable
CloudTrail record of every key usage — AWS-managed keys don't expose the same
level of policy control. The trade-off is operational: someone has to own key
administration, which is why the key policy explicitly names an IAM user as
administrator rather than relying on implicit root-only access.

**GitHub OIDC federation, over IAM users with access keys stored as GitHub
Secrets.** Static keys in CI/CD secrets are a standing, non-expiring attack
surface. OIDC issues credentials that exist only for the duration of a
single job run, scoped by an exact-match trust policy condition on repo and
branch. This is discussed further, including the session's unresolved live
test, in Section 7.

---

## 4. Threat Model and Controls

| Threat | Control(s) | Verified how |
|---|---|---|
| Attacker or insider with admin rights terminates a compromised instance to destroy evidence | Production SCP denies `ec2:TerminateInstances` | Live `TerminateInstances` attempt via `OrganizationAccountAccessRole`, denied with SCP cited by ARN |
| Attacker or insider disables audit logging to cover tracks | Production SCP denies `cloudtrail:StopLogging`/`DeleteTrail`/`UpdateTrail` | Deployed and attached; not independently re-tested against a live stop-logging attempt this session |
| Overprivileged automation role deletes production data | `DevOpsEngineer` permission boundary denies destructive S3 actions regardless of attached policy | Live `DeleteObject` and `DeleteBucket` attempts, both denied with the boundary cited by ARN |
| Compromised CI/CD pipeline deploys from an attacker-controlled fork/branch | OIDC trust policy scoped to exact repo + branch | AWS-side configuration verified correct via IAM inspection; live end-to-end run unresolved (Section 7) |
| Compromised EC2 instance communicating with C2 infrastructure | GuardDuty → Step Functions → automatic tag + SG quarantine | Proven via both manual execution and a real automatic GuardDuty-triggered run |
| Data exfiltration via a misconfigured or public S3 bucket | Config rules with SSM auto-remediation | Remediation configuration verified correct; live trigger for SSE rule blocked by an AWS platform default (Section 6); public-read rule genuinely triggered, remediation execution not fully confirmed (Section 7) |
| SQL injection / XSS against the customer-facing application | WAF managed rule groups | Both attack types run against the live ALB, both returned `HTTP 403` |
| Credential-stuffing / scraping / DoS-style abuse | WAF rate-based rule | 120-request burst test: 117× `200`, then `403`, confirming the rule enforces with a rolling-window delay |
| Data in transit intercepted between client and application | ACM certificate + TLS enforcement, intended | Currently blocked pending a real domain for DNS validation (Section 7) |

---

## 5. How Automation Reduces Risk

Every control here that can be automated, is — not as a convenience, but as a
risk decision. Human-gated response introduces both latency (the average gap
between detection and human action is measured in hours even in well-staffed
teams) and inconsistency (two engineers responding to the same finding type
will not take identical action). Encoding the response once — in a Step
Functions definition, an SSM Automation document, a WAF rule — produces the
same outcome every time with a timestamped execution record that can be
handed to an auditor without reconstruction from tickets and memory.

This session surfaced a second, less obvious dimension of the same point: the
public cloud platform itself is also automating security on your behalf,
sometimes ahead of your own tooling. AWS's default S3 encryption is a case of
the platform closing a gap the Config rule was designed to catch — which is a
genuinely good outcome for security posture, but it also means a compliance
program's test plans need periodic re-validation against current platform
behavior, not just against the original design intent.

---

## 6. Live Test Evidence Summary

Condensed results from the actual test session — full command-level detail is
in the repository's `ISSUES.md`.

| Test | Command / trigger | Result |
|---|---|---|
| SCP blocks admin-level termination | `ec2:TerminateInstances` via `OrganizationAccountAccessRole` on a real running instance | `UnauthorizedOperation ... explicit deny in a service control policy: p-o0ws4v62` |
| SCP blocks Terraform's own automation | Terraform-driven instance replacement | Same SCP denial, from Terraform's assumed-role session |
| Boundary blocks destructive S3 delete | `s3:DeleteObject` via `DevOpsEngineer` (PowerUserAccess attached) | `AccessDenied ... explicit deny in a permissions boundary: DevOpsEngineerPermissionBoundary` |
| Boundary blocks bucket deletion (consistency check) | `s3:DeleteBucket` via `DevOpsEngineer` | Same boundary denial |
| Incident response, happy path | Manual Step Functions execution, real EC2 instance ID | `SUCCEEDED` in ~3s; instance tagged + isolated; S3 log written; SNS delivered |
| Incident response, automatic trigger | `guardduty create-sample-findings` | Fired without manual intervention; isolation step failed gracefully on synthetic instance ID; SNS still delivered with error context |
| S3 default-encryption platform check | `delete-bucket-encryption` then immediate re-check | Encryption reapplied instantly — confirmed AWS platform default, not our remediation |
| Remediation configuration correctness | `describe-remediation-configurations` | Correct SSM document, IAM role, `automatic: true` confirmed for both rules |
| WAF — SQL injection | `curl ...?id=1' OR '1'='1` against live ALB | `HTTP 403` |
| WAF — XSS | `curl ...?q=<script>alert(1)</script>` against live ALB | `HTTP 403` |
| WAF — rate limiting | 120 sequential requests against live ALB | Requests 1–117: `HTTP 200`; requests 118–120: `HTTP 403` |
| Target health after AMI/user-data fix | `describe-target-health` after switching `dnf` → `yum` and refreshing the AMI | `healthy` |

---

## 7. Known Limitations and Open Items

Documented deliberately rather than omitted:

1. **HTTPS is not currently live.** Requires registering a real domain,
   completing ACM DNS validation, and restoring the commented-out HTTPS
   listener plus reverting the HTTP listener to a 301 redirect.
2. **GitHub Actions OIDC federation is unresolved.** AWS-side configuration
   verified correct by direct inspection; a live workflow run still returns
   `AccessDenied`. Root cause not isolated within the session.
3. **KMS encryption is not yet uniform across all S3 buckets.** The findings
   bucket, WAF log archive, and Config bucket currently rely on S3-managed
   (`AES256`) encryption rather than the platform's customer-managed key.
4. **The public-read-prohibition remediation's live execution could not be
   fully confirmed** — a test bucket entered an unrelated S3 `AccessDenied`
   state across multiple metadata APIs after the test, root cause not
   isolated; the remediation configuration itself was independently verified
   as correctly deployed.
5. **A partial `terraform destroy` failure occurred mid-build.** AWS
   Organizations will not allow `aws_organizations_account` resources to be
   removed via API without standalone billing/contact prerequisites that
   fresh accounts never have. A destroy against the org layer tore down
   CloudTrail, the KMS key, and the SCP before halting on the account-removal
   step. Recovered by careful `terraform plan` review before re-applying.
   Recommendation: never run an unscoped `terraform destroy` against a layer
   containing account-creation resources; use `-target` if partial teardown
   is genuinely needed.
6. **Root email aliasing** (Gmail `+` addressing) was used for the four
   member accounts, appropriate for a single-owner build. Production
   deployment would use dedicated, monitored group mailboxes per account.

---

## 8. Alignment with DevOps and AWS Best Practices

- **Infrastructure as Code, verified, not just written.** Every resource is
  Terraform-managed and version-controlled; critically, the controls were not
  just deployed but adversarially tested against genuinely privileged
  credentials before being considered proven.
- **Layered least privilege.** SCPs (org-wide ceiling) + permission boundaries
  (per-role ceiling) + identity policies (actual grant) — the three-layer
  model AWS's own reference architecture recommends, each layer independently
  confirmed to actually deny what it claims to deny.
- **Centralized, tamper-resistant audit trail.** Org-wide CloudTrail to a
  dedicated Logging account that Production/Development admins cannot write
  to.
- **Zero standing CI/CD credentials**, by design — even with the live OIDC
  run currently unresolved, no static AWS key exists anywhere in the
  pipeline configuration.
- **Honest operational transparency.** Real infrastructure work surfaces real
  constraints — a platform default closing a test scenario, an AWS API
  restriction blocking a clean teardown, a package-manager mismatch causing a
  silent boot failure. Documenting these rather than omitting them is itself
  consistent with the incident-review culture that mature DevOps
  organizations practice.

---

## 9. Recommendations for Next Phase

1. Register a real domain and complete ACM validation to bring HTTPS fully
   online.
2. Isolate the GitHub Actions OIDC failure with `ACTIONS_STEP_DEBUG=true` and
   full CloudTrail event inspection of the denied `AssumeRoleWithWebIdentity`
   calls.
3. Extend KMS encryption uniformly across every S3 bucket in the platform,
   including cross-account key grants where buckets and the CMK live in
   different accounts.
4. Add a dedicated Shared Services account for centralized egress and a
   transit gateway.
5. Layer AWS Backup with cross-account, cross-region vault copies.
6. Formalize a break-glass procedure for the SCP's emergency-access exception
   path, with MFA enforcement and time-boxed activation.
7. Pilot AWS Control Tower for account vending going forward, rather than
   hand-rolled `aws_organizations_account` resources — partly to avoid the
   destroy-related friction documented in Section 7.