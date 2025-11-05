
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

# Add this new function after the check_query_performance function:

enhanced_realtime_analysis() {
    print_section "Enhanced Real-time Query Analysis"
    
    echo "This section provides detailed real-time analysis using:"
    echo "- _V_QRYSTAT (current running queries)"
    echo "- _V_SESSION_DETAIL (session information)"
    echo "- Advanced filtering and pattern matching"
    echo ""
    
    echo -e "${CYAN}Search Options:${NC}"
    echo "1. All active queries (no filter)"
    echo "2. Filter by Client OS Username"
    echo "3. Filter by Database Name"
    echo "4. Filter by Session Username (pattern matching)"
    echo "5. Filter by Client OS Username + Database"
    echo "6. Filter by Session Username + Database"
    echo "7. Custom multi-filter search"
    echo "8. Return to previous menu"
    echo ""
    
    read -p "Choose search method (1-8): " search_method
    
    case $search_method in
        1)
            realtime_all_queries
            ;;
        2)
            realtime_by_client_os_user
            ;;
        3)
            realtime_by_database
            ;;
        4)
            realtime_by_session_user
            ;;
        5)
            realtime_by_client_os_user_and_db
            ;;
        6)
            realtime_by_session_user_and_db
            ;;
        7)
            realtime_custom_filter
            ;;
        8)
            return
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
}

# All active queries (no filter)
realtime_all_queries() {
    execute_sql "
    SELECT 
        b.CLIENT_OS_USERNAME, 
        b.SESSION_USERNAME, 
        a.qs_sessionid, 
        priority_name, 
        dbname, 
        schema, 
        substring(a.qs_sql, 1, 100) AS sql_preview, 
        qs_tsubmit, 
        qs_tstart, 
        a.qs_estcost, 
        a.qs_estmem, 
        a.qs_estdisk, 
        a.qs_resrows, 
        a.qs_resbytes,
        ROUND(EXTRACT(EPOCH FROM (NOW() - qs_tstart))/60, 1) AS minutes_running
    FROM _v_qrystat a
    LEFT JOIN _v_session_detail b ON b.session_id = a.qs_sessionid
    WHERE DBNAME != 'null'
    ORDER BY qs_estcost DESC;" "All Active Queries (Real-time)"
}

# Filter by Client OS Username
realtime_by_client_os_user() {
    read -p "Enter Client OS Username (pattern matching enabled): " client_username
    
    if [[ -z "$client_username" ]]; then
        print_error "Client OS Username cannot be empty"
        return
    fi
    
    # Auto-add % for pattern matching
    local username_pattern="%${client_username}%"
    
    execute_sql "
    SELECT 
        b.CLIENT_OS_USERNAME, 
        b.SESSION_USERNAME, 
        a.qs_sessionid, 
        priority_name, 
        dbname, 
        schema, 
        substring(a.qs_sql, 1, 100) AS sql_preview, 
        qs_tsubmit, 
        qs_tstart, 
        a.qs_estcost, 
        a.qs_estmem, 
        a.qs_estdisk, 
        a.qs_resrows, 
        a.qs_resbytes,
        ROUND(EXTRACT(EPOCH FROM (NOW() - qs_tstart))/60, 1) AS minutes_running
    FROM _v_qrystat a
    LEFT JOIN _v_session_detail b ON b.session_id = a.qs_sessionid
    WHERE DBNAME != 'null'
    AND UPPER(b.CLIENT_OS_USERNAME) LIKE UPPER('${username_pattern}')
    ORDER BY qs_estcost DESC;" "Active Queries for Client OS User: ${client_username}"
}

# Filter by Database Name
realtime_by_database() {
    read -p "Enter Database Name: " database_name
    
    if [[ -z "$database_name" ]]; then
        print_error "Database Name cannot be empty"
        return
    fi
    
    execute_sql "
    SELECT 
        b.CLIENT_OS_USERNAME, 
        b.SESSION_USERNAME, 
        a.qs_sessionid, 
        priority_name, 
        dbname, 
        schema, 
        substring(a.qs_sql, 1, 100) AS sql_preview, 
        qs_tsubmit, 
        qs_tstart, 
        a.qs_estcost, 
        a.qs_estmem, 
        a.qs_estdisk, 
        a.qs_resrows, 
        a.qs_resbytes,
        ROUND(EXTRACT(EPOCH FROM (NOW() - qs_tstart))/60, 1) AS minutes_running
    FROM _v_qrystat a
    LEFT JOIN _v_session_detail b ON b.session_id = a.qs_sessionid
    WHERE UPPER(dbname) = UPPER('${database_name}')
    ORDER BY qs_estcost DESC;" "Active Queries for Database: ${database_name}"
}

# Filter by Session Username with pattern matching
realtime_by_session_user() {
    read -p "Enter Session Username (pattern matching enabled): " session_username
    
    if [[ -z "$session_username" ]]; then
        print_error "Session Username cannot be empty"
        return
    fi
    
    # Auto-add % for pattern matching
    local username_pattern="%${session_username}%"
    
    execute_sql "
    SELECT 
        b.CLIENT_OS_USERNAME, 
        b.SESSION_USERNAME, 
        a.qs_sessionid, 
        priority_name, 
        dbname, 
        schema, 
        substring(a.qs_sql, 1, 100) AS sql_preview, 
        qs_tsubmit, 
        qs_tstart, 
        a.qs_estcost, 
        a.qs_estmem, 
        a.qs_estdisk, 
        a.qs_resrows, 
        a.qs_resbytes,
        ROUND(EXTRACT(EPOCH FROM (NOW() - qs_tstart))/60, 1) AS minutes_running
    FROM _v_qrystat a
    LEFT JOIN _v_session_detail b ON b.session_id = a.qs_sessionid
    WHERE DBNAME != 'null'
    AND UPPER(b.SESSION_USERNAME) LIKE UPPER('${username_pattern}')
    ORDER BY qs_estcost DESC;" "Active Queries for Session User: ${session_username}"
}

# Filter by Client OS Username + Database
realtime_by_client_os_user_and_db() {
    read -p "Enter Client OS Username (pattern matching enabled): " client_username
    read -p "Enter Database Name: " database_name
    
    if [[ -z "$client_username" || -z "$database_name" ]]; then
        print_error "Both Client OS Username and Database Name are required"
        return
    fi
    
    # Auto-add % for pattern matching
    local username_pattern="%${client_username}%"
    
    execute_sql "
    SELECT 
        b.CLIENT_OS_USERNAME, 
        b.SESSION_USERNAME, 
        a.qs_sessionid, 
        priority_name, 
        dbname, 
        schema, 
        substring(a.qs_sql, 1, 100) AS sql_preview, 
        qs_tsubmit, 
        qs_tstart, 
        a.qs_estcost, 
        a.qs_estmem, 
        a.qs_estdisk, 
        a.qs_resrows, 
        a.qs_resbytes,
        ROUND(EXTRACT(EPOCH FROM (NOW() - qs_tstart))/60, 1) AS minutes_running
    FROM _v_qrystat a
    LEFT JOIN _v_session_detail b ON b.session_id = a.qs_sessionid
    WHERE UPPER(dbname) = UPPER('${database_name}')
    AND UPPER(b.CLIENT_OS_USERNAME) LIKE UPPER('${username_pattern}')
    ORDER BY qs_estcost DESC;" "Active Queries for Client OS User: ${client_username} and Database: ${database_name}"
}

