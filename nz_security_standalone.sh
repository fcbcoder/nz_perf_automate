#!/bin/bash

#=============================================================================
# Netezza Security and Permissions Analysis Tool - Updated for Actual Schema
# Version: 1.2
# Date: October 3, 2025
# Description: Interactive security audit and permission analysis for Netezza
# Author: Database Administrator
#=============================================================================

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration variables
NZSQL_PATH="/nz/bin/nzsql"
NETEZZA_HOST=""
NETEZZA_DB="SYSTEM"
NETEZZA_USER="ADMIN"
SECURITY_LOG_FILE="/tmp/netezza_security_$(date +%Y%m%d_%H%M%S).log"

# Build nzsql command
build_nzsql_cmd() {
    local cmd="$NZSQL_PATH"
    
    if [[ -n "$NETEZZA_HOST" ]]; then
        cmd="$cmd -host $NETEZZA_HOST"
    fi
    
    if [[ -n "$NETEZZA_DB" ]]; then
        cmd="$cmd -d $NETEZZA_DB"
    fi
    
    if [[ -n "$NETEZZA_USER" ]]; then
        cmd="$cmd -u $NETEZZA_USER"
    fi
    
    echo "$cmd"
}

# Set the NZSQL command
NZSQL_CMD=$(build_nzsql_cmd)

#=============================================================================
# Utility Functions
#=============================================================================

print_header() {
    local title="$1"
    echo -e "\n${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN} $title${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}\n"
}

print_section() {
    local title="$1"
    echo -e "\n${YELLOW}▶ $title${NC}"
    echo -e "${YELLOW}$(printf '─%.0s' {1..80})${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_security_header() {
    local title="$1"
    echo -e "\n${PURPLE}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE} 🔐 $title${NC}"
    echo -e "${PURPLE}════════════════════════════════════════════════════════════════════════════════${NC}\n"
}

# Execute SQL with error handling
execute_sql() {
    local sql="$1"
    local description="${2:-Query}"
    local show_output="${3:-true}"
    local log_file="${4:-$SECURITY_LOG_FILE}"
    
    # Log the SQL
    echo "$(date): $description" >> "$log_file"
    echo "SQL: $sql" >> "$log_file"
    
    if [[ "$show_output" == "true" ]]; then
        echo -e "${CYAN}Executing: $description${NC}"
    fi
    
    # Execute the SQL
    local result
    if result=$($NZSQL_CMD -c "$sql" 2>&1); then
        if [[ "$show_output" == "true" ]]; then
            echo "$result"
        fi
        echo "Result: SUCCESS" >> "$log_file"
        return 0
    else
        if [[ "$show_output" == "true" ]]; then
            print_error "Failed to execute: $description"
            echo "Error: $result"
        fi
        echo "Result: ERROR - $result" >> "$log_file"
        return 1
    fi
}

# Safe SQL execution with fallback
execute_safe_sql() {
    local view_name="$1"
    local sql="$2"
    local description="${3:-Query}"
    
    # Check if view exists first
    if ! $NZSQL_CMD -c "SELECT COUNT(*) FROM $view_name LIMIT 1;" &>/dev/null; then
        print_warning "View $view_name is not available"
        return 1
    fi
    
    execute_sql "$sql" "$description" true
}

# Test database connection
test_connection() {
    print_section "Testing Database Connection"
    
    if execute_sql "SELECT CURRENT_TIMESTAMP;" "Connection Test" true; then
        print_success "Database connection successful"
        return 0
    else
        print_error "Database connection failed"
        echo ""
        echo "Current settings:"
        echo "  - nzsql path: $NZSQL_PATH"
        echo "  - Host: ${NETEZZA_HOST:-'(local connection)'}"
        echo "  - Database: $NETEZZA_DB"
        echo "  - User: $NETEZZA_USER"
        echo ""
        return 1
    fi
}

