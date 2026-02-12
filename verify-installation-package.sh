#!/bin/bash

##############################################################################
# OpenClaw Installation Scripts - Verification & Integrity Check
# Purpose: Verify all scripts are present, executable, and valid
# Usage: ./verify-installation-package.sh
##############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
print_header() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ $1${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
}

print_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

print_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

# Check file exists
check_file_exists() {
    local file=$1
    local description=$2
    
    if [[ -f "$file" ]]; then
        print_pass "Found: $description"
        return 0
    else
        print_fail "Missing: $description ($file)"
        return 1
    fi
}

# Check file is executable
check_file_executable() {
    local file=$1
    local description=$2
    
    if [[ -x "$file" ]]; then
        print_pass "Executable: $description"
        return 0
    else
        print_warn "Not executable: $description (Need: chmod +x $file)"
        return 1
    fi
}

# Check bash syntax
check_bash_syntax() {
    local file=$1
    local description=$2
    
    if bash -n "$file" 2>/dev/null; then
        print_pass "Valid bash syntax: $description"
        return 0
    else
        print_fail "Invalid bash syntax: $description"
        bash -n "$file" 2>&1 | head -3
        return 1
    fi
}

# Check markdown files
check_markdown() {
    local file=$1
    local description=$2
    
    if [[ -f "$file" && $(wc -l < "$file") -gt 10 ]]; then
        local lines=$(wc -l < "$file")
        print_pass "Valid: $description ($lines lines)"
        return 0
    else
        print_fail "Invalid/Empty: $description"
        return 1
    fi
}

# File size check
check_file_size() {
    local file=$1
    local min_size=$2
    local description=$3
    
    if [[ -f "$file" ]]; then
        local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
        if [[ $size -gt $min_size ]]; then
            print_pass "Size OK: $description ($size bytes)"
            return 0
        else
            print_warn "File seems small: $description ($size bytes)"
            return 1
        fi
    fi
}

