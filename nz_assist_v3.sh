#!/bin/bash

#=============================================================================
# Netezza Performance Tool - Core Version
# Version: 2.0 - Clean & Focused
# Date: October 10, 2025
# Description: Core functionality for Netezza 11.2.1.13 Performance Analysis
# Author: Love Malhotra
#=============================================================================

# Configuration Variables
NETEZZA_HOST="${NETEZZA_HOST:-}"  # Will prompt for host if not set
NETEZZA_DB="${NETEZZA_DB:-SYSTEM}"
NETEZZA_USER="${NETEZZA_USER:-ADMIN}"
NZSQL_PATH="${NZSQL_PATH:-nzsql}"  # Allow custom nzsql path

# Build nzsql command with proper options
build_nzsql_cmd() {
    local cmd="$NZSQL_PATH"
    if [[ -n "$NETEZZA_HOST" ]]; then
        cmd="$cmd -host ${NETEZZA_HOST}"
    fi
    cmd="$cmd -d ${NETEZZA_DB} -u ${NETEZZA_USER}"
    echo "$cmd"
}

NZSQL_CMD=$(build_nzsql_cmd)

# Runtime thresholds (configurable)
LONG_RUNNING_QUERY_HOURS=4
TOP_SESSIONS_LIMIT=40
TOP_QUERIES_LIMIT=100

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/tmp/netezza_perf_$(date +%Y%m%d_%H%M%S).log"

#=============================================================================
# Core Utility Functions (From V1)
#=============================================================================

print_header() {
    local title="$1"
    echo -e "\n${BLUE}================================================================================================${NC}"
    echo -e "${BLUE}$title${NC}"
    echo -e "${BLUE}$(date)${NC}"
    echo -e "${BLUE}================================================================================================${NC}\n"
}

print_section() {
    local title="$1"
    echo -e "\n${CYAN}--- $title ---${NC}"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

execute_sql() {
    local sql="$1"
    local description="$2"
    local show_errors="${3:-false}"
    
    echo "-- $description" >> "$LOG_FILE"
    echo "$sql" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    if [ "$show_errors" = "true" ]; then
        echo "Executing: $description"
        $NZSQL_CMD -c "$sql"
        local exit_code=$?
    else
        $NZSQL_CMD -c "$sql" 2>/dev/null
        local exit_code=$?
    fi
    
    if [ $exit_code -ne 0 ]; then
        print_error "Failed to execute: $description"
        if [ "$show_errors" = "false" ]; then
            echo "Run with debug mode to see detailed error messages"
        fi
        return 1
    fi
    return 0
}

test_connection() {
    print_section "Testing Netezza Connection"
    
    if [[ -z "$NETEZZA_HOST" ]]; then
        echo "No Netezza host specified."
        read -p "Enter Netezza host (or press Enter for local connection): " input_host
        if [[ -n "$input_host" ]]; then
            NETEZZA_HOST="$input_host"
            NZSQL_CMD=$(build_nzsql_cmd)
        fi
    fi
    
    if [[ -n "$NETEZZA_HOST" ]]; then
        echo "Connecting to: $NETEZZA_HOST/$NETEZZA_DB as $NETEZZA_USER"
    else
        echo "Connecting to: local/$NETEZZA_DB as $NETEZZA_USER"
    fi
    
    if execute_sql "SELECT CURRENT_TIMESTAMP;" "Connection Test" true; then
        print_success "Connection successful!"
        return 0
    else
        print_error "Connection failed!"
        return 1
    fi
}

#=============================================================================
# Core Function 1: Active Sessions & Transactions (From V1 - WORKING)
#=============================================================================

check_active_sessions() {
    print_header "ACTIVE SESSIONS AND TRANSACTIONS ANALYSIS"
    
    # Use nzsession utility for enhanced session analysis - EXACTLY FROM V1
    print_section "Enhanced Session Analysis using nzsession"
    
    # Check if nzsession utility is available
    local nzsession_path="/nz/bin/nzsession"
    local alt_paths=(
        "/opt/nz/bin/nzsession"
        "/usr/local/nz/bin/nzsession"
        "/nz/support/bin/nzsession"
        "/nz/kit/bin/nzsession"
    )
    
    local found_nzsession=""
    
    if [[ -f "$nzsession_path" && -x "$nzsession_path" ]]; then
        found_nzsession="$nzsession_path"
    else
        for path in "${alt_paths[@]}"; do
            if [[ -f "$path" && -x "$path" ]]; then
                found_nzsession="$path"
                break
            fi
        done
    fi
    
    if [[ -n "$found_nzsession" ]]; then
        print_success "Using nzsession at: $found_nzsession"
        
        # Active transactions analysis - THE KEY FEATURE FROM V1
        print_section "Active Transactions Analysis"
        local activetxn_file="/tmp/netezza_activetxn_$(date +%Y%m%d_%H%M%S).txt"
        
        echo "Analyzing active transactions..."
        if [[ -n "$NETEZZA_HOST" ]]; then
            if "$found_nzsession" -host "$NETEZZA_HOST" -activetxn > "$activetxn_file" 2>&1; then
                if [[ -s "$activetxn_file" ]]; then
                    print_success "Active transactions found!"
                    echo ""
                    echo "Active Transactions Report:"
                    echo "=============================================================="
                    cat "$activetxn_file"
                    echo "=============================================================="
                    
                    # Count transactions
                    local txn_count=$(wc -l < "$activetxn_file" 2>/dev/null || echo "0")
                    if [[ "$txn_count" -gt 2 ]]; then  # More than just headers
                        print_warning "$((txn_count-1)) active transactions detected"
                    else
                        print_success "No active transactions detected"
                    fi
                else
                    print_success "No active transactions currently running"
                fi
                echo "Full report saved to: $activetxn_file"
            fi
        else
            if "$found_nzsession" -activetxn > "$activetxn_file" 2>&1; then
                if [[ -s "$activetxn_file" ]]; then
                    print_success "Active transactions found!"
                    echo ""
                    echo "Active Transactions Report:"
                    echo "=============================================================="
                    cat "$activetxn_file"
                    echo "=============================================================="
                else
                    print_success "No active transactions currently running"
                fi
                echo "Full report saved to: $activetxn_file"
            fi
        fi
    fi
    
    # Basic session analysis using system views - CORRECT COLUMNS FROM V1
    print_section "Current Sessions Analysis (System Views)"
    
    execute_sql "
    SELECT 
        ID,
        USERNAME,
        DBNAME,
        STATUS,
        IPADDR,
        CONNTIME,
        PRIORITY,
        COMMAND,
        CLIENT_OS_USERNAME
    FROM _V_SESSION
    ORDER BY CONNTIME DESC
    LIMIT ${TOP_SESSIONS_LIMIT};" "Current Sessions Overview"
    
    # Session status summary
    execute_sql "
    SELECT 
        STATUS,
        COUNT(*) AS SESSION_COUNT
    FROM _V_SESSION
    GROUP BY STATUS
    ORDER BY SESSION_COUNT DESC;" "Session Status Distribution"
    
    # Sessions by database
    execute_sql "
    SELECT 
        DBNAME,
        COUNT(*) AS SESSION_COUNT,
        COUNT(DISTINCT USERNAME) AS UNIQUE_USERS
    FROM _V_SESSION
    WHERE DBNAME IS NOT NULL
    GROUP BY DBNAME
    ORDER BY SESSION_COUNT DESC;" "Database Connection Summary"
}

#=============================================================================
# Core Function 2: Query Performance (From V1 - WORKING) 
#=============================================================================

check_query_performance() {
    print_header "REAL-TIME  & HIST QUERY PERFORMANCE ANALYSIS"
    
    # Check what views are available
    local has_qrystat=false
    if execute_sql "SELECT COUNT(*) FROM _V_QRYSTAT LIMIT 1;" "Test _V_QRYSTAT" false; then
        has_qrystat=true
        print_success "Using _V_QRYSTAT for real-time query analysis"
    else
        print_warning "Using _V_QRYHIST for historical analysis"
    fi
    
    if [[ "$has_qrystat" == true ]]; then
        # Real-time analysis with _V_QRYSTAT - ADD QS_USER COLUMN
        print_section "Current Running Queries (Real-time)"
        execute_sql "
        SELECT 
            QS_SESSIONID,
            QS_PLANID,
            QS_ESTCOST,
            QS_ESTMEM,
            QS_ESTDISK,
            QS_TSTART,
            ROUND(EXTRACT(EPOCH FROM (NOW() - QS_TSTART))/60, 1) AS MINUTES_RUNNING,
            SUBSTRING(QS_SQL, 1, 100) AS SQL_PREVIEW
        FROM _V_QRYSTAT
        WHERE QS_TSTART < NOW() - INTERVAL '${LONG_RUNNING_QUERY_HOURS} HOURS'
        ORDER BY QS_TSTART
        LIMIT ${TOP_QUERIES_LIMIT};" "Long Running Queries (Real-time)"
        
        # High cost queries - ADD QS_USER COLUMN
        print_section "High Cost Current Running Queries (Real-time)"
	execute_sql "
        SELECT 
            QS_SESSIONID,
            QS_PLANID,
            QS_ESTCOST,
            QS_ESTMEM,
            QS_TSTART,
            ROUND(EXTRACT(EPOCH FROM (NOW() - QS_TSTART))/60, 1) AS MINUTES_RUNNING,
            SUBSTRING(QS_SQL, 1, 80) AS SQL_PREVIEW
        FROM _V_QRYSTAT
        WHERE QS_ESTCOST > 100
        ORDER BY QS_ESTCOST DESC
        LIMIT ${TOP_QUERIES_LIMIT};" "High Cost Queries (Currently Running)"
        
    fi
         # Historical analysis with _V_QRYHIST - EXISTING CODE IS CORRECT
    print_section "Query History Analysis (Last 24 Hours)"
    execute_sql "
        SELECT 
            QH_SESSIONID,
            QH_USER,
            QH_DATABASE,
            QH_TSTART,
            QH_TEND,
            ROUND(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)), 2) AS EXECUTION_SECONDS,
            QH_ESTCOST,
            QH_RESROWS,
            SUBSTR(QH_SQL, 1, 80) AS SQL_PREVIEW
        FROM _V_QRYHIST
        WHERE QH_TEND > NOW() - INTERVAL '24 HOURS'
        --AND QH_TSTART IS NOT NULL 
        -- AND QH_TEND IS NOT NULL
        --AND EXTRACT(EPOCH FROM (QH_TEND - QH_TEND)) > 30
        ORDER BY EXECUTION_SECONDS DESC
        LIMIT ${TOP_QUERIES_LIMIT};" "Slowest Queries (Last 24h)"
        
        # Query activity by user
    execute_sql "
        SELECT 
            QH_USER,
            COUNT(*) AS QUERY_COUNT,
            ROUND(AVG(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART))), 2) AS AVG_EXECUTION_SEC,
            ROUND(SUM(QH_ESTCOST), 2) AS TOTAL_EST_COST
        FROM _V_QRYHIST
        WHERE QH_TEND > NOW() - INTERVAL '24 HOURS'
        AND QH_TSTART IS NOT NULL 
        AND QH_TEND IS NOT NULL
        GROUP BY QH_USER
        ORDER BY QUERY_COUNT DESC
        LIMIT 10;" "Top Users by Query Activity"
    
}