# Configuration management
configure_settings() {
    print_header "SECURITY TOOL CONFIGURATION"
    
    echo "Current settings:"
    echo "1. nzsql path: $NZSQL_PATH"
    echo "2. Host: ${NETEZZA_HOST:-'(local connection)'}"
    echo "3. Database: $NETEZZA_DB"
    echo "4. User: $NETEZZA_USER"
    echo ""
    
    read -p "Enter new nzsql path (current: $NZSQL_PATH): " new_path
    if [[ -n "$new_path" ]]; then
        NZSQL_PATH="$new_path"
    fi
    
    read -p "Enter Netezza host (leave blank for local): " new_host
    NETEZZA_HOST="$new_host"
    
    read -p "Enter database name (current: $NETEZZA_DB): " new_db
    if [[ -n "$new_db" ]]; then
        NETEZZA_DB="$new_db"
    fi
    
    read -p "Enter username (current: $NETEZZA_USER): " new_user
    if [[ -n "$new_user" ]]; then
        NETEZZA_USER="$new_user"
    fi
    
    # Rebuild command
    NZSQL_CMD=$(build_nzsql_cmd)
    
    print_success "Configuration updated"
    
    # Test new connection
    test_connection
}

# View log file
view_log_file() {
    print_section "Security Analysis Log"
    
    if [[ -f "$SECURITY_LOG_FILE" ]]; then
        echo "Log file: $SECURITY_LOG_FILE"
        echo ""
        echo "Recent entries:"
        tail -20 "$SECURITY_LOG_FILE"
    else
        print_warning "No log file found at: $SECURITY_LOG_FILE"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

#=============================================================================
# Security Analysis Functions - Updated for Correct Schema
#=============================================================================

discover_security_views() {
    print_security_header "NETEZZA SECURITY VIEWS DISCOVERY"
    
    print_section "Discovering Security-Related System Views"
    
    # Test security-related views based on your actual system
    local security_views=(
        "_V_USER" "_V_ROLE" "_V_GROUP" "_V_AUTHENTICATION" "_V_AUTHENTICATION_SETTINGS"
        "_V_ACL_DATA" "_V_SECURITY_LEVEL" "_V_SECURITY_CATEGORY"
        "_V_SESSION" "_V_DATABASE" "_V_SCHEMA" "_V_TABLE" "_V_VIEW"
    )
    
    local available_security_views=()
    local unavailable_security_views=()
    
    for view in "${security_views[@]}"; do
        echo -n "Testing $view... "
        if $NZSQL_CMD -c "SELECT COUNT(*) FROM $view LIMIT 1;" &>/dev/null; then
            echo -e "${GREEN}✓ Available${NC}"
            available_security_views+=("$view")
        else
            echo -e "${RED}✗ Not available${NC}"
            unavailable_security_views+=("$view")
        fi
    done
    
    echo ""
    print_section "Available Security Views (${#available_security_views[@]})"
    for view in "${available_security_views[@]}"; do
        echo -e "  ${GREEN}✓${NC} $view"
    done
    
    echo ""
    print_section "Column Structure Analysis"
    
    # Check column structures for key views
    for view in "${available_security_views[@]}"; do
        echo ""
        echo -e "${CYAN}Columns in $view:${NC}"
        execute_sql "SELECT * FROM $view LIMIT 0;" "Column Structure for $view" true
    done
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_user_permissions() {
    print_security_header "USER PERMISSIONS ANALYSIS"
    
    echo "What would you like to analyze?"
    echo "1. Specific user information"
    echo "2. All users summary"
    echo "3. Account status analysis"
    echo "4. User resource group assignments"
    echo "5. Authentication method analysis"
    echo "6. Return to security menu"
    echo ""
    
    read -p "Choose an option (1-6): " choice
    
    case $choice in
        1) analyze_specific_user ;;
        2) analyze_all_users_summary ;;
        3) analyze_account_status ;;
        4) analyze_user_resource_groups ;;
        5) analyze_authentication_methods ;;
        6) return ;;
        *) print_error "Invalid option" ;;
    esac
}

