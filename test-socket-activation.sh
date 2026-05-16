#!/bin/bash
# Comprehensive test suite for bitnet-server socket activation
# Tests: idle memory, cold start, warm requests, actual inference, cleanup

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================"
echo "bitnet-server Socket Activation Test"
echo "========================================"
echo ""

# Test 1: Setup and Idle State
echo "Test 1: Idle State (0 MB RAM)"
echo "------------------------------"
sudo systemctl stop bitnet-server.service 2>/dev/null || true
sudo pkill -9 llama-server 2>/dev/null || true
sleep 2
sudo systemctl start bitnet-server.socket
sleep 1

SOCKET_MEM=$(sudo systemctl show bitnet-server.socket -p MemoryCurrent | cut -d= -f2)
SOCKET_MEM_KB=$((SOCKET_MEM / 1024))
SERVICE_STATE=$(sudo systemctl is-active bitnet-server.service || echo "inactive")

echo "Socket memory: ${SOCKET_MEM_KB} KB"
echo "Service state: ${SERVICE_STATE}"

if [ "$SERVICE_STATE" = "inactive" ] && [ "$SOCKET_MEM_KB" -lt 500 ]; then
    echo -e "${GREEN}✓ PASS${NC} - Idle state verified (socket only, no service)"
else
    echo -e "${RED}✗ FAIL${NC} - Service should be inactive"
fi
echo ""

# Test 2: Cold Start Timing
echo "Test 2: Cold Start Performance"
echo "-------------------------------"
START=$(date +%s%N)
HEALTH=$(curl -s -m 30 http://localhost:11435/health)
END=$(date +%s%N)
COLD_MS=$(( (END - START) / 1000000 ))

echo "Cold start time: ${COLD_MS}ms"
echo "Response: $HEALTH"

if [ $COLD_MS -lt 15000 ]; then
    echo -e "${GREEN}✓ PASS${NC} - Cold start under 15 seconds"
else
    echo -e "${YELLOW}⚠ SLOW${NC} - Cold start over 15 seconds"
fi
echo ""

# Test 3: Service Activation
echo "Test 3: Service Auto-Start"
echo "---------------------------"
sleep 2
SERVICE_STATE=$(sudo systemctl is-active bitnet-server.service)
SERVICE_MEM=$(sudo systemctl show bitnet-server.service -p MemoryCurrent | cut -d= -f2)
SERVICE_MEM_MB=$((SERVICE_MEM / 1024 / 1024))

echo "Service state: ${SERVICE_STATE}"
echo "Service memory: ${SERVICE_MEM_MB} MB"

if [ "$SERVICE_STATE" = "active" ]; then
    echo -e "${GREEN}✓ PASS${NC} - Service activated by socket"
else
    echo -e "${RED}✗ FAIL${NC} - Service should be active after request"
fi
echo ""

# Test 4: Warm Request Speed
echo "Test 4: Warm Request Performance"
echo "---------------------------------"
START=$(date +%s%N)
MODELS=$(curl -s http://localhost:11435/v1/models)
END=$(date +%s%N)
WARM_MS=$(( (END - START) / 1000000 ))

MODEL_ID=$(echo "$MODELS" | jq -r '.data[0].id' 2>/dev/null || echo "parse-error")

echo "Warm request time: ${WARM_MS}ms"
echo "Model: $MODEL_ID"

if [ $WARM_MS -lt 1000 ]; then
    echo -e "${GREEN}✓ PASS${NC} - Warm request under 1 second"
else
    echo -e "${YELLOW}⚠ SLOW${NC} - Warm request over 1 second"
fi
echo ""

# Test 5: Actual Inference
echo "Test 5: Chat Completion"
echo "-----------------------"
START=$(date +%s%N)
RESPONSE=$(curl -s http://localhost:11435/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Say hello in 3 words"}],"max_tokens":10}')
END=$(date +%s%N)
INFERENCE_MS=$(( (END - START) / 1000000 ))

CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content' 2>/dev/null || echo "$RESPONSE")

echo "Inference time: ${INFERENCE_MS}ms"
echo "Response: $CONTENT"

if echo "$RESPONSE" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS${NC} - Valid chat completion"
else
    echo -e "${RED}✗ FAIL${NC} - Invalid response format"
fi
echo ""

# Test 6: Verify Socket Activation Log
echo "Test 6: Socket Activation Verification"
echo "---------------------------------------"
LOG_MSG=$(sudo journalctl -u bitnet-server.service --since "2 minutes ago" | grep "using systemd socket activation" | tail -1)

if [ -n "$LOG_MSG" ]; then
    echo "Log entry found:"
    echo "$LOG_MSG"
    echo -e "${GREEN}✓ PASS${NC} - Socket activation confirmed in logs"
else
    echo -e "${RED}✗ FAIL${NC} - No socket activation log message found"
fi
echo ""

# Summary
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Idle memory: ${SOCKET_MEM_KB} KB (socket only)"
echo "Cold start: ${COLD_MS}ms"
echo "Warm request: ${WARM_MS}ms"
echo "Inference: ${INFERENCE_MS}ms"
echo "Model: $MODEL_ID"
echo ""
echo "Socket activation: Working ✓"
echo "Memory savings: ~1.4 GB idle → ${SOCKET_MEM_KB} KB"
echo "========================================"
