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
NZSQL_PATH="${NZSQL_PATH:-nzsql}"  # Allow custom nzsql path
NZSQL_CMD="$NZSQL_PATH -host ${NETEZZA_HOST} -db ${NETEZZA_DB} -u ${NETEZZA_USER}"

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

#=============================================================================
# System Discovery Functions
#=============================================================================

discover_system_views() {
    print_header "NETEZZA SYSTEM VIEWS DISCOVERY"
    
    print_section "Available System Views"
    echo "Discovering available system views and tables..."
    
    # Check for different possible system view patterns
    local view_patterns=("_V_%" "_T_%" "V_%" "T_%")
    local found_views=()
    
    for pattern in "${view_patterns[@]}"; do
        print_section "Checking pattern: $pattern"
        if execute_sql "
        SELECT VIEWNAME 
        FROM _V_VIEW 
        WHERE VIEWNAME LIKE '$pattern' 
        ORDER BY VIEWNAME;" "System Views matching $pattern" true; then
            found_views+=("$pattern")
        elif execute_sql "
        SELECT TABLE_NAME 
        FROM INFORMATION_SCHEMA.TABLES 
        WHERE TABLE_NAME LIKE '$pattern' 
        ORDER BY TABLE_NAME;" "System Tables matching $pattern" true; then
            found_views+=("$pattern")
        elif execute_sql "
        SELECT TABLENAME 
        FROM _T_TABLE 
        WHERE TABLENAME LIKE '$pattern' 
        ORDER BY TABLENAME;" "System Objects matching $pattern" true; then
            found_views+=("$pattern")
        fi
    done
    
    # Try common system views individually
    print_section "Testing Common System Views"
    local common_views=(
        "_V_SESSION" "_V_SYSTEM_STATE" "_V_DATABASE" "_V_DISK" "_V_HOST"
        "_V_QRYHIST" "_V_SQL_TEXT" "_V_LOCK" "_V_SYSTEM_CONFIG"
        "_V_CPU" "_V_SCSI_ERRORS" "_V_DISKENCLOSURE" "_V_SPA" "_V_CONNECTION"
        "_V_BACKUP_HISTORY" "_V_AUTHENTICATION_SETTINGS" "_V_SCHEMA"
        "V_SESSION" "V_SYSTEM_STATE" "V_DATABASE" "V_DISK" "V_HOST"
        "_T_SESSION" "_T_SYSTEM_STATE" "_T_DATABASE" "_T_DISK" "_T_HOST"
    )
    
    local available_views=()
    local unavailable_views=()
    
    for view in "${common_views[@]}"; do
        echo -n "Testing $view... "
        if execute_sql "SELECT COUNT(*) FROM $view LIMIT 1;" "Test $view" false; then
            echo -e "${GREEN}✓ Available${NC}"
            available_views+=("$view")
        else
            echo -e "${RED}✗ Not available${NC}"
            unavailable_views+=("$view")
        fi
    done
    
    # Now check column structures for available views
    print_section "Column Structure Analysis for Available Views"
    
    for view in "${available_views[@]}"; do
        print_section "Columns in $view"
        
        # Try different methods to get column information
        if execute_sql "
        SELECT ATTNAME, ATTTYPMOD 
        FROM _V_ATTRIBUTE 
        WHERE OBJNAME = '$view' 
        ORDER BY ATTNAME;" "Columns in $view (Method 1)" false; then
            continue
        elif execute_sql "
        SELECT COLUMN_NAME, DATA_TYPE 
        FROM INFORMATION_SCHEMA.COLUMNS 
        WHERE TABLE_NAME = '$view' 
        ORDER BY COLUMN_NAME;" "Columns in $view (Method 2)" false; then
            continue
        else
            # Fallback: try to select * with limit 0 to see column names
            echo "Attempting to get column structure for $view..."
            $NZSQL_CMD -c "SELECT * FROM $view LIMIT 0;" 2>/dev/null | head -5
        fi
    done
    
    # Specific column checks for key views
    print_section "Key Column Availability Check"
    
    check_view_columns "_V_DATABASE" "DATABASE OWNER CREATEDATE USED_BYTES SKEW"
    check_view_columns "_V_DISK" "HOST FILESYSTEM TOTAL_BYTES USED_BYTES FREE_BYTES READS_PER_SEC WRITES_PER_SEC"
    check_view_columns "_V_SESSION" "SESSIONID USERNAME DBNAME STATE CLIENT_IP LOGON_TIME QUERY_START_TIME PRIORITY"
    check_view_columns "_V_QRYHIST" "SESSIONID USERNAME DBNAME START_TIME END_TIME ELAPSED_TIME CPU_TIME MEMORY_USAGE_BYTES STATUS ERROR_CODE ERROR_MESSAGE"
    check_view_columns "_V_CPU" "HOST CPU_NUMBER CPU_TYPE CPU_SPEED_MHZ CPU_UTILIZATION_PCT"
    
    print_section "System Catalog Information"
    # Try different ways to get system catalog info
    execute_sql "SELECT VERSION();" "Database Version" true
    execute_sql "SELECT CURRENT_USER, CURRENT_DATABASE, CURRENT_TIMESTAMP;" "Current Connection Info" true
}

check_view_columns() {
    local view_name="$1"
    local expected_columns="$2"
    
    echo ""
    echo -e "${YELLOW}Checking columns in $view_name...${NC}"
    
    # Check if view exists first
    if ! execute_sql "SELECT COUNT(*) FROM $view_name LIMIT 1;" "Test $view_name existence" false; then
        echo -e "${RED}✗ View $view_name not available${NC}"
        return
    fi
    
    echo -e "${GREEN}✓ View $view_name is available${NC}"
    
    # Get actual column structure
    echo "Actual columns in $view_name:"
    if execute_sql "
    SELECT ATTNAME 
    FROM _V_ATTRIBUTE 
    WHERE OBJNAME = '$view_name' 
    ORDER BY ATTNAME;" "Get columns for $view_name" false; then
        echo ""
    else
        # Fallback method
        echo "Using fallback method to check columns..."
        $NZSQL_CMD -c "SELECT * FROM $view_name LIMIT 0;" 2>/dev/null
    fi
    
    # Check specific expected columns
    echo -e "${CYAN}Checking expected columns:${NC}"
    for column in $expected_columns; do
        echo -n "  Testing column $column... "
        if execute_sql "SELECT $column FROM $view_name LIMIT 1;" "Test column $column" false; then
            echo -e "${GREEN}✓ Available${NC}"
        else
            echo -e "${RED}✗ Not available${NC}"
        fi
    done
}

check_nzsql_availability() {
    print_section "Checking nzsql availability"
    
    # Check if nzsql is available
    if ! command -v "$NZSQL_PATH" &> /dev/null; then
        print_error "nzsql command not found at: $NZSQL_PATH"
        echo ""
        echo "Common nzsql locations:"
        echo "  - /nz/bin/nzsql"
        echo "  - /opt/nz/bin/nzsql"
        echo "  - /usr/local/bin/nzsql"
        echo ""
        echo "Please set the correct path using:"
        echo "  export NZSQL_PATH=/path/to/nzsql"
        echo "  or update the configuration in this script"
        return 1
    fi
    
    print_success "nzsql found at: $NZSQL_PATH"
    return 0
}

# Function to check if a column exists in a view
column_exists() {
    local view_name="$1"
    local column_name="$2"
    
    execute_sql "SELECT $column_name FROM $view_name LIMIT 1;" "Test column $column_name in $view_name" false
    return $?
}

# Function to build safe SQL with available columns
build_safe_sql() {
    local view_name="$1"
    local base_columns="$2"
    local optional_columns="$3"
    
    local safe_columns=""
    local available_columns=""
    
    # Check base columns (required)
    for column in $base_columns; do
        if column_exists "$view_name" "$column"; then
            if [[ -n "$available_columns" ]]; then
                available_columns="$available_columns, $column"
            else
                available_columns="$column"
            fi
        else
            print_warning "Required column $column not found in $view_name"
        fi
    done
    
    # Check optional columns
    for column in $optional_columns; do
        if column_exists "$view_name" "$column"; then
            if [[ -n "$available_columns" ]]; then
                available_columns="$available_columns, $column"
            else
                available_columns="$column"
            fi
        fi
    done
    
    echo "$available_columns"
}

# Function to execute SQL with column validation
execute_safe_sql() {
    local view_name="$1"
    local sql_template="$2"
    local description="$3"
    local show_errors="${4:-false}"
    
    # Simple column existence check by trying the query first
    if execute_sql "$sql_template" "$description" "$show_errors"; then
        return 0
    else
        print_warning "Query failed for $view_name - possibly due to missing columns"
        print_warning "Attempting with basic columns only..."
        
        # Try a basic fallback query
        local basic_sql="SELECT * FROM $view_name LIMIT 5"
        execute_sql "$basic_sql" "$description (Basic Fallback)" "$show_errors"
        return $?
    fi
}

#=============================================================================
# System State Checks
#=============================================================================

