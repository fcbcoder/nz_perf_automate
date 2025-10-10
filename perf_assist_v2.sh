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
LONG_RUNNING_QUERY_HOURS=2
TOP_SESSIONS_LIMIT=10
TOP_QUERIES_LIMIT=20

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
    print_header "QUERY PERFORMANCE ANALYSIS"
    
    # Check what views are available
    local has_qrystat=false
    if execute_sql "SELECT COUNT(*) FROM _V_QRYSTAT LIMIT 1;" "Test _V_QRYSTAT" false; then
        has_qrystat=true
        print_success "Using _V_QRYSTAT for real-time query analysis"
    else
        print_warning "Using _V_QRYHIST for historical analysis"
    fi
    
    if [[ "$has_qrystat" == true ]]; then
        # Real-time analysis with _V_QRYSTAT - CORRECT COLUMNS
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
        
        # High cost queries
        execute_sql "
        SELECT 
            QS_SESSIONID,
            QS_PLANID,
            QS_ESTCOST,
            QS_ESTMEM,
            QS_TSTART,
            SUBSTRING(QS_SQL, 1, 80) AS SQL_PREVIEW
        FROM _V_QRYSTAT
        WHERE QS_ESTCOST > 100
        ORDER BY QS_ESTCOST DESC
        LIMIT ${TOP_QUERIES_LIMIT};" "High Cost Queries (Currently Running)"
        
    else
        # Historical analysis with _V_QRYHIST - CORRECT COLUMNS FROM V1
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
        AND QH_TSTART IS NOT NULL 
        AND QH_TEND IS NOT NULL
        AND EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)) > 30
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
    fi
}

#=============================================================================
# Core Function 3: Cost-Based Analysis (SIMPLIFIED & WORKING)
#=============================================================================

check_cost_based_performance() {
    print_header "COST-BASED PERFORMANCE ANALYSIS"
    
    # Focus on _V_QRYSTAT for cost analysis
    if execute_sql "SELECT COUNT(*) FROM _V_QRYSTAT LIMIT 1;" "Test _V_QRYSTAT" false; then
        print_success "_V_QRYSTAT available - Enhanced cost analysis"
        
        # Top queries by cost
        execute_sql "
        SELECT 
            QS_SESSIONID,
            QS_PLANID,
            QS_ESTCOST,
            QS_ESTMEM,
            QS_ESTDISK,
            QS_TSTART,
            SUBSTRING(QS_SQL, 1, 100) AS SQL_PREVIEW
        FROM _V_QRYSTAT
        WHERE QS_ESTCOST > 0
        ORDER BY QS_ESTCOST DESC
        LIMIT ${TOP_QUERIES_LIMIT};" "Top Queries by Estimated Cost"
        
        # Resource usage summary
        execute_sql "
        SELECT 
            COUNT(*) AS TOTAL_QUERIES,
            COUNT(DISTINCT QS_PLANID) AS UNIQUE_PLANS,
            COUNT(DISTINCT QS_SESSIONID) AS UNIQUE_SESSIONS,
            ROUND(AVG(QS_ESTCOST), 2) AS AVG_EST_COST,
            ROUND(MAX(QS_ESTCOST), 2) AS MAX_EST_COST,
            ROUND(AVG(QS_ESTMEM), 2) AS AVG_EST_MEM,
            ROUND(MAX(QS_ESTMEM), 2) AS MAX_EST_MEM
        FROM _V_QRYSTAT;" "Query Resource Usage Summary"
        
        # Plan analysis - find repeated execution plans
        execute_sql "
        SELECT 
            QS_PLANID,
            COUNT(*) AS EXECUTION_COUNT,
            ROUND(AVG(QS_ESTCOST), 2) AS AVG_COST,
            MAX(QS_TSTART) AS LAST_EXECUTION,
            SUBSTRING(MAX(QS_SQL), 1, 80) AS SAMPLE_SQL
        FROM _V_QRYSTAT
        WHERE QS_PLANID IS NOT NULL
        GROUP BY QS_PLANID
        HAVING COUNT(*) > 1
        ORDER BY EXECUTION_COUNT DESC
        LIMIT 15;" "Most Frequently Used Plans"
        
    else
        print_warning "_V_QRYSTAT not available - Using _V_QRYHIST for cost analysis"
        
        # Fallback to historical cost analysis
        execute_sql "
        SELECT 
            QH_SESSIONID,
            QH_USER,
            QH_DATABASE,
            QH_TSTART,
            QH_TEND,
            QH_ESTCOST,
            QH_RESROWS,
            ROUND(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)), 2) AS EXECUTION_SECONDS,
            SUBSTR(QH_SQL, 1, 100) AS SQL_PREVIEW
        FROM _V_QRYHIST
        WHERE QH_TEND > NOW() - INTERVAL '24 HOURS'
        AND QH_ESTCOST > 0
        ORDER BY QH_ESTCOST DESC
        LIMIT ${TOP_QUERIES_LIMIT};" "Top Queries by Cost (Last 24h)"
    fi
}

#=============================================================================
# Core Function 4: Explain Plan Analysis (From V1 - WORKING nz_plan utility)
#=============================================================================

interactive_explain_plan() {
    print_header "INTERACTIVE SQL EXPLAIN PLAN ANALYSIS"
    
    echo -e "${CYAN}Available options:${NC}"
    echo "1. Analyze SQL from recent query history"  
    echo "2. Use nz_plan utility (requires plan ID)"
    echo "3. Enter custom SQL for analysis"
    echo "4. Return to main menu"
    echo ""
    
    read -p "Choose an option (1-4): " choice
    
    case $choice in
        1)
            analyze_recent_queries
            ;;
        2)
            use_nz_plan_utility  # FROM V1 - THIS WORKS
            ;;
        3)
            analyze_custom_sql
            ;;
        4)
            return
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
}

analyze_recent_queries() {
    print_section "Recent Query Analysis"
    
    # Show recent queries with plan IDs
    execute_sql "
    SELECT 
        QH_SESSIONID,
        QH_USER,
        QH_DATABASE,
        QH_TSTART,
        QH_TEND,
        QH_PLANID,
        ROUND(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)), 2) AS ELAPSED_SECONDS,
        SUBSTR(QH_SQL, 1, 100) AS SQL_PREVIEW
    FROM _V_QRYHIST
    WHERE QH_TEND > NOW() - INTERVAL '2 HOURS'
    AND QH_PLANID IS NOT NULL
    ORDER BY QH_TEND DESC
    LIMIT 20;" "Recent Queries with Plan IDs"
    
    echo ""
    read -p "Enter Session ID to analyze: " session_id
    
    if [[ "$session_id" =~ ^[0-9]+$ ]]; then
        execute_sql "
        SELECT 
            QH_SESSIONID,
            QH_USER,
            QH_DATABASE,
            QH_TSTART,
            QH_TEND,
            QH_PLANID,
            QH_ESTCOST,
            QH_ESTMEM,
            QH_RESROWS,
            ROUND(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)), 2) AS ELAPSED_SECONDS,
            SUBSTR(QH_SQL, 1, 500) AS SQL_TEXT
        FROM _V_QRYHIST
        WHERE QH_SESSIONID = ${session_id}
        ORDER BY QH_TSTART DESC;" "Detailed Analysis for Session ${session_id}"
    else
        print_error "Invalid session ID"
    fi
}

use_nz_plan_utility() {
    # EXACT COPY FROM V1 - THIS WORKS PERFECTLY
    print_section "Using nz_plan Utility"
    
    echo "This method uses the nz_plan utility to retrieve execution plans by plan ID."
    echo ""
    echo "First, let's find plan IDs from recent query history:"
    
    # Show recent queries with their potential plan IDs
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
        print_warning "nz_plan utility not found in standard locations."
        read -p "Enter full path to nz_plan utility (or press Enter to skip): " custom_path
        
        if [[ -n "$custom_path" && -f "$custom_path" && -x "$custom_path" ]]; then
            found_nz_plan="$custom_path"
        else
            print_error "nz_plan utility not available"
            return
        fi
    fi
    
    print_section "Generating Plan using nz_plan utility"
    print_success "Using nz_plan at: $found_nz_plan"
    
    # Create output file
    local plan_file="/tmp/netezza_plan_${plan_id}_$(date +%Y%m%d_%H%M%S).pln"
    
    echo "Executing: $found_nz_plan $plan_id"
    
    if "$found_nz_plan" "$plan_id" > "$plan_file" 2>&1; then
        print_success "Plan generated successfully!"
        echo ""
        echo "Plan contents:"
        echo "=============================================================="
        cat "$plan_file"
        echo "=============================================================="
        echo ""
        echo "Plan saved to: $plan_file"
    else
        print_error "Failed to generate plan with nz_plan utility"
        echo "Error output:"
        cat "$plan_file"
        rm -f "$plan_file"
    fi
}

analyze_custom_sql() {
    echo ""
    echo "Enter your SQL statement (end with semicolon and press Enter twice):"
    
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
    
    print_section "SQL Analysis"
    echo "SQL Statement: $sql_statement"
    
    # Basic EXPLAIN
    echo ""
    echo "Generating EXPLAIN plan..."
    if execute_sql "EXPLAIN $sql_statement" "Custom SQL Explain Plan" true; then
        print_success "Explain plan generated successfully"
    else
        print_error "Failed to generate explain plan"
    fi
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
    echo -e "${GREEN}║                    NETEZZA PERFORMANCE TOOL - CORE VERSION                  ║${NC}"
    echo -e "${GREEN}║                              Version 2.0                                    ║${NC}"
    echo -e "${GREEN}║                         Clean & Focused                                     ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Core Functions (Rock Solid):${NC}"
    echo "1. Active Sessions & Transactions (with nzsession -activetxn)"
    echo "2. Query Performance Analysis (_V_QRYSTAT + _V_QRYHIST)" 
    echo "3. Cost-Based Analysis (Focus on resource usage)"
    echo "4. Interactive Explain Plan (nz_plan utility)"
    echo "5. System State Overview"
    echo "6. Configuration Settings"
    echo "7. Exit"
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
                configure_settings
                read -p "Press Enter to continue..."
                ;;
            7)
                print_success "Thank you for using Netezza Performance Tool!"
                exit 0
                ;;
            *)
                print_error "Invalid option. Please choose 1-7."
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi