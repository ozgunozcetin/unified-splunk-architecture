#!/usr/bin/env bash
# =============================================================================
# Local lint runner — same checks as CI, but run locally before push
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ALL_OK=1

echo "Running local lint checks..."
echo ""

# --- YAML ---
if command -v yamllint >/dev/null 2>&1; then
    echo -e "${YELLOW}[1/4] yamllint${NC}"
    if yamllint -d "{extends: default, rules: {line-length: {max: 200}, document-start: disable, truthy: disable, comments: disable, indentation: {spaces: 2, indent-sequences: false}}}" docker-compose.yml .github/ 2>&1; then
        echo -e "${GREEN}  ✓ YAML clean${NC}"
    else
        echo -e "${RED}  ✗ YAML issues${NC}"
        ALL_OK=0
    fi
else
    echo -e "${YELLOW}[1/4] yamllint not installed (pip install yamllint)${NC}"
fi
echo ""

# --- Dockerfile ---
if command -v hadolint >/dev/null 2>&1; then
    echo -e "${YELLOW}[2/4] hadolint${NC}"
    if hadolint --ignore DL3008 --ignore DL3009 --ignore DL3015 syslog/Dockerfile; then
        echo -e "${GREEN}  ✓ Dockerfile clean${NC}"
    else
        echo -e "${RED}  ✗ Dockerfile issues${NC}"
        ALL_OK=0
    fi
else
    echo -e "${YELLOW}[2/4] hadolint not installed${NC}"
fi
echo ""

# --- Splunk .conf basic check ---
echo -e "${YELLOW}[3/4] Splunk .conf basic structure${NC}"
for conf in $(find apps syslog -name "*.conf" 2>/dev/null); do
    if grep -qE '^\[' "$conf"; then
        echo -e "${GREEN}  ✓ $conf${NC}"
    else
        echo -e "${RED}  ✗ $conf — no stanza headers${NC}"
        ALL_OK=0
    fi
done
echo ""

# --- Secret scan ---
echo -e "${YELLOW}[4/4] Secret scan (basic)${NC}"
SUSPECT=$(grep -rEn 'password|token|secret' --include='*.yml' --include='*.conf' --include='*.sh' \
    --exclude-dir=.git --exclude='.env.example' \
    -l 2>/dev/null || true)
if [ -n "$SUSPECT" ]; then
    echo -e "${YELLOW}  Files mentioning password/token/secret (review manually):${NC}"
    echo "$SUSPECT" | sed 's/^/    /'
fi

if grep -rE '^[A-Z_]+=[A-Za-z0-9].*[!@#$%]' --include='*.yml' --exclude-dir=.git . 2>/dev/null; then
    echo -e "${RED}  ✗ Possible hardcoded secret found${NC}"
    ALL_OK=0
fi
echo ""

if [ $ALL_OK -eq 1 ]; then
    echo -e "${GREEN}All local lint checks passed.${NC}"
    exit 0
else
    echo -e "${RED}Lint failed — fix issues before pushing.${NC}"
    exit 1
fi
