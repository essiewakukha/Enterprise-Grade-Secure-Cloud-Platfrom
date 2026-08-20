#!/usr/bin/env bash
# Scenario 1 - Misconfigured S3 Bucket -> Config auto-remediation
# Scenario 2 - Malicious network activity -> GuardDuty sample finding -> IR pipeline
set -euo pipefail
REGION="${AWS_REGION:-af-south-1}"
cmd="${1:-help}"

case "$cmd" in
  scenario1)
    BUCKET="fintech-test-unencrypted-$(date +%s)"
    echo "Creating deliberately unencrypted bucket: $BUCKET"
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION"

    echo "Triggering an immediate Config evaluation..."
    aws configservice start-config-rules-evaluation \
      --config-rule-names s3-bucket-server-side-encryption-enabled --region "$REGION"

    echo "Waiting 90s for evaluation + auto-remediation SSM automation to run..."
    sleep 90

    echo "Compliance status:"
    aws configservice get-compliance-details-by-config-rule \
      --config-rule-name s3-bucket-server-side-encryption-enabled --region "$REGION" \
      --query "EvaluationResults[?EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId=='$BUCKET']"

    echo "Bucket encryption config (should now show aws:kms):"
    aws s3api get-bucket-encryption --bucket "$BUCKET" --region "$REGION"
    ;;

  scenario2)
    echo "Generating GuardDuty sample findings..."
    DETECTOR_ID=$(aws guardduty list-detectors --region "$REGION" --query "DetectorIds[0]" --output text)
    aws guardduty create-sample-findings --detector-id "$DETECTOR_ID" --region "$REGION" \
      --finding-types "Backdoor:EC2/C&CActivity.B!DNS" "UnauthorizedAccess:EC2/SSHBruteForce" "Trojan:EC2/BlackholeTraffic"

    echo "Sample findings created. EventBridge should route them to Step Functions within ~1 minute."
    ;;
  *)
    echo "Usage: $0 {scenario1|scenario2}"
    ;;
esac