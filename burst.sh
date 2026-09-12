#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://localhost:8000}"
echo "============================================================"
echo "Paytm Wallet & P2P Transfer: Automated Invariant Probe"
echo "Target URL: ${BASE_URL}"
echo "============================================================"

# Dependency check
command -v jq >/dev/null 2>&1 || { echo "Error: 'jq' is required. Install via: sudo apt-get install -y jq"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "Error: 'curl' is required."; exit 1; }

# -----------------------------------------------------------------------------
# GATE 1: Race-free get-or-create (50 Concurrent Requests)
# -----------------------------------------------------------------------------
echo ""
echo ">>> [PROBE 1/3] Gate 1: Testing Race-Free Get-or-Create (50 concurrent)..."
GATE1_USER="burst_user_$(date +%s%N)"
GATE1_DIR=$(mktemp -d)

for i in $(seq 1 50); do
  curl -s --noproxy "*" -X POST "${BASE_URL}/wallets" \
    -H "Content-Type: application/json" \
    -d "{\"userId\": \"${GATE1_USER}\"}" \
    -o "${GATE1_DIR}/res_${i}.json" &
done
wait

DISTINCT_WALLETS=$(cat "${GATE1_DIR}"/res_*.json | jq -r '.id' | sort -u | wc -l)
rm -rf "${GATE1_DIR}"

if [ "${DISTINCT_WALLETS}" -eq 1 ]; then
  echo "  ✔ GATE 1 PASSED: 50 concurrent requests yielded exactly 1 wallet."
else
  echo "  ✖ GATE 1 FAILED: Expected 1 distinct wallet, found ${DISTINCT_WALLETS}."
  exit 1
fi

# -----------------------------------------------------------------------------
# GATE 2: Idempotent Retry Storm (30 Concurrent Requests with Same Key)
# -----------------------------------------------------------------------------
echo ""
echo ">>> [PROBE 2/3] Gate 2: Testing Idempotent Retry Storm (K=30 concurrent)..."
W_A=$(curl -s --noproxy "*" -X POST "${BASE_URL}/wallets" -H "Content-Type: application/json" -d "{\"userId\": \"storm_a_$(date +%s%N)\"}" | jq -r '.id')
W_B=$(curl -s --noproxy "*" -X POST "${BASE_URL}/wallets" -H "Content-Type: application/json" -d "{\"userId\": \"storm_b_$(date +%s%N)\"}" | jq -r '.id')

# Top-up wallet A with 10,000 paise (₹100)
curl -s --noproxy "*" -X POST "${BASE_URL}/wallets/${W_A}/topup" \
  -H "Content-Type: application/json" \
  -d '{"amountPaise": 10000}' > /dev/null

STORM_KEY="storm_key_$(date +%s%N)"
GATE2_DIR=$(mktemp -d)

for i in $(seq 1 30); do
  curl -s --noproxy "*" -X POST "${BASE_URL}/transfers" \
    -H "Content-Type: application/json" \
    -H "Idempotency-Key: ${STORM_KEY}" \
    -d "{\"sourceWalletId\": \"${W_A}\", \"targetWalletId\": \"${W_B}\", \"amountPaise\": 2500}" \
    -o "${GATE2_DIR}/res_${i}.json" &
done
wait

DISTINCT_TX_IDS=$(cat "${GATE2_DIR}"/res_*.json | jq -r '.transferId' | sort -u | wc -l)
BAL_A=$(curl -s --noproxy "*" "${BASE_URL}/wallets/${W_A}" | jq -r '.balancePaise')
BAL_B=$(curl -s --noproxy "*" "${BASE_URL}/wallets/${W_B}" | jq -r '.balancePaise')
rm -rf "${GATE2_DIR}"

if [ "${DISTINCT_TX_IDS}" -eq 1 ] && [ "${BAL_A}" -eq 7500 ] && [ "${BAL_B}" -eq 2500 ]; then
  echo "  ✔ GATE 2 (Retry Storm) PASSED: Exactly 1 debit applied (Balance A: 7500, Balance B: 2500)."
else
  echo "  ✖ GATE 2 FAILED: Distinct IDs=${DISTINCT_TX_IDS}, Bal A=${BAL_A}, Bal B=${BAL_B}"
  exit 1
fi

# Gate 2 Extension: Same Key with Altered Payload must return 409 Conflict
CONFLICT_HTTP_STATUS=$(curl -s --noproxy "*" -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}/transfers" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: ${STORM_KEY}" \
  -d "{\"sourceWalletId\": \"${W_A}\", \"targetWalletId\": \"${W_B}\", \"amountPaise\": 5000}")

