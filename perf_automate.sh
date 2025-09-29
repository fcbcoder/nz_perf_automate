#!/bin/bash

#=============================================================================
# Netezza Performance Automation Tool
# Version: 1.0
# Date: September 29, 2025
# Description: Automated system checks for Netezza 11.2.1.13
# Author: Database Administrator
#=============================================================================

# Configuration Variables
NETEZZA_HOST="${NETEZZA_HOST:-localhost}"
NETEZZA_DB="${NETEZZA_DB:-SYSTEM}"
NETEZZA_USER="${NETEZZA_USER:-ADMIN}"
NZSQL_CMD="nzsql -host ${NETEZZA_HOST} -db ${NETEZZA_DB} -u ${NETEZZA_USER}"

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
# Utility Functions
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
    
    echo "-- $description" >> "$LOG_FILE"
    echo "$sql" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    $NZSQL_CMD -c "$sql" 2>/dev/null
    if [ $? -ne 0 ]; then
        print_error "Failed to execute: $description"
        return 1
    fi
}

#=============================================================================
# System State Checks
#=============================================================================

check_netezza_system_state() {
    print_header "NETEZZA SYSTEM STATE ANALYSIS"
    
    # System version and state
    print_section "System Version and State"
    execute_sql "SELECT * FROM _V_SYSTEM_STATE;" "System State"
    
    # Database list and sizes
    print_section "Database Information"
    execute_sql "
    SELECT 
        DATABASE,
        OWNER,
        CREATEDATE,
        ROUND(USED_BYTES/1024/1024/1024, 2) AS USED_GB,
        ROUND(SKEW/100.0, 2) AS SKEW_PCT
    FROM _V_DATABASE 
    ORDER BY USED_BYTES DESC;" "Database Sizes"
    
    # Disk usage
    print_section "Disk Usage"
    execute_sql "
    SELECT 
        HOST,
        FILESYSTEM,
        ROUND(TOTAL_BYTES/1024/1024/1024, 2) AS TOTAL_GB,
        ROUND(USED_BYTES/1024/1024/1024, 2) AS USED_GB,
        ROUND(FREE_BYTES/1024/1024/1024, 2) AS FREE_GB,
        ROUND((USED_BYTES*100.0/TOTAL_BYTES), 2) AS USED_PCT
    FROM _V_DISK
    ORDER BY USED_PCT DESC;" "Disk Usage by Host"
    
    # System configuration
    print_section "Key System Configuration"
    execute_sql "
    SELECT 
        NAME,
        VALUE,
        DESCRIPTION
    FROM _V_SYSTEM_CONFIG 
    WHERE NAME IN ('SYSTEM.HOSTNAME', 'SYSTEM.VERSION', 'SYSTEM.MAX_SESSIONS', 
                   'SYSTEM.MEMORY.TOTAL', 'SYSTEM.CPU.COUNT')
    ORDER BY NAME;" "System Configuration"
}

#=============================================================================
# Linux OS Performance Monitoring
#=============================================================================

check_os_performance() {
    print_header "LINUX OS PERFORMANCE MONITORING"
    
    # Host system information
    print_section "Host System Status"
    execute_sql "
    SELECT 
        HOST,
        CPU_USER_PCT,
        CPU_SYSTEM_PCT,
        CPU_IDLE_PCT,
        ROUND(MEMORY_USED_BYTES/1024/1024/1024, 2) AS MEMORY_USED_GB,
        ROUND(MEMORY_FREE_BYTES/1024/1024/1024, 2) AS MEMORY_FREE_GB,
        ROUND((MEMORY_USED_BYTES*100.0/(MEMORY_USED_BYTES+MEMORY_FREE_BYTES)), 2) AS MEMORY_USED_PCT,
        SWAP_USED_BYTES/1024/1024 AS SWAP_USED_MB,
        LOAD_AVERAGE_1MIN,
        LOAD_AVERAGE_5MIN,
        LOAD_AVERAGE_15MIN
    FROM _V_HOST
    ORDER BY HOST;" "Host Performance Metrics"
    
    # System processes
    print_section "Top System Processes"
    execute_sql "
    SELECT 
        HOST,
        PID,
        SUBSTR(COMMAND, 1, 50) AS COMMAND,
        CPU_PCT,
        MEMORY_PCT,
        VSZ_KB/1024 AS VSZ_MB,
        RSS_KB/1024 AS RSS_MB
    FROM _V_SYSTEM_PROCESSES 
    WHERE CPU_PCT > 1.0 OR MEMORY_PCT > 1.0
    ORDER BY CPU_PCT DESC, MEMORY_PCT DESC
    LIMIT 20;" "Resource Intensive Processes"
    
    # I/O Statistics
    print_section "I/O Performance"
    execute_sql "
    SELECT 
        HOST,
        DEVICE,
        READS_PER_SEC,
        WRITES_PER_SEC,
        READ_KB_PER_SEC,
        WRITE_KB_PER_SEC,
        ROUND(AVG_QUEUE_SIZE, 2) AS AVG_QUEUE_SIZE,
        ROUND(UTIL_PCT, 2) AS UTIL_PCT
    FROM _V_SYSTEM_IO
    WHERE UTIL_PCT > 10
    ORDER BY UTIL_PCT DESC;" "I/O Statistics"
}

