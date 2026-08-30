# Five Exam-Style Answers

### 1. How do SCPs and Permission Boundaries differ?

A Service Control Policy is an AWS Organizations construct applied to an
account or OU; it sets the maximum permissions for **every principal in that
account**, including the account's own root user and any admin-level assumed
role, and is managed only by the Organizations management account. An SCP
never grants anything by itself — it only filters what IAM policies are
allowed to grant.

This project's Production OU carries an SCP denying `ec2:TerminateInstances`
and `cloudtrail:StopLogging`/`DeleteTrail`/`UpdateTrail`. It was tested twice
against a genuinely privileged identity: first deliberately, by assuming
`OrganizationAccountAccessRole` (full `AdministratorAccess`) and attempting to
terminate a real running EC2 instance — denied, with AWS's own error citing
the SCP by ARN. Second, unintentionally: mid-session, replacing a
misconfigured instance required Terraform itself (using the same admin role)
to call `TerminateInstances`, and it was blocked identically. That second case
is worth calling out specifically — an SCP has no concept of "this call came
from infrastructure-as-code automation acting on my behalf." It evaluates the
calling principal and the action, full stop, which is exactly the point: a
guardrail that only stops humans isn't a real guardrail.

A Permission Boundary is an IAM construct attached to a **single user or
role**. It's set by anyone in that account with
`iam:PutRolePermissionsBoundary` permission — not necessarily the org's
top-level security team — and, like an SCP, only removes permissions rather
than granting them. This project's `DevOpsEngineer` role has `PowerUserAccess`
attached but is capped by a boundary that explicitly denies destructive S3
actions and IAM privilege-escalation paths. Proven directly: assumed the role,
attempted `s3:DeleteObject` against a real bucket — denied, with AWS citing
the permission boundary by ARN, not the SCP (Production's SCP says nothing
about S3). Repeated with `s3:DeleteBucket` for consistency — same result.

The practical difference: SCPs are an organization-wide governance control set
once and forgotten; boundaries are a per-identity guardrail attached as each
role is created, useful for delegating "create roles for other teams" safely
because whatever gets created can never exceed the boundary, regardless of
which managed policy someone later attaches to make the role usable.

### 2. Why is OIDC preferred over long-lived credentials for CI/CD?

Long-lived IAM access keys in CI/CD secrets are a standing attack surface —
they don't expire on their own, get copied into build logs, and a single leak
grants access until someone notices and manually revokes it. OIDC federation
removes the credential entirely: GitHub's Actions runner requests a
short-lived, signed JWT from GitHub's own issuer per job; AWS STS validates
that token against the IAM role's trust policy — in this project, an exact
`sub` match on `repo:essiewakukha/Enterprise-Grade-Secure-Cloud-Platfrom:ref:refs/heads/main`
— and only then issues temporary credentials directly into the job's
environment. Nothing is stored in GitHub Secrets.

Worth being candid: the AWS-side infrastructure for this (OIDC provider,
scoped trust policy, deploy role) was built and independently verified as
correct via direct `aws iam get-role` inspection, but a live GitHub Actions
run returned `AccessDenied` on `sts:AssumeRoleWithWebIdentity` despite every
checkable condition matching — correct repo, correct branch, correct role
ARN, correct audience. This was not resolved within the build session and is
documented as an open item rather than papered over. It doesn't change the
architectural reasoning above — a correctly-scoped trust policy that fails at
runtime for an unidentified reason is a debugging problem, not evidence that
long-lived keys would have been the better design. If anything, it's a
reminder that OIDC trust conditions are exact-match and unforgiving, which is
precisely the property that makes them secure once correctly wired.

### 3. How does Step Functions ensure consistent incident remediation?

Ad-hoc Lambda-to-Lambda chaining has no retry semantics and produces different
outcomes depending on which invocation happens to fail. Step Functions turns
the response into an explicit, auditable state machine —
`ValidateFinding → IsValidated → HasInstanceId → IsolateInstance/NotifySecurityTeam`
— with `Retry`/`Catch` blocks on every risky step, so a transient failure is
retried with backoff and any unhandled error routes to a defined
notification path instead of silently vanishing.