if [ "${CONFLICT_HTTP_STATUS}" -eq 409 ]; then
  echo "  ✔ GATE 2 (Payload Tampering) PASSED: Altered body with reused key returned HTTP 409 Conflict."
else
  echo "  ✖ GATE 2 (Payload Tampering) FAILED: Expected HTTP 409, got ${CONFLICT_HTTP_STATUS}."
  exit 1
fi

# -----------------------------------------------------------------------------
# GATE 3: Conservation & No-Overdraft Under Contention (100 Concurrent Cross-Transfers)
# -----------------------------------------------------------------------------
echo ""
echo ">>> [PROBE 3/3] Gate 3: Testing Conservation & Contention (100 concurrent A↔B↔C)..."
W1=$(curl -s --noproxy "*" -X POST "${BASE_URL}/wallets" -H "Content-Type: application/json" -d "{\"userId\": \"user_1_$(date +%s%N)\"}" | jq -r '.id')
W2=$(curl -s --noproxy "*" -X POST "${BASE_URL}/wallets" -H "Content-Type: application/json" -d "{\"userId\": \"user_2_$(date +%s%N)\"}" | jq -r '.id')
W3=$(curl -s --noproxy "*" -X POST "${BASE_URL}/wallets" -H "Content-Type: application/json" -d "{\"userId\": \"user_3_$(date +%s%N)\"}" | jq -r '.id')

# Seed with 10,000 paise each (Total: 30,000 paise)
curl -s --noproxy "*" -X POST "${BASE_URL}/wallets/${W1}/topup" -H "Content-Type: application/json" -d '{"amountPaise": 10000}' > /dev/null
curl -s --noproxy "*" -X POST "${BASE_URL}/wallets/${W2}/topup" -H "Content-Type: application/json" -d '{"amountPaise": 10000}' > /dev/null
curl -s --noproxy "*" -X POST "${BASE_URL}/wallets/${W3}/topup" -H "Content-Type: application/json" -d '{"amountPaise": 10000}' > /dev/null

INITIAL_TOTAL=30000

# Fire 100 transfers back and forth, including overdraw amounts (7000 paise)
WALLETS=("${W1}" "${W2}" "${W3}")
AMOUNTS=(500 1200 2500 7000)

for i in $(seq 1 100); do
  SRC=${WALLETS[$((RANDOM % 3))]}
  TGT=${WALLETS[$((RANDOM % 3))]}
  while [ "${SRC}" == "${TGT}" ]; do
    TGT=${WALLETS[$((RANDOM % 3))]}
  done
  AMT=${AMOUNTS[$((RANDOM % 4))]}
  KEY="contention_$(date +%s%N)_${i}"

  curl -s --noproxy "*" -X POST "${BASE_URL}/transfers" \
    -H "Content-Type: application/json" \
    -H "Idempotency-Key: ${KEY}" \
    -d "{\"sourceWalletId\": \"${SRC}\", \"targetWalletId\": \"${TGT}\", \"amountPaise\": ${AMT}}" > /dev/null &
done
wait

FINAL_B1=$(curl -s --noproxy "*" "${BASE_URL}/wallets/${W1}" | jq -r '.balancePaise')
FINAL_B2=$(curl -s --noproxy "*" "${BASE_URL}/wallets/${W2}" | jq -r '.balancePaise')
FINAL_B3=$(curl -s --noproxy "*" "${BASE_URL}/wallets/${W3}" | jq -r '.balancePaise')
FINAL_TOTAL=$((FINAL_B1 + FINAL_B2 + FINAL_B3))

echo "  Balances: W1=${FINAL_B1}p, W2=${FINAL_B2}p, W3=${FINAL_B3}p"
echo "  Total before: ${INITIAL_TOTAL}p | Total after: ${FINAL_TOTAL}p"

if [ "${FINAL_TOTAL}" -eq "${INITIAL_TOTAL}" ] && [ "${FINAL_B1}" -ge 0 ] && [ "${FINAL_B2}" -ge 0 ] && [ "${FINAL_B3}" -ge 0 ]; then
  echo "  ✔ GATE 3 PASSED: Conservation invariant held exact (Zero loss/gain) and no overdraft occurred."
else
  echo "  ✖ GATE 3 FAILED: Conservation broken or negative balance detected!"
  exit 1
fi

echo ""
echo "============================================================"
echo "ALL HARD GATES PASSED CLEANLY!"
echo "============================================================"