# Filter by Session Username + Database
realtime_by_session_user_and_db() {
    read -p "Enter Session Username (pattern matching enabled): " session_username
    read -p "Enter Database Name: " database_name
    
    if [[ -z "$session_username" || -z "$database_name" ]]; then
        print_error "Both Session Username and Database Name are required"
        return
    fi
    
    # Auto-add % for pattern matching
    local username_pattern="%${session_username}%"
    
    execute_sql "
    SELECT 
        b.CLIENT_OS_USERNAME, 
        b.SESSION_USERNAME, 
        a.qs_sessionid, 
        priority_name, 
        dbname, 
        schema, 
        substring(a.qs_sql, 1, 100) AS sql_preview, 
        qs_tsubmit, 
        qs_tstart, 
        a.qs_estcost, 
        a.qs_estmem, 
        a.qs_estdisk, 
        a.qs_resrows, 
        a.qs_resbytes,
        ROUND(EXTRACT(EPOCH FROM (NOW() - qs_tstart))/60, 1) AS minutes_running
    FROM _v_qrystat a
    LEFT JOIN _v_session_detail b ON b.session_id = a.qs_sessionid
    WHERE UPPER(dbname) = UPPER('${database_name}')
    AND UPPER(b.SESSION_USERNAME) LIKE UPPER('${username_pattern}')
    ORDER BY qs_estcost DESC;" "Active Queries for Session User: ${session_username} and Database: ${database_name}"
}

# Custom multi-filter search
realtime_custom_filter() {
    echo "Custom Multi-Filter Search"
    echo "Leave any field blank to skip that filter"
    echo ""
    
    read -p "Client OS Username (pattern matching): " client_username
    read -p "Session Username (pattern matching): " session_username
    read -p "Database Name: " database_name
    read -p "Minimum Cost Threshold (leave blank for no limit): " min_cost
    
    # Build WHERE clause dynamically
    local where_conditions=()
    where_conditions+=("DBNAME != 'null'")
    
    if [[ -n "$client_username" ]]; then
        local client_pattern="%${client_username}%"
        where_conditions+=("UPPER(b.CLIENT_OS_USERNAME) LIKE UPPER('${client_pattern}')")
    fi
    
    if [[ -n "$session_username" ]]; then
        local session_pattern="%${session_username}%"
        where_conditions+=("UPPER(b.SESSION_USERNAME) LIKE UPPER('${session_pattern}')")
    fi
    
    if [[ -n "$database_name" ]]; then
        where_conditions+=("UPPER(dbname) = UPPER('${database_name}')")
    fi
    
    if [[ -n "$min_cost" && "$min_cost" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        where_conditions+=("a.qs_estcost >= ${min_cost}")
    fi
    
    # Join conditions with AND
    local where_clause=""
    if [[ ${#where_conditions[@]} -gt 0 ]]; then
        where_clause="WHERE $(IFS=' AND '; echo "${where_conditions[*]}")"
    fi
    
    local filter_desc="Custom Filter"
    if [[ -n "$client_username" ]]; then
        filter_desc="${filter_desc} - Client OS User: ${client_username}"
    fi
    if [[ -n "$session_username" ]]; then
        filter_desc="${filter_desc} - Session User: ${session_username}"
    fi
    if [[ -n "$database_name" ]]; then
        filter_desc="${filter_desc} - Database: ${database_name}"
    fi
    if [[ -n "$min_cost" ]]; then
        filter_desc="${filter_desc} - Min Cost: ${min_cost}"
    fi
    
    execute_sql "
    SELECT 
        b.CLIENT_OS_USERNAME, 
        b.SESSION_USERNAME, 
        a.qs_sessionid, 
        priority_name, 
        dbname, 
        schema, 
        substring(a.qs_sql, 1, 100) AS sql_preview, 
        qs_tsubmit, 
        qs_tstart, 
        a.qs_estcost, 
        a.qs_estmem, 
        a.qs_estdisk, 
        a.qs_resrows, 
        a.qs_resbytes,
        ROUND(EXTRACT(EPOCH FROM (NOW() - qs_tstart))/60, 1) AS minutes_running
    FROM _v_qrystat a
    LEFT JOIN _v_session_detail b ON b.session_id = a.qs_sessionid
    ${where_clause}
    ORDER BY qs_estcost DESC;" "Active Queries - ${filter_desc}"
}

# Replace the existing check_query_performance function:

check_query_performance() {
    print_header "REAL-TIME & HIST QUERY PERFORMANCE ANALYSIS"
    
    echo -e "${CYAN}Analysis Options:${NC}"
    echo "1. Standard Real-time Analysis (existing functionality)"
    echo "2. Enhanced Real-time Analysis (detailed filtering) ⭐ NEW"
    echo "3. Return to main menu"
    echo ""
    
    read -p "Choose analysis type (1-3): " analysis_choice
    
    case $analysis_choice in
        1)
            standard_realtime_analysis
            ;;
        2)
            enhanced_realtime_analysis
            ;;
        3)
            return
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
}


# Add this as Option 9 in your main menu, after check_historical_queries:

#=============================================================================
# Core Function 9: Session Management & Termination
#=============================================================================

session_management() {
    print_header "SESSION MANAGEMENT & TERMINATION"
    
    echo "This section provides safe session termination capabilities using:"
    echo "- nzsession abort command (preferred over kill)"
    echo "- Dry-run mode to preview sessions before termination"
    echo "- Confirmation and verification of session termination"
    echo ""
    
    echo -e "${CYAN}Session Management Options:${NC}"
    echo "1. Kill sessions by Username (with dry-run)"
    echo "2. Kill sessions by Username + Database"
    echo "3. Kill sessions by Client OS Username"
    echo "4. Kill specific Session ID"
    echo "5. Kill inactive/idle sessions"
    echo "6. Custom multi-criteria session termination"
    echo "7. View all active sessions (read-only)"
    echo "8. Return to main menu"
    echo ""
    
    read -p "Choose session management option (1-8): " session_choice
    
    case $session_choice in
        1)
            kill_sessions_by_username
            ;;
        2)
            kill_sessions_by_username_and_db
            ;;
        3)
            kill_sessions_by_client_os_user
            ;;
        4)
            kill_specific_session
            ;;
        5)
            kill_inactive_sessions
            ;;
        6)
            custom_session_termination
            ;;
        7)
            view_all_sessions
            ;;
        8)
            return
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
}

