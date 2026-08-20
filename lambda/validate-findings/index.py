"""
validate-finding Lambda

First step invoked by the Step Functions state machine after EventBridge
routes a High-severity GuardDuty finding. Responsibilities:
  1. Validate the finding shape and severity threshold (defense in depth --
     the EventBridge rule already filters on severity, this re-checks it).
  2. Extract the instance ID (if the finding is EC2-related) for downstream
     isolation.
  3. Persist the full finding JSON to the findings S3 bucket for audit trail.
  4. Return a normalized payload for the next state (isolate + notify).
"""
import json
import os
import uuid
from datetime import datetime, timezone

import boto3

s3 = boto3.client("s3")

FINDINGS_BUCKET = os.environ["FINDINGS_BUCKET"]
SEVERITY_THRESHOLD = float(os.environ.get("SEVERITY_THRESHOLD", "7.0"))


def handler(event, context):
    detail = event.get("detail", event)
    severity = float(detail.get("severity", 0))
    finding_type = detail.get("type", "Unknown")
    finding_id = detail.get("id", str(uuid.uuid4()))

    if severity < SEVERITY_THRESHOLD:
        return {
            "validated": False,
            "reason": f"Severity {severity} below threshold {SEVERITY_THRESHOLD}",
            "findingId": finding_id,
        }

    instance_id = None
    resource = detail.get("resource", {})
    instance_details = resource.get("instanceDetails", {})
    if instance_details:
        instance_id = instance_details.get("instanceId")

    timestamp = datetime.now(timezone.utc).isoformat()
    key = f"guardduty-findings/{finding_id}/{timestamp}.json"

    s3.put_object(
        Bucket=FINDINGS_BUCKET,
        Key=key,
        Body=json.dumps(detail, default=str).encode("utf-8"),
        ContentType="application/json",
        ServerSideEncryption="aws:kms",
    )

    return {
        "validated": True,
        "findingId": finding_id,
        "findingType": finding_type,
        "severity": severity,
        "instanceId": instance_id,
        "region": detail.get("region"),
        "accountId": detail.get("accountId"),
        "s3Location": f"s3://{FINDINGS_BUCKET}/{key}",
        "timestamp": timestamp,
    }