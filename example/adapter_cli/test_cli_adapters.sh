#!/bin/bash
# Test script for simple_cli examples
# Tests all three CLIs (Claude, Codex, Gemini) through various scenarios

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

# Clean up any artifacts from previous test runs (e.g., files created by Gemini)
rm -f "$TEST_DIR"/*.py "$TEST_DIR"/*.sh "$TEST_DIR"/*.txt 2>/dev/null || true

# Clean up stale Gemini session cache for test directory
# Gemini stores sessions in ~/.gemini/tmp/{sha256(projectPath)}/chats/
# These can become stale and cause 404 errors when the server-side session expires
GEMINI_PROJECT_HASH=$(echo -n "$TEST_DIR" | shasum -a 256 | cut -d' ' -f1)
rm -rf "$HOME/.gemini/tmp/$GEMINI_PROJECT_HASH/chats"/* 2>/dev/null || true

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Simple CLI Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Test directory: $TEST_DIR"
echo ""

# Function to run a test
run_test() {
    local cli=$1
    local description=$2
    local args=$3

    echo -e "${YELLOW}Testing: $cli - $description${NC}"
    echo "  Command: dart run ${cli}_cli.dart $args"

    if eval "dart run \"${cli}_cli.dart\" $args"; then
        echo -e "${GREEN}  ✓ Passed${NC}"
    else
        echo -e "${RED}  ✗ Failed${NC}"
        return 1
    fi
    echo ""
}

# Function to run a test with input
run_test_with_input() {
    local cli=$1
    local description=$2
    local args=$3
    local input=$4

    echo -e "${YELLOW}Testing: $cli - $description${NC}"
    echo "  Command: echo '$input' | dart run ${cli}_cli.dart $args"

    if echo "$input" | eval "dart run \"${cli}_cli.dart\" $args"; then
        echo -e "${GREEN}  ✓ Passed${NC}"
    else
        echo -e "${RED}  ✗ Failed${NC}"
        return 1
    fi
    echo ""
}

# ============================================
# CLAUDE CLI TESTS
# ============================================
echo -e "${BLUE}----------------------------------------${NC}"
echo -e "${BLUE}  Claude CLI Tests${NC}"
echo -e "${BLUE}----------------------------------------${NC}"
echo ""

# Test 1: One-shot prompt
run_test "claude" "One-shot prompt" "-p 'What is 2+2? Reply with just the number.' -y"

# Test 2: List sessions
run_test "claude" "List sessions" "-l -d $TEST_DIR"

# Test 3: One-shot with custom directory
run_test "claude" "One-shot with custom directory" "-d $TEST_DIR -p 'Say hello' -y"

# Test 4: Create a session and capture ID for resume test
echo -e "${YELLOW}Testing: claude - Create session for resume test${NC}"
CLAUDE_OUTPUT=$(dart run claude_cli.dart -d "$TEST_DIR" -p "Remember the word BANANA" -y 2>&1)
echo "$CLAUDE_OUTPUT"
echo -e "${GREEN}  ✓ Session created${NC}"
echo ""

# Test 5: List sessions (should now have at least one)
run_test "claude" "List sessions (after creating)" "-l -d $TEST_DIR"

# Test 6: Interactive REPL with immediate exit
run_test_with_input "claude" "Interactive REPL (immediate exit)" "-d $TEST_DIR -y" "/exit"

# ============================================
# CODEX CLI TESTS
# ============================================
echo -e "${BLUE}----------------------------------------${NC}"
echo -e "${BLUE}  Codex CLI Tests${NC}"
echo -e "${BLUE}----------------------------------------${NC}"
echo ""

# Test 1: One-shot prompt
run_test "codex" "One-shot prompt" "-p 'What is 3+3? Reply with just the number.' -y"

# Test 2: List sessions
run_test "codex" "List sessions" "-l"

# Test 3: One-shot with custom directory
run_test "codex" "One-shot with custom directory" "-d $TEST_DIR -p 'Say hello' -y"

# Test 4: Interactive REPL with immediate exit
run_test_with_input "codex" "Interactive REPL (immediate exit)" "-d $TEST_DIR -y" "/exit"

# ============================================
# GEMINI CLI TESTS
# ============================================
echo -e "${BLUE}----------------------------------------${NC}"
echo -e "${BLUE}  Gemini CLI Tests${NC}"
echo -e "${BLUE}----------------------------------------${NC}"
echo ""

# Note: Gemini API needs delays between calls to avoid rate limiting
sleep 2

# Test 1: One-shot prompt
run_test "gemini" "One-shot prompt" "-p 'What is 4+4? Reply with just the number.' -y"

sleep 2

# Test 2: List sessions
run_test "gemini" "List sessions" "-l"

sleep 2

# Test 3: One-shot with custom directory
run_test "gemini" "One-shot with custom directory" "-d $TEST_DIR -p 'Say hello' -y"

sleep 2

# Test 4: Interactive REPL with immediate exit
run_test_with_input "gemini" "Interactive REPL (immediate exit)" "-d $TEST_DIR -y" "/exit"

# ============================================
# SUMMARY
# ============================================
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}  All tests completed!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "To test resume functionality manually, run:"
echo "  1. dart run claude_cli.dart -l -d $TEST_DIR"
echo "  2. Copy a session ID from the list"
echo "  3. dart run claude_cli.dart -r <session-id> -d $TEST_DIR"
echo ""