# Check if nzsession command is available
check_nzsession_availability() {
    local nzsession_paths=(
        "/nz/bin/nzsession"
        "/opt/nz/bin/nzsession"
        "/usr/local/nz/bin/nzsession"
        "/nz/support/bin/nzsession"
        "/nz/kit/bin/nzsession"
    )
    
    for path in "${nzsession_paths[@]}"; do
        if [[ -f "$path" && -x "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    
    # Try system PATH
    if command -v nzsession >/dev/null 2>&1; then
        echo "nzsession"
        return 0
    fi
    
    return 1
}

# Execute nzsession abort command
execute_nzsession_abort() {
    local session_id="$1"
    local nzsession_cmd="$2"
    
    echo "  Terminating session $session_id using: $nzsession_cmd abort"
    
    local abort_result
    if [[ -n "$NETEZZA_HOST" ]]; then
        abort_result=$($nzsession_cmd -host "$NETEZZA_HOST" -u "$NETEZZA_USER" abort -id "$session_id" 2>&1)
    else
        abort_result=$($nzsession_cmd -u "$NETEZZA_USER" abort -id "$session_id" 2>&1)
    fi
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        print_success "✓ Session $session_id terminated successfully"
        echo "    $abort_result"
        return 0
    else
        print_error "✗ Failed to terminate session $session_id"
        echo "    Error: $abort_result"
        return 1
    fi
}

# Verify session termination
verify_session_termination() {
    local session_ids=("$@")
    
    print_section "Verifying Session Termination"
    
    echo "Checking if sessions were successfully terminated..."
    sleep 2  # Give time for sessions to close
    
    local still_active=()
    
    for session_id in "${session_ids[@]}"; do
        local check_result=$(execute_sql "SELECT COUNT(*) FROM _V_SESSION WHERE ID = $session_id;" "Check Session $session_id" false)
        
        if [[ "$check_result" =~ "1" ]]; then
            still_active+=("$session_id")
            echo "  ✗ Session $session_id is still active"
        else
            echo "  ✓ Session $session_id successfully terminated"
        fi
    done
    
    if [[ ${#still_active[@]} -eq 0 ]]; then
        print_success "All sessions successfully terminated"
    else
        print_warning "${#still_active[@]} sessions are still active: ${still_active[*]}"
        echo ""
        read -p "Would you like to retry terminating remaining sessions? (y/n): " retry_choice
        
        if [[ "$retry_choice" =~ ^[Yy] ]]; then
            retry_session_termination "${still_active[@]}"
        fi
    fi
}

# Retry termination for persistent sessions
retry_session_termination() {
    local session_ids=("$@")
    
    local nzsession_cmd=$(check_nzsession_availability)
    if [[ $? -ne 0 ]]; then
        print_error "nzsession command not available for retry"
        return 1
    fi
    
    print_section "Retrying Session Termination"
    
    for session_id in "${session_ids[@]}"; do
        echo "Retrying termination of session $session_id..."
        execute_nzsession_abort "$session_id" "$nzsession_cmd"
    done
    
    echo ""
    verify_session_termination "${session_ids[@]}"
}

# Dry-run: Show sessions that would be affected
dry_run_session_preview() {
    local query="$1"
    local description="$2"
    
    print_section "DRY-RUN: Sessions that would be terminated"
    echo "Description: $description"
    echo ""
    
    local preview_file="/tmp/netezza_session_preview_$(date +%Y%m%d_%H%M%S).txt"
    
    # Execute query and capture session IDs
    $NZSQL_CMD -t -c "$query" > "$preview_file" 2>/dev/null
    
    if [[ -s "$preview_file" ]]; then
        local session_count=$(wc -l < "$preview_file")
        
        echo "Sessions to be terminated: $session_count"
        echo ""
        echo "Session Details:"
        echo "=============================================================="
        
        # Show detailed session information
        execute_sql "${query/SELECT s.ID/SELECT s.ID, s.USERNAME, s.DBNAME, s.STATUS, s.IPADDR, s.CONNTIME}" "$description (Preview)"
        
        echo "=============================================================="
        echo ""
        echo "Session IDs: $(cat "$preview_file" | tr '\n' ' ')"
        
        # Store session IDs for potential termination
        readarray -t SESSIONS_TO_KILL < "$preview_file"
        
        rm -f "$preview_file"
        return 0
    else
        print_success "No sessions found matching the criteria"
        rm -f "$preview_file"
        return 1
    fi
}

# Confirm and execute session termination
confirm_and_execute_termination() {
    local description="$1"
    
    if [[ ${#SESSIONS_TO_KILL[@]} -eq 0 ]]; then
        print_warning "No sessions selected for termination"
        return 1
    fi
    
    echo ""
    echo -e "${RED}WARNING: You are about to terminate ${#SESSIONS_TO_KILL[@]} session(s)${NC}"
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    
    read -p "Type 'CONFIRM' to proceed with termination: " confirmation
    
    if [[ "$confirmation" != "CONFIRM" ]]; then
        print_warning "Termination cancelled by user"
        return 1
    fi
    
    # Check nzsession availability
    local nzsession_cmd=$(check_nzsession_availability)
    if [[ $? -ne 0 ]]; then
        print_error "nzsession command not available"
        echo "Please ensure nzsession utility is installed and accessible"
        return 1
    fi
    
    print_section "Executing Session Termination"
    echo "Using nzsession command: $nzsession_cmd"
    echo "Terminating ${#SESSIONS_TO_KILL[@]} sessions..."
    echo ""
    
    local terminated_sessions=()
    local failed_sessions=()
    
    for session_id in "${SESSIONS_TO_KILL[@]}"; do
        if execute_nzsession_abort "$session_id" "$nzsession_cmd"; then
            terminated_sessions+=("$session_id")
        else
            failed_sessions+=("$session_id")
        fi
        echo ""
    done
    
    # Summary
    print_section "Termination Summary"
    echo "Successfully terminated: ${#terminated_sessions[@]} sessions"
    echo "Failed to terminate: ${#failed_sessions[@]} sessions"
    
    if [[ ${#terminated_sessions[@]} -gt 0 ]]; then
        echo "Terminated sessions: ${terminated_sessions[*]}"
    fi
    
    if [[ ${#failed_sessions[@]} -gt 0 ]]; then
        echo "Failed sessions: ${failed_sessions[*]}"
    fi
    
    # Verify termination
    echo ""
    verify_session_termination "${SESSIONS_TO_KILL[@]}"
    
    # Log the action
    echo "$(date): Terminated ${#terminated_sessions[@]} sessions: ${terminated_sessions[*]}" >> "$LOG_FILE"
}

# Kill sessions by username
kill_sessions_by_username() {
    read -p "Enter Username (pattern matching enabled): " username
    
    if [[ -z "$username" ]]; then
        print_error "Username cannot be empty"
        return
    fi
    
    # Auto-add % for pattern matching
    local username_pattern="%${username}%"
    
    # Get current session ID first to exclude it
    local current_session_id=$($NZSQL_CMD -t -c "SELECT ID FROM _V_SESSION WHERE UPPER(USERNAME) = UPPER('$NETEZZA_USER') AND IPADDR = 'localhost' ORDER BY CONNTIME DESC LIMIT 1;" 2>/dev/null | head -1 | tr -d ' ')
    
    local query="
    SELECT s.ID
    FROM _V_SESSION s
    LEFT JOIN _V_SESSION_DETAIL sd ON s.ID = sd.SESSION_ID
    WHERE UPPER(s.USERNAME) LIKE UPPER('${username_pattern}')"
    
    # Add exclusion for current session if we found it
    if [[ -n "$current_session_id" && "$current_session_id" =~ ^[0-9]+$ ]]; then
        query="$query AND s.ID != $current_session_id"
        echo "Note: Current session ($current_session_id) will be excluded from termination"
    fi
    
    query="$query ORDER BY s.CONNTIME DESC"
    
    if dry_run_session_preview "$query" "Sessions for Username: $username"; then
        echo ""
        read -p "Proceed with termination of these sessions? (y/n): " proceed_choice
        
        if [[ "$proceed_choice" =~ ^[Yy] ]]; then
            confirm_and_execute_termination "Username: $username"
        else
            print_warning "Termination cancelled"
        fi
    fi
}

# Kill sessions by username and database
kill_sessions_by_username_and_db() {
    read -p "Enter Username (pattern matching enabled): " username
    read -p "Enter Database Name: " database_name
    
    if [[ -z "$username" || -z "$database_name" ]]; then
        print_error "Both Username and Database Name are required"
        return
    fi
    
    local username_pattern="%${username}%"
    
    # Get current session ID first to exclude it
    local current_session_id=$($NZSQL_CMD -t -c "SELECT ID FROM _V_SESSION WHERE UPPER(USERNAME) = UPPER('$NETEZZA_USER') AND UPPER(DBNAME) = UPPER('$NETEZZA_DB') ORDER BY CONNTIME DESC LIMIT 1;" 2>/dev/null | head -1 | tr -d ' ')
    
    local query="
    SELECT s.ID
    FROM _V_SESSION s
    LEFT JOIN _V_SESSION_DETAIL sd ON s.ID = sd.SESSION_ID
    WHERE UPPER(s.USERNAME) LIKE UPPER('${username_pattern}')
    AND UPPER(s.DBNAME) = UPPER('${database_name}')"
    
    # Add exclusion for current session if we found it
    if [[ -n "$current_session_id" && "$current_session_id" =~ ^[0-9]+$ ]]; then
        query="$query AND s.ID != $current_session_id"
        echo "Note: Current session ($current_session_id) will be excluded from termination"
    fi
    
    query="$query ORDER BY s.CONNTIME DESC"
    
    if dry_run_session_preview "$query" "Sessions for Username: $username, Database: $database_name"; then
        echo ""
        read -p "Proceed with termination of these sessions? (y/n): " proceed_choice
        
        if [[ "$proceed_choice" =~ ^[Yy] ]]; then
            confirm_and_execute_termination "Username: $username, Database: $database_name"
        else
            print_warning "Termination cancelled"
        fi
    fi
}

# Kill sessions by Client OS Username
kill_sessions_by_client_os_user() {
    read -p "Enter Client OS Username (pattern matching enabled): " client_username
    
    if [[ -z "$client_username" ]]; then
        print_error "Client OS Username cannot be empty"
        return
    fi
    
    local username_pattern="%${client_username}%"
    
    # Get current session info to exclude it
    local current_session_info=$($NZSQL_CMD -t -c "
    SELECT s.ID 
    FROM _V_SESSION s 
    LEFT JOIN _V_SESSION_DETAIL sd ON s.ID = sd.SESSION_ID 
    WHERE UPPER(s.USERNAME) = UPPER('$NETEZZA_USER') 
    AND UPPER(s.DBNAME) = UPPER('$NETEZZA_DB') 
    ORDER BY s.CONNTIME DESC LIMIT 1;" 2>/dev/null | head -1 | tr -d ' ')
    
    local query="
    SELECT s.ID
    FROM _V_SESSION s
    LEFT JOIN _V_SESSION_DETAIL sd ON s.ID = sd.SESSION_ID
    WHERE UPPER(sd.CLIENT_OS_USERNAME) LIKE UPPER('${username_pattern}')"
    
    # Add exclusion for current session if we found it
    if [[ -n "$current_session_info" && "$current_session_info" =~ ^[0-9]+$ ]]; then
        query="$query AND s.ID != $current_session_info"
        echo "Note: Current session ($current_session_info) will be excluded from termination"
    fi
    
    query="$query ORDER BY s.CONNTIME DESC"
    
    if dry_run_session_preview "$query" "Sessions for Client OS User: $client_username"; then
        echo ""
        read -p "Proceed with termination of these sessions? (y/n): " proceed_choice
        
        if [[ "$proceed_choice" =~ ^[Yy] ]]; then
            confirm_and_execute_termination "Client OS User: $client_username"
        else
            print_warning "Termination cancelled"
        fi
    fi
}

# Kill specific session ID
kill_specific_session() {
    read -p "Enter Session ID to terminate: " session_id
    
    if [[ ! "$session_id" =~ ^[0-9]+$ ]]; then
        print_error "Invalid session ID"
        return
    fi
    
    # Check if session exists
    local session_exists=$(execute_sql "SELECT COUNT(*) FROM _V_SESSION WHERE ID = $session_id;" "Check Session Exists" false)
    
    if [[ ! "$session_exists" =~ "1" ]]; then
        print_error "Session ID $session_id not found"
        return
    fi
    
    # Show session details
    print_section "Session Details"
    execute_sql "
    SELECT 
        s.ID,
        s.USERNAME,
        s.DBNAME,
        s.STATUS,
        s.IPADDR,
        s.CONNTIME,
        sd.CLIENT_OS_USERNAME,
        sd.PROCESS_ID
    FROM _V_SESSION s
    LEFT JOIN _V_SESSION_DETAIL sd ON s.ID = sd.SESSION_ID
    WHERE s.ID = $session_id;" "Session $session_id Details"
    
    echo ""
    read -p "Confirm termination of Session ID $session_id? (y/n): " confirm_single
    
    if [[ "$confirm_single" =~ ^[Yy] ]]; then
        SESSIONS_TO_KILL=("$session_id")
        confirm_and_execute_termination "Session ID: $session_id"
    else
        print_warning "Termination cancelled"
    fi
}

# Kill inactive sessions
kill_inactive_sessions() {
    echo "Inactive session criteria:"
    echo "1. Sessions with STATUS = 'idle'"
    echo "2. Sessions idle for more than X hours"
    echo "3. Sessions with no active queries"
    echo ""
    
    read -p "Choose inactive criteria (1-3): " inactive_type
    
    local query=""
    local description=""
    
    # Get current session ID to exclude it
    local current_session_id=$($NZSQL_CMD -t -c "SELECT ID FROM _V_SESSION WHERE UPPER(USERNAME) = UPPER('$NETEZZA_USER') AND UPPER(DBNAME) = UPPER('$NETEZZA_DB') ORDER BY CONNTIME DESC LIMIT 1;" 2>/dev/null | head -1 | tr -d ' ')
    
    case $inactive_type in
        1)
            query="
            SELECT s.ID
            FROM _V_SESSION s
            WHERE UPPER(s.STATUS) = 'IDLE'"
            
            if [[ -n "$current_session_id" && "$current_session_id" =~ ^[0-9]+$ ]]; then
                query="$query AND s.ID != $current_session_id"
            fi
            
            query="$query ORDER BY s.CONNTIME ASC"
            description="Idle Sessions (STATUS = 'idle')"
            ;;
        2)
            read -p "Enter minimum idle hours: " idle_hours
            if [[ ! "$idle_hours" =~ ^[0-9]+$ ]]; then
                print_error "Invalid hours"
                return
            fi
            query="
            SELECT s.ID
            FROM _V_SESSION s
            WHERE s.CONNTIME < NOW() - INTERVAL '${idle_hours} HOURS'"
            
            if [[ -n "$current_session_id" && "$current_session_id" =~ ^[0-9]+$ ]]; then
                query="$query AND s.ID != $current_session_id"
            fi
            
            query="$query ORDER BY s.CONNTIME ASC"
            description="Sessions idle for more than $idle_hours hours"
            ;;
        3)
            query="
            SELECT s.ID
            FROM _V_SESSION s
            WHERE s.ID NOT IN (SELECT DISTINCT QS_SESSIONID FROM _V_QRYSTAT WHERE QS_SESSIONID IS NOT NULL)"
            
            if [[ -n "$current_session_id" && "$current_session_id" =~ ^[0-9]+$ ]]; then
                query="$query AND s.ID != $current_session_id"
            fi
            
            query="$query ORDER BY s.CONNTIME ASC"
            description="Sessions with no active queries"
            ;;
        *)
            print_error "Invalid option"
            return
            ;;
    esac
    
    if [[ -n "$current_session_id" ]]; then
        echo "Note: Current session ($current_session_id) will be excluded from termination"
    fi
    
    if dry_run_session_preview "$query" "$description"; then
        echo ""
        read -p "Proceed with termination of these inactive sessions? (y/n): " proceed_choice
        
        if [[ "$proceed_choice" =~ ^[Yy] ]]; then
            confirm_and_execute_termination "$description"
        else
            print_warning "Termination cancelled"
        fi
    fi
}

# Custom multi-criteria session termination
custom_session_termination() {
    echo "Custom Multi-Criteria Session Termination"
    echo "Leave any field blank to skip that filter"
    echo ""
    
    read -p "Username (pattern matching): " username
    read -p "Database Name: " database_name
    read -p "Client OS Username (pattern matching): " client_username
    read -p "Session Status (e.g., IDLE, ACTIVE): " status
    read -p "Minimum connection age in hours: " min_hours
    
    # Get current session ID to exclude it
    local current_session_id=$($NZSQL_CMD -t -c "SELECT ID FROM _V_SESSION WHERE UPPER(USERNAME) = UPPER('$NETEZZA_USER') AND UPPER(DBNAME) = UPPER('$NETEZZA_DB') ORDER BY CONNTIME DESC LIMIT 1;" 2>/dev/null | head -1 | tr -d ' ')
    
    # Build WHERE clause dynamically
    local where_conditions=()
    
    # Always exclude current session if we found it
    if [[ -n "$current_session_id" && "$current_session_id" =~ ^[0-9]+$ ]]; then
        where_conditions+=("s.ID != $current_session_id")
        echo "Note: Current session ($current_session_id) will be excluded from termination"
    fi
    
    if [[ -n "$username" ]]; then
        local user_pattern="%${username}%"
        where_conditions+=("UPPER(s.USERNAME) LIKE UPPER('${user_pattern}')")
    fi
    
    if [[ -n "$database_name" ]]; then
        where_conditions+=("UPPER(s.DBNAME) = UPPER('${database_name}')")
    fi
    
    if [[ -n "$client_username" ]]; then
        local client_pattern="%${client_username}%"
        where_conditions+=("UPPER(sd.CLIENT_OS_USERNAME) LIKE UPPER('${client_pattern}')")
    fi
    
    if [[ -n "$status" ]]; then
        where_conditions+=("UPPER(s.STATUS) = UPPER('${status}')")
    fi
    
    if [[ -n "$min_hours" && "$min_hours" =~ ^[0-9]+$ ]]; then
        where_conditions+=("s.CONNTIME < NOW() - INTERVAL '${min_hours} HOURS'")
    fi
    
    # Join conditions with AND
    local where_clause=""
    if [[ ${#where_conditions[@]} -gt 0 ]]; then
        where_clause="WHERE $(IFS=' AND '; echo "${where_conditions[*]}")"
    fi
    
    local query="
    SELECT s.ID
    FROM _V_SESSION s
    LEFT JOIN _V_SESSION_DETAIL sd ON s.ID = sd.SESSION_ID
    ${where_clause}
    ORDER BY s.CONNTIME DESC"
    
    local filter_desc="Custom Filter"
    if [[ -n "$username" ]]; then
        filter_desc="${filter_desc} - User: ${username}"
    fi
    if [[ -n "$database_name" ]]; then
        filter_desc="${filter_desc} - DB: ${database_name}"
    fi
    if [[ -n "$client_username" ]]; then
        filter_desc="${filter_desc} - Client: ${client_username}"
    fi
    if [[ -n "$status" ]]; then
        filter_desc="${filter_desc} - Status: ${status}"
    fi
    if [[ -n "$min_hours" ]]; then
        filter_desc="${filter_desc} - Age: ${min_hours}h+"
    fi
    
    if dry_run_session_preview "$query" "$filter_desc"; then
        echo ""
        read -p "Proceed with termination of these sessions? (y/n): " proceed_choice
        
        if [[ "$proceed_choice" =~ ^[Yy] ]]; then
            confirm_and_execute_termination "$filter_desc"
        else
            print_warning "Termination cancelled"
        fi
    fi
}

# View all active sessions (read-only)
view_all_sessions() {
    print_section "All Active Sessions (Read-Only View)"
    
    execute_sql "
    SELECT 
        s.ID,
        s.USERNAME,
        s.DBNAME,
        s.STATUS,
        s.IPADDR,
        s.CONNTIME,
        s.PRIORITY,
        s.COMMAND,
        sd.CLIENT_OS_USERNAME,
        sd.PROCESS_ID,
        ROUND(EXTRACT(EPOCH FROM (NOW() - s.CONNTIME))/3600, 1) AS HOURS_CONNECTED
    FROM _V_SESSION s
    LEFT JOIN _V_SESSION_DETAIL sd ON s.ID = sd.SESSION_ID
    ORDER BY s.CONNTIME DESC;" "All Active Sessions"
    
    echo ""
    echo "Session counts by status:"
    execute_sql "
    SELECT 
        STATUS,
        COUNT(*) AS SESSION_COUNT
    FROM _V_SESSION
    GROUP BY STATUS
    ORDER BY SESSION_COUNT DESC;" "Session Status Summary"
}

# Global variable to store sessions to be killed
declare -a SESSIONS_TO_KILL=()


# Move existing functionality to standard_realtime_analysis
standard_realtime_analysis() {
    print_section "Standard Real-time Query Analysis"
    
    # Check what views are available
    local has_qrystat=false
    if execute_sql "SELECT COUNT(*) FROM _V_QRYSTAT LIMIT 1;" "Test _V_QRYSTAT" false; then
        has_qrystat=true
        print_success "Using _V_QRYSTAT for real-time query analysis"
    else
        print_warning "Using _V_QRYHIST for historical analysis"
    fi
    
    if [[ "$has_qrystat" == true ]]; then
        # Real-time analysis with _V_QRYSTAT
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
        ORDER BY QS_ESTCOST DESC
        LIMIT ${TOP_QUERIES_LIMIT};" "Long Running Queries (Real-time)"
        
        # High cost queries
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
    
    # Historical analysis with _V_QRYHIST
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
        ORDER BY QH_ESTCOST DESC
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
        ORDER BY TOTAL_EST_COST DESC
        LIMIT 10;" "Top Users by Total Cost"
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


# Enhanced nz_plan function with intelligent content validation
use_nz_plan_for_id() {
    local plan_id="$1"
    
    # Check if nz_plan utility is available
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
    
    if [[ -z "$found_nz_plan" ]]; then
        print_warning "nz_plan utility not found in standard locations"
        return 1
    fi
    
    local plan_file="/tmp/netezza_plan_${plan_id}_$(date +%Y%m%d_%H%M%S).pln"
    
    echo "Using nz_plan utility: $found_nz_plan"
    echo "Plan ID: $plan_id"
    echo ""
    
    # Execute nz_plan and capture output
    if "$found_nz_plan" "$plan_id" > "$plan_file" 2>&1; then
        # Check if file was created and has content
        if [[ -s "$plan_file" ]]; then
            # Intelligent content validation - check for error patterns
            local has_valid_plan=true
            local error_messages=()
            
            # Check for common error patterns
            if grep -q "This script cannot find/access the requested.*\.pln file" "$plan_file"; then
                has_valid_plan=false
                error_messages+=("Plan file not accessible")
            fi
            
            if grep -q "NOTICE:.*Trying to access the.*\.pln file" "$plan_file"; then
                has_valid_plan=false
                error_messages+=("Plan file access failed")
            fi
            
            if grep -q "nz_plan -tar" "$plan_file"; then
                has_valid_plan=false
                error_messages+=("Suggested using nz_plan -tar option")
            fi
            
            if grep -q "ERROR\|FAILED\|not found\|No such file" "$plan_file"; then
                has_valid_plan=false
                error_messages+=("General error detected")
            fi
            
            # Check if file only contains NOTICE/error messages (no actual plan content)
            local content_lines=$(grep -v "^NOTICE\|^ERROR\|^This script" "$plan_file" | grep -c ".")
            if [[ $content_lines -lt 5 ]]; then
                has_valid_plan=false
                error_messages+=("Insufficient plan content (only $content_lines meaningful lines)")
            fi
            
            # Report results
            if [[ "$has_valid_plan" == true ]]; then
                print_success "Valid execution plan retrieved successfully!"
                echo ""
                echo "Plan Content:"
                echo "=============================================================="
                cat "$plan_file"
                echo "=============================================================="
                echo ""
                echo "Plan saved to: $plan_file"
                return 0
            else
                print_error "nz_plan failed to retrieve valid plan for Plan ID $plan_id"
                echo ""
                echo "Error indicators found:"
                for error in "${error_messages[@]}"; do
                    echo "  - $error"
                done
                echo ""
                echo "nz_plan output:"
                echo "=============================================================="
                cat "$plan_file"
                echo "=============================================================="
                
                # Clean up the invalid plan file
                rm -f "$plan_file"
                return 1
            fi
        else
            print_error "nz_plan produced no output for Plan ID $plan_id"
            rm -f "$plan_file"
            return 1
        fi
    else
        print_error "nz_plan execution failed for Plan ID $plan_id"
        if [[ -s "$plan_file" ]]; then
            echo "Error output:"
            echo "=============================================================="
            cat "$plan_file"
            echo "=============================================================="
        fi
        rm -f "$plan_file"
        return 1
    fi
}

# Update the discover_plan_archives function to ensure proper variable export:

discover_plan_archives() {
    local base_path="/nzscratch/monitor/log/plansarchive"
    local available_dirs=()
    
    print_section "Discovering Plan Archive Directories"
    
    echo "Checking base path: $base_path"
    
    if [[ ! -d "$base_path" ]]; then
        print_warning "Plan archive base directory not found: $base_path"
        echo "Please verify the correct path for plan archives on your system."
        echo "Common alternative paths:"
        echo "  - /nz/kit/log/planarchive"
        echo "  - /opt/nz/log/planarchive"
        echo "  - /var/log/nz/planarchive"
        echo ""
        read -p "Enter alternative plan archive path (or press Enter to skip): " alt_path
        
        if [[ -n "$alt_path" && -d "$alt_path" ]]; then
            base_path="$alt_path"
            echo "Using alternative path: $base_path"
        else
            return 1
        fi
    fi
    
    echo "Base directory exists: $base_path"
    echo "Listing contents of base directory:"
    ls -la "$base_path" 2>/dev/null || echo "Cannot list directory contents"
    echo ""
    
    echo "Searching for numeric directories..."
    
    # Find all numeric directories and sort them in descending order
    local found_dirs=0
    while IFS= read -r -d '' dir; do
        local dir_name=$(basename "$dir")
        echo "Found directory: $dir_name"
        if [[ "$dir_name" =~ ^[0-9]+$ ]]; then
            available_dirs+=("$dir_name")
            echo "  -> Added numeric directory: $dir_name"
            ((found_dirs++))
        else
            echo "  -> Skipped non-numeric directory: $dir_name"
        fi
    done < <(find "$base_path" -maxdepth 1 -type d -print0 2>/dev/null)
    
    echo ""
    echo "Total directories found: $found_dirs"
    
    if [[ $found_dirs -eq 0 ]]; then
        echo "No directories found. Checking if find command worked..."
        echo "Manual directory check:"
        for item in "$base_path"/*; do
            if [[ -d "$item" ]]; then
                local item_name=$(basename "$item")
                echo "  Directory: $item_name"
                if [[ "$item_name" =~ ^[0-9]+$ ]]; then
                    available_dirs+=("$item_name")
                    echo "    -> This is numeric, adding to list"
                fi
            fi
        done
    fi
    
    # Sort in descending order (newest first)
    if [[ ${#available_dirs[@]} -gt 0 ]]; then
        IFS=$'\n' available_dirs=($(sort -nr <<<"${available_dirs[*]}"))
        unset IFS
        
        echo "Found ${#available_dirs[@]} numeric plan archive directories (newest first):"
        for i in "${!available_dirs[@]}"; do
            local dir="${available_dirs[$i]}"
            echo "  $((i+1)). $dir (${base_path}/${dir})"
        done
        
        # Export to global variables - make sure these are set in the calling context
        PLAN_ARCHIVE_DIRS=("${available_dirs[@]}")
        PLAN_ARCHIVE_BASE="$base_path"
        
        # Debug: Confirm the arrays are set
        echo ""
        echo "DEBUG: Set PLAN_ARCHIVE_DIRS with ${#PLAN_ARCHIVE_DIRS[@]} elements"
        echo "DEBUG: Set PLAN_ARCHIVE_BASE to: $PLAN_ARCHIVE_BASE"
        
        return 0
    else
        print_warning "No numeric plan archive directories found in $base_path"
        echo ""
        echo "This could mean:"
        echo "  1. Plan archiving is not configured"
        echo "  2. No plans have been archived yet"
        echo "  3. Different archive directory structure"
        echo "  4. Permissions issue accessing the directory"
        echo ""
        return 1
    fi
}



use_nz_plan_for_id_enhanced() {
    local plan_id="$1"
    local search_archives="${2:-true}"
    
    print_section "Enhanced nz_plan Analysis for Plan ID: $plan_id"
    
    # Step 1: Try the standard nz_plan utility (for default planshist location)
    echo "Step 1: Searching in default planshist location..."
    echo "Command: nz_plan $plan_id"
    
    if use_nz_plan_for_id "$plan_id"; then
        print_success "Plan retrieved successfully from default location!"
        return 0
    else
        print_warning "Plan not found in default planshist location"
        
        if [[ "$search_archives" == "true" ]]; then
            echo ""
            echo "Step 2: Searching plan archives..."
            echo "This will use nz_plan --tardir to search compressed archives..."
            search_plan_in_archives "$plan_id"
        else
            echo ""
            echo "Archive search disabled."
            return 1
        fi
    fi
}

# Fix the search_plan_in_archives function to properly use discovered directories:

search_plan_in_archives() {
    local plan_id="$1"
    local found_plan=false
    
    # Discover available archives if not already done or if array is empty
    if [[ -z "${PLAN_ARCHIVE_DIRS[*]}" ]] || [[ ${#PLAN_ARCHIVE_DIRS[@]} -eq 0 ]]; then
        echo "Rediscovering plan archives..."
        if ! discover_plan_archives; then
            print_error "Failed to discover plan archives automatically"
            echo ""
            read -p "Would you like to manually specify a plan archive directory? (y/n): " manual_search
            
            if [[ "$manual_search" =~ ^[Yy] ]]; then
                read -p "Enter full path to plan archive directory: " manual_path
                if [[ -d "$manual_path" ]]; then
                    echo "Trying manual search in: $manual_path"
                    manual_plan_search "$plan_id" "$manual_path"
                else
                    print_error "Directory does not exist: $manual_path"
                fi
            fi
            return 1
        fi
    fi
    
    print_section "Searching Plan Archives for Plan ID: $plan_id"
    echo "Note: Plan not found in default location, searching archives..."
    echo "Using nz_plan -tar to search compressed plan archives..."
    
    # Debug: Show what we have
    echo "Available archive directories: ${#PLAN_ARCHIVE_DIRS[@]}"
    echo "Archive base: $PLAN_ARCHIVE_BASE"
    
    if [[ ${#PLAN_ARCHIVE_DIRS[@]} -eq 0 ]]; then
        print_error "No archive directories available for search after discovery"
        echo "This indicates that plan archiving may not be set up on this system."
        return 1
    fi
    
    echo "Searching in ${#PLAN_ARCHIVE_DIRS[@]} archive directories (newest first)..."
    echo ""
    
    # Find nz_plan utility
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
    
    if [[ -z "$found_nz_plan" ]]; then
        print_error "nz_plan utility not found - cannot search archives"
        return 1
    fi
    
    echo "Using nz_plan utility: $found_nz_plan"
    echo ""
    
    local search_count=0
    local max_search=10  # Reasonable limit for archive search
    
    for dir in "${PLAN_ARCHIVE_DIRS[@]}"; do
        if [[ $search_count -ge $max_search ]]; then
            print_warning "Reached archive search limit ($max_search directories)"
            echo "Use comprehensive search option to search more archives."
            break
        fi
        
        local archive_path="${PLAN_ARCHIVE_BASE}/${dir}"
        echo "[$((search_count+1))/${#PLAN_ARCHIVE_DIRS[@]}] Checking archive: $dir"
        echo "  Path: $archive_path"
        echo "  Command: nz_plan -tar $plan_id -tardir $archive_path"
        
        local archive_plan_file="/tmp/netezza_archive_plan_${plan_id}_${dir}_$(date +%Y%m%d_%H%M%S).pln"
        
        # CORRECTED SYNTAX: nz_plan -tar <plan_id> -tardir <archive_path>
        if "$found_nz_plan" -tar "$plan_id" -tardir "$archive_path" > "$archive_plan_file" 2>&1; then
            if [[ -s "$archive_plan_file" ]]; then
                echo "  Output file created, checking content..."
                
                # Show first few lines for debugging
                echo "  First few lines of output:"
                head -3 "$archive_plan_file" | sed 's/^/    /'
                
                # Intelligent validation of archive plan content
                local has_valid_plan=true
                
                # Check for error patterns
                if grep -q "This script cannot find/access the requested.*\.pln file" "$archive_plan_file" || \
                   grep -q "NOTICE:.*Trying to access" "$archive_plan_file" || \
                   grep -q "ERROR\|FAILED\|not found\|No such file" "$archive_plan_file"; then
                    has_valid_plan=false
                    echo "  ✗ Error patterns detected in output"
                fi
                
                # Check for meaningful plan content
                local content_lines=$(grep -v "^NOTICE\|^ERROR\|^This script" "$archive_plan_file" | grep -c ".")
                if [[ $content_lines -lt 5 ]]; then
                    has_valid_plan=false
                    echo "  ✗ Insufficient meaningful content ($content_lines lines)"
                fi
                
                if [[ "$has_valid_plan" == true ]]; then
                    print_success "✓ Valid plan found in archive: $dir"
                    echo ""
                    echo "Plan Contents:"
                    echo "=============================================================="
                    cat "$archive_plan_file"
                    echo "=============================================================="
                    found_plan=true
                    
                    # Save a copy for reference
                    local saved_plan="/tmp/netezza_archived_plan_${plan_id}_$(date +%Y%m%d_%H%M%S).pln"
                    cp "$archive_plan_file" "$saved_plan" 2>/dev/null
                    echo ""
                    echo "Plan saved to: $saved_plan"
                    echo "To retrieve this plan again, use:"
                    echo "  nz_plan -tar $plan_id -tardir $archive_path"
                    rm -f "$archive_plan_file"
                    break  # Exit the loop since we found a valid plan
                else
                    echo "  ✗ Plan not found or invalid in archive $dir"
                    rm -f "$archive_plan_file"
                fi
            else
                echo "  ✗ No output from nz_plan -tar"
            fi
        else
            echo "  ✗ nz_plan -tar command failed"
            
            # Show error if there's output
            if [[ -s "$archive_plan_file" ]]; then
                echo "  Error output:"
                head -3 "$archive_plan_file" | sed 's/^/    /'
                rm -f "$archive_plan_file"
            fi
        fi
        
        ((search_count++))
        echo ""
    done
    
    if [[ "$found_plan" == false ]]; then
        print_warning "Plan ID $plan_id not found in the first $search_count archive directories"
        echo ""
        echo "Searched archives:"
        for ((i=0; i<search_count; i++)); do
            echo "  - ${PLAN_ARCHIVE_DIRS[$i]} (${PLAN_ARCHIVE_BASE}/${PLAN_ARCHIVE_DIRS[$i]})"
        done
        
        if [[ $search_count -lt ${#PLAN_ARCHIVE_DIRS[@]} ]]; then
            echo ""
            echo "Remaining archives not searched: $((${#PLAN_ARCHIVE_DIRS[@]} - search_count))"
            echo ""
            read -p "Would you like to search ALL remaining archives? (y/n): " comprehensive_search
            
            if [[ "$comprehensive_search" =~ ^[Yy] ]]; then
                comprehensive_plan_search "$plan_id"
            fi
        fi
        
        return 1
    fi
    
    return 0
}

# Add manual plan search function
manual_plan_search() {
    local plan_id="$1"
    local manual_path="$2"
    
    print_section "Manual Plan Search in: $manual_path"
    
    # Find nz_plan utility
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
    
    if [[ -z "$found_nz_plan" ]]; then
        print_error "nz_plan utility not found"
        return 1
    fi
    
    echo "Command: nz_plan -tar $plan_id -tardir $manual_path"
    local manual_plan_file="/tmp/netezza_manual_plan_${plan_id}_$(date +%Y%m%d_%H%M%S).pln"
    
    if "$found_nz_plan" -tar "$plan_id" -tardir "$manual_path" > "$manual_plan_file" 2>&1; then
        if [[ -s "$manual_plan_file" ]]; then
            # Check for valid plan content
            if grep -q "This script cannot find/access the requested.*\.pln file\|NOTICE:.*Trying to access\|ERROR\|FAILED\|not found\|No such file" "$manual_plan_file"; then
                print_error "Plan not found in manual directory"
                cat "$manual_plan_file"
            else
                local content_lines=$(grep -v "^NOTICE\|^ERROR\|^This script" "$manual_plan_file" | grep -c ".")
                if [[ $content_lines -gt 5 ]]; then
                    print_success "Plan found in manual directory!"
                    echo ""
                    echo "Plan Contents:"
                    echo "=============================================================="
                    cat "$manual_plan_file"
                    echo "=============================================================="
                    echo ""
                    echo "Plan saved to: $manual_plan_file"
                else
                    print_error "Plan file contains insufficient content"
                fi
            fi
        else
            print_error "No output from nz_plan command"
        fi
    else
        print_error "nz_plan command failed"
    fi
    
    rm -f "$manual_plan_file"
}

# Fix the comprehensive_plan_search function to use correct nz_plan syntax:

comprehensive_plan_search() {
    local plan_id="$1"
    
    print_section "Comprehensive Archive Search for Plan ID: $plan_id"
    echo "Searching ALL available archive directories..."
    echo "This may take several minutes as we check each compressed archive..."
    echo ""
    
    # Find nz_plan utility
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
        for path in "${alt_paths[@]}"
        do
            if [[ -f "$path" && -x "$path" ]]; then
                found_nz_plan="$path"
                break
            fi
        done
    fi
    
    if [[ -z "$found_nz_plan" ]]; then
        print_error "nz_plan utility not found - cannot perform comprehensive search"
        return 1
    fi
    
    local search_results="/tmp/netezza_comprehensive_search_${plan_id}_$(date +%Y%m%d_%H%M%S).txt"
    local found_in_archives=()
    
    # Get ALL available archive directories
    local all_archive_dirs=()
    if [[ -d "$PLAN_ARCHIVE_BASE" ]]; then
        while IFS= read -r -d '' dir; do
            local dir_name=$(basename "$dir")
            if [[ "$dir_name" =~ ^[0-9]+$ ]]; then
                all_archive_dirs+=("$dir_name")
            fi
        done < <(find "$PLAN_ARCHIVE_BASE" -maxdepth 1 -type d -print0)
        
        # Sort in descending order (newest first)
        IFS=$'\n' all_archive_dirs=($(sort -nr <<<"${all_archive_dirs[*]}"))
        unset IFS
    fi
    
    echo "Found ${#all_archive_dirs[@]} total archive directories to search..."
    echo "Searching ALL archives using: nz_plan -tar $plan_id -tardir <archive>"
    echo ""
    
    local search_count=0
    
    for archive_dir in "${all_archive_dirs[@]}"; do
        local archive_path="${PLAN_ARCHIVE_BASE}/${archive_dir}"
        echo "[$((search_count+1))/${#all_archive_dirs[@]}] Searching archive: $archive_dir"
        
        # Try nz_plan -tar for this archive - CORRECTED SYNTAX
        local temp_plan_file="/tmp/netezza_comprehensive_${plan_id}_${archive_dir}_$(date +%Y%m%d_%H%M%S).pln"
        
        if "$found_nz_plan" -tar "$plan_id" -tardir "$archive_path" > "$temp_plan_file" 2>&1; then
            if [[ -s "$temp_plan_file" ]]; then
                # Intelligent validation of the plan content
                local has_valid_plan=true
                
                # Check for error patterns and content
                if grep -q "This script cannot find/access the requested.*\.pln file\|NOTICE:.*Trying to access\|ERROR\|FAILED\|not found\|No such file" "$temp_plan_file"; then
                    has_valid_plan=false
                fi
                
                # Check for meaningful plan content
                local content_lines=$(grep -v "^NOTICE\|^ERROR\|^This script" "$temp_plan_file" | grep -c ".")
                if [[ $content_lines -lt 5 ]]; then
                    has_valid_plan=false
                fi
                
                if [[ "$has_valid_plan" == true ]]; then
                    print_success "✓ Plan found in archive: $archive_dir"
                    found_in_archives+=("$archive_dir")
                    
                    # Save the search results
                    echo "Archive: $archive_dir" >> "$search_results"
                    echo "Path: $archive_path" >> "$search_results"
                    echo "Command: nz_plan -tar $plan_id -tardir $archive_path" >> "$search_results"
                    echo "Plan Content:" >> "$search_results"
                    cat "$temp_plan_file" >> "$search_results"
                    echo "===========================================" >> "$search_results"
                    echo "" >> "$search_results"
                else
                    echo "  ✗ Plan not found in archive $archive_dir"
                fi
                
                rm -f "$temp_plan_file"
            else
                echo "  ✗ No output from nz_plan -tar for archive $archive_dir"
            fi
        else
            echo "  ✗ nz_plan -tar failed for archive $archive_dir"
        fi
        
        ((search_count++))
    done
    
    echo ""
    echo "=============================================================="
    
    if [[ ${#found_in_archives[@]} -gt 0 ]]; then
        print_success "Plan ID $plan_id found in ${#found_in_archives[@]} archive(s)!"
        echo ""
        echo "Archives containing the plan:"
        for archive in "${found_in_archives[@]}"; do
            echo "  - $archive (${PLAN_ARCHIVE_BASE}/${archive})"
        done
        
        echo ""
        read -p "Would you like to view the plan from the newest archive? (y/n): " view_plan
        
        if [[ "$view_plan" =~ ^[Yy] ]] && [[ -s "$search_results" ]]; then
            echo ""
            echo "Plan Details from Comprehensive Search:"
            echo "=============================================================="
            head -50 "$search_results"  # Show first 50 lines to avoid overwhelming output
            echo "=============================================================="
            
            # Save a copy for reference
            local saved_plan="/tmp/netezza_comprehensive_plan_${plan_id}_$(date +%Y%m%d_%H%M%S).pln"
            cp "$search_results" "$saved_plan" 2>/dev/null
            echo ""
            echo "Complete search results saved to: $saved_plan"
        fi
        
        echo ""
        echo "To retrieve this plan in the future, use:"
        echo "  nz_plan -tar $plan_id -tardir ${PLAN_ARCHIVE_BASE}/${found_in_archives[0]}"
        
    else
        print_warning "Plan ID $plan_id not found in any of the $search_count searched archives"
        echo ""
        echo "This means the plan is either:"
        echo "  1. Older than the archived data"
        echo "  2. Plan ID doesn't exist"
        echo "  3. Plan was never successfully created"
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
    echo -e "${YELLOW}6. Historical Query Analysis (HISTDB) ⭐${NC}"
    echo "7. Configuration Settings"
    echo -e "${RED}8. Session Management & Termination ⭐ NEW${NC}"
    echo "9. Exit"
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
        read -p "Choose an option (1-9): " choice
        
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
                session_management
                read -p "Press Enter to continue..."
                ;;
            9)
                print_success "Thank you for using Netezza Performance Tool!"
                exit 0
                ;;
            *)
                print_error "Invalid option. Please choose 1-9."
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