check_netezza_system_state() {
    print_header "NETEZZA SYSTEM STATE ANALYSIS"
    
    # Basic system information
    print_section "Basic System Information"
    execute_sql "SELECT VERSION();" "Database Version" true
    execute_sql "SELECT CURRENT_USER, CURRENT_DATABASE, CURRENT_TIMESTAMP;" "Current Connection" true
    
    # Database information with safe column checking
    print_section "Database Information"
    if column_exists "_V_DATABASE" "DATABASE" && column_exists "_V_DATABASE" "OWNER"; then
        local db_sql="SELECT DATABASE, OWNER"
        
        if column_exists "_V_DATABASE" "CREATEDATE"; then
            db_sql="$db_sql, CREATEDATE"
        fi
        
        if column_exists "_V_DATABASE" "USED_BYTES"; then
            db_sql="$db_sql, ROUND(USED_BYTES/1024/1024/1024, 2) AS USED_GB"
        fi
        
        if column_exists "_V_DATABASE" "SKEW"; then
            db_sql="$db_sql, ROUND(SKEW/100.0, 2) AS SKEW_PCT"
        fi
        
        db_sql="$db_sql FROM _V_DATABASE ORDER BY DATABASE"
        execute_sql "$db_sql" "Database Information"
    else
        execute_safe_sql "_V_DATABASE" "SELECT * FROM _V_DATABASE LIMIT 10" "Database Information (Basic)"
    fi
    
    # Disk usage with safe column checking
    print_section "Disk Usage Information"
    if column_exists "_V_DISK" "HOST"; then
        local disk_sql="SELECT HOST"
        
        if column_exists "_V_DISK" "FILESYSTEM"; then
            disk_sql="$disk_sql, FILESYSTEM"
        fi
        
        if column_exists "_V_DISK" "TOTAL_BYTES"; then
            disk_sql="$disk_sql, ROUND(TOTAL_BYTES/1024/1024/1024, 2) AS TOTAL_GB"
        fi
        
        if column_exists "_V_DISK" "USED_BYTES"; then
            disk_sql="$disk_sql, ROUND(USED_BYTES/1024/1024/1024, 2) AS USED_GB"
        fi
        
        if column_exists "_V_DISK" "FREE_BYTES"; then
            disk_sql="$disk_sql, ROUND(FREE_BYTES/1024/1024/1024, 2) AS FREE_GB"
        fi
        
        if column_exists "_V_DISK" "USED_BYTES" && column_exists "_V_DISK" "TOTAL_BYTES"; then
            disk_sql="$disk_sql, ROUND((USED_BYTES*100.0/TOTAL_BYTES), 2) AS USED_PCT"
        fi
        
        disk_sql="$disk_sql FROM _V_DISK ORDER BY HOST"
        execute_sql "$disk_sql" "Disk Usage Analysis"
        
        # Summary by host if possible
        if column_exists "_V_DISK" "HOST" && column_exists "_V_DISK" "TOTAL_BYTES"; then
            execute_sql "
            SELECT 
                HOST,
                COUNT(*) AS DISK_COUNT,
                ROUND(SUM(TOTAL_BYTES)/1024/1024/1024, 2) AS TOTAL_GB_ALL,
                ROUND(SUM(USED_BYTES)/1024/1024/1024, 2) AS USED_GB_ALL
            FROM _V_DISK
            GROUP BY HOST
            ORDER BY HOST;" "Disk Summary by Host"
        fi
    else
        execute_safe_sql "_V_DISK" "SELECT * FROM _V_DISK LIMIT 10" "Disk Information (Basic)"
    fi
    
    # Backup information (if available)
    print_section "Recent Backup History"
    execute_safe_sql "_V_BACKUP_HISTORY" "
    SELECT 
        DATABASE,
        START_TIME,
        END_TIME,
        STATUS
    FROM _V_BACKUP_HISTORY 
    WHERE START_TIME > NOW() - INTERVAL '7 DAYS'
    ORDER BY START_TIME DESC
    LIMIT 10" "Recent Backup Activity"
    
    # Authentication settings (if available)
    print_section "Authentication Settings"
    execute_safe_sql "_V_AUTHENTICATION_SETTINGS" "
    SELECT 
        NAME,
        VALUE
    FROM _V_AUTHENTICATION_SETTINGS
    ORDER BY NAME" "Authentication Configuration"
    
    # Schema information (if available)
    print_section "Schema Summary"
    execute_safe_sql "_V_SCHEMA" "
    SELECT 
        SCHEMA,
        OWNER
    FROM _V_SCHEMA
    WHERE SCHEMA NOT LIKE 'TEMP_%'
    ORDER BY SCHEMA" "Database Schemas"
}

#=============================================================================
# Linux OS Performance Monitoring
#=============================================================================

