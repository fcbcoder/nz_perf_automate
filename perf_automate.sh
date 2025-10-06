#!/bin/bash

#=============================================================================
# Netezza Performance Automation Tool
# Version: 1.1 - Enhanced Cost Analysis
# Date: October 10, 2025
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

#=============================================================================
# Enhanced System Discovery with New Views
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
    
    # Try common system views individually - UPDATED with new views
    print_section "Testing Common System Views"
    local common_views=(
        "_V_SESSION" "_V_SESSION_DETAIL" "_V_SYSTEM_STATE" "_V_DATABASE" "_V_DISK" "_V_HOST"
        "_V_QRYHIST" "_V_QRYSTAT" "_V_SQL_TEXT" "_V_LOCK" "_V_SYSTEM_CONFIG"
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
    
    # Specific column checks for key views - UPDATED with enhanced columns
    print_section "Key Column Availability Check"
    
    check_view_columns "_V_DATABASE" "DATABASE OWNER CREATEDATE OBJID"
    check_view_columns "_V_DISK" "HW_HWID HW_ROLE HW_DISKSZ HW_DISKMODEL HW_STATE"
    check_view_columns "_V_SESSION" "ID USERNAME DBNAME STATUS IPADDR CONNTIME PRIORITY"
    check_view_columns "_V_SESSION_DETAIL" "SESSION_ID CLIENT_OS_USERNAME SESSION_USERNAME DBNAME PRIORITY_NAME SCHEMA SESSION_PID"
    check_view_columns "_V_QRYHIST" "QH_SESSIONID QH_USER QH_DATABASE QH_TSUBMIT QH_TSTART QH_TEND QH_SQL QH_PRIORITY"
    check_view_columns "_V_QRYSTAT" "QS_SESSIONID QS_PLANID QS_SQL QS_TSUBMIT QS_TSTART QS_ESTCOST QS_ESTMEM QS_ESTDISK QS_RESROWS QS_RESBYTES QS_RUNTIME"
    check_view_columns "_V_CPU" "HOST CPU_NUMBER CPU_TYPE CPU_SPEED_MHZ CPU_UTILIZATION_PCT"
    
    print_section "System Catalog Information"
    # Try different ways to get system catalog info
    execute_sql "SELECT VERSION();" "Database Version" true
    execute_sql "SELECT CURRENT_USER, CURRENT_DATABASE, CURRENT_TIMESTAMP;" "Current Connection Info" true
    
    # Enhanced analysis recommendations based on available views
    print_section "Performance Analysis Recommendations"
    
    local has_qrystat=false
    local has_session_detail=false
    
    # Check for enhanced views
    for view in "${available_views[@]}"; do
        if [[ "$view" == "_V_QRYSTAT" ]]; then
            has_qrystat=true
        elif [[ "$view" == "_V_SESSION_DETAIL" ]]; then
            has_session_detail=true
        fi
    done
    
    echo ""
    echo "Based on available system views, here are the recommended analysis approaches:"
    echo ""
    
    if [[ "$has_qrystat" == true && "$has_session_detail" == true ]]; then
        print_success "✓ ENHANCED ANALYSIS AVAILABLE"
        echo "  Both _V_QRYSTAT and _V_SESSION_DETAIL are available"
        echo "  → Use Option 7 (Cost-Based Performance Analysis) for comprehensive insights"
        echo "  → Plan ID tracking and process correlation available"
        echo "  → Real-time cost and resource usage analysis enabled"
    elif [[ "$has_qrystat" == true ]]; then
        print_success "✓ INTERMEDIATE ANALYSIS AVAILABLE"
        echo "  _V_QRYSTAT is available but _V_SESSION_DETAIL is not"
        echo "  → Use Option 7 for cost-based analysis (limited session correlation)"
        echo "  → Plan ID tracking available"
        echo "  → Resource usage analysis enabled"
    elif [[ "$has_session_detail" == true ]]; then
        print_warning "⚠ BASIC ENHANCED SESSIONS AVAILABLE"
        echo "  _V_SESSION_DETAIL is available but _V_QRYSTAT is not"
        echo "  → Enhanced session analysis available in Option 4"
        echo "  → Cost-based analysis will use _V_QRYHIST fallback"
    else
        print_warning "⚠ BASIC ANALYSIS ONLY"
        echo "  Neither _V_QRYSTAT nor _V_SESSION_DETAIL are available"
        echo "  → Using standard _V_SESSION and _V_QRYHIST views"
        echo "  → Limited cost and session correlation analysis"
    fi
    
    echo ""
    echo "Recommended execution order:"
    echo "1. Run this discovery (Option 1) - ✓ COMPLETED"
    echo "2. System State Analysis (Option 2) - Basic system health"
    echo "3. Active Sessions Analysis (Option 4) - Current activity"
    if [[ "$has_qrystat" == true ]]; then
        echo "4. Cost-Based Analysis (Option 7) - ENHANCED resource analysis"
    else
        echo "4. Query Performance Analysis (Option 6) - Historical analysis"
    fi
    echo "5. Lock Analysis (Option 5) - If performance issues detected"
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
    local available_count=0
    local total_count=0
    
    for column in $expected_columns; do
        echo -n "  Testing column $column... "
        total_count=$((total_count + 1))
        if execute_sql "SELECT $column FROM $view_name LIMIT 1;" "Test column $column" false; then
            echo -e "${GREEN}✓ Available${NC}"
            available_count=$((available_count + 1))
        else
            echo -e "${RED}✗ Not available${NC}"
        fi
    done
    
    # Summary for this view
    echo -e "  ${CYAN}Summary: $available_count of $total_count expected columns available${NC}"
    
    # Special recommendations for key views
    case $view_name in
        "_V_QRYSTAT")
            if [[ $available_count -ge 8 ]]; then
                echo -e "  ${GREEN}→ Enhanced cost-based analysis fully supported${NC}"
            elif [[ $available_count -ge 5 ]]; then
                echo -e "  ${YELLOW}→ Basic cost-based analysis supported${NC}"
            else
                echo -e "  ${RED}→ Limited cost analysis - consider using _V_QRYHIST${NC}"
            fi
            ;;
        "_V_SESSION_DETAIL")
            if [[ $available_count -ge 6 ]]; then
                echo -e "  ${GREEN}→ Enhanced session correlation fully supported${NC}"
            elif [[ $available_count -ge 4 ]]; then
                echo -e "  ${YELLOW}→ Basic session correlation supported${NC}"
            else
                echo -e "  ${RED}→ Limited session analysis - using basic _V_SESSION${NC}"
            fi
            ;;
    esac
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

