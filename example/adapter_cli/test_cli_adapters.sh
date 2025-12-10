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

# Clean up any artifacts from previous test runs (e.g., files created by agents)
rm -f "$TEST_DIR"/*.py "$TEST_DIR"/*.sh "$TEST_DIR"/*.txt "$TEST_DIR"/*.dart 2>/dev/null || true

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

# Function to run a tool test (create file) and verify result
run_tool_test() {
    local cli=$1
    local description=$2
    local args=$3
    local expect_file=$4  # "yes" if file should be created, "no" if not
    local file_path="$TEST_DIR/hello.dart"

    echo -e "${YELLOW}Testing: $cli - $description${NC}"
    echo "  Command: dart run ${cli}_cli.dart $args"

    # Run the command and capture output
    # For non-yolo tests, pipe empty input to auto-deny approval prompts
    local output
    if [ "$expect_file" = "no" ]; then
        output=$(echo "" | eval "dart run \"${cli}_cli.dart\" $args" 2>&1) || true
    else
        output=$(eval "dart run \"${cli}_cli.dart\" $args" 2>&1) || true
    fi
    echo "$output"

    # Check if file was created
    if [ "$expect_file" = "yes" ]; then
        if [ -f "$file_path" ]; then
            echo -e "${GREEN}  ✓ File created as expected${NC}"
        else
            echo -e "${RED}  ✗ File NOT created (expected it to be created)${NC}"
            rm -f "$file_path"
            return 1
        fi
    else
        if [ -f "$file_path" ]; then
            echo -e "${RED}  ✗ File was created (expected it NOT to be created - auto-deny failed)${NC}"
            rm -f "$file_path"
            return 1
        else
            echo -e "${GREEN}  ✓ File NOT created as expected (auto-deny worked)${NC}"
        fi
    fi

    # Clean up
    rm -f "$file_path"
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

# Test 7: Tool use with yolo mode (should create file)
run_tool_test "claude" "Tool use with yolo mode (create file)" "-d $TEST_DIR -p 'Create a simple hello.dart file that prints Hello World. Just create the file, no explanation needed.' -y" "yes"

# Test 8: Tool use without yolo mode (should auto-deny, file not created)
run_tool_test "claude" "Tool use without yolo mode (auto-deny)" "-d $TEST_DIR -p 'Create a simple hello.dart file that prints Hello World. Just create the file, no explanation needed.'" "no"

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

# Test 5: Tool use with yolo mode (should create file)
run_tool_test "codex" "Tool use with yolo mode (create file)" "-d $TEST_DIR -p 'Create a simple hello.dart file that prints Hello World. Just create the file, no explanation needed.' -y" "yes"

# Test 6: Tool use without yolo mode (should auto-deny, file not created)
# Non-yolo mode now uses readOnly sandbox, requiring approval for writes (which gets auto-denied)
run_tool_test "codex" "Tool use without yolo mode (auto-deny)" "-d $TEST_DIR -p 'Create a simple hello.dart file that prints Hello World. Just create the file, no explanation needed.'" "no"

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

sleep 2

# Test 5: Tool use with yolo mode (should create file)
run_tool_test "gemini" "Tool use with yolo mode (create file)" "-d $TEST_DIR -p 'Create a simple hello.dart file that prints Hello World. Just create the file, no explanation needed.' -y" "yes"

sleep 2

# Test 6: Tool use without yolo mode (should use safe mode, limited tools)
run_tool_test "gemini" "Tool use without yolo mode" "-d $TEST_DIR -p 'Create a simple hello.dart file that prints Hello World. Just create the file, no explanation needed.'" "no"

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