#=============================================================================
# Session and SQL Monitoring
#=============================================================================

check_active_sessions() {
    print_header "ACTIVE SESSIONS AND SQL ANALYSIS"
    
    # Top active sessions
    print_section "Top Active Sessions (Running > ${LONG_RUNNING_QUERY_HOURS} hours)"
    execute_sql "
    SELECT 
        s.SESSIONID,
        s.USERNAME,
        s.DBNAME,
        s.CLIENT_IP,
        s.CLIENT_PID,
        s.STATE,
        ROUND(EXTRACT(EPOCH FROM (NOW() - s.LOGON_TIME))/3600, 2) AS SESSION_HOURS,
        ROUND(EXTRACT(EPOCH FROM (NOW() - COALESCE(s.QUERY_START_TIME, s.LOGON_TIME)))/3600, 2) AS QUERY_HOURS,
        s.PRIORITY,
        SUBSTR(COALESCE(t.SQL, 'No active query'), 1, 100) AS CURRENT_SQL
    FROM _V_SESSION s
    LEFT JOIN _V_SQL_TEXT t ON s.SESSIONID = t.SESSIONID
    WHERE s.STATE IN ('active', 'queued', 'paused')
    AND EXTRACT(EPOCH FROM (NOW() - s.LOGON_TIME))/3600 > ${LONG_RUNNING_QUERY_HOURS}
    ORDER BY QUERY_HOURS DESC
    LIMIT ${TOP_SESSIONS_LIMIT};" "Long Running Sessions"
    
    # All active sessions summary
    print_section "Current Active Sessions Summary"
    execute_sql "
    SELECT 
        STATE,
        COUNT(*) AS SESSION_COUNT,
        ROUND(AVG(EXTRACT(EPOCH FROM (NOW() - LOGON_TIME))/3600), 2) AS AVG_SESSION_HOURS
    FROM _V_SESSION
    WHERE STATE != 'idle'
    GROUP BY STATE
    ORDER BY SESSION_COUNT DESC;" "Session State Summary"
    
    # Current executing queries
    print_section "Currently Executing Queries"
    execute_sql "
    SELECT 
        s.SESSIONID,
        s.USERNAME,
        s.DBNAME,
        s.STATE,
        ROUND(EXTRACT(EPOCH FROM (NOW() - s.QUERY_START_TIME))/60, 2) AS QUERY_MINUTES,
        SUBSTR(t.SQL, 1, 150) AS SQL_TEXT
    FROM _V_SESSION s
    JOIN _V_SQL_TEXT t ON s.SESSIONID = t.SESSIONID
    WHERE s.STATE = 'active' 
    AND s.QUERY_START_TIME IS NOT NULL
    ORDER BY QUERY_MINUTES DESC;" "Active Queries"
}

check_query_performance() {
    print_header "QUERY PERFORMANCE ANALYSIS"
    
    # Top queries by elapsed time (last 24 hours)
    print_section "Top Queries by Elapsed Time (Last 24 Hours)"
    execute_sql "
    SELECT 
        h.SESSIONID,
        h.USERNAME,
        h.DBNAME,
        ROUND(h.ELAPSED_TIME/1000000, 2) AS ELAPSED_SECONDS,
        ROUND(h.COMPILE_TIME/1000000, 2) AS COMPILE_SECONDS,
        h.QUEUE_TIME/1000000 AS QUEUE_SECONDS,
        h.ROWS_INSERTED + h.ROWS_UPDATED + h.ROWS_DELETED + h.ROWS_RETURNED AS TOTAL_ROWS,
        h.MEMORY_USAGE_BYTES/1024/1024 AS MEMORY_MB,
        SUBSTR(t.SQL, 1, 100) AS SQL_TEXT
    FROM _V_QRYHIST h
    JOIN _V_SQL_TEXT t ON h.SESSIONID = t.SESSIONID
    WHERE h.END_TIME > NOW() - INTERVAL '24 HOURS'
    AND h.ELAPSED_TIME > ${LONG_RUNNING_QUERY_HOURS} * 3600 * 1000000
    ORDER BY h.ELAPSED_TIME DESC
    LIMIT ${TOP_QUERIES_LIMIT};" "Slowest Queries (24h)"
    
    # Top queries by CPU usage
    print_section "Top Queries by CPU Usage (Last 24 Hours)"
    execute_sql "
    SELECT 
        h.SESSIONID,
        h.USERNAME,
        h.DBNAME,
        ROUND(h.ELAPSED_TIME/1000000, 2) AS ELAPSED_SECONDS,
        h.CPU_TIME/1000000 AS CPU_SECONDS,
        ROUND((h.CPU_TIME * 100.0 / h.ELAPSED_TIME), 2) AS CPU_PCT,
        h.MEMORY_USAGE_BYTES/1024/1024 AS MEMORY_MB,
        SUBSTR(t.SQL, 1, 100) AS SQL_TEXT
    FROM _V_QRYHIST h
    JOIN _V_SQL_TEXT t ON h.SESSIONID = t.SESSIONID
    WHERE h.END_TIME > NOW() - INTERVAL '24 HOURS'
    AND h.CPU_TIME > 0
    ORDER BY h.CPU_TIME DESC
    LIMIT ${TOP_QUERIES_LIMIT};" "CPU Intensive Queries (24h)"
    
    # Lock information
    print_section "Current Lock Information"
    execute_sql "
    SELECT 
        l.SESSIONID,
        l.USERNAME,
        l.DBNAME,
        l.OBJNAME,
        l.LOCKTYPE,
        l.LOCKMODE,
        ROUND(EXTRACT(EPOCH FROM (NOW() - l.GRANTED_TIME))/60, 2) AS LOCK_MINUTES
    FROM _V_LOCK l
    WHERE l.GRANTED_TIME IS NOT NULL
    ORDER BY LOCK_MINUTES DESC;" "Active Locks"
}

#=============================================================================
# Interactive SQL Analysis
#=============================================================================

interactive_explain_plan() {
    print_header "INTERACTIVE SQL ANALYSIS"
    
    echo -e "${CYAN}Available options:${NC}"
    echo "1. Generate explain plan for a specific session"
    echo "2. Analyze SQL from query history"
    echo "3. Enter custom SQL for analysis"
    echo "4. Return to main menu"
    echo ""
    
    read -p "Choose an option (1-4): " choice
    
    case $choice in
        1)
            analyze_session_sql
            ;;
        2)
            analyze_historical_sql
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

analyze_session_sql() {
    echo ""
    read -p "Enter Session ID: " session_id
    
    if [[ ! "$session_id" =~ ^[0-9]+$ ]]; then
        print_error "Invalid session ID"
        return
    fi
    
    print_section "Session Information"
    execute_sql "
    SELECT 
        s.SESSIONID,
        s.USERNAME,
        s.DBNAME,
        s.STATE,
        s.CLIENT_IP,
        ROUND(EXTRACT(EPOCH FROM (NOW() - s.LOGON_TIME))/3600, 2) AS SESSION_HOURS,
        ROUND(EXTRACT(EPOCH FROM (NOW() - COALESCE(s.QUERY_START_TIME, s.LOGON_TIME)))/60, 2) AS QUERY_MINUTES
    FROM _V_SESSION s
    WHERE s.SESSIONID = ${session_id};" "Session ${session_id} Details"
    
    print_section "Current/Last SQL Statement"
    execute_sql "
    SELECT SQL 
    FROM _V_SQL_TEXT 
    WHERE SESSIONID = ${session_id};" "SQL Text for Session ${session_id}"
    
    # Generate explain plan
    echo ""
    read -p "Generate explain plan for this SQL? (y/n): " generate_plan
    
    if [[ "$generate_plan" =~ ^[Yy] ]]; then
        generate_explain_plan_for_session "$session_id"
    fi
}

analyze_historical_sql() {
    print_section "Recent Query History"
    execute_sql "
    SELECT 
        h.SESSIONID,
        h.USERNAME,
        h.DBNAME,
        ROUND(h.ELAPSED_TIME/1000000, 2) AS ELAPSED_SECONDS,
        h.MEMORY_USAGE_BYTES/1024/1024 AS MEMORY_MB,
        SUBSTR(t.SQL, 1, 80) AS SQL_PREVIEW
    FROM _V_QRYHIST h
    JOIN _V_SQL_TEXT t ON h.SESSIONID = t.SESSIONID
    WHERE h.END_TIME > NOW() - INTERVAL '24 HOURS'
    ORDER BY h.END_TIME DESC
    LIMIT 20;" "Recent Query History"
    
    echo ""
    read -p "Enter Session ID to analyze: " session_id
    
    if [[ ! "$session_id" =~ ^[0-9]+$ ]]; then
        print_error "Invalid session ID"
        return
    fi
    
    generate_explain_plan_for_session "$session_id"
}

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
    
    # Create a temporary file with the SQL
    temp_sql_file=$(mktemp)
    echo "$sql_statement" > "$temp_sql_file"
    
    print_section "Explain Plan Analysis"
    $NZSQL_CMD -c "EXPLAIN VERBOSE $sql_statement"
    
    analyze_sql_for_issues "$sql_statement"
    
    rm -f "$temp_sql_file"
}

generate_explain_plan_for_session() {
    local session_id="$1"
    
    # Get the SQL for this session
    sql_text=$($NZSQL_CMD -t -c "SELECT SQL FROM _V_SQL_TEXT WHERE SESSIONID = ${session_id};" 2>/dev/null | head -1)
    
    if [[ -z "$sql_text" || "$sql_text" == *"0 rows"* ]]; then
        print_error "No SQL found for session $session_id"
        return
    fi
    
    print_section "Detailed Explain Plan"
    echo "SQL: $sql_text"
    echo ""
    
    # Generate explain plan
    $NZSQL_CMD -c "EXPLAIN VERBOSE $sql_text" 2>/dev/null
    
    analyze_sql_for_issues "$sql_text"
}

analyze_sql_for_issues() {
    local sql="$1"
    
    print_section "SQL Analysis and Recommendations"
    
    # Convert SQL to uppercase for pattern matching
    sql_upper=$(echo "$sql" | tr '[:lower:]' '[:upper:]')
    
    # Check for potential issues
    issues_found=0
    
    # Large table joins
    if echo "$sql_upper" | grep -q "JOIN.*_FACT\|JOIN.*_LARGE\|JOIN.*_BIG"; then
        print_warning "Potential large table join detected"
        echo "  - Consider using appropriate distribution keys"
        echo "  - Verify join conditions are on distribution keys"
        issues_found=$((issues_found + 1))
    fi
    
    # Missing WHERE clause on large tables
    if echo "$sql_upper" | grep -q "FROM.*_FACT\|FROM.*_LARGE" && ! echo "$sql_upper" | grep -q "WHERE"; then
        print_warning "Query on large table without WHERE clause"
        echo "  - Consider adding appropriate filters"
        echo "  - This may result in full table scan"
        issues_found=$((issues_found + 1))
    fi
    
    # SELECT * usage
    if echo "$sql_upper" | grep -q "SELECT \*"; then
        print_warning "SELECT * detected"
        echo "  - Consider selecting only required columns"
        echo "  - This may impact network and memory usage"
        issues_found=$((issues_found + 1))
    fi
    
    # ORDER BY without LIMIT
    if echo "$sql_upper" | grep -q "ORDER BY" && ! echo "$sql_upper" | grep -q "LIMIT"; then
        print_warning "ORDER BY without LIMIT detected"
        echo "  - This may cause expensive sort operations"
        echo "  - Consider adding LIMIT if appropriate"
        issues_found=$((issues_found + 1))
    fi
    
    # Subqueries
    if echo "$sql_upper" | grep -q "SELECT.*SELECT"; then
        print_warning "Nested subqueries detected"
        echo "  - Consider using CTEs (WITH clauses) for better readability"
        echo "  - Verify subquery performance"
        issues_found=$((issues_found + 1))
    fi
    
    if [[ $issues_found -eq 0 ]]; then
        print_success "No obvious performance issues detected"
    else
        echo -e "\n${PURPLE}Total potential issues found: $issues_found${NC}"
    fi
}

#=============================================================================
# Main Menu and Program Flow
#=============================================================================

show_main_menu() {
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    NETEZZA PERFORMANCE AUTOMATION TOOL                      ║${NC}"
    echo -e "${GREEN}║                              Version 1.0                                    ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Main Options:${NC}"
    echo "1. Netezza System State Analysis"
    echo "2. Linux OS Performance Monitoring"
    echo "3. Active Sessions and SQL Analysis"
    echo "4. Query Performance Analysis"
    echo "5. Interactive SQL Explain Plan Analysis"
    echo "6. Run Complete System Check (All Above)"
    echo "7. Configuration Settings"
    echo "8. View Log File"
    echo "9. Exit"
    echo ""
    echo -e "${YELLOW}Current Settings:${NC}"
    echo "  - Host: $NETEZZA_HOST"
    echo "  - Database: $NETEZZA_DB"
    echo "  - User: $NETEZZA_USER"
    echo "  - Long Query Threshold: $LONG_RUNNING_QUERY_HOURS hours"
    echo "  - Log File: $LOG_FILE"
    echo ""
}

configure_settings() {
    print_header "CONFIGURATION SETTINGS"
    
    echo "Current configuration:"
    echo "1. Netezza Host: $NETEZZA_HOST"
    echo "2. Database: $NETEZZA_DB"
    echo "3. User: $NETEZZA_USER"
    echo "4. Long Running Query Threshold: $LONG_RUNNING_QUERY_HOURS hours"
    echo "5. Top Sessions Limit: $TOP_SESSIONS_LIMIT"
    echo "6. Top Queries Limit: $TOP_QUERIES_LIMIT"
    echo ""
    
    read -p "Which setting would you like to change (1-6, or press Enter to return)? " setting_choice
    
    case $setting_choice in
        1)
            read -p "Enter new Netezza host: " new_host
            NETEZZA_HOST="$new_host"
            NZSQL_CMD="nzsql -host ${NETEZZA_HOST} -db ${NETEZZA_DB} -u ${NETEZZA_USER}"
            ;;
        2)
            read -p "Enter new database: " new_db
            NETEZZA_DB="$new_db"
            NZSQL_CMD="nzsql -host ${NETEZZA_HOST} -db ${NETEZZA_DB} -u ${NETEZZA_USER}"
            ;;
        3)
            read -p "Enter new username: " new_user
            NETEZZA_USER="$new_user"
            NZSQL_CMD="nzsql -host ${NETEZZA_HOST} -db ${NETEZZA_DB} -u ${NETEZZA_USER}"
            ;;
        4)
            read -p "Enter new long running query threshold (hours): " new_threshold
            if [[ "$new_threshold" =~ ^[0-9]+$ ]]; then
                LONG_RUNNING_QUERY_HOURS="$new_threshold"
            else
                print_error "Invalid threshold value"
            fi
            ;;
        5)
            read -p "Enter new top sessions limit: " new_limit
            if [[ "$new_limit" =~ ^[0-9]+$ ]]; then
                TOP_SESSIONS_LIMIT="$new_limit"
            else
                print_error "Invalid limit value"
            fi
            ;;
        6)
            read -p "Enter new top queries limit: " new_limit
            if [[ "$new_limit" =~ ^[0-9]+$ ]]; then
                TOP_QUERIES_LIMIT="$new_limit"
            else
                print_error "Invalid limit value"
            fi
            ;;
        "")
            return
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
    
    print_success "Configuration updated successfully"
    read -p "Press Enter to continue..."
}

view_log_file() {
    if [[ -f "$LOG_FILE" ]]; then
        echo -e "${CYAN}Last 50 lines of log file: $LOG_FILE${NC}"
        echo "============================================================"
        tail -50 "$LOG_FILE"
        echo "============================================================"
    else
        print_warning "Log file not found: $LOG_FILE"
    fi
    read -p "Press Enter to continue..."
}

run_complete_check() {
    print_header "COMPLETE SYSTEM CHECK STARTING"
    echo "This will run all system checks. This may take several minutes..."
    echo ""
    read -p "Continue? (y/n): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        return
    fi
    
    check_netezza_system_state
    check_os_performance
    check_active_sessions
    check_query_performance
    
    print_header "COMPLETE SYSTEM CHECK FINISHED"
    print_success "All checks completed successfully!"
    echo "Log file: $LOG_FILE"
    read -p "Press Enter to continue..."
}

test_connection() {
    print_section "Testing Netezza Connection"
    echo "Connecting to: $NETEZZA_HOST/$NETEZZA_DB as $NETEZZA_USER"
    
    if execute_sql "SELECT CURRENT_TIMESTAMP;" "Connection Test"; then
        print_success "Connection successful!"
        return 0
    else
        print_error "Connection failed!"
        echo "Please check your connection settings and credentials."
        return 1
    fi
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
                check_netezza_system_state
                read -p "Press Enter to continue..."
                ;;
            2)
                check_os_performance
                read -p "Press Enter to continue..."
                ;;
            3)
                check_active_sessions
                read -p "Press Enter to continue..."
                ;;
            4)
                check_query_performance
                read -p "Press Enter to continue..."
                ;;
            5)
                interactive_explain_plan
                ;;
            6)
                run_complete_check
                ;;
            7)
                configure_settings
                ;;
            8)
                view_log_file
                ;;
            9)
                print_success "Thank you for using Netezza Performance Automation Tool!"
                exit 0
                ;;
            *)
                print_error "Invalid option. Please choose 1-9."
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi