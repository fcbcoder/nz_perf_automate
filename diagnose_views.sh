#!/bin/bash

#=============================================================================
# Diagnostic Script - Test Netezza System Views
# Purpose: Determine which views exist and work for object ownership queries
#=============================================================================

echo "================================================================================================"
echo "NETEZZA SYSTEM VIEWS DIAGNOSTIC"
echo "Testing which views are available for object ownership detection"
echo "================================================================================================"
echo ""

# Configuration (update these for your environment)
NETEZZA_HOST="${NETEZZA_HOST:-}"
NETEZZA_DB="${NETEZZA_DB:-SYSTEM}"
NETEZZA_USER="${NETEZZA_USER:-ADMIN}"

# Build nzsql command
if [[ -n "$NETEZZA_HOST" ]]; then
    NZSQL_CMD="nzsql -host ${NETEZZA_HOST} -d ${NETEZZA_DB} -u ${NETEZZA_USER}"
else
    NZSQL_CMD="nzsql -d ${NETEZZA_DB} -u ${NETEZZA_USER}"
fi

echo "Using connection: $NZSQL_CMD"
echo ""

# Test user for queries (change this to a real user in your system)
TEST_USER="${1:-USG75}"

echo "Testing with user: $TEST_USER"
echo ""

#=============================================================================
# Test 1: Check if _V_RELATION_TABLE exists
#=============================================================================

echo "--- Test 1: _V_RELATION_TABLE view ---"
echo "Query: SELECT COUNT(*) FROM _V_RELATION_TABLE WHERE OWNER = '$TEST_USER';"
echo ""

RESULT=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_RELATION_TABLE WHERE UPPER(OWNER) = UPPER('${TEST_USER}');" 2>&1)
EXIT_CODE=$?

if [[ $EXIT_CODE -eq 0 ]]; then
    echo "✓ View exists and query succeeded"
    echo "  Result: '$RESULT'"
    echo "  Trimmed: '$(echo "$RESULT" | tr -d ' ')'"
else
    echo "✗ View does not exist or query failed"
    echo "  Error: $RESULT"
fi
echo ""

#=============================================================================
# Test 2: Check if _V_RELATION_VIEW exists
#=============================================================================

echo "--- Test 2: _V_RELATION_VIEW view ---"
echo "Query: SELECT COUNT(*) FROM _V_RELATION_VIEW WHERE OWNER = '$TEST_USER';"
echo ""

RESULT=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_RELATION_VIEW WHERE UPPER(OWNER) = UPPER('${TEST_USER}');" 2>&1)
EXIT_CODE=$?

if [[ $EXIT_CODE -eq 0 ]]; then
    echo "✓ View exists and query succeeded"
    echo "  Result: '$RESULT'"
    echo "  Trimmed: '$(echo "$RESULT" | tr -d ' ')'"
else
    echo "✗ View does not exist or query failed"
    echo "  Error: $RESULT"
fi
echo ""

#=============================================================================
# Test 3: Check if _V_RELATION_SEQUENCE exists
#=============================================================================

echo "--- Test 3: _V_RELATION_SEQUENCE view ---"
echo "Query: SELECT COUNT(*) FROM _V_RELATION_SEQUENCE WHERE OWNER = '$TEST_USER';"
echo ""

RESULT=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_RELATION_SEQUENCE WHERE UPPER(OWNER) = UPPER('${TEST_USER}');" 2>&1)
EXIT_CODE=$?

if [[ $EXIT_CODE -eq 0 ]]; then
    echo "✓ View exists and query succeeded"
    echo "  Result: '$RESULT'"
    echo "  Trimmed: '$(echo "$RESULT" | tr -d ' ')'"
else
    echo "✗ View does not exist or query failed"
    echo "  Error: $RESULT"
fi
echo ""

#=============================================================================
# Test 4: Fallback - Try _V_TABLE (single database)
#=============================================================================

echo "--- Test 4: _V_TABLE view (fallback) ---"
echo "Query: SELECT COUNT(*) FROM _V_TABLE WHERE OWNER = '$TEST_USER';"
echo ""

RESULT=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_TABLE WHERE UPPER(OWNER) = UPPER('${TEST_USER}');" 2>&1)
EXIT_CODE=$?

if [[ $EXIT_CODE -eq 0 ]]; then
    echo "✓ View exists and query succeeded"
    echo "  Result: '$RESULT'"
    echo "  Trimmed: '$(echo "$RESULT" | tr -d ' ')'"
else
    echo "✗ View does not exist or query failed"
    echo "  Error: $RESULT"
fi
echo ""

#=============================================================================
# Test 5: List all available _V_RELATION* views
#=============================================================================

echo "--- Test 5: List all available system views with 'RELATION' in name ---"
echo ""

$NZSQL_CMD -c "
SELECT 
    VIEWNAME,
    DATABASE
FROM _V_VIEW
WHERE VIEWNAME LIKE '%RELATION%'
ORDER BY VIEWNAME;" 2>&1

echo ""

#=============================================================================
# Test 6: Check system catalog directly
#=============================================================================

echo "--- Test 6: Query system catalog for objects ---"
echo "Query: SELECT COUNT(*) FROM _T_OBJECT WHERE OWNER = '$TEST_USER';"
echo ""

RESULT=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _T_OBJECT WHERE UPPER(OWNER) = UPPER('${TEST_USER}');" 2>&1)
EXIT_CODE=$?

if [[ $EXIT_CODE -eq 0 ]]; then
    echo "✓ System catalog query succeeded"
    echo "  Result: '$RESULT'"
    echo "  Trimmed: '$(echo "$RESULT" | tr -d ' ')'"
else
    echo "✗ System catalog query failed"
    echo "  Error: $RESULT"
fi
echo ""

#=============================================================================
# Test 7: Try alternative view names
#=============================================================================

echo "--- Test 7: Test alternative view names ---"
echo ""

for VIEW_NAME in "_V_OBJ_RELATION_XDB" "_V_TABLE_XDB" "_V_RELATION"; do
    echo "Testing: $VIEW_NAME"
    RESULT=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM $VIEW_NAME LIMIT 1;" 2>&1)
    EXIT_CODE=$?
    
    if [[ $EXIT_CODE -eq 0 ]]; then
        echo "  ✓ View exists: $VIEW_NAME"
        
        # Try to count objects for test user
        COUNT=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM $VIEW_NAME WHERE UPPER(OWNER) = UPPER('${TEST_USER}');" 2>&1)
        if [[ $? -eq 0 ]]; then
            echo "    Objects for $TEST_USER: $(echo "$COUNT" | tr -d ' ')"
        fi
    else
        echo "  ✗ View does not exist: $VIEW_NAME"
    fi
    echo ""
done

#=============================================================================
# Test 8: Sample data from working view
#=============================================================================

echo "--- Test 8: Show sample data from _V_RELATION_TABLE (if exists) ---"
echo ""

$NZSQL_CMD -c "
SELECT 
    TABLENAME,
    DATABASE,
    OWNER,
    SCHEMA
FROM _V_RELATION_TABLE
WHERE UPPER(OWNER) = UPPER('${TEST_USER}')
LIMIT 10;" 2>&1

echo ""

#=============================================================================
# Test 9: Check database connection
#=============================================================================

echo "--- Test 9: Verify database connection ---"
echo ""

$NZSQL_CMD -c "
SELECT 
    CURRENT_DATABASE,
    CURRENT_USER,
    VERSION();" 2>&1

echo ""

#=============================================================================
# Summary and Recommendations
#=============================================================================

echo "================================================================================================"
echo "DIAGNOSTIC SUMMARY"
echo "================================================================================================"
echo ""
echo "Review the results above to determine:"
echo ""
echo "1. Which views exist on your Netezza system"
echo "2. Whether _V_RELATION_* views are available"
echo "3. If views return NULL or actual counts"
echo "4. What alternative views can be used"
echo ""
echo "If _V_RELATION_* views don't exist, the script needs to be updated to use:"
echo "  - _V_TABLE, _V_VIEW, _V_SEQUENCE (single database)"
echo "  - OR query each database separately"
echo "  - OR use _T_OBJECT system catalog directly"
echo ""
echo "================================================================================================"
