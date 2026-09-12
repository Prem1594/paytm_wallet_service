#!/usr/bin/env bash

WALLET_A="7279cc37-9777-4817-a882-7274d951fecb"
WALLET_B="06f9779a-3d4d-4ea5-b65f-f6fde04c0fb9"

echo "=== 1. Reading Pre-Test Balances ==="
BAL_A_BEFORE=$(curl -s --noproxy "*" http://localhost:8000/wallets/users/user_101 | grep -o '"balancePaise":[0-9]*' | cut -d: -f2)
BAL_B_BEFORE=$(curl -s --noproxy "*" http://localhost:8000/wallets/users/user_102 | grep -o '"balancePaise":[0-9]*' | cut -d: -f2)
TOTAL_BEFORE=$((BAL_A_BEFORE + BAL_B_BEFORE))

echo "Wallet A Balance: ${BAL_A_BEFORE} paise"
echo "Wallet B Balance: ${BAL_B_BEFORE} paise"
echo "Combined Total:   ${TOTAL_BEFORE} paise"
echo "--------------------------------------------------"

echo "=== 2. Launching 20 Concurrent Cross-Transfers ==="

for i in $(seq 1 10); do
  (
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --noproxy "*" -X POST http://localhost:8000/transfers \
      -H "Content-Type: application/json" \
      -H "Idempotency-Key: stress_a_to_b_${i}_$(date +%s%N)" \
      -d "{\"sourceWalletId\": \"${WALLET_A}\", \"targetWalletId\": \"${WALLET_B}\", \"amountPaise\": 1000}")
    echo "Transfer A -> B (#$i): HTTP $CODE"
  ) &
done

for i in $(seq 1 10); do
  (
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --noproxy "*" -X POST http://localhost:8000/transfers \
      -H "Content-Type: application/json" \
      -H "Idempotency-Key: stress_b_to_a_${i}_$(date +%s%N)" \
      -d "{\"sourceWalletId\": \"${WALLET_B}\", \"targetWalletId\": \"${WALLET_A}\", \"amountPaise\": 1000}")
    echo "Transfer B -> A (#$i): HTTP $CODE"
  ) &
done

wait

echo "--------------------------------------------------"
echo "=== 3. Validating Conservation of Money ==="
BAL_A_AFTER=$(curl -s --noproxy "*" http://localhost:8000/wallets/users/user_101 | grep -o '"balancePaise":[0-9]*' | cut -d: -f2)
BAL_B_AFTER=$(curl -s --noproxy "*" http://localhost:8000/wallets/users/user_102 | grep -o '"balancePaise":[0-9]*' | cut -d: -f2)
TOTAL_AFTER=$((BAL_A_AFTER + BAL_B_AFTER))

echo "Wallet A Balance: ${BAL_A_AFTER} paise"
echo "Wallet B Balance: ${BAL_B_AFTER} paise"
echo "Combined Total:   ${TOTAL_AFTER} paise"

if [ "$TOTAL_BEFORE" -eq "$TOTAL_AFTER" ]; then
  echo ">>> AUDIT PASSED: Zero lost updates, funds are conserved! <<<"
else
  echo ">>> AUDIT FAILED: Ledger mismatch! Funds leaked or duplicated! <<<"
  exit 1
fi