This was proven in two genuinely different ways in the same session, which is
more useful than either alone. The **happy path**: a manual execution against
a real, running EC2 instance completed in about 3 seconds — finding logged to
S3, instance tagged and network-isolated, SNS notified with the full
validation and isolation payload embedded. The **failure path**: a real
GuardDuty sample finding (which by design references a synthetic,
non-existent instance ID) triggered the pipeline automatically via
EventBridge — `IsolateInstance` correctly failed with
`InvalidInstanceID.NotFound`, was caught by the state machine's error
handling, and the security team was still notified, with the failure reason
embedded in the alert. The execution itself reported `SUCCEEDED` — meaning the
*workflow* completed as designed, not that every individual action inside it
succeeded. That distinction, observed directly rather than assumed, is the
actual argument for Step Functions over ad-hoc chaining: a downstream failure
degrades gracefully into a notification, not into a dropped finding.

### 4. Why attach WAF at the ALB instead of CloudFront?

CloudFront is the stronger choice when the application is globally
distributed, benefits from edge caching, or needs DDoS absorption before
traffic reaches the region (CloudFront + WAF + Shield Advanced). ALB is the
better attachment point for a regional service with no caching benefit —
this project's sample app is exactly that case: a single-region deployment
behind one ALB, with no CDN requirement.

Attaching WAF at the ALB was validated directly, not just assumed correct: a
`aws_wafv2_web_acl` in `REGIONAL` scope was associated with the ALB, and three
real attacks were run against the live endpoint. SQL injection
(`?id=1' OR '1'='1`) was blocked by `AWSManagedRulesSQLiRuleSet` — `HTTP 403`.
XSS (`<script>alert(1)</script>`) was blocked by
`AWSManagedRulesCommonRuleSet` — `HTTP 403`. A 120-request burst against the
rate-based rule (limit 100/5min/IP) returned `HTTP 200` for the first 117
requests, then flipped to `HTTP 403` and stayed blocked — a rolling-window
delay past the nominal threshold, consistent with AWS's documented ~1-minute
evaluation cycle for rate-based rules rather than an instant per-request
counter. Confirming that rate limits are eventually-consistent, not
instant, matters for anyone relying on this rule for tight abuse-prevention
SLAs — a genuinely useful finding for the design decision, not just for this
one app.

### 5. Why is auto-remediation critical for compliance?

Continuous compliance tooling is only as good as the speed of the fix that
follows a finding. A manually-remediated model leaves a non-compliant
resource exposed for however long it takes a human to notice, prioritize, and
fix it — often hours, which is itself a reportable control failure for a
CBK-regulated fintech, independent of whether the resource was ever exploited.

This project's Config layer surfaced a genuinely useful, unplanned lesson
about what "auto-remediation" means in practice on modern AWS. The spec's
literal test — deploy an unencrypted S3 bucket, watch Config fix it — turned
out to be **structurally impossible to trigger** on any account created after
January 2023, because AWS itself now applies default encryption to every new
bucket at creation, with no API opt-out. This was confirmed directly:
`delete-bucket-encryption` followed immediately by a re-check showed
encryption reapplied *instantly* — faster than Config's evaluation cycle could
possibly run — proving it was AWS's own platform default, not the deployed
remediation logic, doing the work. The remediation configuration itself was
independently verified as correctly wired (`describe-remediation-configurations`
showing the correct SSM document, IAM role, and `automatic: true`), and a
second, genuinely triggerable rule — `s3-bucket-public-read-prohibited` — was
deployed to demonstrate an auto-remediation cycle where the platform doesn't
already close the gap on its own.

The broader point this surfaced: "why is auto-remediation critical" has a
second, less obvious answer beyond speed — a security team's own tooling and
test plans need to be re-validated against the *current* platform, not
assumed correct forever. A control that made sense to test in 2021 may be
untestable in its original form in 2026 because the cloud provider closed the
gap first. Auto-remediation still matters — for buckets restored from old
backups, created by legacy tooling, or on accounts/regions where the default
differs — but knowing precisely why a test scenario no longer applies is
itself a piece of the compliance posture, not a footnote.