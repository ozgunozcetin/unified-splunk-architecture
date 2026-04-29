#!/bin/sh
set -e

echo "[loadgen] Waiting 60s for HF HEC..."
sleep 60

TOKEN="${SPLUNK_HEC_TOKEN}"
TARGET="https://sitea-hf:8088/services/collector/event"

echo "[loadgen] Starting event generation, target=$TARGET"
echo "[loadgen] Token=${TOKEN:0:8}..."

i=0
while true; do
    i=$((i + 1))
    PAYLOAD="{\"event\":\"LOADGEN seq=$i host=app-01 site=A action=login user=u$((i % 100))\",\"sourcetype\":\"loadgen_test\",\"index\":\"sitea_buffer\"}"
    RESPONSE=$(curl -sk -o /dev/null -w "%{http_code}" \
        -H "Authorization: Splunk $TOKEN" \
        -d "$PAYLOAD" \
        "$TARGET" 2>&1 || echo "ERR")
    
    if [ $((i % 10)) -eq 0 ]; then
        echo "[loadgen] seq=$i http_code=$RESPONSE"
    fi
    
    sleep 1
done
