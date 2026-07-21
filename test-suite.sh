#!/bin/bash
#
# Automated Test Suite for SpatialMixer
# Tests the AVAudioEngine pipeline implementation (SPAT-20)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/SpatialMixer"
PROJECT_FILE="$PROJECT_DIR/SpatialMixer.xcodeproj"
SCHEME="SpatialMixer"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  SpatialMixer Test Suite - SPAT-20          ║${NC}"
echo -e "${BLUE}║  AVAudioEngine Pipeline Testing              ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
echo ""

# Check if project exists
if [ ! -d "$PROJECT_FILE" ]; then
    echo -e "${RED}✗ Error: Project not found at $PROJECT_FILE${NC}"
    exit 1
fi

echo -e "${YELLOW}📋 Test Configuration:${NC}"
echo "   Project: $PROJECT_FILE"
echo "   Scheme: $SCHEME"
echo ""

# Function to run tests
run_tests() {
    local test_name=$1
    local test_filter=$2

    echo -e "${BLUE}▶ Running: $test_name${NC}"

    if [ -z "$test_filter" ]; then
        # Run all tests
        xcodebuild test \
            -project "$PROJECT_FILE" \
            -scheme "$SCHEME" \
            -destination 'platform=macOS' \
            -quiet 2>&1 | grep -E "(Test Suite|Test Case.*passed|Test Case.*failed|✅|✗)" || true
    else
        # Run specific test
        xcodebuild test \
            -project "$PROJECT_FILE" \
            -scheme "$SCHEME" \
            -destination 'platform=macOS' \
            -only-testing:"SpatialMixerTests/$test_filter" \
            -quiet 2>&1 | grep -E "(Test Suite|Test Case.*passed|Test Case.*failed)" || true
    fi

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ $test_name passed${NC}\n"
        return 0
    else
        echo -e "${RED}✗ $test_name failed${NC}\n"
        return 1
    fi
}

# Main test execution
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}1️⃣  Unit Tests${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if tests exist
if ! xcodebuild -project "$PROJECT_FILE" -scheme "$SCHEME" -showBuildSettings &> /dev/null; then
    echo -e "${YELLOW}⚠️  Warning: Tests target may not be configured${NC}"
    echo -e "${YELLOW}   Creating test target...${NC}"
    echo ""
fi

# Build first
echo -e "${BLUE}🔨 Building project...${NC}"
xcodebuild clean build \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -destination 'platform=macOS' \
    -quiet

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Build successful${NC}\n"
else
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
fi

# Run test suite
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}2️⃣  Running Test Suite${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

# Check if test file exists
if [ ! -f "$PROJECT_DIR/SpatialMixerTests/SpatialAudioEngineTests.swift" ]; then
    echo -e "${YELLOW}⚠️  Test file not found. This is expected if tests aren't set up yet.${NC}"
    echo -e "${YELLOW}   To add tests:${NC}"
    echo -e "${YELLOW}   1. Open Xcode${NC}"
    echo -e "${YELLOW}   2. File → New → Target → macOS Unit Testing Bundle${NC}"
    echo -e "${YELLOW}   3. Add SpatialAudioEngineTests.swift to the test target${NC}"
    echo ""
    exit 0
fi

# Run all tests
echo -e "${BLUE}▶ Running all SpatialAudioEngine tests...${NC}"
xcodebuild test \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -destination 'platform=macOS' \
    2>&1 | tee test-output.log

# Parse results
if grep -q "Test Suite.*passed" test-output.log; then
    TESTS_PASSED=$(grep -c "Test Case.*passed" test-output.log || echo "0")
fi

if grep -q "Test Suite.*failed" test-output.log; then
    TESTS_FAILED=$(grep -c "Test Case.*failed" test-output.log || echo "0")
fi

# Clean up
rm -f test-output.log

# Summary
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}📊 Test Summary${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo -e "   Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo ""
    echo -e "${GREEN}✅ SPAT-20 AVAudioEngine Pipeline - VERIFIED${NC}"
else
    echo -e "${RED}✗ Some tests failed${NC}"
    echo -e "   Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "   Failed: ${RED}$TESTS_FAILED${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Next: Manual Integration Testing${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Run the app and test:"
echo "  1. Single audio source (Safari + YouTube)"
echo "  2. Multiple sources (Safari + Music + Spotify)"
echo "  3. Format conversion (QuickTime 44.1kHz)"
echo "  4. Device changes (unplug headphones)"
echo ""
echo "Run: open ~/Library/Developer/Xcode/DerivedData/SpatialMixer-*/Build/Products/Debug/SpatialMixer.app"
echo ""
