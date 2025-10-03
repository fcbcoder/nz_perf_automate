#!/bin/bash

#=============================================================================
# Netezza Security and Permissions Analysis Tool - Standalone Version
# Version: 1.1
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
# Security Analysis Functions
#=============================================================================

discover_security_views() {
    print_security_header "NETEZZA SECURITY VIEWS DISCOVERY"
    
    print_section "Discovering Security-Related System Views"
    
    # Test security-related views
    local security_views=(
        "_V_USER" "_V_ROLE" "_V_USER_ROLE" "_V_PRIVILEGE" "_V_OBJECT_PRIVILEGE"
        "_V_AUTHENTICATION" "_V_AUTHENTICATION_SETTINGS" "_V_GROUP" "_V_USER_GROUP"
        "_V_SCHEMA_PRIVILEGE" "_V_TABLE_PRIVILEGE" "_V_DATABASE_PRIVILEGE"
        "_V_ACL" "_V_ACL_DATA" "_V_SECURITY_LEVEL" "_V_SECURITY_CATEGORY"
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
    
    # Check column structures for available views
    for view in "${available_security_views[@]}"; do
        echo ""
        echo -e "${CYAN}Analyzing $view:${NC}"
        execute_sql "SELECT * FROM $view LIMIT 0;" "Column Structure for $view" true
    done
    
    echo ""
    print_section "Sample Security Data"
    
    # Show sample data from key views
    for view in "${available_security_views[@]}"; do
        echo ""
        echo -e "${YELLOW}Sample from $view:${NC}"
        execute_sql "SELECT * FROM $view LIMIT 3;" "Sample data from $view" true
    done
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_user_permissions() {
    print_security_header "USER PERMISSIONS ANALYSIS"
    
    echo "What would you like to analyze?"
    echo "1. Specific user permissions"
    echo "2. All users summary"
    echo "3. Users with admin privileges"
    echo "4. Inactive users analysis"
    echo "5. Return to security menu"
    echo ""
    
    read -p "Choose an option (1-5): " choice
    
    case $choice in
        1) analyze_specific_user ;;
        2) analyze_all_users_summary ;;
        3) analyze_admin_users ;;
        4) analyze_inactive_users ;;
        5) return ;;
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
    
    # Basic user information
    execute_sql "
    SELECT 
        USERNAME,
        USERID,
        CREATEDATE,
        USERTYPE,
        ADMIN_OPTION,
        RESOURCE_LIMIT,
        CONNECTION_LIMIT
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
    
    # Role memberships
    print_section "Role Memberships for $username"
    execute_safe_sql "_V_USER_ROLE" "
    SELECT 
        ur.USERNAME,
        ur.ROLENAME,
        ur.ADMIN_OPTION
    FROM _V_USER_ROLE ur
    WHERE UPPER(ur.USERNAME) = '$username'
    ORDER BY ur.ROLENAME;" "User Role Memberships"
    
    # Database privileges
    print_section "Database-Level Privileges for $username"
    execute_safe_sql "_V_DATABASE_PRIVILEGE" "
    SELECT 
        DATABASE,
        PRIVILEGE,
        GRANTOR,
        GRANTEE,
        ADMIN_OPTION
    FROM _V_DATABASE_PRIVILEGE
    WHERE UPPER(GRANTEE) = '$username'
    ORDER BY DATABASE, PRIVILEGE;" "Database Privileges"
    
    # Schema privileges
    print_section "Schema-Level Privileges for $username"
    execute_safe_sql "_V_SCHEMA_PRIVILEGE" "
    SELECT 
        SCHEMA,
        PRIVILEGE,
        GRANTOR,
        GRANTEE,
        ADMIN_OPTION
    FROM _V_SCHEMA_PRIVILEGE
    WHERE UPPER(GRANTEE) = '$username'
    ORDER BY SCHEMA, PRIVILEGE;" "Schema Privileges"
    
    # Object privileges
    print_section "Object-Level Privileges for $username"
    execute_safe_sql "_V_OBJECT_PRIVILEGE" "
    SELECT 
        OBJDB,
        OBJSCHEMA,
        OBJNAME,
        OBJTYPE,
        PRIVILEGE,
        GRANTOR,
        ADMIN_OPTION
    FROM _V_OBJECT_PRIVILEGE
    WHERE UPPER(GRANTEE) = '$username'
    ORDER BY OBJDB, OBJSCHEMA, OBJNAME, PRIVILEGE
    LIMIT 20;" "Object Privileges (Top 20)"
    
    # Current active sessions
    print_section "Current Active Sessions for $username"
    execute_sql "
    SELECT 
        ID,
        USERNAME,
        DBNAME,
        STATUS,
        IPADDR,
        CONNTIME
    FROM _V_SESSION
    WHERE UPPER(USERNAME) = '$username';" "Current Sessions"
    
    # Permission summary
    print_section "Permission Summary for $username"
    
    # Check admin status
    admin_status=$($NZSQL_CMD -t -c "SELECT ADMIN_OPTION FROM _V_USER WHERE UPPER(USERNAME) = '$username';" 2>/dev/null | tr -d ' ')
    if [[ "$admin_status" == "t" || "$admin_status" == "true" ]]; then
        print_warning "⚠️  USER HAS ADMIN PRIVILEGES"
    else
        print_success "✓ User does not have admin privileges"
    fi
    
    # Count privileges
    role_count=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_USER_ROLE WHERE UPPER(USERNAME) = '$username';" 2>/dev/null | tr -d ' ')
    echo "Role memberships: $role_count"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_all_users_summary() {
    print_section "All Users Summary"
    
    execute_sql "
    SELECT 
        USERNAME,
        USERTYPE,
        ADMIN_OPTION,
        CREATEDATE
    FROM _V_USER
    ORDER BY USERNAME;" "All Users Summary"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_admin_users() {
    print_section "Users with Admin Privileges"
    
    execute_sql "
    SELECT 
        USERNAME,
        USERTYPE,
        CREATEDATE,
        ADMIN_OPTION,
        RESOURCE_LIMIT,
        CONNECTION_LIMIT
    FROM _V_USER
    WHERE ADMIN_OPTION = 't'
    ORDER BY CREATEDATE;" "Admin Users"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_inactive_users() {
    print_section "Inactive Users Analysis"
    
    # Users who haven't logged in recently
    execute_safe_sql "_V_QRYHIST" "
    SELECT 
        u.USERNAME,
        u.USERTYPE,
        u.CREATEDATE,
        MAX(q.QH_TSTART) as LAST_ACTIVITY
    FROM _V_USER u
    LEFT JOIN _V_QRYHIST q ON UPPER(u.USERNAME) = UPPER(q.QH_USER)
    WHERE q.QH_TSTART IS NULL OR q.QH_TSTART < NOW() - INTERVAL '30 DAYS'
    GROUP BY u.USERNAME, u.USERTYPE, u.CREATEDATE
    ORDER BY LAST_ACTIVITY NULLS LAST;" "Inactive Users (30+ days)"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_ad_group_permissions() {
    print_security_header "AD GROUP PERMISSIONS ANALYSIS"
    
    echo "What would you like to analyze?"
    echo "1. Specific AD group/role permissions"
    echo "2. All roles/groups summary"
    echo "3. AD group members and their permissions"
    echo "4. Database/schema access by group"
    echo "5. Return to security menu"
    echo ""
    
    read -p "Choose an option (1-5): " choice
    
    case $choice in
        1) analyze_specific_group ;;
        2) analyze_all_groups_summary ;;
        3) analyze_group_members ;;
        4) analyze_group_database_access ;;
        5) return ;;
        *) print_error "Invalid option" ;;
    esac
}

