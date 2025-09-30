#!/bin/bash

#=============================================================================
# Netezza Performance Automation Tool
# Version: 1.0
# Date: September 29, 2025
# Description: Automated system checks for Netezza 11.2.1.13
# Author: Database Administrator
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
    
    check_view_columns "_V_DATABASE" "DATABASE OWNER CREATEDATE OBJID"
    check_view_columns "_V_DISK" "HW_HWID HW_ROLE HW_DISKSZ HW_DISKMODEL HW_STATE"
    check_view_columns "_V_SESSION" "ID USERNAME DBNAME STATUS IPADDR CONNTIME PRIORITY"
    check_view_columns "_V_QRYHIST" "QH_SESSIONID QH_USER QH_DATABASE QH_TSUBMIT QH_TSTART QH_TEND QH_SQL QH_PRIORITY"
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
    
    # Database information with correct column names
    print_section "Database Information"
    execute_sql "
    SELECT 
        DATABASE,
        OWNER,
        CREATEDATE,
        OBJID,
        DB_CHARSET,
        ENCODING
    FROM _V_DATABASE 
    ORDER BY DATABASE;" "Database Information"
    
    # Hardware Disk Information (not filesystem usage)
    print_section "Hardware Disk Information"
    execute_sql "
    SELECT 
        HW_HWID,
        HW_ROLE,
        HW_ROLETEXT,
        HW_DISKSZ,
        HW_DISKMODEL,
        HW_STATE,
        HW_STATETEXT
    FROM _V_DISK 
    ORDER BY HW_HWID;" "Hardware Disk Inventory"
    
    # Summary by disk state
    execute_sql "
    SELECT 
        HW_STATE,
        HW_STATETEXT,
        COUNT(*) AS DISK_COUNT
    FROM _V_DISK
    GROUP BY HW_STATE, HW_STATETEXT
    ORDER BY DISK_COUNT DESC;" "Disk Status Summary"
    
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
    
    # Active Sessions using correct column names
    print_section "Current Sessions Analysis"
    
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
    ORDER BY CONNTIME DESC;" "Current Sessions Overview"
    
    # Session status summary
    print_section "Session Status Summary"
    execute_sql "
    SELECT 
        STATUS,
        COUNT(*) AS SESSION_COUNT
    FROM _V_SESSION
    GROUP BY STATUS
    ORDER BY SESSION_COUNT DESC;" "Session Status Distribution"
    
    # Sessions by user
    print_section "Sessions by User"
    execute_sql "
    SELECT 
        USERNAME,
        COUNT(*) AS SESSION_COUNT,
        MAX(CONNTIME) AS LATEST_CONNECTION
    FROM _V_SESSION
    GROUP BY USERNAME
    ORDER BY SESSION_COUNT DESC;" "User Session Summary"
    
    # Sessions by database
    print_section "Sessions by Database"
    execute_sql "
    SELECT 
        DBNAME,
        COUNT(*) AS SESSION_COUNT,
        COUNT(DISTINCT USERNAME) AS UNIQUE_USERS
    FROM _V_SESSION
    GROUP BY DBNAME
    ORDER BY SESSION_COUNT DESC;" "Database Connection Summary"
}

check_query_performance() {
    print_header "QUERY PERFORMANCE ANALYSIS"
    
    # Query History Analysis using correct column names
    print_section "Query History Analysis"
    
    execute_sql "
    SELECT 
        QH_SESSIONID,
        QH_USER,
        QH_DATABASE,
        QH_TSUBMIT,
        QH_TSTART,
        QH_TEND,
        QH_PRIORITY,
        QH_ESTCOST,
        QH_RESROWS,
        SUBSTR(QH_SQL, 1, 100) AS SQL_PREVIEW
    FROM _V_QRYHIST
    WHERE QH_TEND > NOW() - INTERVAL '24 HOURS'
    ORDER BY QH_TEND DESC
    LIMIT ${TOP_QUERIES_LIMIT};" "Recent Query History (24h)"
    
    # Query performance by execution time
    print_section "Query Performance Analysis"
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
    AND EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)) > ${LONG_RUNNING_QUERY_HOURS} * 3600
    ORDER BY EXECUTION_SECONDS DESC
    LIMIT ${TOP_QUERIES_LIMIT};" "Long Running Queries (24h)"
    
    # Query summary statistics
    print_section "Query Statistics Summary (Last 24 Hours)"
    execute_sql "
    SELECT 
        COUNT(*) AS TOTAL_QUERIES,
        COUNT(DISTINCT QH_USER) AS UNIQUE_USERS,
        COUNT(DISTINCT QH_DATABASE) AS DATABASES_USED,
        ROUND(AVG(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART))), 2) AS AVG_EXECUTION_SEC,
        ROUND(MAX(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART))), 2) AS MAX_EXECUTION_SEC,
        ROUND(AVG(QH_ESTCOST), 2) AS AVG_EST_COST,
        ROUND(MAX(QH_ESTCOST), 2) AS MAX_EST_COST
    FROM _V_QRYHIST
    WHERE QH_TEND > NOW() - INTERVAL '24 HOURS'
    AND QH_TSTART IS NOT NULL 
    AND QH_TEND IS NOT NULL;" "24-Hour Query Statistics"
    
    # Top users by query volume
    print_section "Top Users by Query Activity"
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
    LIMIT 10;" "Top Users by Query Volume"
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
    echo "4. Use nz_plan utility (requires plan ID)"
    echo "5. Return to main menu"
    echo ""
    
    read -p "Choose an option (1-5): " choice
    
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
            use_nz_plan_utility
            ;;
        5)
            return
            ;;
        *)
            print_error "Invalid option"
            read -p "Press Enter to continue..."
            ;;
    esac
    
    # After any analysis, ask if user wants to continue or return to main menu
    echo ""
    read -p "Would you like to perform another analysis? (y/n): " continue_choice
    if [[ "$continue_choice" =~ ^[Yy] ]]; then
        interactive_explain_plan  # Recursive call to show menu again
    fi
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
    WHERE ID = ${session_id};" "Session ${session_id} Details"
    
    print_section "Session Query History"
    execute_sql "
    SELECT 
        QH_SESSIONID,
        QH_TSUBMIT,
        QH_TSTART,
        QH_TEND,
        ROUND(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)), 2) AS ELAPSED_SECONDS,
        QH_ESTCOST,
        QH_RESROWS,
        SUBSTR(QH_SQL, 1, 200) AS SQL_TEXT
    FROM _V_QRYHIST
    WHERE QH_SESSIONID = ${session_id}
    ORDER BY QH_TSUBMIT DESC
    LIMIT 5;" "Recent Query History for Session ${session_id}"
    
    print_success "SQL text is available from _V_QRYHIST.QH_SQL column!"
    
    # Get the most recent SQL for this session
    echo ""
    echo "Recent SQL statements for this session:"
    execute_sql "
    SELECT 
        QH_TSUBMIT,
        SUBSTR(QH_SQL, 1, 200) AS SQL_PREVIEW
    FROM _V_QRYHIST
    WHERE QH_SESSIONID = ${session_id}
    ORDER BY QH_TSUBMIT DESC
    LIMIT 3;" "Recent SQL for Session ${session_id}"
    
    echo ""
    read -p "Do you want to analyze the most recent SQL statement? (y/n): " analyze_sql
    
    if [[ "$analyze_sql" =~ ^[Yy] ]]; then
        # Get the full SQL text
        sql_text=$($NZSQL_CMD -t -c "SELECT QH_SQL FROM _V_QRYHIST WHERE QH_SESSIONID = ${session_id} ORDER BY QH_TSUBMIT DESC LIMIT 1;" 2>/dev/null | head -1)
        
        if [[ -n "$sql_text" && "$sql_text" != *"0 rows"* ]]; then
            print_section "SQL Analysis for Session $session_id"
            echo "SQL Statement:"
            echo "$sql_text"
            echo ""
            
            # Generate explain plan with proper context
            print_section "Explain Plan"
            
            # Get database context from session
            session_db=$($NZSQL_CMD -t -c "SELECT DBNAME FROM _V_SESSION WHERE ID = ${session_id} LIMIT 1;" 2>/dev/null | head -1 | tr -d ' ')
            if [[ -n "$session_db" ]]; then
                echo "Using session database: $session_db"
                generate_explain_plan "$sql_text" "$session_db" ""
            else
                echo "Using current database: $NETEZZA_DB"
                generate_explain_plan "$sql_text" "$NETEZZA_DB" ""
            fi
            
            analyze_sql_for_issues "$sql_text"
        else
            print_warning "Could not retrieve SQL text for session $session_id"
        fi
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_historical_sql() {
    print_section "Recent Query History"
    execute_sql "
    SELECT 
        QH_SESSIONID,
        QH_USER,
        QH_DATABASE,
        QH_TSTART,
        QH_TEND,
        ROUND(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)), 2) AS ELAPSED_SECONDS,
        QH_ESTCOST,
        QH_RESROWS
    FROM _V_QRYHIST
    WHERE QH_TEND > NOW() - INTERVAL '24 HOURS'
    ORDER BY QH_TEND DESC
    LIMIT 20;" "Recent Query History"
    
    echo ""
    print_success "SQL text is available from _V_QRYHIST.QH_SQL!"
    echo ""
    
    read -p "Enter Session ID for performance details: " session_id
    
    if [[ ! "$session_id" =~ ^[0-9]+$ ]]; then
        print_error "Invalid session ID"
        read -p "Press Enter to continue..."
        return
    fi
    
    print_section "Detailed Performance for Session $session_id"
    execute_sql "
    SELECT 
        QH_SESSIONID,
        QH_USER,
        QH_DATABASE,
        QH_TSUBMIT,
        QH_TSTART,
        QH_TEND,
        ROUND(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)), 2) AS ELAPSED_SECONDS,
        QH_PRIORITY,
        QH_ESTCOST,
        QH_ESTDISK,
        QH_ESTMEM,
        QH_SNIPPETS,
        QH_RESROWS,
        QH_RESBYTES,
        QH_PLANID,
        SUBSTR(QH_SQL, 1, 500) AS SQL_TEXT
    FROM _V_QRYHIST
    WHERE QH_SESSIONID = ${session_id}
    ORDER BY QH_TSUBMIT DESC;" "Performance Details for Session ${session_id}"
    
    # Check if plan IDs are available
    plan_id_count=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_QRYHIST WHERE QH_SESSIONID = ${session_id} AND QH_PLANID IS NOT NULL;" 2>/dev/null | head -1 | tr -d ' ')
    
    if [[ "$plan_id_count" -gt 0 ]]; then
        print_success "Plan IDs available! You can use option 4 (nz_plan utility) for detailed execution plans."
        echo "Available Plan IDs for this session:"
        execute_sql "
        SELECT 
            QH_PLANID,
            QH_TSTART,
            SUBSTR(QH_SQL, 1, 100) AS SQL_PREVIEW
        FROM _V_QRYHIST
        WHERE QH_SESSIONID = ${session_id} 
        AND QH_PLANID IS NOT NULL
        ORDER BY QH_TSTART DESC;" "Plan IDs for Session ${session_id}"
    fi
    
    # Ask if user wants to analyze the SQL
    echo ""
    read -p "Do you want to analyze the SQL from this session? (y/n): " analyze_choice
    
    if [[ "$analyze_choice" =~ ^[Yy] ]]; then
        # Get the most recent SQL for analysis
        sql_text=$($NZSQL_CMD -t -c "SELECT QH_SQL FROM _V_QRYHIST WHERE QH_SESSIONID = ${session_id} ORDER BY QH_TSUBMIT DESC LIMIT 1;" 2>/dev/null | head -1)
        
        if [[ -n "$sql_text" && "$sql_text" != *"0 rows"* ]]; then
            print_section "SQL Analysis for Session $session_id"
            echo "SQL Statement:"
            echo "$sql_text"
            echo ""
            
            # Generate explain plan
            read -p "Generate explain plan for this SQL? (y/n): " explain_choice
            if [[ "$explain_choice" =~ ^[Yy] ]]; then
                print_section "Explain Plan"
                
                # Get database context from query history
                session_db=$($NZSQL_CMD -t -c "SELECT QH_DATABASE FROM _V_QRYHIST WHERE QH_SESSIONID = ${session_id} ORDER BY QH_TSUBMIT DESC LIMIT 1;" 2>/dev/null | head -1 | tr -d ' ')
                if [[ -n "$session_db" ]]; then
                    echo "Using query database: $session_db"
                    generate_explain_plan "$sql_text" "$session_db" ""
                else
                    echo "Using current database: $NETEZZA_DB"
                    generate_explain_plan "$sql_text" "$NETEZZA_DB" ""
                fi
            fi
            
            analyze_sql_for_issues "$sql_text"
        else
            print_warning "Could not retrieve SQL text for session $session_id"
        fi
    fi
    
    echo ""
    read -p "Press Enter to continue..."
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
    
    # Ask which database/schema to use for explain plan
    echo ""
    read -p "Enter database name for EXPLAIN (or press Enter to use current: $NETEZZA_DB): " explain_db
    if [[ -z "$explain_db" ]]; then
        explain_db="$NETEZZA_DB"
    fi
    
    read -p "Enter schema name (or press Enter for default): " explain_schema
    
    # Create a temporary file with the SQL
    temp_sql_file=$(mktemp)
    echo "$sql_statement" > "$temp_sql_file"
    
    print_section "Explain Plan Analysis"
    generate_explain_plan "$sql_statement" "$explain_db" "$explain_schema"
    
    analyze_sql_for_issues "$sql_statement"
    
    rm -f "$temp_sql_file"
    
    echo ""
    read -p "Press Enter to continue..."
}

use_nz_plan_utility() {
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
        echo ""
        echo "Standard locations checked:"
        echo "  - /nz/support/contrib/bin/nz_plan"
        echo "  - /opt/nz/support/contrib/bin/nz_plan"
        echo "  - /usr/local/nz/support/contrib/bin/nz_plan"
        echo "  - /nz/bin/nz_plan"
        echo ""
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
    echo "Output file: $plan_file"
    
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
        echo ""
        echo "Error output:"
        cat "$plan_file"
        rm -f "$plan_file"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
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
            QH_SESSIONID,
            QH_USER,
            QH_DATABASE,
            ROUND(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)), 2) AS ELAPSED_SECONDS,
            QH_ESTCOST,
            QH_RESROWS,
            SUBSTR(QH_SQL, 1, 200) AS SQL_PREVIEW
        FROM _V_QRYHIST
        WHERE QH_SESSIONID = ${session_id}
        ORDER BY QH_TSUBMIT DESC
        LIMIT 1;" "Session Performance Summary"
    fi
}

# Enhanced explain plan generation with proper database/schema context
generate_explain_plan() {
    local sql="$1"
    local target_db="$2"
    local target_schema="$3"
    
    echo "Generating explain plan..."
    echo "Target Database: $target_db"
    if [[ -n "$target_schema" ]]; then
        echo "Target Schema: $target_schema"
    fi
    
    # Build connection command for target database
    local explain_cmd="$NZSQL_PATH"
    if [[ -n "$NETEZZA_HOST" ]]; then
        explain_cmd="$explain_cmd -host ${NETEZZA_HOST}"
    fi
    explain_cmd="$explain_cmd -d ${target_db} -u ${NETEZZA_USER}"
    
    # Prepare SQL with schema context if provided
    local full_sql="$sql"
    if [[ -n "$target_schema" ]]; then
        full_sql="SET SCHEMA '$target_schema'; $sql"
    fi
    
    echo ""
    echo "Method 1: Direct EXPLAIN with database context"
    echo "=============================================================="
    if $explain_cmd -c "EXPLAIN VERBOSE $full_sql" 2>/dev/null; then
        print_success "Explain plan generated successfully using direct method"
    else
        print_warning "Direct EXPLAIN failed, trying alternative approach..."
        echo ""
        echo "Method 2: Basic EXPLAIN without VERBOSE"
        echo "=============================================================="
        if $explain_cmd -c "EXPLAIN $full_sql" 2>/dev/null; then
            print_success "Basic explain plan generated"
        else
            print_error "Both EXPLAIN methods failed"
            echo ""
            echo "Possible issues:"
            echo "1. SQL syntax errors"
            echo "2. Missing tables or insufficient permissions"
            echo "3. Database/schema context issues"
            echo "4. Connection problems to target database"
            echo ""
            echo "Try manually:"
            echo "$explain_cmd -c \"EXPLAIN $full_sql\""
        fi
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
    echo "  - Host: ${NETEZZA_HOST:-'(local connection)'}"
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
    echo "2. Netezza Host: ${NETEZZA_HOST:-'(local connection)'}"
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
            NZSQL_CMD=$(build_nzsql_cmd)
            ;;
        2)
            read -p "Enter new Netezza host (leave blank for local connection): " new_host
            NETEZZA_HOST="$new_host"
            NZSQL_CMD=$(build_nzsql_cmd)
            ;;
        3)
            read -p "Enter new database: " new_db
            NETEZZA_DB="$new_db"
            NZSQL_CMD=$(build_nzsql_cmd)
            ;;
        4)
            read -p "Enter new username: " new_user
            NETEZZA_USER="$new_user"
            NZSQL_CMD=$(build_nzsql_cmd)
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
    
    # Prompt for host if not set
    if [[ -z "$NETEZZA_HOST" ]]; then
        echo ""
        echo "No Netezza host specified. You can:"
        echo "1. Connect to local Netezza instance"
        echo "2. Specify a remote host"
        echo ""
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
    echo "Using nzsql at: $NZSQL_PATH"
    echo "Command: $NZSQL_CMD"
    
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