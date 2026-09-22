#!/usr/bin/env bash
# Provision a client tenant: a LiteLLM virtual key with budget, rate limit and model allowlist.
# Usage: LITELLM_MASTER_KEY=... ./create-tenant.sh <client-slug> <monthly_budget_usd> <tier: basic|standard|pro>
set -euo pipefail
GATEWAY=${GATEWAY:-http://localhost:4000}
slug=${1:?client slug}; budget=${2:?monthly budget usd}; tier=${3:-standard}
case "$tier" in
  basic)    models='["tier-basic","claude-haiku-4-5"]' ;;
  standard) models='["tier-standard","tier-basic","claude-haiku-4-5"]' ;;
  pro)      models='["tier-pro","tier-standard","tier-basic","claude-fable-5-1","claude-haiku-4-5"]' ;;
  *) echo "tier must be basic|standard|pro"; exit 1 ;;
esac
curl -sS -X POST "$GATEWAY/key/generate" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY:?}" \
  -H "Content-Type: application/json" \
  -d "{
    \"key_alias\": \"tenant-$slug\",
    \"team_id\": \"$slug\",
    \"models\": $models,
    \"max_budget\": $budget,
    \"budget_duration\": \"30d\",
    \"rpm_limit\": 120,
    \"tpm_limit\": 400000,
    \"metadata\": {\"tier\": \"$tier\", \"created_by\": \"create-tenant.sh\"}
  }" | tee "tenant-$slug.json"
echo
echo "Give the 'key' above to the client's agent container as OPENAI_API_KEY. Spend: $GATEWAY/spend/logs?team_id=$slug"