analyze_specific_group() {
    echo ""
    read -p "Enter AD group/role name to analyze: " groupname
    
    if [[ -z "$groupname" ]]; then
        print_error "Group name cannot be empty"
        return
    fi
    
    groupname=$(echo "$groupname" | tr '[:lower:]' '[:upper:]')
    
    print_section "Group/Role Information for: $groupname"
    
    # Basic role information
    execute_sql "
    SELECT 
        ROLENAME,
        ROLETYPE,
        CREATEDATE,
        OWNER
    FROM _V_ROLE 
    WHERE UPPER(ROLENAME) = '$groupname';" "Role Details" true
    
    # Check if role exists
    role_exists=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_ROLE WHERE UPPER(ROLENAME) = '$groupname';" 2>/dev/null | tr -d ' ')
    
    if [[ "$role_exists" -eq 0 ]]; then
        print_warning "Role '$groupname' not found in the system"
        echo ""
        echo "Searching for similar role names..."
        execute_sql "
        SELECT ROLENAME 
        FROM _V_ROLE 
        WHERE ROLENAME LIKE '%${groupname}%' 
        ORDER BY ROLENAME;" "Similar Role Names" true
        return
    fi
    
    print_success "Role '$groupname' found in the system"
    
    # Members of this role
    print_section "Members of Role: $groupname"
    execute_safe_sql "_V_USER_ROLE" "
    SELECT 
        ur.USERNAME,
        ur.ADMIN_OPTION
    FROM _V_USER_ROLE ur
    WHERE UPPER(ur.ROLENAME) = '$groupname'
    ORDER BY ur.USERNAME;" "Role Members"
    
    # Database privileges granted to this role
    print_section "Database Privileges for Role: $groupname"
    execute_safe_sql "_V_DATABASE_PRIVILEGE" "
    SELECT 
        DATABASE,
        PRIVILEGE,
        GRANTOR,
        ADMIN_OPTION
    FROM _V_DATABASE_PRIVILEGE
    WHERE UPPER(GRANTEE) = '$groupname'
    ORDER BY DATABASE, PRIVILEGE;" "Database Privileges"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_all_groups_summary() {
    print_section "All Roles/Groups Summary"
    
    execute_sql "
    SELECT 
        ROLENAME,
        ROLETYPE,
        CREATEDATE,
        OWNER
    FROM _V_ROLE
    ORDER BY ROLENAME;" "All Roles Summary"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_group_members() {
    print_section "Group Members Analysis"
    
    execute_safe_sql "_V_USER_ROLE" "
    SELECT 
        ur.ROLENAME,
        COUNT(*) as MEMBER_COUNT,
        STRING_AGG(ur.USERNAME, ', ') as MEMBERS
    FROM _V_USER_ROLE ur
    GROUP BY ur.ROLENAME
    ORDER BY MEMBER_COUNT DESC;" "Group Member Counts"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_group_database_access() {
    print_section "Database Access by Group"
    
    execute_safe_sql "_V_DATABASE_PRIVILEGE" "
    SELECT 
        GRANTEE as ROLE_NAME,
        COUNT(DISTINCT DATABASE) as DATABASE_COUNT,
        STRING_AGG(DISTINCT DATABASE, ', ') as DATABASES
    FROM _V_DATABASE_PRIVILEGE
    GROUP BY GRANTEE
    ORDER BY DATABASE_COUNT DESC;" "Database Access by Role"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_database_schema_access() {
    print_security_header "DATABASE & SCHEMA ACCESS ANALYSIS"
    
    echo "What would you like to analyze?"
    echo "1. Who has access to a specific database"
    echo "2. Who has access to a specific schema"
    echo "3. Database access summary (all databases)"
    echo "4. Schema access summary (all schemas)"
    echo "5. Cross-database access analysis"
    echo "6. Return to security menu"
    echo ""
    
    read -p "Choose an option (1-6): " choice
    
    case $choice in
        1) analyze_database_access ;;
        2) analyze_schema_access ;;
        3) analyze_all_database_access ;;
        4) analyze_all_schema_access ;;
        5) analyze_cross_database_access ;;
        6) return ;;
        *) print_error "Invalid option" ;;
    esac
}