#=============================================================================
# Core Function 3: Cost-Based Analysis (SIMPLIFIED & WORKING)
#=============================================================================

check_cost_based_performance() {
    print_header "HISTORICAL COST ANALYSIS"
    
    echo -e "${CYAN}Search Options:${NC}"
    echo "1. Search by Session ID"
    echo "2. Search by Username" 
    echo "3. Show all high-cost queries"
    echo "4. Return to main menu"
    echo ""
    
    read -p "Choose search method (1-4): " search_method
    
    case $search_method in
        1)
            read -p "Enter Session ID: " session_id
            if [[ "$session_id" =~ ^[0-9]+$ ]]; then
                execute_sql "
                SELECT 
                    QH_SESSIONID,
                    QH_USER,
                    QH_DATABASE,
                    QH_TSTART,
                    QH_TEND,
                    QH_ESTCOST,
                    QH_PLANID,
                    ROUND(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)), 2) AS EXECUTION_SECONDS,
                    QH_RESROWS,
                    SUBSTR(QH_SQL, 1, 100) AS SQL_PREVIEW
                FROM _V_QRYHIST
                WHERE QH_SESSIONID = ${session_id}
                AND QH_TSTART IS NOT NULL 
                AND QH_TEND IS NOT NULL
                ORDER BY QH_ESTCOST DESC, EXECUTION_SECONDS DESC
                LIMIT ${TOP_QUERIES_LIMIT};" "Historical Queries for Session ${session_id} (by Cost & Time)"
            else
                print_error "Invalid session ID"
            fi
            ;;
        2)
            read -p "Enter Username: " username
            if [[ -n "$username" ]]; then
                execute_sql "
                SELECT 
                    QH_SESSIONID,
                    QH_USER,
                    QH_DATABASE,
                    QH_TSTART,
                    QH_TEND,
                    QH_ESTCOST,
                    QH_PLANID,
                    ROUND(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)), 2) AS EXECUTION_SECONDS,
                    QH_RESROWS,
                    SUBSTR(QH_SQL, 1, 100) AS SQL_PREVIEW
                FROM _V_QRYHIST
                WHERE UPPER(QH_USER) = UPPER('${username}')
                AND QH_TSTART IS NOT NULL 
                AND QH_TEND IS NOT NULL
                AND QH_TEND > NOW() - INTERVAL '7 DAYS'
                ORDER BY QH_ESTCOST DESC, EXECUTION_SECONDS DESC
                LIMIT ${TOP_QUERIES_LIMIT};" "Historical Queries for User ${username} (by Cost & Time)"
            else
                print_error "Username cannot be empty"
            fi
            ;;
        3)
            # Show all high-cost queries - ADD QS_USER TO _V_QRYSTAT QUERIES
            if execute_sql "SELECT COUNT(*) FROM _V_QRYSTAT LIMIT 1;" "Test _V_QRYSTAT" false; then
                print_success "_V_QRYSTAT available - Enhanced cost analysis"
                
                execute_sql "
                SELECT 
                    QS_SESSIONID,
                    QS_PLANID,
                    QS_ESTCOST,
                    QS_ESTMEM,
                    QS_ESTDISK,
                    QS_TSTART,
                    ROUND(EXTRACT(EPOCH FROM (NOW() - QS_TSTART))/60, 1) AS MINUTES_RUNNING,
                    SUBSTRING(QS_SQL, 1, 100) AS SQL_PREVIEW
                FROM _V_QRYSTAT
                WHERE QS_ESTCOST > 0
                ORDER BY QS_ESTCOST DESC
                LIMIT ${TOP_QUERIES_LIMIT};" "Top Queries by Estimated Cost (Active)"
                
            else
                execute_sql "
                SELECT 
                    QH_SESSIONID,
                    QH_USER,
                    QH_DATABASE,
                    QH_TSTART,
                    QH_TEND,
                    QH_ESTCOST,
                    QH_PLANID,
                    ROUND(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)), 2) AS EXECUTION_SECONDS,
                    SUBSTR(QH_SQL, 1, 100) AS SQL_PREVIEW
                FROM _V_QRYHIST
                WHERE QH_TEND > NOW() - INTERVAL '24 HOURS'
                AND QH_ESTCOST > 0
                ORDER BY QH_ESTCOST DESC
                LIMIT ${TOP_QUERIES_LIMIT};" "Top Queries by Cost (Last 24h)"
            fi
            ;;
        4)
            return
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
}

#=============================================================================
# Core Function 4: Explain Plan Analysis (From V1 - WORKING nz_plan utility)
#=============================================================================

interactive_explain_plan() {
    print_header "INTERACTIVE SQL EXPLAIN PLAN ANALYSIS"
    
    echo -e "${CYAN}Available options:${NC}"
    echo "1. Analyze Active SQL (Session ID or Username → _V_QRYSTAT → explain plan)"  
    echo "2. Analyze SQL from recent query history (Session ID or Username → _V_QRYHIST → explain plan)"
    echo "3. Use nz_plan utility (Plan ID)"
    echo "4. Enter custom SQL for analysis"
    echo "5. Return to main menu"
    echo ""
    
    read -p "Choose an option (1-5): " choice
    
    case $choice in
        1)
            analyze_active_sql
            ;;
        2)
            analyze_recent_queries_enhanced
            ;;
        3)
            use_nz_plan_utility
            ;;
        4)
            analyze_custom_sql
            ;;
        5)
            return
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
}

# NEW: Analyze Active SQL (Option 4.1)
analyze_active_sql() {
    print_section "Active SQL Analysis (_V_QRYSTAT)"
    
    # First check if _V_QRYSTAT is available
    if ! execute_sql "SELECT COUNT(*) FROM _V_QRYSTAT LIMIT 1;" "Test _V_QRYSTAT" false; then
        print_error "_V_QRYSTAT not available. Use option 2 for historical analysis."
        return
    fi
    
    # Show all active queries with plan IDs, cost, ordered by execution time
    print_section "Active Queries (Ordered by Execution Time & Cost)"
    execute_sql "
    SELECT 
        ROW_NUMBER() OVER (ORDER BY EXTRACT(EPOCH FROM (NOW() - QS_TSTART)) DESC, QS_ESTCOST DESC) as NUM,
        QS_SESSIONID,
--        QS_USER,
        QS_PLANID,
        QS_ESTCOST,
        QS_ESTMEM,
        QS_TSTART,
        ROUND(EXTRACT(EPOCH FROM (NOW() - QS_TSTART))/60, 1) AS MINUTES_RUNNING,
        SUBSTRING(QS_SQL, 1, 80) AS SQL_PREVIEW
    FROM _V_QRYSTAT
    WHERE QS_PLANID IS NOT NULL
    ORDER BY MINUTES_RUNNING DESC, QS_ESTCOST DESC
    LIMIT 20;" "Active Queries with Plan IDs"
    
    echo ""
    echo "Search Options:"
    echo "1. Select by query number (from list above)"
    echo "2. Search by Session ID"
    echo "3. Search by Username"
    echo ""
    
    read -p "Choose search method (1-3): " search_method
    
    case $search_method in
        1)
            read -p "Enter query number (1-20): " query_num
            if [[ "$query_num" =~ ^[0-9]+$ ]] && [[ "$query_num" -ge 1 ]] && [[ "$query_num" -le 20 ]]; then
                generate_plans_for_active_query_by_number "$query_num"
            else
                print_error "Invalid query number"
            fi
            ;;
        2)
            read -p "Enter Session ID: " session_id
            if [[ "$session_id" =~ ^[0-9]+$ ]]; then
                generate_plans_for_active_session "$session_id"
            else
                print_error "Invalid session ID"
            fi
            ;;
        3)
            read -p "Enter Username: " username
            if [[ -n "$username" ]]; then
                generate_plans_for_active_user "$username"
            else
                print_error "Username cannot be empty"
            fi
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
}

# ENHANCED: Analyze Recent Queries (Option 4.2)  
analyze_recent_queries_enhanced() {
    print_section "Recent Query History Analysis (_V_QRYHIST)"
    
    # Show all recent queries with plan IDs, cost, ordered by execution time
    print_section "Recent Queries (Ordered by Execution Time & Cost)"
    execute_sql "
    SELECT 
        ROW_NUMBER() OVER (ORDER BY EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)) DESC, QH_ESTCOST DESC) as NUM,
        QH_SESSIONID,
        QH_USER,
        QH_DATABASE,
        QH_TSTART,
        QH_TEND,
        QH_PLANID,
        QH_ESTCOST,
        ROUND(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)), 2) AS EXECUTION_SECONDS,
        SUBSTR(QH_SQL, 1, 80) AS SQL_PREVIEW
    FROM _V_QRYHIST
    WHERE QH_TEND > NOW() - INTERVAL '2 HOURS'
    AND QH_PLANID IS NOT NULL
    AND QH_TSTART IS NOT NULL 
    AND QH_TEND IS NOT NULL
    ORDER BY EXECUTION_SECONDS DESC, QH_ESTCOST DESC
    LIMIT 20;" "Recent Queries with Plan IDs"
    
    echo ""
    echo "Search Options:"
    echo "1. Select by query number (from list above)"
    echo "2. Search by Session ID"
    echo "3. Search by Username"
    echo ""
    
    read -p "Choose search method (1-3): " search_method
    
    case $search_method in
        1)
            read -p "Enter query number (1-20): " query_num
            if [[ "$query_num" =~ ^[0-9]+$ ]] && [[ "$query_num" -ge 1 ]] && [[ "$query_num" -le 20 ]]; then
                generate_plans_for_recent_query_by_number "$query_num"
            else
                print_error "Invalid query number"
            fi
            ;;
        2)
            read -p "Enter Session ID: " session_id
            if [[ "$session_id" =~ ^[0-9]+$ ]]; then
                generate_plans_for_recent_session "$session_id"
            else
                print_error "Invalid session ID"
            fi
            ;;
        3)
            read -p "Enter Username: " username
            if [[ -n "$username" ]]; then
                generate_plans_for_recent_user "$username"
            else
                print_error "Username cannot be empty"
            fi
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
}

# NEW: Generate Both EXPLAIN and nz_plan for Active Query
generate_plans_for_active_query_by_number() {
    local query_num="$1"
    
    # Get the query details by row number
    local query_details_file="/tmp/netezza_active_query_${query_num}_$(date +%Y%m%d_%H%M%S).txt"
    
    $NZSQL_CMD -c "
    SELECT 
        QS_SESSIONID,
        QS_USER,
        QS_PLANID,
        QS_ESTCOST,
        QS_SQL
    FROM (
        SELECT 
            ROW_NUMBER() OVER (ORDER BY EXTRACT(EPOCH FROM (NOW() - QS_TSTART)) DESC, QS_ESTCOST DESC) as NUM,
            QS_SESSIONID,
            QS_PLANID,
            QS_ESTCOST,
            QS_SQL
        FROM _V_QRYSTAT
        WHERE QS_PLANID IS NOT NULL
        ORDER BY EXTRACT(EPOCH FROM (NOW() - QS_TSTART)) DESC, QS_ESTCOST DESC
        LIMIT 20
    ) numbered_queries
    WHERE NUM = $query_num;" > "$query_details_file" 2>/dev/null
    
    if [[ -s "$query_details_file" ]]; then
        local query_info=$(tail -1 "$query_details_file")
        local session_id=$(echo "$query_info" | awk -F'|' '{print $1}' | tr -d ' ')
        local username=$(echo "$query_info" | awk -F'|' '{print $2}' | tr -d ' ')  
        local plan_id=$(echo "$query_info" | awk -F'|' '{print $3}' | tr -d ' ')
        local cost=$(echo "$query_info" | awk -F'|' '{print $4}' | tr -d ' ')
        local sql_text=$(echo "$query_info" | awk -F'|' '{print $5}')
        
        print_section "Selected Active Query Analysis"
        echo "Session ID: $session_id"
        echo "User: $username"
        echo "Plan ID: $plan_id"
        echo "Cost: $cost"
        echo ""
        echo "SQL:"
        echo "=============================================================="
        echo "$sql_text"
        echo "=============================================================="
        
        # Generate both EXPLAIN and nz_plan
        generate_dual_explain_plans "$sql_text" "$plan_id"
    else
        print_error "Could not retrieve query details for query number $query_num"
    fi
    
    rm -f "$query_details_file"
}

