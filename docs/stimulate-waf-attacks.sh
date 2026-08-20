#!/usr/bin/env bash
# Scenario 4 - Application Attack simulation.
# Usage: ./simulate-waf-attacks.sh https://app.fintechco.co.ke
set -euo pipefail
TARGET="${1:?Usage: $0 <https://target-domain>}"

echo "== Baseline request (expect 200) =="
curl -s -o /dev/null -w "HTTP %{http_code}\n" "$TARGET/"

echo
echo "== SQL injection attempt (expect 403 - blocked by AWSManagedRulesSQLiRuleSet) =="
curl -s -o /dev/null -w "HTTP %{http_code}\n" \
  "$TARGET/?id=1' OR '1'='1"

echo
echo "== XSS attempt (expect 403 - blocked by AWSManagedRulesCommonRuleSet) =="
curl -s -o /dev/null -w "HTTP %{http_code}\n" \
  -G "$TARGET/" --data-urlencode "q=<script>alert(document.cookie)</script>"

echo
echo "== Rate limit test: 120 requests in rapid succession =="
for i in $(seq 1 120); do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET/")
  echo "Request $i: HTTP $code"
done