analyze_database_access() {
    echo ""
    echo "Available databases:"
    execute_sql "SELECT DATABASE, OWNER FROM _V_DATABASE ORDER BY DATABASE;" "Available Databases" true
    
    echo ""
    read -p "Enter database name to analyze: " dbname
    
    if [[ -z "$dbname" ]]; then
        print_error "Database name cannot be empty"
        return
    fi
    
    dbname=$(echo "$dbname" | tr '[:lower:]' '[:upper:]')
    
    print_section "Access Analysis for Database: $dbname"
    
    # Direct database privileges
    print_section "Direct Database Privileges"
    execute_safe_sql "_V_DATABASE_PRIVILEGE" "
    SELECT 
        GRANTEE,
        PRIVILEGE,
        GRANTOR,
        ADMIN_OPTION
    FROM _V_DATABASE_PRIVILEGE
    WHERE UPPER(DATABASE) = '$dbname'
    ORDER BY GRANTEE, PRIVILEGE;" "Direct Database Privileges"
    
    # Users with access through roles
    print_section "Access Through Role Membership"
    execute_safe_sql "_V_DATABASE_PRIVILEGE" "
    SELECT DISTINCT
        ur.USERNAME,
        dp.PRIVILEGE,
        dp.GRANTEE as ROLE_NAME,
        dp.ADMIN_OPTION
    FROM _V_DATABASE_PRIVILEGE dp
    JOIN _V_USER_ROLE ur ON UPPER(dp.GRANTEE) = UPPER(ur.ROLENAME)
    WHERE UPPER(dp.DATABASE) = '$dbname'
    ORDER BY ur.USERNAME, dp.PRIVILEGE;" "Access Via Roles"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_schema_access() {
    echo ""
    read -p "Enter schema name to analyze: " schemaname
    
    if [[ -z "$schemaname" ]]; then
        print_error "Schema name cannot be empty"
        return
    fi
    
    schemaname=$(echo "$schemaname" | tr '[:lower:]' '[:upper:]')
    
    print_section "Access Analysis for Schema: $schemaname"
    
    # Direct schema privileges
    execute_safe_sql "_V_SCHEMA_PRIVILEGE" "
    SELECT 
        GRANTEE,
        PRIVILEGE,
        GRANTOR,
        ADMIN_OPTION
    FROM _V_SCHEMA_PRIVILEGE
    WHERE UPPER(SCHEMA) = '$schemaname'
    ORDER BY GRANTEE, PRIVILEGE;" "Direct Schema Privileges"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_all_database_access() {
    print_section "Database Access Summary (All Databases)"
    
    execute_safe_sql "_V_DATABASE_PRIVILEGE" "
    SELECT 
        DATABASE,
        COUNT(DISTINCT GRANTEE) as PRIVILEGED_USERS_ROLES,
        STRING_AGG(DISTINCT GRANTEE, ', ') as GRANTEES
    FROM _V_DATABASE_PRIVILEGE
    GROUP BY DATABASE
    ORDER BY DATABASE;" "Database Access Summary"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_all_schema_access() {
    print_section "Schema Access Summary (All Schemas)"
    
    execute_safe_sql "_V_SCHEMA_PRIVILEGE" "
    SELECT 
        SCHEMA,
        COUNT(DISTINCT GRANTEE) as PRIVILEGED_USERS_ROLES,
        STRING_AGG(DISTINCT GRANTEE, ', ') as GRANTEES
    FROM _V_SCHEMA_PRIVILEGE
    GROUP BY SCHEMA
    ORDER BY SCHEMA;" "Schema Access Summary"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_cross_database_access() {
    print_section "Cross-Database Access Analysis"
    
    execute_safe_sql "_V_DATABASE_PRIVILEGE" "
    SELECT 
        GRANTEE,
        COUNT(DISTINCT DATABASE) as DATABASE_COUNT,
        STRING_AGG(DISTINCT DATABASE, ', ') as DATABASES
    FROM _V_DATABASE_PRIVILEGE
    GROUP BY GRANTEE
    HAVING COUNT(DISTINCT DATABASE) > 1
    ORDER BY DATABASE_COUNT DESC;" "Multi-Database Access"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_security_audit() {
    print_security_header "SECURITY AUDIT AND COMPLIANCE"
    
    echo "What type of security audit would you like to perform?"
    echo "1. Excessive privileges audit"
    echo "2. Inactive users analysis"
    echo "3. Admin users review"
    echo "4. Cross-database access review"
    echo "5. Compliance report (comprehensive)"
    echo "6. Return to security menu"
    echo ""
    
    read -p "Choose an option (1-6): " choice
    
    case $choice in
        1) audit_excessive_privileges ;;
        2) analyze_inactive_users ;;
        3) analyze_admin_users ;;
        4) analyze_cross_database_access ;;
        5) generate_compliance_report ;;
        6) return ;;
        *) print_error "Invalid option" ;;
    esac
}

audit_excessive_privileges() {
    print_section "Excessive Privileges Audit"
    
    # Users with admin privileges
    print_section "Users with Admin Privileges"
    execute_sql "
    SELECT 
        USERNAME,
        USERTYPE,
        CREATEDATE,
        ADMIN_OPTION
    FROM _V_USER
    WHERE ADMIN_OPTION = 't'
    ORDER BY CREATEDATE;" "Admin Users"
    
    # Users with access to multiple databases
    print_section "Users with Multi-Database Access"
    execute_safe_sql "_V_DATABASE_PRIVILEGE" "
    SELECT 
        GRANTEE,
        COUNT(DISTINCT DATABASE) as DATABASE_COUNT,
        STRING_AGG(DISTINCT DATABASE, ', ') as DATABASES
    FROM _V_DATABASE_PRIVILEGE
    GROUP BY GRANTEE
    HAVING COUNT(DISTINCT DATABASE) > 3
    ORDER BY DATABASE_COUNT DESC;" "Multi-Database Access"
    
    echo ""
    read -p "Press Enter to continue..."
}

generate_compliance_report() {
    local report_file="/tmp/netezza_security_compliance_$(date +%Y%m%d_%H%M%S).txt"
    
    print_section "Generating Comprehensive Compliance Report"
    echo "Report will be saved to: $report_file"
    
    {
        echo "NETEZZA SECURITY COMPLIANCE REPORT"
        echo "Generated: $(date)"
        echo "Database: $NETEZZA_HOST/$NETEZZA_DB"
        echo "========================================================"
        echo ""
        
        echo "1. USER SUMMARY"
        echo "---------------"
        $NZSQL_CMD -c "
        SELECT 
            COUNT(*) as TOTAL_USERS,
            COUNT(CASE WHEN ADMIN_OPTION = 't' THEN 1 END) as ADMIN_USERS
        FROM _V_USER;"
        echo ""
        
        echo "2. ADMIN USERS"
        echo "--------------"
        $NZSQL_CMD -c "
        SELECT USERNAME, CREATEDATE, USERTYPE 
        FROM _V_USER 
        WHERE ADMIN_OPTION = 't' 
        ORDER BY CREATEDATE;"
        echo ""
        
        echo "3. DATABASE ACCESS SUMMARY"
        echo "--------------------------"
        $NZSQL_CMD -c "
        SELECT 
            DATABASE,
            COUNT(DISTINCT GRANTEE) as PRIVILEGED_USERS_ROLES
        FROM _V_DATABASE_PRIVILEGE
        GROUP BY DATABASE
        ORDER BY DATABASE;" 2>/dev/null || echo "Database privilege information not available"
        
    } > "$report_file"
    
    print_success "Compliance report generated: $report_file"
    
    echo ""
    echo "Report Summary:"
    head -30 "$report_file"
    
    echo ""
    read -p "Press Enter to continue..."
}

quick_permission_lookup() {
    print_security_header "QUICK PERMISSION LOOKUP"
    
    echo "What do you want to check quickly?"
    echo "1. Does user X have permission Y?"
    echo "2. Who has access to database/schema Z?"
    echo "3. What permissions does user X have?"
    echo "4. What permissions does role Y provide?"
    echo "5. Is user X currently active?"
    echo "6. Return to security menu"
    echo ""
    
    read -p "Choose an option (1-6): " choice
    
    case $choice in
        1) quick_check_user_permission ;;
        2) quick_check_access_to_object ;;
        3) quick_check_user_permissions ;;
        4) quick_check_role_permissions ;;
        5) quick_check_user_activity ;;
        6) return ;;
        *) print_error "Invalid option" ;;
    esac
}

quick_check_user_permission() {
    echo ""
    read -p "Enter username: " username
    read -p "Enter database/schema/table name: " object_name
    read -p "Enter permission type (SELECT, INSERT, UPDATE, DELETE, etc.): " permission
    
    username=$(echo "$username" | tr '[:lower:]' '[:upper:]')
    object_name=$(echo "$object_name" | tr '[:lower:]' '[:upper:]')
    permission=$(echo "$permission" | tr '[:lower:]' '[:upper:]')
    
    print_section "Permission Check: $username -> $permission on $object_name"
    
    # Check direct database privileges
    echo "Checking database privileges..."
    execute_safe_sql "_V_DATABASE_PRIVILEGE" "
    SELECT 'DIRECT DATABASE ACCESS' as ACCESS_TYPE, DATABASE, PRIVILEGE, GRANTOR
    FROM _V_DATABASE_PRIVILEGE
    WHERE UPPER(GRANTEE) = '$username'
    AND (UPPER(DATABASE) = '$object_name' OR PRIVILEGE = '$permission');" "Direct Database Access"
    
    # Check role-based access
    echo ""
    echo "Checking role-based access..."
    execute_safe_sql "_V_DATABASE_PRIVILEGE" "
    SELECT 'ROLE-BASED ACCESS' as ACCESS_TYPE, ur.ROLENAME, dp.DATABASE, dp.PRIVILEGE, dp.GRANTOR
    FROM _V_USER_ROLE ur
    JOIN _V_DATABASE_PRIVILEGE dp ON UPPER(ur.ROLENAME) = UPPER(dp.GRANTEE)
    WHERE UPPER(ur.USERNAME) = '$username'
    AND (UPPER(dp.DATABASE) = '$object_name' OR dp.PRIVILEGE = '$permission');" "Role-Based Access"
    
    echo ""
    read -p "Press Enter to continue..."
}

quick_check_access_to_object() {
    echo ""
    read -p "Enter database/schema/table name: " object_name
    
    object_name=$(echo "$object_name" | tr '[:lower:]' '[:upper:]')
    
    print_section "Who has access to: $object_name"
    
    # Check database access
    execute_safe_sql "_V_DATABASE_PRIVILEGE" "
    SELECT 
        GRANTEE,
        PRIVILEGE,
        'DATABASE' as OBJECT_TYPE
    FROM _V_DATABASE_PRIVILEGE
    WHERE UPPER(DATABASE) = '$object_name'
    ORDER BY GRANTEE, PRIVILEGE;" "Database Access"
    
    echo ""
    read -p "Press Enter to continue..."
}

quick_check_user_permissions() {
    echo ""
    read -p "Enter username: " username
    
    username=$(echo "$username" | tr '[:lower:]' '[:upper:]')
    
    print_section "All permissions for user: $username"
    
    # Check if user exists
    user_exists=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_USER WHERE UPPER(USERNAME) = '$username';" 2>/dev/null | tr -d ' ')
    
    if [[ "$user_exists" -eq 0 ]]; then
        print_warning "User '$username' not found"
        return
    fi
    
    # Show admin status
    admin_status=$($NZSQL_CMD -t -c "SELECT ADMIN_OPTION FROM _V_USER WHERE UPPER(USERNAME) = '$username';" 2>/dev/null | tr -d ' ')
    if [[ "$admin_status" == "t" || "$admin_status" == "true" ]]; then
        print_warning "⚠️  USER HAS ADMIN PRIVILEGES"
    else
        print_success "✓ User does not have admin privileges"
    fi
    
    # Show role memberships
    execute_safe_sql "_V_USER_ROLE" "
    SELECT ROLENAME
    FROM _V_USER_ROLE
    WHERE UPPER(USERNAME) = '$username'
    ORDER BY ROLENAME;" "Role Memberships"
    
    echo ""
    read -p "Press Enter to continue..."
}

quick_check_role_permissions() {
    echo ""
    read -p "Enter role/group name: " rolename
    
    rolename=$(echo "$rolename" | tr '[:lower:]' '[:upper:]')
    
    print_section "Permissions for role: $rolename"
    
    # Check database privileges
    execute_safe_sql "_V_DATABASE_PRIVILEGE" "
    SELECT 
        DATABASE,
        PRIVILEGE,
        ADMIN_OPTION
    FROM _V_DATABASE_PRIVILEGE
    WHERE UPPER(GRANTEE) = '$rolename'
    ORDER BY DATABASE, PRIVILEGE;" "Database Privileges"
    
    echo ""
    read -p "Press Enter to continue..."
}

quick_check_user_activity() {
    echo ""
    read -p "Enter username: " username
    
    username=$(echo "$username" | tr '[:lower:]' '[:upper:]')
    
    print_section "Current activity for user: $username"
    
    # Check active sessions
    execute_sql "
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

show_security_menu() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                   NETEZZA SECURITY & PERMISSIONS ANALYZER                   ║${NC}"
    echo -e "${PURPLE}║                              Version 1.1                                    ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Security Analysis Options:${NC}"
    echo "1. 🔍 Discover Security System Views (Run this first!)"
    echo "2. 👤 User Permissions Analysis"
    echo "3. 👥 AD Group/Role Permissions Analysis"
    echo "4. 🗄️  Database & Schema Access Analysis"
    echo "5. 🔐 Security Audit & Compliance"
    echo "6. ❓ Quick Permission Lookup"
    echo "7. ⚙️  Security Configuration"
    echo "8. 📋 View Security Log"
    echo "9. 🚪 Exit"
    echo ""
    echo -e "${YELLOW}Current Settings:${NC}"
    echo "  - Host: ${NETEZZA_HOST:-'(local connection)'}"
    echo "  - Database: $NETEZZA_DB"
    echo "  - User: $NETEZZA_USER"
    echo "  - Security Log: $SECURITY_LOG_FILE"
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
        read -p "Choose an option (1-9): " choice
        
        case $choice in
            1)
                discover_security_views
                ;;
            2)
                analyze_user_permissions
                ;;
            3)
                analyze_ad_group_permissions
                ;;
            4)
                analyze_database_schema_access
                ;;
            5)
                analyze_security_audit
                ;;
            6)
                quick_permission_lookup
                ;;
            7)
                configure_settings
                ;;
            8)
                view_log_file
                ;;
            9)
                print_success "Thank you for using Netezza Security Analyzer!"
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
    main_security "$@"
fi