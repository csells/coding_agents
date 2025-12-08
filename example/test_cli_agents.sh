#!/bin/bash
# Test script for unified coding_cli.dart
# Tests all three agents (Claude, Codex, Gemini) through various scenarios

set -e  # Exit on first error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test directory
TEST_DIR="$(pwd)/tmp"
mkdir -p "$TEST_DIR"

# Clean up any artifacts from previous test runs
rm -f "$TEST_DIR"/*.py "$TEST_DIR"/*.sh "$TEST_DIR"/*.txt 2>/dev/null || true

# Clean up stale Gemini session cache for test directory
GEMINI_PROJECT_HASH=$(echo -n "$TEST_DIR" | shasum -a 256 | cut -d' ' -f1)
rm -rf "$HOME/.gemini/tmp/$GEMINI_PROJECT_HASH/chats"/* 2>/dev/null || true

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Unified Coding CLI Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Test directory: $TEST_DIR"
echo ""

# Function to run a test
run_test() {
    local agent=$1
    local description=$2
    local args=$3

    echo -e "${YELLOW}Testing: $agent - $description${NC}"
    echo "  Command: dart run coding_cli.dart -a $agent $args"

    if eval "dart run coding_cli.dart -a $agent $args"; then
        echo -e "${GREEN}  ✓ Passed${NC}"
    else
        echo -e "${RED}  ✗ Failed${NC}"
        return 1
    fi
    echo ""
}

# Function to run a test with input
run_test_with_input() {
    local agent=$1
    local description=$2
    local args=$3
    local input=$4

    echo -e "${YELLOW}Testing: $agent - $description${NC}"
    echo "  Command: echo '$input' | dart run coding_cli.dart -a $agent $args"

    if echo "$input" | eval "dart run coding_cli.dart -a $agent $args"; then
        echo -e "${GREEN}  ✓ Passed${NC}"
    else
        echo -e "${RED}  ✗ Failed${NC}"
        return 1
    fi
    echo ""
}

# Extract the first session ID from the list output for the given agent
get_session_id() {
    local agent=$1
    local output
    if ! output=$(dart run coding_cli.dart -a "$agent" -d "$TEST_DIR" -l); then
        echo -e "${RED}  ✗ Failed to list sessions for $agent${NC}" >&2
        return 1
    fi

    local id
    id=$(echo "$output" | awk '/^  [^ ]/ {sub(/^  /, "", $0); print $0; exit}')
    if [ -z "$id" ]; then
        echo "$output" >&2
        echo -e "${RED}  ✗ No session ID found for $agent in $TEST_DIR${NC}" >&2
        return 1
    fi

    echo "$id"
}

# ============================================
# CLAUDE AGENT TESTS
# ============================================
echo -e "${BLUE}----------------------------------------${NC}"
echo -e "${BLUE}  Claude Agent Tests${NC}"
echo -e "${BLUE}----------------------------------------${NC}"
echo ""

# Test 1: One-shot prompt
run_test "claude" "One-shot prompt" "-p 'What is 2+2? Reply with just the number.' -y"

# Test 2: List sessions
run_test "claude" "List sessions" "-l -d $TEST_DIR"

# Test 3: One-shot with custom directory
run_test "claude" "One-shot with custom directory" "-d $TEST_DIR -p 'Say hello' -y"

# Test 4: Create a session and resume it
echo -e "${YELLOW}Testing: claude - Create session for resume test${NC}"
dart run coding_cli.dart -a claude -d "$TEST_DIR" -p "Say hello and remember Claude resume test." -y
CLAUDE_SESSION_ID=$(get_session_id claude) || exit 1
echo "  Using session: $CLAUDE_SESSION_ID"
run_test "claude" "Resume existing session" "-d $TEST_DIR -r $CLAUDE_SESSION_ID -p 'Resume: say CLAUDE RESUME OK.' -y"

# Test 5: Interactive REPL with immediate exit
run_test_with_input "claude" "Interactive REPL (immediate exit)" "-d $TEST_DIR -y" "/exit"

# ============================================
# CODEX AGENT TESTS
# ============================================
echo -e "${BLUE}----------------------------------------${NC}"
echo -e "${BLUE}  Codex Agent Tests${NC}"
echo -e "${BLUE}----------------------------------------${NC}"
echo ""

# Test 1: One-shot prompt
run_test "codex" "One-shot prompt" "-p 'What is 3+3? Reply with just the number.' -y"

# Test 2: List sessions
run_test "codex" "List sessions" "-l -d $TEST_DIR"

# Test 3: One-shot with custom directory
run_test "codex" "One-shot with custom directory" "-d $TEST_DIR -p 'Say hello' -y"

# Test 4: Create a session and resume it
echo -e "${YELLOW}Testing: codex - Create session for resume test${NC}"
dart run coding_cli.dart -a codex -d "$TEST_DIR" -p "Say hello and remember Codex resume test." -y
CODEX_SESSION_ID=$(get_session_id codex) || exit 1
echo "  Using session: $CODEX_SESSION_ID"
run_test "codex" "Resume existing session" "-d $TEST_DIR -r $CODEX_SESSION_ID -p 'Resume: say CODEX RESUME OK.' -y"

# Test 5: Interactive REPL with immediate exit
run_test_with_input "codex" "Interactive REPL (immediate exit)" "-d $TEST_DIR -y" "/exit"

# ============================================
# GEMINI AGENT TESTS
# ============================================
echo -e "${BLUE}----------------------------------------${NC}"
echo -e "${BLUE}  Gemini Agent Tests${NC}"
echo -e "${BLUE}----------------------------------------${NC}"
echo ""

# Note: Gemini API needs delays between calls to avoid rate limiting
sleep 2

# Test 1: One-shot prompt
run_test "gemini" "One-shot prompt" "-p 'What is 4+4? Reply with just the number.' -y"

sleep 2

# Test 2: List sessions
run_test "gemini" "List sessions" "-l -d $TEST_DIR"

sleep 2

# Test 3: One-shot with custom directory
run_test "gemini" "One-shot with custom directory" "-d $TEST_DIR -p 'Say hello' -y"

# Test 4: Create a session and resume it
echo -e "${YELLOW}Testing: gemini - Create session for resume test${NC}"
dart run coding_cli.dart -a gemini -d "$TEST_DIR" -p "Say hello and remember Gemini resume test." -y
sleep 2
GEMINI_SESSION_ID=$(get_session_id gemini) || exit 1
echo "  Using session: $GEMINI_SESSION_ID"
run_test "gemini" "Resume existing session" "-d $TEST_DIR -r $GEMINI_SESSION_ID -p 'Resume: say GEMINI RESUME OK.' -y"

sleep 2

# Test 5: Interactive REPL with immediate exit
run_test_with_input "gemini" "Interactive REPL (immediate exit)" "-d $TEST_DIR -y" "/exit"

# ============================================
# DEFAULT AGENT TEST (should use Claude)
# ============================================
echo -e "${BLUE}----------------------------------------${NC}"
echo -e "${BLUE}  Default Agent Test (Claude)${NC}"
echo -e "${BLUE}----------------------------------------${NC}"
echo ""

echo -e "${YELLOW}Testing: default - One-shot without -a flag${NC}"
echo "  Command: dart run coding_cli.dart -p 'What is 5+5? Reply with just the number.' -y"
if dart run coding_cli.dart -p 'What is 5+5? Reply with just the number.' -y; then
    echo -e "${GREEN}  ✓ Passed${NC}"
else
    echo -e "${RED}  ✗ Failed${NC}"
    exit 1
fi
echo ""

# ============================================
# HELP FLAG TEST
# ============================================
echo -e "${BLUE}----------------------------------------${NC}"
echo -e "${BLUE}  Help Flag Test${NC}"
echo -e "${BLUE}----------------------------------------${NC}"
echo ""

echo -e "${YELLOW}Testing: Help flag${NC}"
echo "  Command: dart run coding_cli.dart -h"
if dart run coding_cli.dart -h; then
    echo -e "${GREEN}  ✓ Passed${NC}"
else
    echo -e "${RED}  ✗ Failed${NC}"
    exit 1
fi
echo ""

# ============================================
# SUMMARY
# ============================================
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}  All tests completed!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