check_locks_and_blocking() {
    print_header "LOCK ANALYSIS AND BLOCKING SESSIONS"
    
    # First check system lock views
    print_section "System Lock Information"
    execute_safe_sql "_V_LOCK" "
    SELECT 
        LOCKTYPE,
        LOCKMODE,
        COUNT(*) AS LOCK_COUNT
    FROM _V_LOCK
    GROUP BY LOCKTYPE, LOCKMODE
    ORDER BY LOCK_COUNT DESC;" "Lock Summary by Type"
    
    execute_safe_sql "_V_LOCK" "
    SELECT 
        SESSIONID,
        LOCKTYPE,
        LOCKMODE,
        OBJNAME,
        LOCKTIME
    FROM _V_LOCK
    WHERE LOCKMODE != 'AccessShareLock'
    ORDER BY LOCKTIME DESC
    LIMIT 20;" "Active Non-Share Locks"
    
    # Use nz_show_locks utility
    print_section "Detailed Lock Analysis using nz_show_locks"
    
    # Check if nz_show_locks utility is available
    local nz_show_locks_path="/nz/bin/nz_show_locks"
    local alt_paths=(
        "/opt/nz/bin/nz_show_locks"
        "/usr/local/nz/bin/nz_show_locks"
        "/nz/support/bin/nz_show_locks"
        "/nz/kit/bin/nz_show_locks"
    )
    
    local found_nz_show_locks=""
    
    if [[ -f "$nz_show_locks_path" && -x "$nz_show_locks_path" ]]; then
        found_nz_show_locks="$nz_show_locks_path"
    else
        for path in "${alt_paths[@]}"; do
            if [[ -f "$path" && -x "$path" ]]; then
                found_nz_show_locks="$path"
                break
            fi
        done
    fi
    
    if [[ -n "$found_nz_show_locks" ]]; then
        print_success "Using nz_show_locks at: $found_nz_show_locks"
        
        # Create output file for locks
        local locks_file="/tmp/netezza_locks_$(date +%Y%m%d_%H%M%S).txt"
        
        echo "Executing nz_show_locks..."
        if [[ -n "$NETEZZA_HOST" ]]; then
            # For remote connections
            if "$found_nz_show_locks" -host "$NETEZZA_HOST" > "$locks_file" 2>&1; then
                print_success "Lock analysis completed successfully!"
                
                # Display results
                if [[ -s "$locks_file" ]]; then
                    echo ""
                    echo "Lock Analysis Results:"
                    echo "=============================================================="
                    cat "$locks_file"
                    echo "=============================================================="
                    
                    # Check for blocking situations
                    if grep -q -i "blocked\|waiting\|exclusive" "$locks_file"; then
                        print_warning "Potential blocking detected in lock analysis!"
                    else
                        print_success "No obvious blocking situations detected"
                    fi
                else
                    print_warning "No lock information returned"
                fi
                
                echo ""
                echo "Full lock report saved to: $locks_file"
            else
                print_error "Failed to execute nz_show_locks"
                echo "Error output:"
                cat "$locks_file"
                rm -f "$locks_file"
            fi
        else
            # For local connections
            if "$found_nz_show_locks" > "$locks_file" 2>&1; then
                print_success "Lock analysis completed successfully!"
                
                # Display results
                if [[ -s "$locks_file" ]]; then
                    echo ""
                    echo "Lock Analysis Results:"
                    echo "=============================================================="
                    cat "$locks_file"
                    echo "=============================================================="
                    
                    # Check for blocking situations
                    if grep -q -i "blocked\|waiting\|exclusive" "$locks_file"; then
                        print_warning "Potential blocking detected in lock analysis!"
                    else
                        print_success "No obvious blocking situations detected"
                    fi
                else
                    print_warning "No lock information returned"
                fi
                
                echo ""
                echo "Full lock report saved to: $locks_file"
            else
                print_error "Failed to execute nz_show_locks"
                echo "Error output:"
                cat "$locks_file"
                rm -f "$locks_file"
            fi
        fi
    else
        print_warning "nz_show_locks utility not found in standard locations."
        echo ""
        echo "Standard locations checked:"
        echo "  - /nz/bin/nz_show_locks"
        echo "  - /opt/nz/bin/nz_show_locks"
        echo "  - /usr/local/nz/bin/nz_show_locks"
        echo "  - /nz/support/bin/nz_show_locks"
        echo "  - /nz/kit/bin/nz_show_locks"
        echo ""
        read -p "Enter full path to nz_show_locks utility (or press Enter to skip): " custom_path
        
        if [[ -n "$custom_path" && -f "$custom_path" && -x "$custom_path" ]]; then
            print_success "Using custom nz_show_locks at: $custom_path"
            
            local locks_file="/tmp/netezza_locks_$(date +%Y%m%d_%H%M%S).txt"
            
            if [[ -n "$NETEZZA_HOST" ]]; then
                "$custom_path" -host "$NETEZZA_HOST" > "$locks_file" 2>&1
            else
                "$custom_path" > "$locks_file" 2>&1
            fi
            
            if [[ $? -eq 0 && -s "$locks_file" ]]; then
                echo ""
                echo "Lock Analysis Results:"
                echo "=============================================================="
                cat "$locks_file"
                echo "=============================================================="
                echo ""
                echo "Full report saved to: $locks_file"
            else
                print_error "Failed to execute custom nz_show_locks"
                rm -f "$locks_file"
            fi
        else
            print_warning "Skipping nz_show_locks analysis - utility not available"
        fi
    fi
    
    # Additional blocking session analysis
    print_section "Blocking Session Analysis"
    local blocking_result_file="/tmp/netezza_blocking_$(date +%Y%m%d_%H%M%S).txt"
    
    # Store blocking query results in a file for later processing
    $NZSQL_CMD -c "
    SELECT DISTINCT
        l1.SESSIONID as BLOCKING_SESSION,
        l2.SESSIONID as BLOCKED_SESSION,
        l1.LOCKTYPE,
        l1.OBJNAME,
        s1.USERNAME as BLOCKING_USER,
        s2.USERNAME as BLOCKED_USER,
        s1.COMMAND as BLOCKING_COMMAND,
        s2.COMMAND as BLOCKED_COMMAND
    FROM _V_LOCK l1
    JOIN _V_LOCK l2 ON l1.OBJNAME = l2.OBJNAME AND l1.SESSIONID != l2.SESSIONID
    LEFT JOIN _V_SESSION s1 ON l1.SESSIONID = s1.ID
    LEFT JOIN _V_SESSION s2 ON l2.SESSIONID = s2.ID
    WHERE l1.LOCKMODE IN ('ExclusiveLock', 'AccessExclusiveLock')
    AND l2.LOCKMODE IN ('ExclusiveLock', 'AccessExclusiveLock', 'ShareLock')
    ORDER BY l1.OBJNAME;" > "$blocking_result_file" 2>/dev/null
    
    if [[ -s "$blocking_result_file" ]]; then
        echo "Potential Blocking Relationships:"
        echo "=============================================================="
        cat "$blocking_result_file" 
        echo "=============================================================="
        
        # Check if there are actual blocking relationships (not just headers)
        local blocking_count=$(grep -c "^[[:space:]]*[0-9]" "$blocking_result_file" 2>/dev/null || echo "0")
        
        if [[ "$blocking_count" -gt 0 ]]; then
            print_warning "$blocking_count potential blocking relationships detected!"
            echo ""
            
            # Offer session management options
            print_section "Session Management Options"
            echo "What would you like to do?"
            echo "1. View detailed session information"
            echo "2. Terminate blocking sessions (CAUTION!)"
            echo "3. Continue without action"
            echo ""
            
            read -p "Choose an option (1-3): " blocking_action
            
            case $blocking_action in
                1)
                    show_detailed_blocking_sessions "$blocking_result_file"
                    ;;
                2)
                    terminate_blocking_sessions "$blocking_result_file"
                    ;;
                3)
                    print_success "Continuing without action"
                    ;;
                *)
                    print_warning "Invalid option selected"
                    ;;
            esac
        else
            print_success "No active blocking relationships detected"
        fi
    else
        print_success "No blocking relationships found"
    fi
    
    rm -f "$blocking_result_file"
}

