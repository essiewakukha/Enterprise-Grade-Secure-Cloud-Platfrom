"""
isolate-instance Lambda

Second step invoked by Step Functions when a validated finding includes an
EC2 instance ID. Isolates the instance so it can no longer communicate
laterally or exfiltrate data, while preserving it (not terminated) for
forensics -- consistent with the Production SCP that blocks
ec2:TerminateInstances.

Isolation actions:
  1. Tag the instance (SecurityStatus=Quarantined, IsolationTimestamp=<ts>,
     IsolationFindingId=<id>) for audit and to prevent auto-scaling/automation
     from touching it.
  2. Replace all attached security groups with a single locked-down
     "quarantine" SG (no inbound, no outbound except to the forensics VPC
     endpoint) so the instance is network-isolated in place.
"""
import os
from datetime import datetime, timezone

import boto3

ec2 = boto3.client("ec2")

QUARANTINE_SG_ID = os.environ["QUARANTINE_SECURITY_GROUP_ID"]


def handler(event, context):
    instance_id = event.get("instanceId")
    finding_id = event.get("findingId", "unknown")

    if not instance_id:
        return {"isolated": False, "reason": "No instanceId present on finding"}

    timestamp = datetime.now(timezone.utc).isoformat()

    ec2.create_tags(
        Resources=[instance_id],
        Tags=[
            {"Key": "SecurityStatus", "Value": "Quarantined"},
            {"Key": "IsolationTimestamp", "Value": timestamp},
            {"Key": "IsolationFindingId", "Value": finding_id},
        ],
    )

    ec2.modify_instance_attribute(
        InstanceId=instance_id,
        Groups=[QUARANTINE_SG_ID],
    )

    return {
        "isolated": True,
        "instanceId": instance_id,
        "findingId": finding_id,
        "quarantineSecurityGroup": QUARANTINE_SG_ID,
        "isolatedAt": timestamp,
    }