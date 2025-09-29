#!/bin/bash

#=============================================================================
# Netezza System Views Test Script
# Use this script on your Netezza server to discover available system views
#=============================================================================

# Configuration - Update these for your environment
NETEZZA_HOST="localhost"
NETEZZA_DB="SYSTEM"
NETEZZA_USER="ADMIN"
NZSQL_PATH="/nz/bin/nzsql"  # Update this path as needed

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Netezza System Views Discovery${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

NZSQL_CMD="$NZSQL_PATH -host $NETEZZA_HOST -db $NETEZZA_DB -u $NETEZZA_USER"

# Test basic connection
echo -e "${YELLOW}Testing connection...${NC}"
if $NZSQL_CMD -c "SELECT CURRENT_TIMESTAMP;" 2>/dev/null; then
    echo -e "${GREEN}✓ Connection successful${NC}"
else
    echo -e "${RED}✗ Connection failed${NC}"
    echo "Please update the configuration in this script"
    exit 1
fi

echo ""
echo -e "${YELLOW}Testing common system views...${NC}"

# List of common system views to test
VIEWS=(
    "_V_SESSION"
    "_V_SYSTEM_STATE"
    "_V_DATABASE" 
    "_V_DISK"
    "_V_HOST"
    "_V_QRYHIST"
    "_V_SQL_TEXT"
    "_V_LOCK"
    "_V_SYSTEM_CONFIG"
    "_V_VIEW"
    "_V_TABLE"
    "_V_SYSTEM_PROCESSES"
    "_V_SYSTEM_IO"
    "V_SESSION"
    "V_SYSTEM_STATE"
    "V_DATABASE"
    "V_DISK"
    "V_HOST"
    "_T_SESSION"
    "_T_DATABASE"
)

AVAILABLE_VIEWS=()
UNAVAILABLE_VIEWS=()

for view in "${VIEWS[@]}"; do
    echo -n "Testing $view... "
    if $NZSQL_CMD -c "SELECT COUNT(*) FROM $view LIMIT 1;" &>/dev/null; then
        echo -e "${GREEN}✓ Available${NC}"
        AVAILABLE_VIEWS+=("$view")
    else
        echo -e "${RED}✗ Not available${NC}"
        UNAVAILABLE_VIEWS+=("$view")
    fi
done

echo ""
echo -e "${BLUE}Summary:${NC}"
echo -e "${GREEN}Available views (${#AVAILABLE_VIEWS[@]}):${NC}"
for view in "${AVAILABLE_VIEWS[@]}"; do
    echo "  ✓ $view"
done

echo ""
echo -e "${RED}Unavailable views (${#UNAVAILABLE_VIEWS[@]}):${NC}"
for view in "${UNAVAILABLE_VIEWS[@]}"; do
    echo "  ✗ $view"
done

echo ""
echo -e "${YELLOW}Discovering all system views...${NC}"

# Try to discover all system views
echo "Attempting to list all system views:"
$NZSQL_CMD -c "SELECT VIEWNAME FROM _V_VIEW WHERE VIEWNAME LIKE '_V_%' ORDER BY VIEWNAME;" 2>/dev/null || \
$NZSQL_CMD -c "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME LIKE '_V_%' ORDER BY TABLE_NAME;" 2>/dev/null || \
echo "Could not retrieve system view list"

echo ""
echo -e "${BLUE}Sample data from available views:${NC}"

# Show sample data from key available views
for view in "${AVAILABLE_VIEWS[@]}"; do
    case $view in
        "_V_SESSION"|"V_SESSION")
            echo ""
            echo -e "${YELLOW}Sample from $view:${NC}"
            $NZSQL_CMD -c "SELECT SESSIONID, USERNAME, DBNAME, STATE FROM $view LIMIT 5;" 2>/dev/null
            ;;
        "_V_DATABASE"|"V_DATABASE")
            echo ""
            echo -e "${YELLOW}Sample from $view:${NC}"
            $NZSQL_CMD -c "SELECT DATABASE, OWNER FROM $view LIMIT 5;" 2>/dev/null
            ;;
        "_V_SYSTEM_STATE"|"V_SYSTEM_STATE")
            echo ""
            echo -e "${YELLOW}Sample from $view:${NC}"
            $NZSQL_CMD -c "SELECT * FROM $view LIMIT 3;" 2>/dev/null
            ;;
    esac
done

echo ""
echo -e "${GREEN}Discovery complete!${NC}"
echo "Use this information to update the main performance script."