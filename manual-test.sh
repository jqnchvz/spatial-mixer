#!/bin/bash
#
# Interactive Manual Test Guide for SpatialMixer SPAT-20
# Guides user through each test step-by-step
#

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

clear

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  ${BOLD}SpatialMixer Manual Test Guide - SPAT-20${NC}${BLUE}         ║${NC}"
echo -e "${BLUE}║  AVAudioEngine Pipeline Integration Testing           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to wait for user
wait_for_user() {
    echo ""
    read -p "Press ENTER when ready to continue..."
    echo ""
}

# Function to ask yes/no
ask_pass_fail() {
    local test_name=$1
    echo -e "${YELLOW}Did the test pass? (y/n)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}✅ $test_name - PASSED${NC}"
        return 0
    else
        echo -e "${RED}❌ $test_name - FAILED${NC}"
        echo "Please note what went wrong:"
        read -r notes
        echo "  Notes: $notes"
        return 1
    fi
}

# Track results
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_TESTS=6

# Check if app is built
echo -e "${YELLOW}📦 Building SpatialMixer...${NC}"
xcodebuild -project SpatialMixer/SpatialMixer.xcodeproj \
    -scheme SpatialMixer \
    -configuration Debug \
    -derivedDataPath /tmp/SpatialMixerBuild \
    -quiet 2>&1 | grep -v "^note:"

APP_PATH="/tmp/SpatialMixerBuild/Build/Products/Debug/SpatialMixer.app"

if [ -d "$APP_PATH" ]; then
    echo -e "${GREEN}✓ Built successfully: $APP_PATH${NC}"
else
    echo -e "${RED}✗ Build failed. Please check Xcode for errors.${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Ready to start testing!${NC}"
wait_for_user