# Main verification
main() {
    print_header "OpenClaw Installation Package Verification"
    
    echo ""
    echo -e "${CYAN}Checking installation package integrity...${NC}"
    echo "Location: $SCRIPT_DIR"
    
    # Check shell environment
    print_info "Verification running on: $(uname -s)"
    
    # ===== Documentation Files =====
    print_header "Documentation Files"
    
    check_file_exists "$SCRIPT_DIR/README.md" "README.md" || true
    check_markdown "$SCRIPT_DIR/README.md" "README.md" || true
    
    check_file_exists "$SCRIPT_DIR/DEPLOYMENT-GUIDE.md" "DEPLOYMENT-GUIDE.md" || true
    check_markdown "$SCRIPT_DIR/DEPLOYMENT-GUIDE.md" "DEPLOYMENT-GUIDE.md" || true
    
    check_file_exists "$SCRIPT_DIR/CONFIGURATION-REFERENCE.md" "CONFIGURATION-REFERENCE.md" || true
    check_markdown "$SCRIPT_DIR/CONFIGURATION-REFERENCE.md" "CONFIGURATION-REFERENCE.md" || true
    
    check_file_exists "$SCRIPT_DIR/PROJECT-STRUCTURE.md" "PROJECT-STRUCTURE.md" || true
    check_markdown "$SCRIPT_DIR/PROJECT-STRUCTURE.md" "PROJECT-STRUCTURE.md" || true
    
    # ===== Installation Scripts =====
    print_header "Installation Scripts"
    
    # Quick start
    if check_file_exists "$SCRIPT_DIR/quick-start.sh" "quick-start.sh"; then
        check_file_size "$SCRIPT_DIR/quick-start.sh" 5000 "quick-start.sh"
        check_bash_syntax "$SCRIPT_DIR/quick-start.sh" "quick-start.sh" || true
    fi
    
    # Stage 1
    if check_file_exists "$SCRIPT_DIR/01-initial-setup.sh" "01-initial-setup.sh"; then
        check_file_size "$SCRIPT_DIR/01-initial-setup.sh" 5000 "01-initial-setup.sh"
        check_bash_syntax "$SCRIPT_DIR/01-initial-setup.sh" "01-initial-setup.sh" || true
    fi
    
    # Stage 2
    if check_file_exists "$SCRIPT_DIR/02-install-openclaw.sh" "02-install-openclaw.sh"; then
        check_file_size "$SCRIPT_DIR/02-install-openclaw.sh" 5000 "02-install-openclaw.sh"
        check_bash_syntax "$SCRIPT_DIR/02-install-openclaw.sh" "02-install-openclaw.sh" || true
    fi
    
    # Stage 3
    if check_file_exists "$SCRIPT_DIR/03-setup-tailscale.sh" "03-setup-tailscale.sh"; then
        check_file_size "$SCRIPT_DIR/03-setup-tailscale.sh" 5000 "03-setup-tailscale.sh"
        check_bash_syntax "$SCRIPT_DIR/03-setup-tailscale.sh" "03-setup-tailscale.sh" || true
    fi
    
    # Stage 4
    if check_file_exists "$SCRIPT_DIR/04-post-install-security.sh" "04-post-install-security.sh"; then
        check_file_size "$SCRIPT_DIR/04-post-install-security.sh" 5000 "04-post-install-security.sh"
        check_bash_syntax "$SCRIPT_DIR/04-post-install-security.sh" "04-post-install-security.sh" || true
    fi
    
    # Maintenance
    if check_file_exists "$SCRIPT_DIR/05-maintenance.sh" "05-maintenance.sh"; then
        check_file_size "$SCRIPT_DIR/05-maintenance.sh" 5000 "05-maintenance.sh"
        check_bash_syntax "$SCRIPT_DIR/05-maintenance.sh" "05-maintenance.sh" || true
    fi
    
    # ===== System Requirements Check =====
    print_header "System Prerequisites"
    
    # Check OS
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        print_pass "OS Detected: $PRETTY_NAME"
    else
        print_warn "Cannot detect OS (not critical)"
    fi
    
    # Check for bash
    if command -v bash &>/dev/null; then
        BASH_VERSION=$(bash --version | head -1)
        print_pass "Bash installed: $BASH_VERSION"
    else
        print_fail "Bash not installed (required)"
    fi
    
    # Check for sudo
    if command -v sudo &>/dev/null; then
        print_pass "sudo available"
    else
        print_fail "sudo not available (non-critical on systems with root access)"
    fi
    
    # Check connectivity
    if ping -c 1 8.8.8.8 &>/dev/null 2>&1; then
        print_pass "Internet connectivity verified"
    else
        print_warn "Unable to reach internet (will be needed during installation)"
    fi
    
    # ===== Summary =====
    print_header "Verification Summary"
    
    echo ""
    echo -e "Results:"
    echo -e "$GREEN✓${NC} Passed: $PASSED"
    if [[ $WARNINGS -gt 0 ]]; then
        echo -e "$YELLOW⚠${NC} Warnings: $WARNINGS"
    fi
    if [[ $FAILED -gt 0 ]]; then
        echo -e "$RED✗${NC} Failed: $FAILED"
    fi
    
    echo ""
    
    if [[ $FAILED -eq 0 ]]; then
        echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}Installation package is ready for deployment!${NC}"
        echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo "Next steps:"
        echo "1. Review README.md"
        echo "2. Run: sudo ./quick-start.sh"
        echo ""
    else
        echo -e "${RED}════════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}Installation package has issues that need to be fixed.${NC}"
        echo -e "${RED}════════════════════════════════════════════════════════════════${NC}"
        echo ""
    fi
    
    if [[ $WARNINGS -gt 0 ]]; then
        echo "Recommendations:"
        echo "1. Make all scripts executable: chmod +x *.sh"
        echo "2. Verify bash syntax: bash -n [script-name].sh"
        echo ""
    fi
    
    echo "For more information:"
    echo "- README.md - Main installation guide"
    echo "- DEPLOYMENT-GUIDE.md - Detailed deployment steps"
    echo "- PROJECT-STRUCTURE.md - File descriptions"
    echo ""
    
    # Return exit code
    if [[ $FAILED -gt 0 ]]; then
        return 1
    else
        return 0
    fi
}

# Run main
main "$@"