check_os_performance() {
    print_header "LINUX OS PERFORMANCE MONITORING"
    
    print_section "CPU Performance Information"
    # CPU information with safe column checking
    if column_exists "_V_CPU" "HOST"; then
        local cpu_sql="SELECT HOST"
        
        if column_exists "_V_CPU" "CPU_NUMBER"; then
            cpu_sql="$cpu_sql, CPU_NUMBER"
        fi
        
        if column_exists "_V_CPU" "CPU_TYPE"; then
            cpu_sql="$cpu_sql, CPU_TYPE"
        fi
        
        if column_exists "_V_CPU" "CPU_SPEED_MHZ"; then
            cpu_sql="$cpu_sql, CPU_SPEED_MHZ"
        fi
        
        if column_exists "_V_CPU" "CPU_UTILIZATION_PCT"; then
            cpu_sql="$cpu_sql, CPU_UTILIZATION_PCT"
        fi
        
        cpu_sql="$cpu_sql FROM _V_CPU ORDER BY HOST"
        execute_sql "$cpu_sql" "CPU Details by Host"
    else
        execute_safe_sql "_V_CPU" "SELECT * FROM _V_CPU LIMIT 10" "CPU Information (Basic)"
    fi
    
    print_section "Disk Performance Monitoring"
    # Check what disk performance columns are available
    if column_exists "_V_DISK" "HOST"; then
        local disk_perf_sql="SELECT HOST"
        
        if column_exists "_V_DISK" "FILESYSTEM"; then
            disk_perf_sql="$disk_perf_sql, FILESYSTEM"
        fi
        
        local has_io_cols=false
        if column_exists "_V_DISK" "READS_PER_SEC"; then
            disk_perf_sql="$disk_perf_sql, READS_PER_SEC"
            has_io_cols=true
        fi
        
        if column_exists "_V_DISK" "WRITES_PER_SEC"; then
            disk_perf_sql="$disk_perf_sql, WRITES_PER_SEC"
            has_io_cols=true
        fi
        
        if column_exists "_V_DISK" "READ_KB_PER_SEC"; then
            disk_perf_sql="$disk_perf_sql, ROUND(READ_KB_PER_SEC, 2) AS READ_KB_SEC"
        fi
        
        if column_exists "_V_DISK" "WRITE_KB_PER_SEC"; then
            disk_perf_sql="$disk_perf_sql, ROUND(WRITE_KB_PER_SEC, 2) AS WRITE_KB_SEC"
        fi
        
        if column_exists "_V_DISK" "UTILIZATION_PCT"; then
            disk_perf_sql="$disk_perf_sql, ROUND(UTILIZATION_PCT, 2) AS UTIL_PCT"
        fi
        
        disk_perf_sql="$disk_perf_sql FROM _V_DISK"
        
        if $has_io_cols; then
            disk_perf_sql="$disk_perf_sql WHERE (READS_PER_SEC > 0 OR WRITES_PER_SEC > 0)"
        fi
        
        disk_perf_sql="$disk_perf_sql ORDER BY HOST LIMIT 20"
        execute_sql "$disk_perf_sql" "Disk I/O Performance"
    else
        print_warning "Disk performance monitoring not available"
    fi
    
    print_section "Hardware Error Monitoring"
    # SCSI errors (if available)
    execute_safe_sql "_V_SCSI_ERRORS" "
    SELECT 
        HOST,
        DEVICE,
        ERROR_COUNT
    FROM _V_SCSI_ERRORS
    WHERE ERROR_COUNT > 0
    ORDER BY ERROR_COUNT DESC
    LIMIT 10" "SCSI Hardware Errors"
    
    print_section "System Hardware Status"
    # Disk enclosure information (if available)
    execute_safe_sql "_V_DISKENCLOSURE" "
    SELECT 
        HOST,
        ENCLOSURE_ID,
        STATUS
    FROM _V_DISKENCLOSURE
    ORDER BY HOST, ENCLOSURE_ID
    LIMIT 20" "Disk Enclosure Health"
    
    print_section "System Performance Analysis"
    # SPA data (if available)
    execute_safe_sql "_V_SPA" "
    SELECT 
        HOST,
        TIMESTAMP,
        METRIC_NAME,
        METRIC_VALUE
    FROM _V_SPA
    WHERE TIMESTAMP > NOW() - INTERVAL '1 HOUR'
    ORDER BY TIMESTAMP DESC, HOST
    LIMIT 20" "Recent System Performance Metrics"
    
    print_section "Connection Information"
    # Active connections (if available)
    execute_safe_sql "_V_CONNECTION" "
    SELECT 
        HOST,
        COUNT(*) AS CONNECTION_COUNT
    FROM _V_CONNECTION
    GROUP BY HOST
    ORDER BY CONNECTION_COUNT DESC" "System Connections Summary"
}

#=============================================================================
# Session and SQL Monitoring
#=============================================================================

check_active_sessions() {
    print_header "ACTIVE SESSIONS AND SQL ANALYSIS"
    
    # Build safe session query based on available columns
    print_section "Active Sessions Analysis"
    
    if column_exists "_V_SESSION" "SESSIONID" && column_exists "_V_SESSION" "USERNAME"; then
        local session_sql="SELECT SESSIONID, USERNAME"
        
        if column_exists "_V_SESSION" "DBNAME"; then
            session_sql="$session_sql, DBNAME"
        fi
        
        if column_exists "_V_SESSION" "STATE"; then
            session_sql="$session_sql, STATE"
        fi
        
        if column_exists "_V_SESSION" "CLIENT_IP"; then
            session_sql="$session_sql, CLIENT_IP"
        fi
        
        if column_exists "_V_SESSION" "LOGON_TIME"; then
            session_sql="$session_sql, LOGON_TIME"
            session_sql="$session_sql, ROUND(EXTRACT(EPOCH FROM (NOW() - LOGON_TIME))/3600, 2) AS SESSION_HOURS"
        fi
        
        if column_exists "_V_SESSION" "QUERY_START_TIME"; then
            session_sql="$session_sql, QUERY_START_TIME"
        fi
        
        if column_exists "_V_SESSION" "PRIORITY"; then
            session_sql="$session_sql, PRIORITY"
        fi
        
        session_sql="$session_sql FROM _V_SESSION"
        
        # Add WHERE clause if STATE column exists
        if column_exists "_V_SESSION" "STATE"; then
            session_sql="$session_sql WHERE STATE != 'idle'"
        fi
        
        session_sql="$session_sql ORDER BY SESSIONID LIMIT 20"
        execute_sql "$session_sql" "Active Sessions Overview"
        
        # Long running sessions if LOGON_TIME exists
        if column_exists "_V_SESSION" "LOGON_TIME"; then
            print_section "Long Running Sessions (> ${LONG_RUNNING_QUERY_HOURS} hours)"
            local long_session_sql="$session_sql"
            long_session_sql="${long_session_sql% ORDER BY*}" # Remove existing ORDER BY
            long_session_sql="$long_session_sql AND EXTRACT(EPOCH FROM (NOW() - LOGON_TIME))/3600 > ${LONG_RUNNING_QUERY_HOURS}"
            long_session_sql="$long_session_sql ORDER BY LOGON_TIME ASC LIMIT ${TOP_SESSIONS_LIMIT}"
            execute_sql "$long_session_sql" "Long Running Sessions"
        fi
        
        # Session state summary if STATE column exists
        if column_exists "_V_SESSION" "STATE"; then
            print_section "Session State Summary"
            execute_sql "
            SELECT 
                STATE,
                COUNT(*) AS SESSION_COUNT
            FROM _V_SESSION
            GROUP BY STATE
            ORDER BY SESSION_COUNT DESC;" "Session States"
        fi
        
        # Sessions by user
        print_section "Sessions by User"
        local user_sql="
        SELECT 
            USERNAME,
            COUNT(*) AS SESSION_COUNT"
            
        if column_exists "_V_SESSION" "STATE"; then
            user_sql="$user_sql,
            COUNT(CASE WHEN STATE = 'active' THEN 1 END) AS ACTIVE_SESSIONS,
            COUNT(CASE WHEN STATE = 'idle' THEN 1 END) AS IDLE_SESSIONS"
        fi
        
        user_sql="$user_sql
        FROM _V_SESSION
        GROUP BY USERNAME
        HAVING COUNT(*) > 1
        ORDER BY SESSION_COUNT DESC"
        
        execute_sql "$user_sql" "User Session Summary"
        
    else
        execute_safe_sql "_V_SESSION" "SELECT * FROM _V_SESSION LIMIT 10" "Session Information (Basic)"
    fi
}