# Update the generate_dual_explain_plans function to use enhanced plan search
generate_dual_explain_plans() {
    local sql_text="$1"
    local plan_id="$2"
    
    echo ""
    print_section "Method 1: EXPLAIN Plan (SQL-based)"
    echo "=============================================================="
    if execute_sql "EXPLAIN VERBOSE $sql_text" "EXPLAIN Plan Generation" true; then
        print_success "EXPLAIN plan generated successfully"
    else
        print_warning "EXPLAIN VERBOSE failed, trying basic EXPLAIN..."
        execute_sql "EXPLAIN $sql_text" "Basic EXPLAIN Plan" true
    fi
    
    echo ""
    print_section "Method 2: Enhanced nz_plan with Archive Search (Plan ID: $plan_id)"
    echo "=============================================================="
    
    if [[ -n "$plan_id" && "$plan_id" != "NULL" && "$plan_id" =~ ^[0-9]+$ ]]; then
        # Use the enhanced plan search
        use_nz_plan_for_id_enhanced "$plan_id" true
    else
        print_warning "No valid Plan ID available for nz_plan utility"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# NEW: Simplified nz_plan function for specific plan ID
use_nz_plan_for_id() {
    local plan_id="$1"
    
    # Check if nz_plan utility is available (reuse existing logic)
    local nz_plan_path="/nz/support/contrib/bin/nz_plan"
    local alt_paths=(
        "/opt/nz/support/contrib/bin/nz_plan"
        "/usr/local/nz/support/contrib/bin/nz_plan"
        "/nz/bin/nz_plan"
        "/nz/kit/bin/nz_plan"
    )
    
    local found_nz_plan=""
    
    if [[ -f "$nz_plan_path" && -x "$nz_plan_path" ]]; then
        found_nz_plan="$nz_plan_path"
    else
        for path in "${alt_paths[@]}"; do
            if [[ -f "$path" && -x "$path" ]]; then
                found_nz_plan="$path"
                break
            fi
        done
    fi
    
    if [[ -n "$found_nz_plan" ]]; then
        local plan_file="/tmp/netezza_plan_${plan_id}_$(date +%Y%m%d_%H%M%S).pln"
        
        echo "Using nz_plan utility: $found_nz_plan"
        echo "Plan ID: $plan_id"
        
        if "$found_nz_plan" "$plan_id" > "$plan_file" 2>&1; then
            print_success "nz_plan executed successfully!"
            echo ""
            cat "$plan_file"
            echo ""
            echo "Plan saved to: $plan_file"
        else
            print_error "nz_plan execution failed"
            echo "Error output:"
            cat "$plan_file"
            rm -f "$plan_file"
        fi
    else
        print_warning "nz_plan utility not found in standard locations"
    fi
}

# Add this function after the use_nz_plan_for_id function

#=============================================================================
# Dynamic Plan Archive Discovery and nz_plan Enhancement
#=============================================================================

discover_plan_archives() {
    local base_path="/nzscratch/monitor/log/planarchive"
    local available_dirs=()
    
    print_section "Discovering Plan Archive Directories"
    
    if [[ ! -d "$base_path" ]]; then
        print_warning "Plan archive base directory not found: $base_path"
        return 1
    fi
    
    # Find all numeric directories and sort them in descending order
    while IFS= read -r -d '' dir; do
        local dir_name=$(basename "$dir")
        if [[ "$dir_name" =~ ^[0-9]+$ ]]; then
            available_dirs+=("$dir_name")
        fi
    done < <(find "$base_path" -maxdepth 1 -type d -print0)
    
    # Sort in descending order (newest first)
    IFS=$'\n' available_dirs=($(sort -nr <<<"${available_dirs[*]}"))
    unset IFS
    
    if [[ ${#available_dirs[@]} -eq 0 ]]; then
        print_warning "No numeric plan archive directories found in $base_path"
        return 1
    fi
    
    echo "Found plan archive directories (newest first):"
    for i in "${!available_dirs[@]}"; do
        local dir="${available_dirs[$i]}"
        echo "  $((i+1)). $dir (${base_path}/${dir})"
    done
    
    export PLAN_ARCHIVE_DIRS=("${available_dirs[@]}")
    export PLAN_ARCHIVE_BASE="$base_path"
    return 0
}

# Enhanced nz_plan function with dynamic archive search
use_nz_plan_for_id_enhanced() {
    local plan_id="$1"
    local search_archives="${2:-true}"
    
    print_section "Enhanced nz_plan Analysis for Plan ID: $plan_id"
    
    # First try the standard nz_plan utility
    if use_nz_plan_for_id "$plan_id"; then
        print_success "Plan retrieved using standard nz_plan utility"
    else
        print_warning "Standard nz_plan failed, trying plan archive search..."
        
        if [[ "$search_archives" == "true" ]]; then
            search_plan_in_archives "$plan_id"
        fi
    fi
}

search_plan_in_archives() {
    local plan_id="$1"
    local found_plan=false
    
    # Discover available archives if not already done
    if [[ -z "${PLAN_ARCHIVE_DIRS[*]}" ]]; then
        if ! discover_plan_archives; then
            print_error "Failed to discover plan archives"
            return 1
        fi
    fi
    
    print_section "Searching Plan Archives for Plan ID: $plan_id"
    echo "Searching in ${#PLAN_ARCHIVE_DIRS[@]} archive directories..."
    echo ""
    
    for dir in "${PLAN_ARCHIVE_DIRS[@]}"; do
        local archive_path="${PLAN_ARCHIVE_BASE}/${dir}"
        echo "Checking archive: $dir ($archive_path)"
        
        # Look for plan files in this archive
        local plan_files=()
        if [[ -d "$archive_path" ]]; then
            # Search for files that might contain this plan ID
            while IFS= read -r -d '' file; do
                plan_files+=("$file")
            done < <(find "$archive_path" -name "*${plan_id}*" -type f -print0 2>/dev/null)
            
            # Also search for generic plan files and grep for the plan ID
            while IFS= read -r -d '' file; do
                if grep -l "Plan.*${plan_id}" "$file" 2>/dev/null; then
                    plan_files+=("$file")
                fi
            done < <(find "$archive_path" -name "*.pln" -o -name "*.plan" -o -name "plan_*" -type f -print0 2>/dev/null)
            
            if [[ ${#plan_files[@]} -gt 0 ]]; then
                print_success "Found ${#plan_files[@]} potential plan file(s) in archive $dir"
                
                for plan_file in "${plan_files[@]}"; do
                    echo ""
                    echo "Plan file: $plan_file"
                    echo "=============================================================="
                    
                    # Check if file contains our plan ID
                    if grep -q "$plan_id" "$plan_file" 2>/dev/null; then
                        print_success "Plan ID $plan_id found in: $plan_file"
                        echo ""
                        echo "Plan Contents:"
                        echo "=============================================================="
                        cat "$plan_file"
                        echo "=============================================================="
                        found_plan=true
                        
                        # Save a copy to tmp for reference
                        local saved_plan="/tmp/netezza_archived_plan_${plan_id}_$(date +%Y%m%d_%H%M%S).pln"
                        cp "$plan_file" "$saved_plan" 2>/dev/null
                        echo ""
                        echo "Plan saved to: $saved_plan"
                        break 2  # Exit both loops
                    else
                        echo "File does not contain Plan ID $plan_id"
                    fi
                done
            else
                echo "  No plan files found in archive $dir"
            fi
        else
            echo "  Archive directory not accessible: $archive_path"
        fi
        echo ""
    done
    
    if [[ "$found_plan" == false ]]; then
        print_warning "Plan ID $plan_id not found in any of the ${#PLAN_ARCHIVE_DIRS[@]} plan archives"
        echo ""
        echo "Searched archives:"
        for dir in "${PLAN_ARCHIVE_DIRS[@]}"; do
            echo "  - $dir"
        done
        
        # Offer manual search option
        echo ""
        read -p "Would you like to perform a more comprehensive search? (y/n): " comprehensive_search
        
        if [[ "$comprehensive_search" =~ ^[Yy] ]]; then
            comprehensive_plan_search "$plan_id"
        fi
    fi
}

comprehensive_plan_search() {
    local plan_id="$1"
    
    print_section "Comprehensive Plan Search for Plan ID: $plan_id"
    echo "This may take a few minutes..."
    echo ""
    
    local search_results="/tmp/netezza_plan_search_${plan_id}_$(date +%Y%m%d_%H%M%S).txt"
    
    # Search all files in plan archive base
    echo "Searching all files in plan archives..."
    find "$PLAN_ARCHIVE_BASE" -type f -exec grep -l "$plan_id" {} \; 2>/dev/null > "$search_results"
    
    if [[ -s "$search_results" ]]; then
        local file_count=$(wc -l < "$search_results")
        print_success "Found Plan ID $plan_id in $file_count file(s)"
        echo ""
        
        echo "Files containing Plan ID $plan_id:"
        cat "$search_results"
        echo ""
        
        read -p "Would you like to view the first matching file? (y/n): " view_first
        
        if [[ "$view_first" =~ ^[Yy] ]]; then
            local first_file=$(head -1 "$search_results")
            echo ""
            echo "Contents of: $first_file"
            echo "=============================================================="
            cat "$first_file"
            echo "=============================================================="
            
            # Save a copy
            local saved_plan="/tmp/netezza_comprehensive_plan_${plan_id}_$(date +%Y%m%d_%H%M%S).pln"
            cp "$first_file" "$saved_plan" 2>/dev/null
            echo ""
            echo "Plan saved to: $saved_plan"
        fi
    else
        print_warning "Plan ID $plan_id not found in comprehensive search"
    fi
    
    rm -f "$search_results"
}

# NEW: Generate plans for active session by Session ID
generate_plans_for_active_session() {
    local session_id="$1"
    
    print_section "Active Queries for Session ID: $session_id"
    
    # Get active queries for this session
    local session_queries_file="/tmp/netezza_session_${session_id}_$(date +%Y%m%d_%H%M%S).txt"
    
    $NZSQL_CMD -c "
    SELECT 
        QS_SESSIONID,
--        QS_USER,
        QS_PLANID,
        QS_ESTCOST,
        QS_ESTMEM,
        QS_TSTART,
        ROUND(EXTRACT(EPOCH FROM (NOW() - QS_TSTART))/60, 1) AS MINUTES_RUNNING,
        QS_SQL
    FROM _V_QRYSTAT
    WHERE QS_SESSIONID = $session_id
    AND QS_PLANID IS NOT NULL
    ORDER BY QS_ESTCOST DESC;" > "$session_queries_file" 2>/dev/null
    
    if [[ -s "$session_queries_file" ]]; then
        echo "Active queries found for Session $session_id:"
        echo "=============================================================="
        $NZSQL_CMD -c "
        SELECT 
            QS_SESSIONID,
            QS_USER,
            QS_PLANID,
            QS_ESTCOST,
            ROUND(EXTRACT(EPOCH FROM (NOW() - QS_TSTART))/60, 1) AS MINUTES_RUNNING,
            SUBSTRING(QS_SQL, 1, 100) AS SQL_PREVIEW
        FROM _V_QRYSTAT
        WHERE QS_SESSIONID = $session_id
        AND QS_PLANID IS NOT NULL
        ORDER BY QS_ESTCOST DESC;" 2>/dev/null
        echo "=============================================================="
        
        # Get the highest cost query for this session
        local query_info=$(tail -1 "$session_queries_file")
        local plan_id=$(echo "$query_info" | awk -F'|' '{print $3}' | tr -d ' ')
        local sql_text=$(echo "$query_info" | awk -F'|' '{print $8}')
        
        if [[ -n "$plan_id" && "$plan_id" != "NULL" ]]; then
            echo ""
            echo "Generating plans for highest cost query (Plan ID: $plan_id)..."
            generate_dual_explain_plans "$sql_text" "$plan_id"
        else
            print_warning "No valid Plan ID found for session $session_id"
        fi
    else
        print_warning "No active queries found for Session ID: $session_id"
    fi
    
    rm -f "$session_queries_file"
}

# NEW: Generate plans for active user queries
generate_plans_for_active_user() {
    local username="$1"
    
    print_section "Active Queries for User: $username"
    
    # Get active queries for this user
    $NZSQL_CMD -c "
    SELECT 
        QS_SESSIONID,
        QS_USER,
        QS_PLANID,
        QS_ESTCOST,
        QS_ESTMEM,
        QS_TSTART,
        ROUND(EXTRACT(EPOCH FROM (NOW() - QS_TSTART))/60, 1) AS MINUTES_RUNNING,
        SUBSTRING(QS_SQL, 1, 100) AS SQL_PREVIEW
    FROM _V_QRYSTAT
    WHERE UPPER(QS_USER) = UPPER('$username')
    AND QS_PLANID IS NOT NULL
    ORDER BY QS_ESTCOST DESC
    LIMIT 10;" 2>/dev/null
    
    echo ""
    read -p "Enter Session ID from the list above to analyze: " session_id
    
    if [[ "$session_id" =~ ^[0-9]+$ ]]; then
        generate_plans_for_active_session "$session_id"
    else
        print_error "Invalid session ID"
    fi
}

# NEW: Generate plans for recent query by number
generate_plans_for_recent_query_by_number() {
    local query_num="$1"
    
    # Get the query details by row number from _V_QRYHIST
    local query_details_file="/tmp/netezza_recent_query_${query_num}_$(date +%Y%m%d_%H%M%S).txt"
    
    $NZSQL_CMD -c "
    SELECT 
        QH_SESSIONID,
        QH_USER,
        QH_PLANID,
        QH_ESTCOST,
        QH_SQL
    FROM (
        SELECT 
            ROW_NUMBER() OVER (ORDER BY EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)) DESC, QH_ESTCOST DESC) as NUM,
            QH_SESSIONID,
            QH_USER,
            QH_PLANID,
            QH_ESTCOST,
            QH_SQL
        FROM _V_QRYHIST
        WHERE QH_TEND > NOW() - INTERVAL '2 HOURS'
        AND QH_PLANID IS NOT NULL
        AND QH_TSTART IS NOT NULL 
        AND QH_TEND IS NOT NULL
        ORDER BY EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)) DESC, QH_ESTCOST DESC
        LIMIT 20
    ) numbered_queries
    WHERE NUM = $query_num;" > "$query_details_file" 2>/dev/null
    
    if [[ -s "$query_details_file" ]]; then
        local query_info=$(tail -1 "$query_details_file")
        local session_id=$(echo "$query_info" | awk -F'|' '{print $1}' | tr -d ' ')
        local username=$(echo "$query_info" | awk -F'|' '{print $2}' | tr -d ' ')  
        local plan_id=$(echo "$query_info" | awk -F'|' '{print $3}' | tr -d ' ')
        local cost=$(echo "$query_info" | awk -F'|' '{print $4}' | tr -d ' ')
        local sql_text=$(echo "$query_info" | awk -F'|' '{print $5}')
        
        print_section "Selected Recent Query Analysis"
        echo "Session ID: $session_id"
        echo "User: $username"
        echo "Plan ID: $plan_id"
        echo "Cost: $cost"
        echo ""
        echo "SQL:"
        echo "=============================================================="
        echo "$sql_text"
        echo "=============================================================="
        
        # Generate both EXPLAIN and nz_plan
        generate_dual_explain_plans "$sql_text" "$plan_id"
    else
        print_error "Could not retrieve query details for query number $query_num"
    fi
    
    rm -f "$query_details_file"
}

# NEW: Generate plans for recent session
generate_plans_for_recent_session() {
    local session_id="$1"
    
    print_section "Recent Queries for Session ID: $session_id"
    
    # Show recent queries for this session
    execute_sql "
    SELECT 
        QH_SESSIONID,
        QH_USER,
        QH_DATABASE,
        QH_TSTART,
        QH_TEND,
        QH_PLANID,
        QH_ESTCOST,
        ROUND(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)), 2) AS EXECUTION_SECONDS,
        SUBSTR(QH_SQL, 1, 100) AS SQL_PREVIEW
    FROM _V_QRYHIST
    WHERE QH_SESSIONID = $session_id
    --AND QH_TEND > NOW() - INTERVAL '2 HOURS'
    AND QH_PLANID IS NOT NULL
    ORDER BY QH_ESTCOST DESC
    LIMIT 10;" "Recent Queries for Session $session_id"
    
    echo ""
    read -p "Enter Plan ID from the list above to analyze: " plan_id
    
    if [[ "$plan_id" =~ ^[0-9]+$ ]]; then
        # Get the SQL for this plan ID
        local sql_text=$($NZSQL_CMD -t -c "SELECT QH_SQL FROM _V_QRYHIST WHERE QH_PLANID = $plan_id AND QH_SESSIONID = $session_id ORDER BY QH_TSTART DESC LIMIT 1;" 2>/dev/null | head -1)
        
        if [[ -n "$sql_text" ]]; then
            generate_dual_explain_plans "$sql_text" "$plan_id"
        else
            print_error "Could not retrieve SQL for Plan ID: $plan_id"
        fi
    else
        print_error "Invalid Plan ID"
    fi
}

# NEW: Generate plans for recent user queries
generate_plans_for_recent_user() {
    local username="$1"
    
    print_section "Recent Queries for User: $username"
    
    # Show recent queries for this user
    execute_sql "
    SELECT 
        QH_SESSIONID,
        QH_USER,
        QH_DATABASE,
        QH_TSTART,
        QH_TEND,
        QH_PLANID,
        QH_ESTCOST,
        ROUND(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)), 2) AS EXECUTION_SECONDS,
        SUBSTR(QH_SQL, 1, 100) AS SQL_PREVIEW
    FROM _V_QRYHIST
    WHERE UPPER(QH_USER) = UPPER('$username')
    AND QH_TEND > NOW() - INTERVAL '2 HOURS'
    AND QH_PLANID IS NOT NULL
    ORDER BY QH_ESTCOST DESC
    LIMIT 10;" "Recent Queries for User $username"
    
    echo ""
    read -p "Enter Session ID from the list above to analyze: " session_id
    
    if [[ "$session_id" =~ ^[0-9]+$ ]]; then
        generate_plans_for_recent_session "$session_id"
    else
        print_error "Invalid session ID"
    fi
}

# Enhanced nz_plan utility function (from V1)
use_nz_plan_utility() {
    print_section "Enhanced nz_plan Utility with Archive Search"
    
    echo "This method uses multiple approaches to find execution plans:"
    echo "1. Standard nz_plan utility"
    echo "2. Plan archive search (automatic discovery)"
    echo "3. Comprehensive file search if needed"
    echo ""
    
    # First discover available plan archives
    discover_plan_archives
    
    echo ""
    echo "Recent queries with Plan IDs:"
    execute_sql "
    SELECT 
        QH_SESSIONID,
        QH_USER,
        QH_DATABASE,
        QH_TSTART,
        QH_TEND,
        ROUND(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)), 2) AS ELAPSED_SECONDS,
        QH_PLANID,
        SUBSTR(QH_SQL, 1, 100) AS SQL_PREVIEW
    FROM _V_QRYHIST
    WHERE QH_TEND > NOW() - INTERVAL '24 HOURS'
    AND QH_PLANID IS NOT NULL
    ORDER BY QH_TEND DESC
    LIMIT 20;" "Recent Queries with Plan IDs"
    
    echo ""
    read -p "Enter Plan ID: " plan_id
    
    if [[ ! "$plan_id" =~ ^[0-9]+$ ]]; then
        print_error "Invalid plan ID"
        return
    fi
    
    # Use the enhanced plan search
    use_nz_plan_for_id_enhanced "$plan_id" true
    
    echo ""
    read -p "Press Enter to continue..."
}

# Enhanced custom SQL analysis
analyze_custom_sql() {
    echo ""
    echo "Enter your SQL statement (end with semicolon and press Enter twice):"
    echo ""
    
    sql_statement=""
    while IFS= read -r line; do
        if [[ -z "$line" && "$sql_statement" == *";" ]]; then
            break
        fi
        sql_statement="$sql_statement$line "
    done
    
    if [[ -z "$sql_statement" ]]; then
        print_error "No SQL statement provided"
        return
    fi
    
    echo ""
    read -p "Enter database name for EXPLAIN (or press Enter to use current: $NETEZZA_DB): " explain_db
    if [[ -z "$explain_db" ]]; then
        explain_db="$NETEZZA_DB"
    fi
    
    print_section "Custom SQL Analysis"
    echo "SQL Statement: $sql_statement"
    echo "Target Database: $explain_db"
    
    # Generate EXPLAIN plan
    echo ""
    echo "Generating EXPLAIN plan..."
    local explain_cmd="$NZSQL_PATH"
    if [[ -n "$NETEZZA_HOST" ]]; then
        explain_cmd="$explain_cmd -host ${NETEZZA_HOST}"
    fi
    explain_cmd="$explain_cmd -d ${explain_db} -u ${NETEZZA_USER}"
    
    if $explain_cmd -c "EXPLAIN VERBOSE $sql_statement" 2>/dev/null; then
        print_success "EXPLAIN plan generated successfully"
    else
        print_warning "EXPLAIN VERBOSE failed, trying basic EXPLAIN..."
        $explain_cmd -c "EXPLAIN $sql_statement" 2>/dev/null
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}


#=============================================================================
# Core Function 5: System State (Basic but Essential)
#=============================================================================

check_system_state() {
    print_header "NETEZZA SYSTEM STATE"
    
    # Basic system information
    execute_sql "SELECT VERSION();" "Database Version" true
    execute_sql "SELECT CURRENT_USER, CURRENT_DATABASE, CURRENT_TIMESTAMP;" "Current Connection" true
    
    # Database information
    execute_sql "
    SELECT 
        DATABASE,
        OWNER,
        CREATEDATE,
        OBJID
    FROM _V_DATABASE 
    ORDER BY DATABASE;" "Database Information"
    
    # Hardware status
    execute_sql "
    SELECT 
        HW_HWID,
        HW_ROLE,
        HW_ROLETEXT,
        HW_DISKSZ,
        HW_STATE,
        HW_STATETEXT
    FROM _V_DISK 
    ORDER BY HW_HWID;" "Hardware Status"
}

#=============================================================================
# Main Menu (Simplified & Clean)
#=============================================================================

show_main_menu() {
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    NETEZZA PERFORMANCE TOOL - ENHANCED VERSION              ║${NC}"
    echo -e "${GREEN}║                              Version 3.0                                    ║${NC}"
    echo -e "${GREEN}║                      With HISTDB Integration                                ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Core Functions:${NC}"
    echo "1. Active Sessions & Transactions (nzsession -activetxn)"
    echo "2. Real-time Query Performance (_V_QRYSTAT + _V_QRYHIST)" 
    echo "3. Cost-Based Analysis (Resource usage focus)"
    echo "4. Interactive Explain Plan (nz_plan utility)"
    echo "5. System State Overview"
    echo -e "${YELLOW}6. Historical Query Analysis (HISTDB) ⭐ NEW${NC}"
    echo "7. Configuration Settings"
    echo "8. Exit"
    echo ""
    echo -e "${YELLOW}Current Settings:${NC}"
    echo "  - Host: ${NETEZZA_HOST:-'(local connection)'}"
    echo "  - Database: $NETEZZA_DB"
    echo "  - User: $NETEZZA_USER"
    echo ""
}

configure_settings() {
    print_header "CONFIGURATION SETTINGS"
    
    echo "Current configuration:"
    echo "1. Netezza Host: ${NETEZZA_HOST:-'(local connection)'}"
    echo "2. Database: $NETEZZA_DB"
    echo "3. User: $NETEZZA_USER"
    echo "4. Long Running Query Threshold: $LONG_RUNNING_QUERY_HOURS hours"
    echo ""
    
    read -p "Which setting would you like to change (1-4, or Enter to return)? " setting_choice
    
    case $setting_choice in
        1)
            read -p "Enter new Netezza host (leave blank for local connection): " new_host
            NETEZZA_HOST="$new_host"
            NZSQL_CMD=$(build_nzsql_cmd)
            ;;
        2)
            read -p "Enter new database: " new_db
            NETEZZA_DB="$new_db"
            NZSQL_CMD=$(build_nzsql_cmd)
            ;;
        3)
            read -p "Enter new username: " new_user
            NETEZZA_USER="$new_user"
            NZSQL_CMD=$(build_nzsql_cmd)
            ;;
        4)
            read -p "Enter new long running query threshold (hours): " new_threshold
            if [[ "$new_threshold" =~ ^[0-9]+$ ]]; then
                LONG_RUNNING_QUERY_HOURS="$new_threshold"
            fi
            ;;
        "")
            return
            ;;
    esac
    
    print_success "Configuration updated successfully"
}

# Add after check_system_state function and before show_main_menu

#=============================================================================
# Core Function 6: Historical Query Analysis (HISTDB.NZ_QUERY_HISTORY)
#=============================================================================

check_historical_queries() {
    print_header "HISTORICAL QUERY ANALYSIS (HISTDB.NZ_QUERY_HISTORY)"
    
    print_section "Comprehensive Historical Query Analysis"
    echo "This section uses HISTDB.NZ_QUERY_HISTORY table which contains:"
    echo "- Complete query history (not limited to 10,000 records)"
    echo "- Detailed execution metrics (CPU, memory, disk I/O)"
    echo "- Extended date ranges for historical analysis"
    echo ""
    
    echo -e "${CYAN}Search Options:${NC}"
    echo "1. Search by Session ID"
    echo "2. Search by Username"
    echo "3. Search by Date Range only"
    echo "4. Search by Username + Date Range"
    echo "5. Search by Session ID + Date Range"
    echo "6. Top expensive queries (by execution time/cost)"
    echo "7. Return to main menu"
    echo ""
    
    read -p "Choose search method (1-7): " search_method
    
    case $search_method in
        1)
            search_by_session_id_hist
            ;;
        2)
            search_by_username_hist
            ;;
        3)
            search_by_date_range_hist
            ;;
        4)
            search_by_username_and_date_hist
            ;;
        5)
            search_by_session_and_date_hist
            ;;
        6)
            search_top_expensive_queries_hist
            ;;
        7)
            return
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
}

# Build HISTDB connection command
build_histdb_cmd() {
    local cmd="$NZSQL_PATH"
    if [[ -n "$NETEZZA_HOST" ]]; then
        cmd="$cmd -host ${NETEZZA_HOST}"
    fi
    cmd="$cmd -d HISTDB -u ${NETEZZA_USER}"
    echo "$cmd"
}

# Execute SQL against HISTDB
execute_histdb_sql() {
    local sql="$1"
    local description="$2"
    local show_errors="${3:-false}"
    local histdb_cmd=$(build_histdb_cmd)
    
    echo "-- HISTDB: $description" >> "$LOG_FILE"
    echo "$sql" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    if [ "$show_errors" = "true" ]; then
        echo "Executing against HISTDB: $description"
        $histdb_cmd -c "$sql"
        local exit_code=$?
    else
        $histdb_cmd -c "$sql" 2>/dev/null
        local exit_code=$?
    fi
    
    if [ $exit_code -ne 0 ]; then
        print_error "Failed to execute against HISTDB: $description"
        if [ "$show_errors" = "false" ]; then
            echo "Run with debug mode to see detailed error messages"
        fi
        return 1
    fi
    return 0
}

# Search by Session ID
search_by_session_id_hist() {
    read -p "Enter Session ID: " session_id
    
    if [[ ! "$session_id" =~ ^[0-9]+$ ]]; then
        print_error "Invalid session ID"
        return
    fi
    
    execute_histdb_sql "
    SELECT 
        QH_SESSIONID,
        QH_PLANID,
        QH_USER,
        QH_DATABASE,
        QH_TSTART,
        QH_TEND,
        ROUND(EXECUTION_SECS, 2) AS EXEC_SECONDS,
        QH_ESTCOST,
        QH_ESTMEM,
        QH_RESROWS,
        ROUND(SPU_CPU_SECS, 2) AS SPU_CPU_SEC,
        ROUND(HOST_CPU_SECS, 2) AS HOST_CPU_SEC,
        SPU_MEM_PEAK,
        HOST_MEM_PEAK,
        SUBSTR(QH_SQL, 1, 100) AS SQL_PREVIEW
    FROM NZ_QUERY_HISTORY
    WHERE QH_SESSIONID = $session_id
    ORDER BY QH_TSTART DESC
    LIMIT ${TOP_QUERIES_LIMIT};" "Historical Queries for Session $session_id"
}

# Search by Username
search_by_username_hist() {
    read -p "Enter Username: " username
    
    if [[ -z "$username" ]]; then
        print_error "Username cannot be empty"
        return
    fi
    
    execute_histdb_sql "
    SELECT 
        QH_SESSIONID,
        QH_PLANID,
        QH_USER,
        QH_DATABASE,
        QH_TSTART,
        QH_TEND,
        ROUND(EXECUTION_SECS, 2) AS EXEC_SECONDS,
        QH_ESTCOST,
        QH_ESTMEM,
        QH_RESROWS,
        ROUND(SPU_CPU_SECS, 2) AS SPU_CPU_SEC,
        SPU_MEM_PEAK,
        SUBSTR(QH_SQL, 1, 100) AS SQL_PREVIEW
    FROM NZ_QUERY_HISTORY
    WHERE UPPER(QH_USER) = UPPER('$username')
    ORDER BY EXECUTION_SECS DESC
    LIMIT ${TOP_QUERIES_LIMIT};" "Historical Queries for User $username"
}