# Show detailed information about blocking sessions
show_detailed_blocking_sessions() {
    local blocking_file="$1"
    
    print_section "Detailed Blocking Session Information"
    
    # Extract unique blocking session IDs
    local blocking_sessions=($(grep "^[[:space:]]*[0-9]" "$blocking_file" 2>/dev/null | awk '{print $1}' | sort -u))
    
    if [[ ${#blocking_sessions[@]} -eq 0 ]]; then
        print_warning "No blocking sessions to analyze"
        return
    fi
    
    for session_id in "${blocking_sessions[@]}"; do
        if [[ -n "$session_id" && "$session_id" =~ ^[0-9]+$ ]]; then
            echo ""
            echo "=== Blocking Session ID: $session_id ==="
            
            # Get detailed session information
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
            WHERE ID = ${session_id};" "Session ${session_id} Details" true
            
            # Get recent SQL for this session
            echo ""
            echo "Recent SQL for Session $session_id:"
            execute_sql "
            SELECT 
                QH_TSUBMIT,
                QH_TSTART,
                QH_TEND,
                SUBSTR(QH_SQL, 1, 200) AS SQL_PREVIEW
            FROM _V_QRYHIST
            WHERE QH_SESSIONID = ${session_id}
            ORDER BY QH_TSUBMIT DESC
            LIMIT 3;" "Recent SQL for Session ${session_id}" true
            
            echo "----------------------------------------"
        fi
    done
    
    echo ""
    read -p "Press Enter to continue..."
}

# Terminate blocking sessions with safety checks
terminate_blocking_sessions() {
    local blocking_file="$1"
    
    print_section "Session Termination (CAUTION!)"
    print_warning "WARNING: Terminating sessions will forcefully disconnect users and rollback their transactions!"
    print_warning "This action cannot be undone and may cause data loss if transactions are in progress."
    
    echo ""
    echo "Please review the blocking sessions before proceeding:"
    cat "$blocking_file"
    echo ""
    
    # Extract unique blocking session IDs
    local blocking_sessions=($(grep "^[[:space:]]*[0-9]" "$blocking_file" 2>/dev/null | awk '{print $1}' | sort -u))
    
    if [[ ${#blocking_sessions[@]} -eq 0 ]]; then
        print_warning "No blocking sessions found to terminate"
        return
    fi
    
    echo "Blocking sessions that would be terminated: ${blocking_sessions[*]}"
    echo ""
    
    # Safety confirmation
    read -p "Are you absolutely sure you want to terminate these sessions? (yes/no): " confirm1
    if [[ "$confirm1" != "yes" ]]; then
        print_success "Session termination cancelled"
        return
    fi
    
    read -p "Type 'TERMINATE' to confirm session termination: " confirm2
    if [[ "$confirm2" != "TERMINATE" ]]; then
        print_success "Session termination cancelled"
        return
    fi
    
    # Check for nzkill utility
    local nzkill_path="/nz/bin/nzkill"
    local alt_nzkill_paths=(
        "/opt/nz/bin/nzkill"
        "/usr/local/nz/bin/nzkill"
        "/nz/support/bin/nzkill"
        "/nz/kit/bin/nzkill"
    )
    
    local found_nzkill=""
    
    if [[ -f "$nzkill_path" && -x "$nzkill_path" ]]; then
        found_nzkill="$nzkill_path"
    else
        for path in "${alt_nzkill_paths[@]}"; do
            if [[ -f "$path" && -x "$path" ]]; then
                found_nzkill="$path"
                break
            fi
        done
    fi
    
    print_section "Terminating Blocking Sessions"
    
    local terminated_count=0
    local failed_count=0
    
    for session_id in "${blocking_sessions[@]}"; do
        if [[ -n "$session_id" && "$session_id" =~ ^[0-9]+$ ]]; then
            echo "Terminating session $session_id..."
            
            local success=false
            
            # Method 1: Try using nzkill utility
            if [[ -n "$found_nzkill" ]]; then
                if [[ -n "$NETEZZA_HOST" ]]; then
                    if "$found_nzkill" -host "$NETEZZA_HOST" -id "$session_id" >/dev/null 2>&1; then
                        success=true
                    fi
                else
                    if "$found_nzkill" -id "$session_id" >/dev/null 2>&1; then
                        success=true
                    fi
                fi
            fi
            
            # Method 2: Try using SQL command if nzkill failed
            if [[ "$success" = false ]]; then
                if execute_sql "ABORT SESSION $session_id;" "Abort Session $session_id" false; then
                    success=true
                fi
            fi
            
            # Method 3: Try alternative SQL syntax
            if [[ "$success" = false ]]; then
                if execute_sql "SELECT ABORT_SESSION($session_id);" "Abort Session $session_id (Alt)" false; then
                    success=true
                fi
            fi
            
            if [[ "$success" = true ]]; then
                print_success "✓ Session $session_id terminated successfully"
                terminated_count=$((terminated_count + 1))
            else
                print_error "✗ Failed to terminate session $session_id"
                failed_count=$((failed_count + 1))
            fi
        fi
    done
    
    echo ""
    print_section "Termination Summary"
    echo "Sessions successfully terminated: $terminated_count"
    echo "Sessions failed to terminate: $failed_count"
    
    if [[ "$terminated_count" -gt 0 ]]; then
        print_success "Successfully terminated $terminated_count blocking sessions"
        
        # Wait a moment for cleanup
        echo "Waiting 5 seconds for system cleanup..."
        sleep 5
        
        # Check if blocking is resolved
        echo ""
        echo "Checking if blocking has been resolved..."
        local recheck_file="/tmp/netezza_recheck_$(date +%Y%m%d_%H%M%S).txt"
        
        $NZSQL_CMD -c "
        SELECT DISTINCT
            l1.SESSIONID as BLOCKING_SESSION,
            l2.SESSIONID as BLOCKED_SESSION,
            l1.LOCKTYPE,
            l1.OBJNAME
        FROM _V_LOCK l1
        JOIN _V_LOCK l2 ON l1.OBJNAME = l2.OBJNAME AND l1.SESSIONID != l2.SESSIONID
        WHERE l1.LOCKMODE IN ('ExclusiveLock', 'AccessExclusiveLock')
        AND l2.LOCKMODE IN ('ExclusiveLock', 'AccessExclusiveLock', 'ShareLock');" > "$recheck_file" 2>/dev/null
        
        local remaining_blocks=$(grep -c "^[[:space:]]*[0-9]" "$recheck_file" 2>/dev/null || echo "0")
        
        if [[ "$remaining_blocks" -eq 0 ]]; then
            print_success "✓ All blocking relationships have been resolved!"
        else
            print_warning "⚠ $remaining_blocks blocking relationships still remain"
            echo "Remaining blocks:"
            cat "$recheck_file"
        fi
        
        rm -f "$recheck_file"
    fi
    
    if [[ "$failed_count" -gt 0 ]]; then
        print_warning "Some sessions could not be terminated automatically"
        echo ""
        echo "Manual termination options:"
        echo "1. Use nzadmin command: nzadmin -c 'kill session <session_id>'"
        echo "2. Contact system administrator for manual intervention"
        echo "3. Check if sessions are system processes that cannot be terminated"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Intelligent nzsession analysis with multiple options
intelligent_nzsession_analysis() {
    local nzsession_cmd="$1"
    
    # First get the help to understand correct syntax
    get_nzsession_help "$nzsession_cmd"
    
    print_section "Enhanced Session Analysis Strategy"
    
    # Get basic session information first
    local session_count_file="/tmp/netezza_session_count_$(date +%Y%m%d_%H%M%S).txt"
    
    echo "Getting session information..."
    
    # Try different command formats based on common nzsession syntax
    if [[ -n "$NETEZZA_HOST" ]]; then
        # Try show sessions command (most common)
        if "$nzsession_cmd" show sessions -host "$NETEZZA_HOST" > "$session_count_file" 2>&1; then
            print_success "Sessions retrieved using 'show sessions' command"
        elif "$nzsession_cmd" show -host "$NETEZZA_HOST" > "$session_count_file" 2>&1; then
            print_success "Sessions retrieved using 'show' command"
        elif "$nzsession_cmd" -host "$NETEZZA_HOST" > "$session_count_file" 2>&1; then
            print_success "Sessions retrieved using default command"
        else
            print_warning "Standard nzsession commands failed, trying alternatives..."
            "$nzsession_cmd" > "$session_count_file" 2>&1
        fi
    else
        # Local connection attempts
        if "$nzsession_cmd" show sessions > "$session_count_file" 2>&1; then
            print_success "Sessions retrieved using 'show sessions' command"
        elif "$nzsession_cmd" show > "$session_count_file" 2>&1; then
            print_success "Sessions retrieved using 'show' command"
        elif "$nzsession_cmd" > "$session_count_file" 2>&1; then
            print_success "Sessions retrieved using default command"
        else
            print_warning "nzsession commands failed"
        fi
    fi
    
    # Display results if we got any
    if [[ -s "$session_count_file" ]]; then
        local total_sessions=$(wc -l < "$session_count_file" 2>/dev/null || echo "0")
        total_sessions=$((total_sessions - 1))  # Subtract header line
        
        echo ""
        echo "nzsession Output:"
        echo "=============================================================="
        head -20 "$session_count_file"  # Show first 20 lines
        if [[ "$total_sessions" -gt 20 ]]; then
            echo "... (showing first 20 of $total_sessions total sessions)"
        fi
        echo "=============================================================="
        
        # Try to parse for insights
        analyze_nzsession_output "$session_count_file"
    else
        print_warning "No session data retrieved from nzsession utility"
        echo "This may be due to:"
        echo "1. Different nzsession command syntax in this version"
        echo "2. Permission issues"
        echo "3. Network connectivity (for remote connections)"
        echo ""
        echo "Falling back to system view analysis..."
    fi
    
    rm -f "$session_count_file"
}

# Get correct nzsession syntax
get_nzsession_help() {
    local nzsession_cmd="$1"
    
    print_section "Determining nzsession Command Syntax"
    
    # Get help information
    local help_file="/tmp/nzsession_help_$(date +%Y%m%d_%H%M%S).txt"
    
    if [[ -n "$NETEZZA_HOST" ]]; then
        "$nzsession_cmd" -h > "$help_file" 2>&1
    else
        "$nzsession_cmd" -h > "$help_file" 2>&1
    fi
    
    if [[ -s "$help_file" ]]; then
        echo "Available nzsession commands:"
        echo "=============================================================="
        cat "$help_file"
        echo "=============================================================="
        
        # Check for specific subcommands
        echo ""
        echo "Checking for available subcommands..."
        if [[ -n "$NETEZZA_HOST" ]]; then
            "$nzsession_cmd" -hc show > "${help_file}_subcmds" 2>&1
        else
            "$nzsession_cmd" -hc show > "${help_file}_subcmds" 2>&1
        fi
        
        if [[ -s "${help_file}_subcmds" ]]; then
            echo "Available subcommands:"
            echo "--------------------------------------------------------------"
            cat "${help_file}_subcmds"
            echo "--------------------------------------------------------------"
        fi
    fi
    
    rm -f "$help_file" "${help_file}_subcmds"
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
    echo -e "${GREEN}║                         Version 1.1 - Enhanced Cost Analysis                ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Main Options:${NC}"
    echo "1. Discover Available System Views (Run this first!)"
    echo "2. Netezza System State Analysis"
    echo "3. Linux OS Performance Monitoring"
    echo "4. Active Sessions and SQL Analysis (Enhanced with Cost Data)"
    echo "5. Lock Analysis and Blocking Sessions"
    echo "6. Query Performance Analysis"
    echo "7. Cost-Based Performance Analysis (NEW - uses _V_QRYSTAT)"
    echo "8. Interactive SQL Explain Plan Analysis"
    echo "9. Run Complete System Check (Options 2-7)"
    echo "10. Configuration Settings"
    echo "11. View Log File"
    echo "12. Exit"
    echo ""
    echo -e "${YELLOW}Current Settings:${NC}"
    echo "  - Host: ${NETEZZA_HOST:-'(local connection)'}"
    echo "  - Database: $NETEZZA_DB"
    echo "  - User: $NETEZZA_USER"
    echo "  - Long Query Threshold: $LONG_RUNNING_QUERY_HOURS hours"
    echo "  - Log File: $LOG_FILE"
    echo ""
}

# Update main function to include new option
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
        read -p "Choose an option (1-12): " choice
        
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
                check_locks_and_blocking
                read -p "Press Enter to continue..."
                ;;
            6)
                check_query_performance
                read -p "Press Enter to continue..."
                ;;
            7)
                check_cost_based_performance
                read -p "Press Enter to continue..."
                ;;
            8)
                interactive_explain_plan
                ;;
            9)
                run_complete_check
                ;;
            10)
                configure_settings
                ;;
            11)
                view_log_file
                ;;
            12)
                print_success "Thank you for using Netezza Performance Automation Tool!"
                exit 0
                ;;
            *)
                print_error "Invalid option. Please choose 1-12."
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Update complete check function
run_complete_check() {
    print_header "COMPLETE SYSTEM CHECK STARTING"
    echo "This will run all system checks (options 2-7). This may take several minutes..."
    echo ""
    read -p "Continue? (y/n): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        return
    fi
    
    check_netezza_system_state
    check_os_performance
    check_active_sessions
    check_locks_and_blocking
    check_query_performance
    check_cost_based_performance
    
    print_header "COMPLETE SYSTEM CHECK FINISHED"
    print_success "All checks completed successfully!"
    echo "Log file: $LOG_FILE"
    read -p "Press Enter to continue..."
}

# Add these missing functions after the existing utility functions

# Analyze nzsession output for patterns
analyze_nzsession_output() {
    local output_file="$1"
    
    print_section "nzsession Output Analysis"
    
    if [[ -s "$output_file" ]]; then
        # Count total lines (approximate sessions)
        local line_count=$(wc -l < "$output_file")
        echo "Total output lines: $line_count"
        
        # Look for common patterns in the output
        echo ""
        echo "Looking for patterns in session data..."
        
        # Check for session IDs (numbers in first column typically)
        local session_ids=$(grep -E "^[[:space:]]*[0-9]+" "$output_file" 2>/dev/null | wc -l)
        if [[ "$session_ids" -gt 0 ]]; then
            echo "Approximate active sessions: $session_ids"
        fi
        
        # Check for status patterns
        echo ""
        echo "Session status patterns (if available):"
        grep -E "(Active|Running|Idle|Waiting|Blocked)" "$output_file" 2>/dev/null | head -5
        
        # Check for user patterns
        echo ""
        echo "User patterns (if available):"
        grep -E "([A-Za-z0-9_-]+@|USER|Username)" "$output_file" 2>/dev/null | head -5
        
        # Check for database patterns
        echo ""
        echo "Database patterns (if available):"
        grep -E "(DB:|Database|SYSTEM|PROD)" "$output_file" 2>/dev/null | head -5
        
        # Look for error messages
        if grep -qi "error\|fail\|invalid" "$output_file"; then
            print_warning "Potential errors detected in nzsession output:"
            grep -i "error\|fail\|invalid" "$output_file" | head -3
        fi
    fi
}

#=============================================================================
# Enhanced Cost-Based Query Analysis
#=============================================================================

check_cost_based_performance() {
    print_header "COST-BASED QUERY PERFORMANCE ANALYSIS"
    
    # Check if enhanced views are available
    print_section "Checking Enhanced Query Analysis Views"
    
    local has_qrystat=false
    local has_session_detail=false
    
    if execute_sql "SELECT COUNT(*) FROM _V_QRYSTAT LIMIT 1;" "Test _V_QRYSTAT" false; then
        print_success "_V_QRYSTAT available - Enhanced cost analysis enabled"
        has_qrystat=true
    else
        print_warning "_V_QRYSTAT not available - Using basic query analysis"
    fi
    
    if execute_sql "SELECT COUNT(*) FROM _V_SESSION_DETAIL LIMIT 1;" "Test _V_SESSION_DETAIL" false; then
        print_success "_V_SESSION_DETAIL available - Enhanced session analysis enabled"
        has_session_detail=true
    else
        print_warning "_V_SESSION_DETAIL not available - Using basic session analysis"
    fi
    
    if [[ "$has_qrystat" == true && "$has_session_detail" == true ]]; then
        # Enhanced analysis with both views
        enhanced_cost_analysis
        
        # Offer additional analysis options
        echo ""
        print_section "Additional Analysis Options"
        echo "1. Analyze specific Plan ID"
        echo "2. Continue to next section"
        echo ""
        read -p "Choose an option (1-2): " analysis_choice
        
        case $analysis_choice in
            1) analyze_specific_plan ;;
            2) ;;
        esac
        
    elif [[ "$has_qrystat" == true ]]; then
        # Analysis with _V_QRYSTAT only
        qrystat_only_analysis
    else
        # Fallback to basic analysis
        basic_cost_analysis
    fi
}

enhanced_cost_analysis() {
    print_section "Enhanced Cost-Based Analysis (using _V_QRYSTAT + _V_SESSION_DETAIL)"
    
    # Top queries by estimated cost - ENHANCED with plan and process IDs
    execute_sql "
    SELECT 
        b.CLIENT_OS_USERNAME, 
        b.SESSION_USERNAME, 
        a.QS_SESSIONID, 
        a.QS_PLANID,                    -- NEW: Plan ID
        b.SESSION_PID,                  -- NEW: Session Process ID
        b.PRIORITY_NAME, 
        b.DBNAME, 
        b.SCHEMA,
        SUBSTRING(a.QS_SQL, 1, 100) AS SQL_PREVIEW,
        a.QS_TSUBMIT, 
        a.QS_TSTART, 
        a.QS_ESTCOST, 
        a.QS_ESTMEM, 
        a.QS_ESTDISK, 
        a.QS_RESROWS, 
        a.QS_RESBYTES,
        a.QS_RUNTIME                    -- NEW: Runtime if available
    FROM _V_QRYSTAT a
    LEFT JOIN _V_SESSION_DETAIL b ON b.SESSION_ID = a.QS_SESSIONID
    WHERE b.DBNAME IS NOT NULL AND b.DBNAME != 'null'
    ORDER BY a.QS_ESTCOST DESC
    LIMIT ${TOP_QUERIES_LIMIT};" "Top Queries by Estimated Cost (Enhanced)"
    
    # Top queries by memory usage - ENHANCED
    print_section "Top Queries by Estimated Memory Usage"
    execute_sql "
    SELECT 
        b.CLIENT_OS_USERNAME, 
        b.SESSION_USERNAME, 
        a.QS_SESSIONID, 
        a.QS_PLANID,                    -- NEW: Plan ID
        b.SESSION_PID,                  -- NEW: Session Process ID
        b.PRIORITY_NAME, 
        b.DBNAME,
        a.QS_ESTMEM,
        a.QS_ESTCOST,
        a.QS_ESTDISK,
        SUBSTRING(a.QS_SQL, 1, 80) AS SQL_PREVIEW,
        a.QS_TSTART,
        a.QS_RUNTIME                    -- NEW: Runtime if available
    FROM _V_QRYSTAT a
    LEFT JOIN _V_SESSION_DETAIL b ON b.SESSION_ID = a.QS_SESSIONID
    WHERE b.DBNAME IS NOT NULL AND b.DBNAME != 'null'
    AND a.QS_ESTMEM > 0
    ORDER BY a.QS_ESTMEM DESC
    LIMIT ${TOP_QUERIES_LIMIT};" "Top Queries by Memory Usage (Enhanced)"
    
    # Top queries by disk usage - ENHANCED
    print_section "Top Queries by Estimated Disk Usage"
    execute_sql "
    SELECT 
        b.CLIENT_OS_USERNAME, 
        b.SESSION_USERNAME, 
        a.QS_SESSIONID, 
        a.QS_PLANID,                    -- NEW: Plan ID
        b.SESSION_PID,                  -- NEW: Session Process ID
        b.PRIORITY_NAME, 
        b.DBNAME,
        a.QS_ESTDISK,
        a.QS_ESTCOST,
        a.QS_ESTMEM,
        SUBSTRING(a.QS_SQL, 1, 80) AS SQL_PREVIEW,
        a.QS_TSTART,
        a.QS_RUNTIME                    -- NEW: Runtime if available
    FROM _V_QRYSTAT a
    LEFT JOIN _V_SESSION_DETAIL b ON b.SESSION_ID = a.QS_SESSIONID
    WHERE b.DBNAME IS NOT NULL AND b.DBNAME != 'null'
    AND a.QS_ESTDISK > 0
    ORDER BY a.QS_ESTDISK DESC
    LIMIT ${TOP_QUERIES_LIMIT};" "Top Queries by Disk Usage (Enhanced)"
    
    # NEW: Analysis by Plan ID (find queries using the same execution plan)
    print_section "Query Analysis by Plan ID (Same Execution Plans)"
    execute_sql "
    SELECT 
        a.QS_PLANID,
        COUNT(*) AS QUERY_COUNT,
        COUNT(DISTINCT a.QS_SESSIONID) AS UNIQUE_SESSIONS,
        COUNT(DISTINCT b.CLIENT_OS_USERNAME) AS UNIQUE_USERS,
        ROUND(AVG(a.QS_ESTCOST), 2) AS AVG_EST_COST,
        ROUND(MAX(a.QS_ESTCOST), 2) AS MAX_EST_COST,
        ROUND(AVG(a.QS_ESTMEM), 2) AS AVG_EST_MEM,
        ROUND(AVG(a.QS_ESTDISK), 2) AS AVG_EST_DISK,
        MAX(a.QS_TSTART) AS LAST_EXECUTION,
        SUBSTRING(MAX(a.QS_SQL), 1, 100) AS SAMPLE_SQL
    FROM _V_QRYSTAT a
    LEFT JOIN _V_SESSION_DETAIL b ON b.SESSION_ID = a.QS_SESSIONID
    WHERE b.DBNAME IS NOT NULL AND b.DBNAME != 'null'
    AND a.QS_PLANID IS NOT NULL
    GROUP BY a.QS_PLANID
    HAVING COUNT(*) > 1
    ORDER BY QUERY_COUNT DESC, AVG_EST_COST DESC
    LIMIT 20;" "Queries Grouped by Plan ID"
    
    # NEW: Session Process Analysis
    print_section "Query Analysis by Session Process ID"
    execute_sql "
    SELECT 
        b.SESSION_PID,
        b.CLIENT_OS_USERNAME,
        b.SESSION_USERNAME,
        b.DBNAME,
        b.PRIORITY_NAME,
        COUNT(*) AS QUERY_COUNT,
        ROUND(AVG(a.QS_ESTCOST), 2) AS AVG_EST_COST,
        ROUND(MAX(a.QS_ESTCOST), 2) AS MAX_EST_COST,
        ROUND(SUM(a.QS_ESTCOST), 2) AS TOTAL_EST_COST,
        COUNT(DISTINCT a.QS_PLANID) AS UNIQUE_PLANS,
        MAX(a.QS_TSTART) AS LAST_QUERY_TIME,
        SUBSTRING(MAX(a.QS_SQL), 1, 80) AS LATEST_SQL
    FROM _V_QRYSTAT a
    LEFT JOIN _V_SESSION_DETAIL b ON b.SESSION_ID = a.QS_SESSIONID
    WHERE b.DBNAME IS NOT NULL AND b.DBNAME != 'null'
    AND b.SESSION_PID IS NOT NULL
    GROUP BY b.SESSION_PID, b.CLIENT_OS_USERNAME, b.SESSION_USERNAME, b.DBNAME, b.PRIORITY_NAME
    ORDER BY TOTAL_EST_COST DESC
    LIMIT 20;" "Query Analysis by Session Process"
    
    # Analysis by client OS user - ENHANCED
    print_section "Query Cost Analysis by Client OS User (Enhanced)"
    execute_sql "
    SELECT 
        b.CLIENT_OS_USERNAME,
        COUNT(*) AS QUERY_COUNT,
        COUNT(DISTINCT a.QS_SESSIONID) AS UNIQUE_SESSIONS,
        COUNT(DISTINCT b.SESSION_PID) AS UNIQUE_PROCESSES,
        COUNT(DISTINCT a.QS_PLANID) AS UNIQUE_PLANS,
        ROUND(AVG(a.QS_ESTCOST), 2) AS AVG_EST_COST,
        ROUND(MAX(a.QS_ESTCOST), 2) AS MAX_EST_COST,
        ROUND(SUM(a.QS_ESTCOST), 2) AS TOTAL_EST_COST,
        ROUND(AVG(a.QS_ESTMEM), 2) AS AVG_EST_MEM,
        ROUND(AVG(a.QS_ESTDISK), 2) AS AVG_EST_DISK,
        MAX(a.QS_TSTART) AS LAST_ACTIVITY
    FROM _V_QRYSTAT a
    LEFT JOIN _V_SESSION_DETAIL b ON b.SESSION_ID = a.QS_SESSIONID
    WHERE b.DBNAME IS NOT NULL AND b.DBNAME != 'null'
    AND b.CLIENT_OS_USERNAME IS NOT NULL
    GROUP BY b.CLIENT_OS_USERNAME
    ORDER BY TOTAL_EST_COST DESC
    LIMIT 15;" "Enhanced Cost Analysis by Client OS User"
    
    # Analysis by database - ENHANCED
    print_section "Query Cost Analysis by Database (Enhanced)"
    execute_sql "
    SELECT 
        b.DBNAME,
        COUNT(*) AS QUERY_COUNT,
        COUNT(DISTINCT a.QS_SESSIONID) AS UNIQUE_SESSIONS,
        COUNT(DISTINCT b.SESSION_PID) AS UNIQUE_PROCESSES,
        COUNT(DISTINCT b.CLIENT_OS_USERNAME) AS UNIQUE_USERS,
        COUNT(DISTINCT a.QS_PLANID) AS UNIQUE_PLANS,
        ROUND(AVG(a.QS_ESTCOST), 2) AS AVG_EST_COST,
        ROUND(MAX(a.QS_ESTCOST), 2) AS MAX_EST_COST,
        ROUND(SUM(a.QS_ESTCOST), 2) AS TOTAL_EST_COST,
        MAX(a.QS_TSTART) AS LAST_ACTIVITY
    FROM _V_QRYSTAT a
    LEFT JOIN _V_SESSION_DETAIL b ON b.SESSION_ID = a.QS_SESSIONID
    WHERE b.DBNAME IS NOT NULL AND b.DBNAME != 'null'
    GROUP BY b.DBNAME
    ORDER BY TOTAL_EST_COST DESC;" "Enhanced Cost Analysis by Database"
    
    # Analysis by schema - ENHANCED
    print_section "Query Cost Analysis by Schema (Enhanced)"
    execute_sql "
    SELECT 
        b.DBNAME,
        b.SCHEMA,
        COUNT(*) AS QUERY_COUNT,
        COUNT(DISTINCT a.QS_SESSIONID) AS UNIQUE_SESSIONS,
        COUNT(DISTINCT b.SESSION_PID) AS UNIQUE_PROCESSES,
        COUNT(DISTINCT a.QS_PLANID) AS UNIQUE_PLANS,
        ROUND(AVG(a.QS_ESTCOST), 2) AS AVG_EST_COST,
        ROUND(MAX(a.QS_ESTCOST), 2) AS MAX_EST_COST,
        ROUND(SUM(a.QS_ESTCOST), 2) AS TOTAL_EST_COST,
        MAX(a.QS_TSTART) AS LAST_ACTIVITY
    FROM _V_QRYSTAT a
    LEFT JOIN _V_SESSION_DETAIL b ON b.SESSION_ID = a.QS_SESSIONID
    WHERE b.DBNAME IS NOT NULL AND b.DBNAME != 'null'
    AND b.SCHEMA IS NOT NULL
    GROUP BY b.DBNAME, b.SCHEMA
    ORDER BY TOTAL_EST_COST DESC
    LIMIT 20;" "Enhanced Cost Analysis by Schema"
    
    # Priority-based analysis - ENHANCED
    print_section "Query Cost Analysis by Priority (Enhanced)"
    execute_sql "
    SELECT 
        b.PRIORITY_NAME,
        COUNT(*) AS QUERY_COUNT,
        COUNT(DISTINCT a.QS_SESSIONID) AS UNIQUE_SESSIONS,
        COUNT(DISTINCT b.SESSION_PID) AS UNIQUE_PROCESSES,
        COUNT(DISTINCT a.QS_PLANID) AS UNIQUE_PLANS,
        ROUND(AVG(a.QS_ESTCOST), 2) AS AVG_EST_COST,
        ROUND(MAX(a.QS_ESTCOST), 2) AS MAX_EST_COST,
        ROUND(SUM(a.QS_ESTCOST), 2) AS TOTAL_EST_COST,
        ROUND(AVG(a.QS_RUNTIME), 2) AS AVG_RUNTIME_SEC
    FROM _V_QRYSTAT a
    LEFT JOIN _V_SESSION_DETAIL b ON b.SESSION_ID = a.QS_SESSIONID
    WHERE b.DBNAME IS NOT NULL AND b.DBNAME != 'null'
    AND b.PRIORITY_NAME IS NOT NULL
    GROUP BY b.PRIORITY_NAME
    ORDER BY TOTAL_EST_COST DESC;" "Enhanced Cost Analysis by Priority"
    
    # NEW: Plan efficiency analysis
    print_section "Plan Efficiency Analysis (Cost vs Runtime)"
    execute_sql "
    SELECT 
        a.QS_PLANID,
        COUNT(*) AS EXECUTION_COUNT,
        ROUND(AVG(a.QS_ESTCOST), 2) AS AVG_ESTIMATED_COST,
        ROUND(AVG(a.QS_RUNTIME), 2) AS AVG_ACTUAL_RUNTIME,
        ROUND(AVG(a.QS_ESTCOST) / NULLIF(AVG(a.QS_RUNTIME), 0), 2) AS COST_PER_SECOND,
        ROUND(AVG(a.QS_ESTMEM), 2) AS AVG_EST_MEMORY,
        ROUND(AVG(a.QS_ESTDISK), 2) AS AVG_EST_DISK,
        COUNT(DISTINCT b.CLIENT_OS_USERNAME) AS UNIQUE_USERS,
        SUBSTRING(MAX(a.QS_SQL), 1, 100) AS SAMPLE_SQL
    FROM _V_QRYSTAT a
    LEFT JOIN _V_SESSION_DETAIL b ON b.SESSION_ID = a.QS_SESSIONID
    WHERE b.DBNAME IS NOT NULL AND b.DBNAME != 'null'
    AND a.QS_PLANID IS NOT NULL
    AND a.QS_RUNTIME > 0
    GROUP BY a.QS_PLANID
    HAVING COUNT(*) >= 2
    ORDER BY COST_PER_SECOND DESC
    LIMIT 20;" "Plan Efficiency Analysis"
}

qrystat_only_analysis() {
    print_section "Query Statistics Analysis (using _V_QRYSTAT only)"
    
    # Top queries by cost - ENHANCED
    execute_sql "
    SELECT 
        QS_SESSIONID,
        QS_PLANID,                      -- NEW: Plan ID
        QS_ESTCOST,
        QS_ESTMEM,
        QS_ESTDISK,
        QS_RESROWS,
        QS_RESBYTES,
        QS_RUNTIME,                     -- NEW: Runtime
        QS_TSTART,
        SUBSTRING(QS_SQL, 1, 100) AS SQL_PREVIEW
    FROM _V_QRYSTAT
    WHERE QS_ESTCOST > 0
    ORDER BY QS_ESTCOST DESC
    LIMIT ${TOP_QUERIES_LIMIT};" "Top Queries by Estimated Cost (Enhanced)"
    
    # Resource usage summary - ENHANCED
    execute_sql "
    SELECT 
        COUNT(*) AS TOTAL_QUERIES,
        COUNT(DISTINCT QS_PLANID) AS UNIQUE_PLANS,      -- NEW: Unique plans
        COUNT(DISTINCT QS_SESSIONID) AS UNIQUE_SESSIONS,
        ROUND(AVG(QS_ESTCOST), 2) AS AVG_EST_COST,
        ROUND(MAX(QS_ESTCOST), 2) AS MAX_EST_COST,
        ROUND(AVG(QS_ESTMEM), 2) AS AVG_EST_MEM,
        ROUND(MAX(QS_ESTMEM), 2) AS MAX_EST_MEM,
        ROUND(AVG(QS_ESTDISK), 2) AS AVG_EST_DISK,
        ROUND(MAX(QS_ESTDISK), 2) AS MAX_EST_DISK,
        ROUND(AVG(QS_RUNTIME), 2) AS AVG_RUNTIME_SEC,   -- NEW: Average runtime
        ROUND(MAX(QS_RUNTIME), 2) AS MAX_RUNTIME_SEC     -- NEW: Max runtime
    FROM _V_QRYSTAT;" "Enhanced Query Resource Usage Summary"
    
    # NEW: Plan reuse analysis
    print_section "Query Plan Reuse Analysis"
    execute_sql "
    SELECT 
        QS_PLANID,
        COUNT(*) AS EXECUTION_COUNT,
        COUNT(DISTINCT QS_SESSIONID) AS UNIQUE_SESSIONS,
        ROUND(AVG(QS_ESTCOST), 2) AS AVG_EST_COST,
        ROUND(AVG(QS_RUNTIME), 2) AS AVG_RUNTIME,
        MAX(QS_TSTART) AS LAST_EXECUTION,
        SUBSTRING(MAX(QS_SQL), 1, 80) AS SAMPLE_SQL
    FROM _V_QRYSTAT
    WHERE QS_PLANID IS NOT NULL
    GROUP BY QS_PLANID
    HAVING COUNT(*) > 1
    ORDER BY EXECUTION_COUNT DESC
    LIMIT 20;" "Plan Reuse Analysis"
}

basic_cost_analysis() {
    print_section "Basic Cost Analysis (using _V_QRYHIST)"
    
    # Fallback to original query history analysis with cost focus
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
}

# Add a new function for specific plan analysis
analyze_specific_plan() {
    print_section "Specific Plan Analysis"
    
    echo ""
    read -p "Enter Plan ID to analyze (or press Enter to see available plans): " plan_id
    
    if [[ -z "$plan_id" ]]; then
        # Show available plans
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
        ORDER BY EXECUTION_COUNT DESC
        LIMIT 20;" "Available Plans"
        
        echo ""
        read -p "Enter Plan ID to analyze: " plan_id
    fi
    
    if [[ -n "$plan_id" ]]; then
        print_section "Detailed Analysis for Plan ID: $plan_id"
        
        # Plan execution details
        execute_sql "
        SELECT 
            a.QS_SESSIONID,
            b.CLIENT_OS_USERNAME,
            b.SESSION_USERNAME,
            b.SESSION_PID,
            b.DBNAME,
            b.SCHEMA,
            a.QS_ESTCOST,
            a.QS_ESTMEM,
            a.QS_ESTDISK,
            a.QS_RUNTIME,
            a.QS_TSTART,
            SUBSTRING(a.QS_SQL, 1, 100) AS SQL_PREVIEW
        FROM _V_QRYSTAT a
        LEFT JOIN _V_SESSION_DETAIL b ON b.SESSION_ID = a.QS_SESSIONID
        WHERE a.QS_PLANID = '$plan_id'
        ORDER BY a.QS_TSTART DESC
        LIMIT 20;" "Plan $plan_id Execution History"
        
        # Plan statistics
        execute_sql "
        SELECT 
            COUNT(*) AS TOTAL_EXECUTIONS,
            COUNT(DISTINCT QS_SESSIONID) AS UNIQUE_SESSIONS,
            ROUND(AVG(QS_ESTCOST), 2) AS AVG_EST_COST,
            ROUND(MIN(QS_ESTCOST), 2) AS MIN_EST_COST,
            ROUND(MAX(QS_ESTCOST), 2) AS MAX_EST_COST,
            ROUND(AVG(QS_RUNTIME), 2) AS AVG_RUNTIME_SEC,
            ROUND(MIN(QS_RUNTIME), 2) AS MIN_RUNTIME_SEC,
            ROUND(MAX(QS_RUNTIME), 2) AS MAX_RUNTIME_SEC,
            ROUND(AVG(QS_ESTMEM), 2) AS AVG_EST_MEM,
            ROUND(AVG(QS_ESTDISK), 2) AS AVG_EST_DISK,
            MIN(QS_TSTART) AS FIRST_EXECUTION,
            MAX(QS_TSTART) AS LAST_EXECUTION
        FROM _V_QRYSTAT
        WHERE QS_PLANID = '$plan_id';" "Plan $plan_id Statistics"
        
        # Users executing this plan
        execute_sql "
        SELECT 
            b.CLIENT_OS_USERNAME,
            b.SESSION_USERNAME,
            COUNT(*) AS EXECUTION_COUNT,
            ROUND(AVG(a.QS_ESTCOST), 2) AS AVG_COST,
            MAX(a.QS_TSTART) AS LAST_EXECUTION
        FROM _V_QRYSTAT a
        LEFT JOIN _V_SESSION_DETAIL b ON b.SESSION_ID = a.QS_SESSIONID
        WHERE a.QS_PLANID = '$plan_id'
        AND b.CLIENT_OS_USERNAME IS NOT NULL
        GROUP BY b.CLIENT_OS_USERNAME, b.SESSION_USERNAME
        ORDER BY EXECUTION_COUNT DESC;" "Users Executing Plan $plan_id"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

#=============================================================================
# Enhanced Session Analysis Functions
#=============================================================================

check_active_sessions() {
    print_header "ACTIVE SESSIONS AND SQL ANALYSIS"
    
    # First run the enhanced cost-based analysis
    check_cost_based_performance
    
    # Use nzsession utility for enhanced session analysis
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
        intelligent_nzsession_analysis "$found_nzsession"
    else
        print_warning "nzsession utility not found - using system view analysis only"
    fi
    
    # Enhanced Active Sessions using system views with cost information
    print_section "Current Sessions Analysis (Enhanced with Cost Data)"
    
    # Check if _V_SESSION_DETAIL is available for enhanced session info
    if execute_sql "SELECT COUNT(*) FROM _V_SESSION_DETAIL LIMIT 1;" "Test _V_SESSION_DETAIL" false; then
        execute_sql "
        SELECT 
            SESSION_ID,
            CLIENT_OS_USERNAME,
            SESSION_USERNAME,
            DBNAME,
            SCHEMA,
            PRIORITY_NAME,
            STATUS,
            IPADDR,
            CONNTIME
        FROM _V_SESSION_DETAIL
        ORDER BY CONNTIME DESC
        LIMIT ${TOP_SESSIONS_LIMIT};" "Current Sessions Overview (Enhanced)"
        
        # Sessions by client OS user
               print_section "Sessions by Client OS User"
        execute_sql "
        SELECT 
            CLIENT_OS_USERNAME,
            COUNT(*) AS SESSION_COUNT,
            COUNT(DISTINCT DBNAME) AS DATABASES_USED,
            MAX(CONNTIME) AS LATEST_CONNECTION
        FROM _V_SESSION_DETAIL
        WHERE CLIENT_OS_USERNAME IS NOT NULL
        GROUP BY CLIENT_OS_USERNAME
        ORDER BY SESSION_COUNT DESC
        LIMIT 15;" "Session Summary by Client OS User"
        
    else
        # Fallback to basic _V_SESSION
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
        LIMIT ${TOP_SESSIONS_LIMIT};" "Current Sessions Overview (Basic)"
    fi
    
    # Session status summary
    print_section "Session Status Summary"
    execute_sql "
    SELECT 
        STATUS,
        COUNT(*) AS SESSION_COUNT
    FROM _V_SESSION
    GROUP BY STATUS
    ORDER BY SESSION_COUNT DESC;" "Session Status Distribution"
    
    # Sessions by database with cost correlation if available
    print_section "Sessions by Database (with Cost Correlation)"
    execute_sql "
    SELECT 
        s.DBNAME,
        COUNT(DISTINCT s.ID) AS SESSION_COUNT,
        COUNT(DISTINCT s.USERNAME) AS UNIQUE_USERS,
        COALESCE(ROUND(AVG(q.QS_ESTCOST), 2), 0) AS AVG_QUERY_COST
    FROM _V_SESSION s
    LEFT JOIN _V_QRYSTAT q ON s.ID = q.QS_SESSIONID
    GROUP BY s.DBNAME
    ORDER BY AVG_QUERY_COST DESC, SESSION_COUNT DESC;" "Database Connection Summary with Cost"
}

#=============================================================================
# Query Performance Analysis Functions
#=============================================================================

check_query_performance() {
    print_header "QUERY PERFORMANCE ANALYSIS"
    
    # Check if we should prioritize _V_QRYSTAT or _V_QRYHIST
    local use_qrystat=false
    if execute_sql "SELECT COUNT(*) FROM _V_QRYSTAT LIMIT 1;" "Test _V_QRYSTAT availability" false; then
        use_qrystat=true
        print_success "Using _V_QRYSTAT for enhanced real-time analysis"
    else
        print_warning "Using _V_QRYHIST for historical analysis"
    fi
    
    if [[ "$use_qrystat" == true ]]; then
        # Enhanced analysis using _V_QRYSTAT for real-time data
        print_section "Current Long-Running Queries (Real-time from _V_QRYSTAT)"
        execute_sql "
        SELECT 
            QS_SESSIONID,
            QS_PLANID,
            SUBSTRING(QS_SQL, 1, 100) AS SQL_PREVIEW,
            QS_TSTART,
            ROUND(EXTRACT(EPOCH FROM (NOW() - QS_TSTART))/3600, 2) AS HOURS_RUNNING,
            QS_ESTCOST,
            QS_ESTMEM,
            QS_ESTDISK,
            QS_RUNTIME
        FROM _V_QRYSTAT
        WHERE QS_TSTART < NOW() - INTERVAL '${LONG_RUNNING_QUERY_HOURS} HOURS'
        AND QS_RUNTIME IS NULL  -- Still running
        ORDER BY QS_TSTART
        LIMIT ${TOP_QUERIES_LIMIT};" "Current Long-Running Queries (Real-time)"
        
        # Resource-intensive queries currently running
        print_section "High-Cost Queries Currently Running"
        execute_sql "
        SELECT 
            QS_SESSIONID,
            QS_PLANID,
            QS_ESTCOST,
            QS_ESTMEM,
            QS_ESTDISK,
            ROUND(EXTRACT(EPOCH FROM (NOW() - QS_TSTART))/60, 1) AS MINUTES_RUNNING,
            SUBSTRING(QS_SQL, 1, 80) AS SQL_PREVIEW
        FROM _V_QRYSTAT
        WHERE QS_RUNTIME IS NULL  -- Still running
        AND QS_ESTCOST > 100      -- High estimated cost
        ORDER BY QS_ESTCOST DESC
        LIMIT ${TOP_QUERIES_LIMIT};" "High-Cost Running Queries"
        
        # Completed queries with performance metrics
        print_section "Recently Completed Query Performance"
        execute_sql "
        SELECT 
            QS_SESSIONID,
            QS_PLANID,
            QS_ESTCOST,
            QS_RUNTIME,
            ROUND(QS_ESTCOST / NULLIF(QS_RUNTIME, 0), 2) AS COST_PER_SECOND,
            QS_RESROWS,
            QS_RESBYTES,
            SUBSTRING(QS_SQL, 1, 80) AS SQL_PREVIEW
        FROM _V_QRYSTAT
        WHERE QS_RUNTIME IS NOT NULL  -- Completed
        AND QS_RUNTIME > 30           -- Ran for more than 30 seconds
        ORDER BY QS_RUNTIME DESC
        LIMIT ${TOP_QUERIES_LIMIT};" "Recently Completed Slow Queries"
        
    else
        # Fallback to historical analysis using _V_QRYHIST
        print_section "Long-Running Query Analysis (Historical)"
        
        # Current long-running queries
        execute_sql "
        SELECT 
            QH_SESSIONID,
            QH_USER,
            QH_DATABASE,
            QH_TSTART,
            ROUND(EXTRACT(EPOCH FROM (NOW() - QH_TSTART))/3600, 2) AS HOURS_RUNNING,
            QH_PRIORITY,
            SUBSTR(QH_SQL, 1, 100) AS SQL_PREVIEW
        FROM _V_QRYHIST
        WHERE QH_TEND IS NULL
        AND QH_TSTART < NOW() - INTERVAL '${LONG_RUNNING_QUERY_HOURS} HOURS'
        ORDER BY QH_TSTART
        LIMIT ${TOP_QUERIES_LIMIT};" "Current Long-Running Queries (${LONG_RUNNING_QUERY_HOURS}+ hours)"
        
        # Query performance summary from history
        print_section "Query Performance Summary (Last 24 Hours)"
        execute_sql "
        SELECT 
            QH_DATABASE,
            COUNT(*) as QUERY_COUNT,
            ROUND(AVG(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART))), 2) as AVG_DURATION_SEC,
            ROUND(MAX(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART))), 2) as MAX_DURATION_SEC,
            COUNT(DISTINCT QH_USER) as UNIQUE_USERS
        FROM _V_QRYHIST
        WHERE QH_TEND > NOW() - INTERVAL '24 HOURS'
        AND QH_TEND IS NOT NULL
        GROUP BY QH_DATABASE
        ORDER BY AVG_DURATION_SEC DESC;" "Query Performance by Database"
        
        # Top resource consuming queries
        print_section "Top Resource Consuming Queries (Last 24 Hours)"
        execute_sql "
        SELECT 
            QH_SESSIONID,
            QH_USER,
            QH_DATABASE,
            QH_TSTART,
            QH_TEND,
            ROUND(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)), 2) AS DURATION_SEC,
            QH_RESROWS,
            QH_PRIORITY,
            SUBSTR(QH_SQL, 1, 150) AS SQL_PREVIEW
        FROM _V_QRYHIST
        WHERE QH_TEND > NOW() - INTERVAL '24 HOURS'
        AND QH_TEND IS NOT NULL
        AND EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART)) > 30
        ORDER BY DURATION_SEC DESC
        LIMIT ${TOP_QUERIES_LIMIT};" "Slowest Queries (Last 24h)"
    fi
    
    # Common analysis regardless of view used
    print_section "Query Activity by User (Last 24 Hours)"
    if [[ "$use_qrystat" == true ]]; then
        # Enhanced user analysis with _V_QRYSTAT
        execute_sql "
        SELECT 
            s.CLIENT_OS_USERNAME,
            s.SESSION_USERNAME,
            COUNT(*) as QUERY_COUNT,
            ROUND(AVG(q.QS_ESTCOST), 2) as AVG_EST_COST,
            ROUND(AVG(q.QS_RUNTIME), 2) as AVG_RUNTIME_SEC,
            COUNT(DISTINCT q.QS_PLANID) as UNIQUE_PLANS,
            MAX(q.QS_TSTART) as LAST_QUERY_TIME
        FROM _V_QRYSTAT q
        LEFT JOIN _V_SESSION_DETAIL s ON s.SESSION_ID = q.QS_SESSIONID
        WHERE q.QS_TSTART > NOW() - INTERVAL '24 HOURS'
        AND s.CLIENT_OS_USERNAME IS NOT NULL
        GROUP BY s.CLIENT_OS_USERNAME, s.SESSION_USERNAME
        ORDER BY QUERY_COUNT DESC
        LIMIT 15;" "Most Active Users (Enhanced)"
    else
        # Basic user analysis with _V_QRYHIST
        execute_sql "
        SELECT 
            QH_USER,
            COUNT(*) as QUERY_COUNT,
            ROUND(AVG(EXTRACT(EPOCH FROM (QH_TEND - QH_TSTART))), 2) as AVG_DURATION_SEC,
            SUM(QH_RESROWS) as TOTAL_ROWS_RETURNED,
            MAX(QH_TSTART) as LAST_QUERY_TIME
        FROM _V_QRYHIST
        WHERE QH_TEND > NOW() - INTERVAL '24 HOURS'
        AND QH_TEND IS NOT NULL
        GROUP BY QH_USER
        ORDER BY QUERY_COUNT DESC
        LIMIT 15;" "Most Active Users"
    fi
    
    # Performance recommendations
    print_section "Performance Analysis Summary"
    
    if [[ "$use_qrystat" == true ]]; then
        echo -e "${GREEN}Using _V_QRYSTAT for real-time analysis provides:${NC}"
        echo "✓ Current running query monitoring"
        echo "✓ Plan ID tracking for optimization opportunities"
        echo "✓ Cost vs runtime efficiency analysis"
        echo "✓ Resource usage patterns"
        echo ""
        echo -e "${CYAN}Recommendation: Use Option 7 (Cost-Based Analysis) for deeper insights${NC}"
    else
        echo -e "${YELLOW}Using _V_QRYHIST for historical analysis provides:${NC}"
        echo "✓ Completed query performance trends"
        echo "✓ User activity patterns"
        echo "✓ Long-term performance monitoring"
        echo ""
        echo -e "${CYAN}Recommendation: Consider upgrading to access _V_QRYSTAT for real-time monitoring${NC}"
    fi
}