# ============================================================================
# Test 1: Single Audio Source
# ============================================================================
clear
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Test 1/6: Single Audio Source${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Goal:${NC} Verify basic engine functionality with one app"
echo ""
echo "Steps:"
echo "  1. I'll launch SpatialMixer for you"
echo "  2. Click the menu bar icon"
echo "  3. Verify: Gray circle 'Engine Stopped', '0 active'"
echo "  4. Play a YouTube video in Safari"
echo "  5. Click 'Capture' next to Safari"
echo ""
echo "Expected Results:"
echo "  ✓ Green circle 'Engine Running'"
echo "  ✓ '1 active' source count"
echo "  ✓ Safari shows '🎧 Capturing'"
echo "  ✓ AUDIO PLAYS through SpatialMixer"
echo ""

wait_for_user

# Launch app
echo -e "${BLUE}🚀 Launching SpatialMixer...${NC}"
open "$APP_PATH"

# Open logs in background
echo -e "${BLUE}📊 Opening log viewer...${NC}"
osascript <<EOF &
tell application "Terminal"
    do script "log stream --predicate 'process == \"SpatialMixer\"' --level debug | grep -E '(startTap|FIRST BUFFER|Audio engine)'"
end tell
EOF

sleep 2

echo ""
echo -e "${YELLOW}${BOLD}Now perform the test steps above.${NC}"
echo ""

if ask_pass_fail "Test 1: Single Audio Source"; then
    ((TESTS_PASSED++))
else
    ((TESTS_FAILED++))
fi

wait_for_user

# ============================================================================
# Test 2: Multiple Sources
# ============================================================================
clear
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Test 2/6: Multiple Audio Sources${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Goal:${NC} Verify multiple apps mix correctly"
echo ""
echo "Steps:"
echo "  1. Continue from Test 1 (Safari still capturing)"
echo "  2. Play audio in Music.app or Spotify"
echo "  3. Click 'Capture' on the second app"
echo ""
echo "Expected Results:"
echo "  ✓ '2 active' sources"
echo "  ✓ Both apps show '🎧 Capturing'"
echo "  ✓ BOTH audio sources audible simultaneously"
echo "  ✓ Audio mixes correctly"
echo ""

wait_for_user

echo -e "${YELLOW}${BOLD}Now perform the test steps above.${NC}"
echo ""

if ask_pass_fail "Test 2: Multiple Sources"; then
    ((TESTS_PASSED++))
else
    ((TESTS_FAILED++))
fi

wait_for_user

# ============================================================================
# Test 3: Format Conversion
# ============================================================================
clear
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Test 3/6: Format Conversion${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Goal:${NC} Verify automatic format conversion"
echo ""
echo "Steps:"
echo "  1. Find a 44.1kHz audio file (most music files)"
echo "     OR use QuickTime Player with any video"
echo "  2. Play it"
echo "  3. Capture the app"
echo ""
echo "Expected Results:"
echo "  ✓ Audio plays correctly"
echo "  ✓ No pitch shifting"
echo "  ✓ Console shows 'Format mismatch - creating converter'"
echo ""
echo "Check the Terminal window with logs for:"
echo "  ⚡ Format mismatch - creating converter"
echo ""

wait_for_user

echo -e "${YELLOW}${BOLD}Now perform the test steps above.${NC}"
echo ""

if ask_pass_fail "Test 3: Format Conversion"; then
    ((TESTS_PASSED++))
else
    ((TESTS_FAILED++))
fi

wait_for_user

# ============================================================================
# Test 4: Stop/Start Sources
# ============================================================================
clear
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Test 4/6: Stop/Start Sources${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Goal:${NC} Verify source lifecycle management"
echo ""
echo "Steps:"
echo "  1. Have 2-3 sources capturing"
echo "  2. Click 'Stop' on one source"
echo "  3. Verify that app's audio stops, others continue"
echo "  4. Stop all sources one by one"
echo "  5. When stopping last source:"
echo "     - Gray circle 'Engine Stopped'"
echo "     - '0 active' sources"
echo ""

wait_for_user

echo -e "${YELLOW}${BOLD}Now perform the test steps above.${NC}"
echo ""

if ask_pass_fail "Test 4: Stop/Start Sources"; then
    ((TESTS_PASSED++))
else
    ((TESTS_FAILED++))
fi

wait_for_user

# ============================================================================
# Test 5: Error Recovery
# ============================================================================
clear
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Test 5/6: Error Recovery${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Goal:${NC} Verify graceful app termination handling"
echo ""
echo "Steps:"
echo "  1. Start capturing Safari"
echo "  2. Force quit Safari (Cmd+Q)"
echo ""
echo "Expected Results:"
echo "  ✓ No crash"
echo "  ✓ Active count decrements"
echo "  ✓ Engine stops if no other sources"
echo "  ✓ No error dialogs"
echo ""

wait_for_user

echo -e "${YELLOW}${BOLD}Now perform the test steps above.${NC}"
echo ""

if ask_pass_fail "Test 5: Error Recovery"; then
    ((TESTS_PASSED++))
else
    ((TESTS_FAILED++))
fi

wait_for_user

# ============================================================================
# Test 6: Device Changes (Optional - requires headphones)
# ============================================================================
clear
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Test 6/6: Device Changes (Optional)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Goal:${NC} Verify audio device change handling"
echo -e "${YELLOW}Requires:${NC} Headphones (Bluetooth or wired)"
echo ""
echo "Do you have headphones available? (y/n)"
read -r has_headphones

if [[ "$has_headphones" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Steps:"
    echo "  1. Start capturing with headphones connected"
    echo "  2. While audio playing, unplug/disconnect headphones"
    echo ""
    echo "Expected Results:"
    echo "  ✓ Audio switches to speakers"
    echo "  ✓ Brief interruption OK (< 1 second)"
    echo "  ✓ Engine recovers automatically"
    echo "  ✓ Console shows 'Audio configuration changed'"
    echo ""

    wait_for_user

    echo -e "${YELLOW}${BOLD}Now perform the test steps above.${NC}"
    echo ""

    if ask_pass_fail "Test 6: Device Changes"; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi
else
    echo -e "${YELLOW}⊘ Skipping Test 6 (no headphones available)${NC}"
    ((TOTAL_TESTS--))
fi

# ============================================================================
# Summary
# ============================================================================
clear
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}${BOLD}Test Summary - SPAT-20${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✅ ALL TESTS PASSED!${NC}"
    echo ""
    echo -e "  Passed: ${GREEN}$TESTS_PASSED/$TOTAL_TESTS${NC}"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${BOLD}✓ SPAT-20 AVAudioEngine Pipeline - VERIFIED${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
    echo -e "${RED}${BOLD}Some tests failed${NC}"
    echo ""
    echo -e "  Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "  Failed: ${RED}$TESTS_FAILED${NC}"
fi

echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Post test results to PR: https://github.com/jqnchvz/spatial-mixer/pull/9"
echo "  2. Update Jira: https://comolagente.atlassian.net/browse/SPAT-20"
echo "  3. Request code review"
echo ""
echo -e "${YELLOW}See TESTING.md for detailed troubleshooting and performance testing.${NC}"
echo ""