analyze_specific_user() {
    echo ""
    read -p "Enter username to analyze: " username
    
    if [[ -z "$username" ]]; then
        print_error "Username cannot be empty"
        return
    fi
    
    username=$(echo "$username" | tr '[:lower:]' '[:upper:]')
    
    print_section "User Information for: $username"
    
    # Basic user information using correct column names
    execute_sql "
    SELECT 
        USERNAME,
        OWNER,
        CREATEDATE,
        ACCT_LOCKED,
        PWD_INVALID,
        PWD_LAST_CHGED,
        SESSIONTIMEOUT,
        QUERYTIMEOUT,
        DEF_PRIORITY,
        MAX_PRIORITY,
        USERESOURCEGRPNAME
    FROM _V_USER 
    WHERE UPPER(USERNAME) = '$username';" "User Details" true
    
    # Check if user exists
    user_exists=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_USER WHERE UPPER(USERNAME) = '$username';" 2>/dev/null | tr -d ' ')
    
    if [[ "$user_exists" -eq 0 ]]; then
        print_warning "User '$username' not found in the system"
        echo ""
        echo "Searching for similar usernames..."
        execute_sql "
        SELECT USERNAME 
        FROM _V_USER 
        WHERE USERNAME LIKE '%${username}%' 
        ORDER BY USERNAME;" "Similar Usernames" true
        return
    fi
    
    print_success "User '$username' found in the system"
    
    # Check account status
    print_section "Account Status for $username"
    
    acct_locked=$($NZSQL_CMD -t -c "SELECT ACCT_LOCKED FROM _V_USER WHERE UPPER(USERNAME) = '$username';" 2>/dev/null | tr -d ' ')
    pwd_invalid=$($NZSQL_CMD -t -c "SELECT PWD_INVALID FROM _V_USER WHERE UPPER(USERNAME) = '$username';" 2>/dev/null | tr -d ' ')
    
    if [[ "$acct_locked" == "t" || "$acct_locked" == "true" ]]; then
        print_warning "⚠️  ACCOUNT IS LOCKED"
    else
        print_success "✓ Account is not locked"
    fi
    
    if [[ "$pwd_invalid" == "t" || "$pwd_invalid" == "true" ]]; then
        print_warning "⚠️  PASSWORD IS INVALID"
    else
        print_success "✓ Password is valid"
    fi
    
    # Current active sessions
    print_section "Current Active Sessions for $username"
    execute_safe_sql "_V_SESSION" "
    SELECT 
        ID,
        USERNAME,
        DBNAME,
        STATUS,
        IPADDR,
        CONNTIME
    FROM _V_SESSION
    WHERE UPPER(USERNAME) = '$username';" "Current Sessions"
    
    # Recent activity using query history
    print_section "Recent Query Activity for $username"
    execute_safe_sql "_V_QRYHIST" "
    SELECT 
        QH_DATABASE,
        COUNT(*) as QUERY_COUNT,
        MAX(QH_TSTART) as LAST_ACTIVITY
    FROM _V_QRYHIST
    WHERE UPPER(QH_USER) = '$username'
    AND QH_TSTART > NOW() - INTERVAL '7 DAYS'
    GROUP BY QH_DATABASE
    ORDER BY QUERY_COUNT DESC;" "Recent Activity (Last 7 Days)"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_all_users_summary() {
    print_section "All Users Summary"
    
    execute_sql "
    SELECT 
        USERNAME,
        OWNER,
        CREATEDATE,
        ACCT_LOCKED,
        PWD_INVALID,
        USERESOURCEGRPNAME
    FROM _V_USER
    ORDER BY USERNAME;" "All Users Summary"
    
    echo ""
    print_section "User Statistics"
    
    # Count statistics
    total_users=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_USER;" 2>/dev/null | tr -d ' ')
    locked_users=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_USER WHERE ACCT_LOCKED = 't';" 2>/dev/null | tr -d ' ')
    invalid_pwd_users=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_USER WHERE PWD_INVALID = 't';" 2>/dev/null | tr -d ' ')
    
    echo "Total users: $total_users"
    echo "Locked accounts: $locked_users"
    echo "Invalid passwords: $invalid_pwd_users"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_account_status() {
    print_section "Account Status Analysis"
    
    # Locked accounts
    print_section "Locked Accounts"
    execute_sql "
    SELECT 
        USERNAME,
        OWNER,
        CREATEDATE,
        ACCT_LOCKED,
        INV_CONN_CNT
    FROM _V_USER
    WHERE ACCT_LOCKED = 't'
    ORDER BY USERNAME;" "Locked Accounts"
    
    # Invalid passwords
    print_section "Accounts with Invalid Passwords"
    execute_sql "
    SELECT 
        USERNAME,
        OWNER,
        CREATEDATE,
        PWD_INVALID,
        PWD_LAST_CHGED
    FROM _V_USER
    WHERE PWD_INVALID = 't'
    ORDER BY USERNAME;" "Invalid Password Accounts"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_user_resource_groups() {
    print_section "User Resource Group Analysis"
    
    # Users by resource group
    execute_sql "
    SELECT 
        USERESOURCEGRPNAME,
        COUNT(*) as USER_COUNT,
        STRING_AGG(USERNAME, ', ') as USERS
    FROM _V_USER
    WHERE USERESOURCEGRPNAME IS NOT NULL
    GROUP BY USERESOURCEGRPNAME
    ORDER BY USER_COUNT DESC;" "Users by Resource Group"
    
    # Resource group details
    print_section "Resource Group Details"
    execute_safe_sql "_V_GROUP" "
    SELECT 
        GROUPNAME,
        OWNER,
        CREATEDATE,
        SESSIONTIMEOUT,
        QUERYTIMEOUT,
        DEF_PRIORITY,
        MAX_PRIORITY,
        GRORSGPERCENT,
        RSGMAXPERCENT
    FROM _V_GROUP
    ORDER BY GROUPNAME;" "Resource Group Settings"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_authentication_methods() {
    print_section "Authentication Configuration"
    
    # Authentication settings
    execute_safe_sql "_V_AUTHENTICATION_SETTINGS" "
    SELECT 
        AUTH_OPTION,
        AUTH_VALUE
    FROM _V_AUTHENTICATION_SETTINGS
    ORDER BY AUTH_OPTION;" "Authentication Settings"
    
    # Current authentication method
    execute_safe_sql "_V_AUTHENTICATION" "
    SELECT 
        AUTH_OPTION,
        AUTH_VALUE
    FROM _V_AUTHENTICATION;" "Current Authentication Method"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_role_permissions() {
    print_security_header "ROLE ANALYSIS"
    
    echo "What would you like to analyze?"
    echo "1. All roles summary"
    echo "2. Specific role details"
    echo "3. Role creation analysis"
    echo "4. Admin roles"
    echo "5. Return to security menu"
    echo ""
    
    read -p "Choose an option (1-5): " choice
    
    case $choice in
        1) analyze_all_roles_summary ;;
        2) analyze_specific_role ;;
        3) analyze_role_creation ;;
        4) analyze_admin_roles ;;
        5) return ;;
        *) print_error "Invalid option" ;;
    esac
}

analyze_all_roles_summary() {
    print_section "All Roles Summary"
    
    execute_sql "
    SELECT 
        ROLENAME,
        ROLEGRANTOR,
        ASADMIN,
        CREATEDATE
    FROM _V_ROLE
    ORDER BY ROLENAME;" "All Roles Summary"
    
    echo ""
    print_section "Role Statistics"
    
    total_roles=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_ROLE;" 2>/dev/null | tr -d ' ')
    admin_roles=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_ROLE WHERE ASADMIN = 't';" 2>/dev/null | tr -d ' ')
    
    echo "Total roles: $total_roles"
    echo "Admin roles: $admin_roles"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_specific_role() {
    echo ""
    read -p "Enter role name to analyze: " rolename
    
    if [[ -z "$rolename" ]]; then
        print_error "Role name cannot be empty"
        return
    fi
    
    rolename=$(echo "$rolename" | tr '[:lower:]' '[:upper:]')
    
    print_section "Role Information for: $rolename"
    
    # Basic role information
    execute_sql "
    SELECT 
        ROLENAME,
        ROLEGRANTOR,
        ASADMIN,
        CREATEDATE
    FROM _V_ROLE 
    WHERE UPPER(ROLENAME) = '$rolename';" "Role Details" true
    
    # Check if role exists
    role_exists=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_ROLE WHERE UPPER(ROLENAME) = '$rolename';" 2>/dev/null | tr -d ' ')
    
    if [[ "$role_exists" -eq 0 ]]; then
        print_warning "Role '$rolename' not found in the system"
        echo ""
        echo "Searching for similar role names..."
        execute_sql "
        SELECT ROLENAME 
        FROM _V_ROLE 
        WHERE ROLENAME LIKE '%${rolename}%' 
        ORDER BY ROLENAME;" "Similar Role Names" true
        return
    fi
    
    print_success "Role '$rolename' found in the system"
    
    # Check admin status
    asadmin=$($NZSQL_CMD -t -c "SELECT ASADMIN FROM _V_ROLE WHERE UPPER(ROLENAME) = '$rolename';" 2>/dev/null | tr -d ' ')
    if [[ "$asadmin" == "t" || "$asadmin" == "true" ]]; then
        print_warning "⚠️  ROLE HAS ADMIN PRIVILEGES"
    else
        print_success "✓ Role does not have admin privileges"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_admin_roles() {
    print_section "Roles with Admin Privileges"
    
    execute_sql "
    SELECT 
        ROLENAME,
        ROLEGRANTOR,
        CREATEDATE,
        ASADMIN
    FROM _V_ROLE
    WHERE ASADMIN = 't'
    ORDER BY CREATEDATE;" "Admin Roles"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_role_creation() {
    print_section "Role Creation Analysis"
    
    # Roles by grantor
    execute_sql "
    SELECT 
        ROLEGRANTOR,
        COUNT(*) as ROLES_CREATED,
        STRING_AGG(ROLENAME, ', ') as ROLES
    FROM _V_ROLE
    GROUP BY ROLEGRANTOR
    ORDER BY ROLES_CREATED DESC;" "Roles by Creator"
    
    # Recent role creation
    print_section "Recently Created Roles (Last 30 Days)"
    execute_sql "
    SELECT 
        ROLENAME,
        ROLEGRANTOR,
        CREATEDATE,
        ASADMIN
    FROM _V_ROLE
    WHERE CREATEDATE > NOW() - INTERVAL '30 DAYS'
    ORDER BY CREATEDATE DESC;" "Recent Roles"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_database_access() {
    print_security_header "DATABASE ACCESS ANALYSIS"
    
    echo "What would you like to analyze?"
    echo "1. Database ownership"
    echo "2. Database access through ACL"
    echo "3. Current database sessions"
    echo "4. Database usage statistics"
    echo "5. Return to security menu"
    echo ""
    
    read -p "Choose an option (1-5): " choice
    
    case $choice in
        1) analyze_database_ownership ;;
        2) analyze_database_acl ;;
        3) analyze_database_sessions ;;
        4) analyze_database_usage ;;
        5) return ;;
        *) print_error "Invalid option" ;;
    esac
}

analyze_database_ownership() {
    print_section "Database Ownership Analysis"
    
    execute_safe_sql "_V_DATABASE" "
    SELECT 
        DATABASE,
        OWNER,
        CREATEDATE
    FROM _V_DATABASE
    ORDER BY DATABASE;" "Database Ownership"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_database_acl() {
    print_section "Database Access Control List (ACL) Analysis"
    
    execute_safe_sql "_V_ACL_DATA" "
    SELECT 
        ACLDB,
        ACLOBJECT,
        ACLOBJPRIV,
        COUNT(*) as ACL_COUNT
    FROM _V_ACL_DATA
    GROUP BY ACLDB, ACLOBJECT, ACLOBJPRIV
    ORDER BY ACLDB, ACLOBJECT;" "ACL Summary"
    
    echo ""
    print_warning "Note: ACL data interpretation requires additional system knowledge"
    print_warning "ACLDB: Database ID, ACLOBJECT: Object ID, ACLOBJPRIV: Privilege bitmask"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_database_sessions() {
    print_section "Current Database Sessions"
    
    execute_safe_sql "_V_SESSION" "
    SELECT 
        DBNAME,
        COUNT(*) as SESSION_COUNT,
        COUNT(DISTINCT USERNAME) as UNIQUE_USERS,
        STRING_AGG(DISTINCT STATUS, ', ') as STATUSES
    FROM _V_SESSION
    GROUP BY DBNAME
    ORDER BY SESSION_COUNT DESC;" "Sessions by Database"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_database_usage() {
    print_section "Database Usage Statistics (Last 7 Days)"
    
    execute_safe_sql "_V_QRYHIST" "
    SELECT 
        QH_DATABASE,
        COUNT(*) as QUERY_COUNT,
        COUNT(DISTINCT QH_USER) as UNIQUE_USERS,
        MAX(QH_TSTART) as LAST_ACTIVITY,
        MIN(QH_TSTART) as FIRST_ACTIVITY
    FROM _V_QRYHIST
    WHERE QH_TSTART > NOW() - INTERVAL '7 DAYS'
    GROUP BY QH_DATABASE
    ORDER BY QUERY_COUNT DESC;" "Database Usage Statistics"
    
    echo ""
    read -p "Press Enter to continue..."
}

quick_permission_lookup() {
    print_security_header "QUICK SECURITY LOOKUP"
    
    echo "What do you want to check quickly?"
    echo "1. Is user account locked or has invalid password?"
    echo "2. What resource group is user assigned to?"
    echo "3. Does role have admin privileges?"
    echo "4. Who owns a specific database?"
    echo "5. Is user currently active (has sessions)?"
    echo "6. User's recent activity summary"
    echo "7. Return to security menu"
    echo ""
    
    read -p "Choose an option (1-7): " choice
    
    case $choice in
        1) quick_check_account_status ;;
        2) quick_check_user_resource_group ;;
        3) quick_check_role_admin ;;
        4) quick_check_database_owner ;;
        5) quick_check_user_sessions ;;
        6) quick_check_user_activity ;;
        7) return ;;
        *) print_error "Invalid option" ;;
    esac
}

quick_check_account_status() {
    echo ""
    read -p "Enter username: " username
    
    username=$(echo "$username" | tr '[:lower:]' '[:upper:]')
    
    print_section "Account Status Check: $username"
    
    # Check if user exists and get status
    user_info=$($NZSQL_CMD -t -c "
    SELECT USERNAME, ACCT_LOCKED, PWD_INVALID, CREATEDATE 
    FROM _V_USER 
    WHERE UPPER(USERNAME) = '$username';" 2>/dev/null)
    
    if [[ -z "$user_info" ]]; then
        print_warning "User '$username' not found"
        return
    fi
    
    echo "$user_info" | while IFS='|' read -r uname locked invalid created; do
        uname=$(echo "$uname" | tr -d ' ')
        locked=$(echo "$locked" | tr -d ' ')
        invalid=$(echo "$invalid" | tr -d ' ')
        created=$(echo "$created" | tr -d ' ')
        
        echo "User: $uname"
        echo "Created: $created"
        
        if [[ "$locked" == "t" ]]; then
            print_warning "⚠️  ACCOUNT IS LOCKED"
        else
            print_success "✓ Account is not locked"
        fi
        
        if [[ "$invalid" == "t" ]]; then
            print_warning "⚠️  PASSWORD IS INVALID"
        else
            print_success "✓ Password is valid"
        fi
    done
    
    echo ""
    read -p "Press Enter to continue..."
}

quick_check_user_resource_group() {
    echo ""
    read -p "Enter username: " username
    
    username=$(echo "$username" | tr '[:lower:]' '[:upper:]')
    
    print_section "Resource Group Check: $username"
    
    execute_sql "
    SELECT 
        USERNAME,
        USERESOURCEGRPNAME,
        DEF_PRIORITY,
        MAX_PRIORITY,
        SESSIONTIMEOUT,
        QUERYTIMEOUT
    FROM _V_USER
    WHERE UPPER(USERNAME) = '$username';" "User Resource Group"
    
    echo ""
    read -p "Press Enter to continue..."
}

quick_check_role_admin() {
    echo ""
    read -p "Enter role name: " rolename
    
    rolename=$(echo "$rolename" | tr '[:lower:]' '[:upper:]')
    
    print_section "Admin Privilege Check: $rolename"
    
    role_info=$($NZSQL_CMD -t -c "
    SELECT ROLENAME, ASADMIN, ROLEGRANTOR 
    FROM _V_ROLE 
    WHERE UPPER(ROLENAME) = '$rolename';" 2>/dev/null)
    
    if [[ -z "$role_info" ]]; then
        print_warning "Role '$rolename' not found"
        return
    fi
    
    echo "$role_info" | while IFS='|' read -r rname asadmin grantor; do
        rname=$(echo "$rname" | tr -d ' ')
        asadmin=$(echo "$asadmin" | tr -d ' ')
        grantor=$(echo "$grantor" | tr -d ' ')
        
        echo "Role: $rname"
        echo "Created by: $grantor"
        
        if [[ "$asadmin" == "t" ]]; then
            print_warning "⚠️  ROLE HAS ADMIN PRIVILEGES"
        else
            print_success "✓ Role does not have admin privileges"
        fi
    done
    
    echo ""
    read -p "Press Enter to continue..."
}

quick_check_database_owner() {
    echo ""
    read -p "Enter database name: " dbname
    
    dbname=$(echo "$dbname" | tr '[:lower:]' '[:upper:]')
    
    print_section "Database Owner Check: $dbname"
    
    execute_safe_sql "_V_DATABASE" "
    SELECT 
        DATABASE,
        OWNER,
        CREATEDATE
    FROM _V_DATABASE
    WHERE UPPER(DATABASE) = '$dbname';" "Database Owner"
    
    echo ""
    read -p "Press Enter to continue..."
}

quick_check_user_sessions() {
    echo ""
    read -p "Enter username: " username
    
    username=$(echo "$username" | tr '[:lower:]' '[:upper:]')
    
    print_section "Current Sessions: $username"
    
    execute_safe_sql "_V_SESSION" "
    SELECT 
        ID,
        USERNAME,
        DBNAME,
        STATUS,
        IPADDR,
        CONNTIME
    FROM _V_SESSION
    WHERE UPPER(USERNAME) = '$username';" "Current Sessions"
    
    echo ""
    read -p "Press Enter to continue..."
}

quick_check_user_activity() {
    echo ""
    read -p "Enter username: " username
    
    username=$(echo "$username" | tr '[:lower:]' '[:upper:]')
    
    print_section "Recent Activity Summary: $username"
    
    execute_safe_sql "_V_QRYHIST" "
    SELECT 
        QH_DATABASE,
        COUNT(*) as QUERIES,
        MAX(QH_TSTART) as LAST_ACTIVITY,
        MIN(QH_TSTART) as FIRST_ACTIVITY
    FROM _V_QRYHIST
    WHERE UPPER(QH_USER) = '$username'
    AND QH_TSTART > NOW() - INTERVAL '7 DAYS'
    GROUP BY QH_DATABASE
    ORDER BY QUERIES DESC;" "Recent Activity (7 days)"
    
    echo ""
    read -p "Press Enter to continue..."
}

show_security_menu() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                   NETEZZA SECURITY & PERMISSIONS ANALYZER                   ║${NC}"
    echo -e "${PURPLE}║                         Version 1.2 - Corrected Schema                      ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Security Analysis Options:${NC}"
    echo "1. 🔍 Discover Security System Views (Run this first!)"
    echo "2. 👤 User Account Analysis"
    echo "3. 👥 Role Analysis"
    echo "4. 🗄️  Database Access Analysis"
    echo "5. ❓ Quick Security Lookup"
    echo "6. ⚙️  Security Configuration"
    echo "7. 📋 View Security Log"
    echo "8. 🚪 Exit"
    echo ""
    echo -e "${YELLOW}Current Settings:${NC}"
    echo "  - Host: ${NETEZZA_HOST:-'(local connection)'}"
    echo "  - Database: $NETEZZA_DB"
    echo "  - User: $NETEZZA_USER"
    echo "  - Security Log: $SECURITY_LOG_FILE"
    echo ""
    echo -e "${YELLOW}Note: This version is updated to work with your actual Netezza schema${NC}"
    echo ""
}

#=============================================================================
# Main Security Program
#=============================================================================

main_security() {
    # Test connection if not already done
    if ! test_connection 2>/dev/null; then
        echo ""
        read -p "Would you like to configure connection settings? (y/n): " config_choice
        if [[ "$config_choice" =~ ^[Yy] ]]; then
            configure_settings
        else
            exit 1
        fi
    fi
    
    # Main security program loop
    while true; do
        show_security_menu
        read -p "Choose an option (1-8): " choice
        
        case $choice in
            1)
                discover_security_views
                ;;
            2)
                analyze_user_permissions
                ;;
            3)
                analyze_role_permissions
                ;;
            4)
                analyze_database_access
                ;;
            5)
                quick_permission_lookup
                ;;
            6)
                configure_settings
                ;;
            7)
                view_log_file
                ;;
            8)
                print_success "Thank you for using Netezza Security Analyzer!"
                exit 0
                ;;
            *)
                print_error "Invalid option. Please choose 1-8."
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_security "$@"
fi