# Get date range input
get_date_range() {
    echo "Enter date range for analysis:"
    echo "Format: YYYY-MM-DD (e.g., 2025-10-14)"
    echo ""
    
    read -p "Start date (YYYY-MM-DD): " start_date
    read -p "End date (YYYY-MM-DD): " end_date
    
    # Basic date format validation
    if [[ ! "$start_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || [[ ! "$end_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        print_error "Invalid date format. Please use YYYY-MM-DD"
        return 1
    fi
    
    # Export for use in other functions
    export HIST_START_DATE="$start_date"
    export HIST_END_DATE="$end_date"
    return 0
}

# Search by Date Range only
search_by_date_range_hist() {
    if ! get_date_range; then
        return
    fi
    
    execute_histdb_sql "
    SELECT 
        QH_SESSIONID,
        QH_PLANID,
        QH_USER,
        QH_DATABASE,
        QH_TSTART,
        QH_TEND,
        ROUND(EXECUTION_SECS, 2) AS EXEC_SECONDS,
        QH_ESTCOST,
        QH_ESTMEM,
        QH_RESROWS,
        ROUND(SPU_CPU_SECS, 2) AS SPU_CPU_SEC,
        SPU_MEM_PEAK,
        SUBSTR(QH_SQL, 1, 100) AS SQL_PREVIEW
    FROM NZ_QUERY_HISTORY
    WHERE QH_TSTART >= '$HIST_START_DATE'
    AND QH_TSTART < '$HIST_END_DATE'::DATE + 1
    ORDER BY EXECUTION_SECS DESC
    LIMIT ${TOP_QUERIES_LIMIT};" "Historical Queries from $HIST_START_DATE to $HIST_END_DATE"
}

# Search by Username + Date Range
search_by_username_and_date_hist() {
    read -p "Enter Username: " username
    
    if [[ -z "$username" ]]; then
        print_error "Username cannot be empty"
        return
    fi
    
    if ! get_date_range; then
        return
    fi
    
    execute_histdb_sql "
    SELECT 
        QH_SESSIONID,
        QH_PLANID,
        QH_USER,
        QH_DATABASE,
        QH_TSTART,
        QH_TEND,
        ROUND(EXECUTION_SECS, 2) AS EXEC_SECONDS,
        QH_ESTCOST,
        QH_ESTMEM,
        QH_RESROWS,
        ROUND(SPU_CPU_SECS, 2) AS SPU_CPU_SEC,
        SPU_MEM_PEAK,
        SUBSTR(QH_SQL, 1, 100) AS SQL_PREVIEW
    FROM NZ_QUERY_HISTORY
    WHERE UPPER(QH_USER) = UPPER('$username')
    AND QH_TSTART >= '$HIST_START_DATE'
    AND QH_TSTART < '$HIST_END_DATE'::DATE + 1
    ORDER BY EXECUTION_SECS DESC
    LIMIT ${TOP_QUERIES_LIMIT};" "Historical Queries for User $username from $HIST_START_DATE to $HIST_END_DATE"
}

# Search by Session ID + Date Range
search_by_session_and_date_hist() {
    read -p "Enter Session ID: " session_id
    
    if [[ ! "$session_id" =~ ^[0-9]+$ ]]; then
        print_error "Invalid session ID"
        return
    fi
    
    if ! get_date_range; then
        return
    fi
    
    execute_histdb_sql "
    SELECT 
        QH_SESSIONID,
        QH_PLANID,
        QH_USER,
        QH_DATABASE,
        QH_TSTART,
        QH_TEND,
        ROUND(EXECUTION_SECS, 2) AS EXEC_SECONDS,
        QH_ESTCOST,
        QH_ESTMEM,
        QH_RESROWS,
        ROUND(SPU_CPU_SECS, 2) AS SPU_CPU_SEC,
        ROUND(HOST_CPU_SECS, 2) AS HOST_CPU_SEC,
        SPU_MEM_PEAK,
        HOST_MEM_PEAK,
        SUBSTR(QH_SQL, 1, 100) AS SQL_PREVIEW
    FROM NZ_QUERY_HISTORY
    WHERE QH_SESSIONID = $session_id
    AND QH_TSTART >= '$HIST_START_DATE'
    AND QH_TSTART < '$HIST_END_DATE'::DATE + 1
    ORDER BY QH_TSTART DESC
    LIMIT ${TOP_QUERIES_LIMIT};" "Historical Queries for Session $session_id from $HIST_START_DATE to $HIST_END_DATE"
}

# Top expensive queries
search_top_expensive_queries_hist() {
    echo "Top expensive queries analysis:"
    echo "1. By execution time"
    echo "2. By estimated cost"
    echo "3. By CPU usage"
    echo "4. By memory usage"
    echo ""
    
    read -p "Choose analysis type (1-4): " analysis_type
    
    local order_clause=""
    local analysis_desc=""
    
    case $analysis_type in
        1)
            order_clause="ORDER BY EXECUTION_SECS DESC"
            analysis_desc="Top Queries by Execution Time"
            ;;
        2)
            order_clause="ORDER BY QH_ESTCOST DESC"
            analysis_desc="Top Queries by Estimated Cost"
            ;;
        3)
            order_clause="ORDER BY SPU_CPU_SECS DESC"
            analysis_desc="Top Queries by CPU Usage"
            ;;
        4)
            order_clause="ORDER BY SPU_MEM_PEAK DESC"
            analysis_desc="Top Queries by Memory Usage"
            ;;
        *)
            print_error "Invalid analysis type"
            return
            ;;
    esac
    
    echo ""
    read -p "Include date range filter? (y/n): " use_date_filter
    
    local where_clause=""
    if [[ "$use_date_filter" =~ ^[Yy] ]]; then
        if get_date_range; then
            where_clause="WHERE QH_TSTART >= '$HIST_START_DATE' AND QH_TSTART < '$HIST_END_DATE'::DATE + 1"
            analysis_desc="$analysis_desc (${HIST_START_DATE} to ${HIST_END_DATE})"
        fi
    fi
    
    execute_histdb_sql "
    SELECT 
        QH_SESSIONID,
        QH_PLANID,
        QH_USER,
        QH_DATABASE,
        QH_TSTART,
        QH_TEND,
        ROUND(EXECUTION_SECS, 2) AS EXEC_SECONDS,
        QH_ESTCOST,
        QH_ESTMEM,
        QH_RESROWS,
        ROUND(SPU_CPU_SECS, 2) AS SPU_CPU_SEC,
        ROUND(HOST_CPU_SECS, 2) AS HOST_CPU_SEC,
        SPU_MEM_PEAK,
        HOST_MEM_PEAK,
        ROUND(SPOOLED_MB, 2) AS SPOOLED_MB,
        SUBSTR(QH_SQL, 1, 100) AS SQL_PREVIEW
    FROM NZ_QUERY_HISTORY
    $where_clause
    $order_clause
    LIMIT ${TOP_QUERIES_LIMIT};" "$analysis_desc"
}

#=============================================================================
# Main Program
#=============================================================================

main() {
    # Test connection on startup
    if ! test_connection; then
        echo ""
        read -p "Would you like to configure connection settings? (y/n): " config_choice
        if [[ "$config_choice" =~ ^[Yy] ]]; then
            configure_settings
        else
            exit 1
        fi
    fi
    
    # Main program loop
    while true; do
        show_main_menu
        read -p "Choose an option (1-7): " choice
        
        case $choice in
            1)
                check_active_sessions
                read -p "Press Enter to continue..."
                ;;
            2)
                check_query_performance
                read -p "Press Enter to continue..."
                ;;
            3)
                check_cost_based_performance
                read -p "Press Enter to continue..."
                ;;
            4)
                interactive_explain_plan
                read -p "Press Enter to continue..."
                ;;
            5)
                check_system_state
                read -p "Press Enter to continue..."
                ;;
            6)
                check_historical_queries
                read -p "Press Enter to continue..."
                ;;
            7)
                configure_settings
                read -p "Press Enter to continue..."
                ;;
            8)
                print_success "Thank you for using Netezza Performance Tool!"
                exit 0
                ;;
            *)
                print_error "Invalid option. Please choose 1-8."
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi