#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-https://prems-paytm-wallet-service.onrender.com}"
echo "============================================================"
echo " Paytm Wallet & P2P Transfer: Automated Invariant Probe"
echo " Target URL: ${BASE_URL}"
echo "============================================================"

command -v curl >/dev/null 2>&1 || { echo "curl required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq required (sudo apt install jq)"; exit 1; }

TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

# --- Health Check ---
echo ""
echo ">>> Checking Service Health..."
HEALTH_STATUS=$(curl -s "${BASE_URL}/health" | jq -r '.status // "DOWN"' 2>/dev/null || echo "DOWN")
if [ "${HEALTH_STATUS}" != "UP" ]; then
  echo "Service is not ready at ${BASE_URL} (status: ${HEALTH_STATUS})."
  echo "If hosted on Render Free tier, it may be waking from idle. Wait 30s and retry."
  exit 1
fi
echo "✔ Health check passed: Service is UP"

# --- Invariant 1: Race-Free Get-or-Create ---
echo ""
echo ">>> [PROBE 1/3] Testing Race-Free Get-or-Create (50 concurrent)..."
USER_PROBE_1="concur_user_$(date +%s%N)"
pids=()

for i in $(seq 1 50); do
  (
    curl -s -X POST "${BASE_URL}/wallets" \
      -H "Content-Type: application/json" \
      -d "{\"userId\":\"${USER_PROBE_1}\"}" > "${TMP_DIR}/res1_${i}.json" 2>/dev/null
  ) &
  pids+=($!)
done

for pid in "${pids[@]}"; do wait "$pid"; done

DISTINCT_WALLETS=$(cat "${TMP_DIR}"/res1_*.json | jq -r '.id // empty' 2>/dev/null | sort -u | wc -l)

if [ "${DISTINCT_WALLETS}" -eq 1 ]; then
  echo "✔ Race-free get-or-create PASSED: 50 concurrent requests yielded exactly 1 wallet."
else
  echo "❌ Race-free get-or-create FAILED: ${DISTINCT_WALLETS} distinct wallets found."
  exit 1
fi

# --- Invariant 2: Idempotent Retry Storm & Tamper Defense ---
echo ""
echo ">>> [PROBE 2/3] Testing Idempotent Retry Storm & Tamper Defense..."
USER_A="alice_$(date +%s%N)"
USER_B="bob_$(date +%s%N)"

WALLET_A=$(curl -s -X POST "${BASE_URL}/wallets" -H "Content-Type: application/json" -d "{\"userId\":\"${USER_A}\"}" | jq -r '.id')
WALLET_B=$(curl -s -X POST "${BASE_URL}/wallets" -H "Content-Type: application/json" -d "{\"userId\":\"${USER_B}\"}" | jq -r '.id')

curl -s -X POST "${BASE_URL}/wallets/${WALLET_A}/topup" -H "Content-Type: application/json" -d '{"amountPaise":50000}' > /dev/null

IDEM_KEY="idem_key_$(date +%s%N)"
pids=()

for i in $(seq 1 30); do
  (
    curl -s -X POST "${BASE_URL}/transfers" \
      -H "Content-Type: application/json" \
      -H "Idempotency-Key: ${IDEM_KEY}" \
      -d "{\"sourceWalletId\":\"${WALLET_A}\",\"targetWalletId\":\"${WALLET_B}\",\"amountPaise\":1000}" > "${TMP_DIR}/res2_${i}.json" 2>/dev/null
  ) &
  pids+=($!)
done

for pid in "${pids[@]}"; do wait "$pid"; done

BAL_A=$(curl -s -X POST "${BASE_URL}/wallets" -H "Content-Type: application/json" -d "{\"userId\":\"${USER_A}\"}" | jq -r '.balancePaise')
BAL_B=$(curl -s -X POST "${BASE_URL}/wallets" -H "Content-Type: application/json" -d "{\"userId\":\"${USER_B}\"}" | jq -r '.balancePaise')

if [ "${BAL_A}" -eq 49000 ] && [ "${BAL_B}" -eq 1000 ]; then
  echo "✔ Idempotency retry storm PASSED: 30 identical requests applied exactly once."
else
  echo "❌ Idempotency storm FAILED: Balances inconsistent (A: ${BAL_A}, B: ${BAL_B})."
  exit 1
fi

TAMPER_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}/transfers" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: ${IDEM_KEY}" \
  -d "{\"sourceWalletId\":\"${WALLET_A}\",\"targetWalletId\":\"${WALLET_B}\",\"amountPaise\":5000}")

if [ "${TAMPER_STATUS}" -eq 409 ]; then
  echo "✔ Tampered payload defense PASSED: HTTP 409 Conflict returned on key reuse."
else
  echo "❌ Tampered payload defense FAILED: Expected HTTP 409, got ${TAMPER_STATUS}."
  exit 1
fi

# --- Invariant 3: Conservation & No-Overdraft Under Contention ---
echo ""
echo ">>> [PROBE 3/3] Testing Balance Conservation & Deadlock-Free Contention..."
USER_X="cx_$(date +%s%N)"
USER_Y="cy_$(date +%s%N)"

WX=$(curl -s -X POST "${BASE_URL}/wallets" -H "Content-Type: application/json" -d "{\"userId\":\"${USER_X}\"}" | jq -r '.id')
WY=$(curl -s -X POST "${BASE_URL}/wallets" -H "Content-Type: application/json" -d "{\"userId\":\"${USER_Y}\"}" | jq -r '.id')

curl -s -X POST "${BASE_URL}/wallets/${WX}/topup" -H "Content-Type: application/json" -d '{"amountPaise":10000}' > /dev/null
curl -s -X POST "${BASE_URL}/wallets/${WY}/topup" -H "Content-Type: application/json" -d '{"amountPaise":10000}' > /dev/null

pids=()

for i in $(seq 1 50); do
  (
    curl -s -X POST "${BASE_URL}/transfers" \
      -H "Content-Type: application/json" \
      -H "Idempotency-Key: tx_xy_${i}_$(date +%s%N)" \
      -d "{\"sourceWalletId\":\"${WX}\",\"targetWalletId\":\"${WY}\",\"amountPaise\":300}" > /dev/null
  ) &
  pids+=($!)
  (
    curl -s -X POST "${BASE_URL}/transfers" \
      -H "Content-Type: application/json" \
      -H "Idempotency-Key: tx_yx_${i}_$(date +%s%N)" \
      -d "{\"sourceWalletId\":\"${WY}\",\"targetWalletId\":\"${WX}\",\"amountPaise\":300}" > /dev/null
  ) &
  pids+=($!)
done

for i in $(seq 1 10); do
  (
    curl -s -X POST "${BASE_URL}/transfers" \
      -H "Content-Type: application/json" \
      -H "Idempotency-Key: tx_od_${i}_$(date +%s%N)" \
      -d "{\"sourceWalletId\":\"${WX}\",\"targetWalletId\":\"${WY}\",\"amountPaise\":500000}" > /dev/null
  ) &
  pids+=($!)
done

for pid in "${pids[@]}"; do wait "$pid"; done

FINAL_X=$(curl -s -X POST "${BASE_URL}/wallets" -H "Content-Type: application/json" -d "{\"userId\":\"${USER_X}\"}" | jq -r '.balancePaise')
FINAL_Y=$(curl -s -X POST "${BASE_URL}/wallets" -H "Content-Type: application/json" -d "{\"userId\":\"${USER_Y}\"}" | jq -r '.balancePaise')
TOTAL=$((FINAL_X + FINAL_Y))

if [ "${TOTAL}" -eq 20000 ] && [ "${FINAL_X}" -ge 0 ] && [ "${FINAL_Y}" -ge 0 ]; then
  echo "✔ Conservation PASSED: Total ledger preserved at exactly 20000 paise (WX: ${FINAL_X}, WY: ${FINAL_Y})."
else
  echo "❌ Conservation FAILED: Sum was ${TOTAL}, expected 20000."
  exit 1
fi

echo ""
echo "============================================================"
echo " ALL INVARIANT PROBES COMPLETED CLEANLY"
echo "============================================================"