check_query_performance() {
    print_header "QUERY PERFORMANCE ANALYSIS"
    
    # Build safe query history analysis
    if column_exists "_V_QRYHIST" "SESSIONID"; then
        print_section "Query History Analysis (Last 24 Hours)"
        
        local qry_sql="SELECT SESSIONID"
        
        if column_exists "_V_QRYHIST" "USERNAME"; then
            qry_sql="$qry_sql, USERNAME"
        fi
        
        if column_exists "_V_QRYHIST" "DBNAME"; then
            qry_sql="$qry_sql, DBNAME"
        fi
        
        if column_exists "_V_QRYHIST" "START_TIME"; then
            qry_sql="$qry_sql, START_TIME"
        fi
        
        if column_exists "_V_QRYHIST" "END_TIME"; then
            qry_sql="$qry_sql, END_TIME"
        fi
        
        if column_exists "_V_QRYHIST" "ELAPSED_TIME"; then
            qry_sql="$qry_sql, ROUND(ELAPSED_TIME/1000000, 2) AS ELAPSED_SECONDS"
        fi
        
        if column_exists "_V_QRYHIST" "STATUS"; then
            qry_sql="$qry_sql, STATUS"
        fi
        
        qry_sql="$qry_sql FROM _V_QRYHIST"
        
        # Add time filter if END_TIME exists
        if column_exists "_V_QRYHIST" "END_TIME"; then
            qry_sql="$qry_sql WHERE END_TIME > NOW() - INTERVAL '24 HOURS'"
            
            # Add elapsed time filter if available
            if column_exists "_V_QRYHIST" "ELAPSED_TIME"; then
                qry_sql="$qry_sql AND ELAPSED_TIME > ${LONG_RUNNING_QUERY_HOURS} * 3600 * 1000000"
            fi
        fi
        
        if column_exists "_V_QRYHIST" "ELAPSED_TIME"; then
            qry_sql="$qry_sql ORDER BY ELAPSED_TIME DESC"
        else
            qry_sql="$qry_sql ORDER BY SESSIONID DESC"
        fi
        
        qry_sql="$qry_sql LIMIT ${TOP_QUERIES_LIMIT}"
        execute_sql "$qry_sql" "Top Queries by Performance"
        
        # CPU analysis if CPU_TIME column exists
        if column_exists "_V_QRYHIST" "CPU_TIME" && column_exists "_V_QRYHIST" "END_TIME"; then
            print_section "CPU Intensive Queries (Last 24 Hours)"
            execute_sql "
            SELECT 
                SESSIONID,
                USERNAME,
                ROUND(ELAPSED_TIME/1000000, 2) AS ELAPSED_SECONDS,
                ROUND(CPU_TIME/1000000, 2) AS CPU_SECONDS,
                STATUS
            FROM _V_QRYHIST
            WHERE END_TIME > NOW() - INTERVAL '24 HOURS'
            AND CPU_TIME > 0
            ORDER BY CPU_TIME DESC
            LIMIT ${TOP_QUERIES_LIMIT};" "CPU Intensive Queries"
        fi
        
        # Memory analysis if MEMORY_USAGE_BYTES exists
        if column_exists "_V_QRYHIST" "MEMORY_USAGE_BYTES" && column_exists "_V_QRYHIST" "END_TIME"; then
            print_section "Memory Intensive Queries (Last 24 Hours)"
            execute_sql "
            SELECT 
                SESSIONID,
                USERNAME,
                ROUND(ELAPSED_TIME/1000000, 2) AS ELAPSED_SECONDS,
                ROUND(MEMORY_USAGE_BYTES/1024/1024, 2) AS MEMORY_MB,
                STATUS
            FROM _V_QRYHIST
            WHERE END_TIME > NOW() - INTERVAL '24 HOURS'
            AND MEMORY_USAGE_BYTES > 0
            ORDER BY MEMORY_USAGE_BYTES DESC
            LIMIT ${TOP_QUERIES_LIMIT};" "Memory Intensive Queries"
        fi
        
        # Summary statistics
        print_section "Query Performance Summary (Last 24 Hours)"
        local summary_sql="SELECT COUNT(*) AS TOTAL_QUERIES"
        
        if column_exists "_V_QRYHIST" "ELAPSED_TIME"; then
            summary_sql="$summary_sql, ROUND(AVG(ELAPSED_TIME/1000000), 2) AS AVG_ELAPSED_SEC"
            summary_sql="$summary_sql, ROUND(MAX(ELAPSED_TIME/1000000), 2) AS MAX_ELAPSED_SEC"
        fi
        
        if column_exists "_V_QRYHIST" "STATUS"; then
            summary_sql="$summary_sql, COUNT(CASE WHEN STATUS = 'COMPLETED' THEN 1 END) AS COMPLETED_QUERIES"
            summary_sql="$summary_sql, COUNT(CASE WHEN STATUS = 'FAILED' THEN 1 END) AS FAILED_QUERIES"
        fi
        
        summary_sql="$summary_sql FROM _V_QRYHIST"
        
        if column_exists "_V_QRYHIST" "END_TIME"; then
            summary_sql="$summary_sql WHERE END_TIME > NOW() - INTERVAL '24 HOURS'"
        fi
        
        execute_sql "$summary_sql" "24-Hour Query Statistics"
        
        # Failed queries analysis
        if column_exists "_V_QRYHIST" "STATUS" && column_exists "_V_QRYHIST" "END_TIME"; then
            print_section "Recent Failed Queries"
            local failed_sql="
            SELECT 
                SESSIONID,
                USERNAME,
                START_TIME,
                STATUS"
                
            if column_exists "_V_QRYHIST" "ERROR_CODE"; then
                failed_sql="$failed_sql, ERROR_CODE"
            fi
            
            if column_exists "_V_QRYHIST" "ERROR_MESSAGE"; then
                failed_sql="$failed_sql, SUBSTR(ERROR_MESSAGE, 1, 100) AS ERROR_MSG"
            fi
            
            failed_sql="$failed_sql
            FROM _V_QRYHIST
            WHERE END_TIME > NOW() - INTERVAL '24 HOURS'
            AND STATUS = 'FAILED'
            ORDER BY END_TIME DESC
            LIMIT 10"
            
            execute_sql "$failed_sql" "Recent Query Failures"
        fi
        
    else
        execute_safe_sql "_V_QRYHIST" "SELECT * FROM _V_QRYHIST LIMIT 10" "Query History (Basic)"
    fi
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
        SESSIONID,
        USERNAME,
        DBNAME,
        STATE,
        CLIENT_IP,
        LOGON_TIME,
        QUERY_START_TIME,
        PRIORITY,
        ROUND(EXTRACT(EPOCH FROM (NOW() - LOGON_TIME))/3600, 2) AS SESSION_HOURS,
        CASE 
            WHEN QUERY_START_TIME IS NOT NULL THEN 
                ROUND(EXTRACT(EPOCH FROM (NOW() - QUERY_START_TIME))/60, 2)
            ELSE NULL 
        END AS QUERY_MINUTES
    FROM _V_SESSION
    WHERE SESSIONID = ${session_id};" "Session ${session_id} Details"
    
    print_section "Session Query History"
    execute_sql "
    SELECT 
        SESSIONID,
        START_TIME,
        END_TIME,
        ROUND(ELAPSED_TIME/1000000, 2) AS ELAPSED_SECONDS,
        STATUS,
        SUBSTR(ERROR_MESSAGE, 1, 100) AS ERROR_MSG
    FROM _V_QRYHIST
    WHERE SESSIONID = ${session_id}
    ORDER BY START_TIME DESC
    LIMIT 5;" "Recent Query History for Session ${session_id}"
    
    print_warning "Note: _V_SQL_TEXT is not available in your Netezza version."
    print_warning "SQL text analysis requires manual entry or query from application logs."
    
    echo ""
    read -p "Do you want to enter SQL manually for analysis? (y/n): " manual_sql
    
    if [[ "$manual_sql" =~ ^[Yy] ]]; then
        analyze_custom_sql
    fi
}

analyze_historical_sql() {
    print_section "Recent Query History"
    execute_sql "
    SELECT 
        SESSIONID,
        USERNAME,
        DBNAME,
        START_TIME,
        END_TIME,
        ROUND(ELAPSED_TIME/1000000, 2) AS ELAPSED_SECONDS,
        ROUND(MEMORY_USAGE_BYTES/1024/1024, 2) AS MEMORY_MB,
        STATUS
    FROM _V_QRYHIST
    WHERE END_TIME > NOW() - INTERVAL '24 HOURS'
    ORDER BY END_TIME DESC
    LIMIT 20;" "Recent Query History"
    
    echo ""
    echo "Note: SQL text is not available from system views in your Netezza version."
    echo "For detailed SQL analysis, you'll need to:"
    echo "1. Check application logs"
    echo "2. Use query monitoring tools"
    echo "3. Enter SQL manually for analysis"
    echo ""
    
    read -p "Enter Session ID for performance details: " session_id
    
    if [[ ! "$session_id" =~ ^[0-9]+$ ]]; then
        print_error "Invalid session ID"
        return
    fi
    
    print_section "Detailed Performance for Session $session_id"
    execute_sql "
    SELECT 
        SESSIONID,
        USERNAME,
        DBNAME,
        START_TIME,
        END_TIME,
        ROUND(ELAPSED_TIME/1000000, 2) AS ELAPSED_SECONDS,
        ROUND(COMPILE_TIME/1000000, 2) AS COMPILE_SECONDS,
        ROUND(QUEUE_TIME/1000000, 2) AS QUEUE_SECONDS,
        ROUND(CPU_TIME/1000000, 2) AS CPU_SECONDS,
        ROUND(MEMORY_USAGE_BYTES/1024/1024, 2) AS MEMORY_MB,
        ROWS_INSERTED,
        ROWS_UPDATED,
        ROWS_DELETED,
        ROWS_RETURNED,
        STATUS,
        ERROR_CODE,
        SUBSTR(ERROR_MESSAGE, 1, 200) AS ERROR_MESSAGE
    FROM _V_QRYHIST
    WHERE SESSIONID = ${session_id}
    ORDER BY START_TIME DESC;" "Performance Details for Session ${session_id}"
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
    
    print_warning "SQL text retrieval not available from system views."
    print_warning "To generate explain plan, you need to provide the SQL statement manually."
    
    echo ""
    read -p "Do you want to enter the SQL statement manually? (y/n): " manual_entry
    
    if [[ "$manual_entry" =~ ^[Yy] ]]; then
        analyze_custom_sql
    else
        print_section "Performance Summary for Session $session_id"
        execute_sql "
        SELECT 
            'Performance summary without SQL text' AS NOTE,
            SESSIONID,
            USERNAME,
            DBNAME,
            ROUND(ELAPSED_TIME/1000000, 2) AS ELAPSED_SECONDS,
            ROUND(MEMORY_USAGE_BYTES/1024/1024, 2) AS MEMORY_MB,
            STATUS
        FROM _V_QRYHIST
        WHERE SESSIONID = ${session_id}
        ORDER BY START_TIME DESC
        LIMIT 1;" "Session Performance Summary"
    fi
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
    echo "1. Discover Available System Views (Run this first!)"
    echo "2. Netezza System State Analysis"
    echo "3. Linux OS Performance Monitoring"
    echo "4. Active Sessions and SQL Analysis"
    echo "5. Query Performance Analysis"
    echo "6. Interactive SQL Explain Plan Analysis"
    echo "7. Run Complete System Check (Options 2-5)"
    echo "8. Configuration Settings"
    echo "9. View Log File"
    echo "10. Exit"
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
    echo "1. nzsql Path: $NZSQL_PATH"
    echo "2. Netezza Host: $NETEZZA_HOST"
    echo "3. Database: $NETEZZA_DB"
    echo "4. User: $NETEZZA_USER"
    echo "5. Long Running Query Threshold: $LONG_RUNNING_QUERY_HOURS hours"
    echo "6. Top Sessions Limit: $TOP_SESSIONS_LIMIT"
    echo "7. Top Queries Limit: $TOP_QUERIES_LIMIT"
    echo ""
    
    read -p "Which setting would you like to change (1-7, or press Enter to return)? " setting_choice
    
    case $setting_choice in
        1)
            read -p "Enter full path to nzsql: " new_path
            NZSQL_PATH="$new_path"
            NZSQL_CMD="$NZSQL_PATH -host ${NETEZZA_HOST} -db ${NETEZZA_DB} -u ${NETEZZA_USER}"
            ;;
        2)
            read -p "Enter new Netezza host: " new_host
            NETEZZA_HOST="$new_host"
            NZSQL_CMD="$NZSQL_PATH -host ${NETEZZA_HOST} -db ${NETEZZA_DB} -u ${NETEZZA_USER}"
            ;;
        3)
            read -p "Enter new database: " new_db
            NETEZZA_DB="$new_db"
            NZSQL_CMD="$NZSQL_PATH -host ${NETEZZA_HOST} -db ${NETEZZA_DB} -u ${NETEZZA_USER}"
            ;;
        4)
            read -p "Enter new username: " new_user
            NETEZZA_USER="$new_user"
            NZSQL_CMD="$NZSQL_PATH -host ${NETEZZA_HOST} -db ${NETEZZA_DB} -u ${NETEZZA_USER}"
            ;;
        5)
            read -p "Enter new long running query threshold (hours): " new_threshold
            if [[ "$new_threshold" =~ ^[0-9]+$ ]]; then
                LONG_RUNNING_QUERY_HOURS="$new_threshold"
            else
                print_error "Invalid threshold value"
            fi
            ;;
        6)
            read -p "Enter new top sessions limit: " new_limit
            if [[ "$new_limit" =~ ^[0-9]+$ ]]; then
                TOP_SESSIONS_LIMIT="$new_limit"
            else
                print_error "Invalid limit value"
            fi
            ;;
        7)
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
    echo "This will run all system checks (options 2-5). This may take several minutes..."
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
    
    # First check if nzsql is available
    if ! check_nzsql_availability; then
        return 1
    fi
    
    echo "Connecting to: $NETEZZA_HOST/$NETEZZA_DB as $NETEZZA_USER"
    echo "Using nzsql at: $NZSQL_PATH"
    
    if execute_sql "SELECT CURRENT_TIMESTAMP;" "Connection Test" true; then
        print_success "Connection successful!"
        return 0
    else
        print_error "Connection failed!"
        echo ""
        echo "Possible issues:"
        echo "1. Check nzsql path: $NZSQL_PATH"
        echo "2. Verify connection parameters (host, database, user)"
        echo "3. Ensure network connectivity to Netezza host"
        echo "4. Check if authentication is required (password prompt)"
        echo ""
        echo "Try running manually:"
        echo "$NZSQL_CMD -c 'SELECT CURRENT_TIMESTAMP;'"
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
                discover_system_views
                read -p "Press Enter to continue..."
                ;;
            2)
                check_netezza_system_state
                read -p "Press Enter to continue..."
                ;;
            3)
                check_os_performance
                read -p "Press Enter to continue..."
                ;;
            4)
                check_active_sessions
                read -p "Press Enter to continue..."
                ;;
            5)
                check_query_performance
                read -p "Press Enter to continue..."
                ;;
            6)
                interactive_explain_plan
                ;;
            7)
                run_complete_check
                ;;
            8)
                configure_settings
                ;;
            9)
                view_log_file
                ;;
            10)
                print_success "Thank you for using Netezza Performance Automation Tool!"
                exit 0
                ;;
            *)
                print_error "Invalid option. Please choose 1-10."
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi