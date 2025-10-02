#!/bin/bash

#=============================================================================
# Netezza Security and Permissions Analysis Tool
# Version: 1.0
# Date: October 2, 2025
# Description: Interactive security audit and permission analysis for Netezza
# Author: Database Administrator
#=============================================================================

# Source the main performance tool for common functions
if [[ -f "perf_automate.sh" ]]; then
    source perf_automate.sh
else
    echo "Warning: Main performance tool not found. Some functions may not be available."
fi

# Security-specific configuration
SECURITY_LOG_FILE="/tmp/netezza_security_$(date +%Y%m%d_%H%M%S).log"

#=============================================================================
# Security Analysis Functions
#=============================================================================

print_security_header() {
    local title="$1"
    echo -e "\n${PURPLE}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE} 🔐 $title${NC}"
    echo -e "${PURPLE}════════════════════════════════════════════════════════════════════════════════${NC}\n"
}

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
        if execute_sql "SELECT COUNT(*) FROM $view LIMIT 1;" "Test $view" false; then
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
        CONNECTION_LIMIT,
        EFFECTIVE_USERID
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
        ur.ADMIN_OPTION,
        r.ROLETYPE,
        r.CREATEDATE as ROLE_CREATEDATE
    FROM _V_USER_ROLE ur
    LEFT JOIN _V_ROLE r ON ur.ROLENAME = r.ROLENAME
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
    
    # Table/Object privileges
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
    ORDER BY OBJDB, OBJSCHEMA, OBJNAME, PRIVILEGE;" "Object Privileges"
    
    # Recent login activity (if available)
    print_section "Recent Login Activity for $username"
    execute_safe_sql "_V_QRYHIST" "
    SELECT DISTINCT
        QH_USER,
        QH_DATABASE,
        MIN(QH_TSTART) as FIRST_LOGIN,
        MAX(QH_TSTART) as LAST_LOGIN,
        COUNT(*) as QUERY_COUNT
    FROM _V_QRYHIST
    WHERE UPPER(QH_USER) = '$username'
    AND QH_TSTART > NOW() - INTERVAL '30 DAYS'
    GROUP BY QH_USER, QH_DATABASE
    ORDER BY LAST_LOGIN DESC;" "Recent Activity (Last 30 Days)"
    
    # Current active sessions
    print_section "Current Active Sessions for $username"
    execute_sql "
    SELECT 
        ID,
        USERNAME,
        DBNAME,
        STATUS,
        IPADDR,
        CONNTIME,
        COMMAND
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
    
    db_priv_count=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_DATABASE_PRIVILEGE WHERE UPPER(GRANTEE) = '$username';" 2>/dev/null | tr -d ' ')
    echo "Database privileges: $db_priv_count"
    
    obj_priv_count=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_OBJECT_PRIVILEGE WHERE UPPER(GRANTEE) = '$username';" 2>/dev/null | tr -d ' ')
    echo "Object privileges: $obj_priv_count"
    
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
        OWNER,
        ADMIN_OPTION,
        RESOURCE_LIMIT
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
        ur.ADMIN_OPTION,
        u.USERTYPE,
        u.CREATEDATE as USER_CREATEDATE,
        u.ADMIN_OPTION as USER_ADMIN
    FROM _V_USER_ROLE ur
    LEFT JOIN _V_USER u ON ur.USERNAME = u.USERNAME
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
    
    # Schema privileges
    print_section "Schema Privileges for Role: $groupname"
    execute_safe_sql "_V_SCHEMA_PRIVILEGE" "
    SELECT 
        SCHEMA,
        PRIVILEGE,
        GRANTOR,
        ADMIN_OPTION
    FROM _V_SCHEMA_PRIVILEGE
    WHERE UPPER(GRANTEE) = '$groupname'
    ORDER BY SCHEMA, PRIVILEGE;" "Schema Privileges"
    
    # Object privileges
    print_section "Object Privileges for Role: $groupname"
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
    WHERE UPPER(GRANTEE) = '$groupname'
    ORDER BY OBJDB, OBJSCHEMA, OBJNAME, PRIVILEGE
    LIMIT 50;" "Object Privileges (Top 50)"
    
    # Effective permissions analysis
    print_section "Effective Permissions Analysis for Role: $groupname"
    
    # Count members
    member_count=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_USER_ROLE WHERE UPPER(ROLENAME) = '$groupname';" 2>/dev/null | tr -d ' ')
    echo "Total members: $member_count"
    
    # Count privileges
    db_priv_count=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_DATABASE_PRIVILEGE WHERE UPPER(GRANTEE) = '$groupname';" 2>/dev/null | tr -d ' ')
    echo "Database privileges: $db_priv_count"
    
    schema_priv_count=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_SCHEMA_PRIVILEGE WHERE UPPER(GRANTEE) = '$groupname';" 2>/dev/null | tr -d ' ')
    echo "Schema privileges: $schema_priv_count"
    
    obj_priv_count=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_OBJECT_PRIVILEGE WHERE UPPER(GRANTEE) = '$groupname';" 2>/dev/null | tr -d ' ')
    echo "Object privileges: $obj_priv_count"
    
    # Check for admin privileges
    admin_members=$($NZSQL_CMD -t -c "
    SELECT COUNT(*) 
    FROM _V_USER_ROLE ur
    JOIN _V_USER u ON ur.USERNAME = u.USERNAME
    WHERE UPPER(ur.ROLENAME) = '$groupname'
    AND (ur.ADMIN_OPTION = 't' OR u.ADMIN_OPTION = 't');" 2>/dev/null | tr -d ' ')
    
    if [[ "$admin_members" -gt 0 ]]; then
        print_warning "⚠️  $admin_members MEMBERS HAVE ADMIN PRIVILEGES"
    fi
    
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
        ADMIN_OPTION,
        'DIRECT' as PRIVILEGE_TYPE
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
        dp.ADMIN_OPTION,
        'VIA_ROLE' as PRIVILEGE_TYPE
    FROM _V_DATABASE_PRIVILEGE dp
    JOIN _V_USER_ROLE ur ON UPPER(dp.GRANTEE) = UPPER(ur.ROLENAME)
    WHERE UPPER(dp.DATABASE) = '$dbname'
    ORDER BY ur.USERNAME, dp.PRIVILEGE;" "Access Via Roles"
    
    # Current active sessions in this database
    print_section "Current Active Sessions"
    execute_sql "
    SELECT 
        USERNAME,
        COUNT(*) as SESSION_COUNT,
        MIN(CONNTIME) as FIRST_CONNECTION,
        MAX(CONNTIME) as LAST_CONNECTION,
        STRING_AGG(DISTINCT STATUS, ', ') as STATUSES
    FROM _V_SESSION
    WHERE UPPER(DBNAME) = '$dbname'
    GROUP BY USERNAME
    ORDER BY SESSION_COUNT DESC;" "Active Sessions in $dbname"
    
    # Recent query activity
    print_section "Recent Query Activity (Last 7 Days)"
    execute_safe_sql "_V_QRYHIST" "
    SELECT 
        QH_USER,
        COUNT(*) as QUERY_COUNT,
        MIN(QH_TSTART) as FIRST_QUERY,
        MAX(QH_TSTART) as LAST_QUERY
    FROM _V_QRYHIST
    WHERE UPPER(QH_DATABASE) = '$dbname'
    AND QH_TSTART > NOW() - INTERVAL '7 DAYS'
    GROUP BY QH_USER
    ORDER BY QUERY_COUNT DESC
    LIMIT 20;" "Recent Query Activity"
    
    # Summary statistics
    print_section "Access Summary for $dbname"
    
    direct_users=$($NZSQL_CMD -t -c "SELECT COUNT(DISTINCT GRANTEE) FROM _V_DATABASE_PRIVILEGE WHERE UPPER(DATABASE) = '$dbname';" 2>/dev/null | tr -d ' ')
    echo "Users/roles with direct privileges: $direct_users"
    
    role_users=$($NZSQL_CMD -t -c "
    SELECT COUNT(DISTINCT ur.USERNAME) 
    FROM _V_DATABASE_PRIVILEGE dp
    JOIN _V_USER_ROLE ur ON UPPER(dp.GRANTEE) = UPPER(ur.ROLENAME)
    WHERE UPPER(dp.DATABASE) = '$dbname';" 2>/dev/null | tr -d ' ')
    echo "Users with access via roles: $role_users"
    
    active_sessions=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_SESSION WHERE UPPER(DBNAME) = '$dbname';" 2>/dev/null | tr -d ' ')
    echo "Current active sessions: $active_sessions"
    
    echo ""
    read -p "Press Enter to continue..."
}

analyze_schema_access() {
    echo ""
    echo "Available schemas:"
    execute_safe_sql "_V_SCHEMA" "SELECT SCHEMA, OWNER FROM _V_SCHEMA ORDER BY SCHEMA;" "Available Schemas"
    
    echo ""
    read -p "Enter schema name to analyze: " schemaname
    
    if [[ -z "$schemaname" ]]; then
        print_error "Schema name cannot be empty"
        return
    fi
    
    schemaname=$(echo "$schemaname" | tr '[:lower:]' '[:upper:]')
    
    print_section "Access Analysis for Schema: $schemaname"
    
    # Direct schema privileges
    print_section "Direct Schema Privileges"
    execute_safe_sql "_V_SCHEMA_PRIVILEGE" "
    SELECT 
        GRANTEE,
        PRIVILEGE,
        GRANTOR,
        ADMIN_OPTION,
        'DIRECT' as PRIVILEGE_TYPE
    FROM _V_SCHEMA_PRIVILEGE
    WHERE UPPER(SCHEMA) = '$schemaname'
    ORDER BY GRANTEE, PRIVILEGE;" "Direct Schema Privileges"
    
    # Access through roles
    print_section "Access Through Role Membership"
    execute_safe_sql "_V_SCHEMA_PRIVILEGE" "
    SELECT DISTINCT
        ur.USERNAME,
        sp.PRIVILEGE,
        sp.GRANTEE as ROLE_NAME,
        sp.ADMIN_OPTION,
        'VIA_ROLE' as PRIVILEGE_TYPE
    FROM _V_SCHEMA_PRIVILEGE sp
    JOIN _V_USER_ROLE ur ON UPPER(sp.GRANTEE) = UPPER(ur.ROLENAME)
    WHERE UPPER(sp.SCHEMA) = '$schemaname'
    ORDER BY ur.USERNAME, sp.PRIVILEGE;" "Access Via Roles"
    
    # Object-level privileges in this schema
    print_section "Object-Level Privileges in Schema"
    execute_safe_sql "_V_OBJECT_PRIVILEGE" "
    SELECT 
        OBJNAME,
        OBJTYPE,
        GRANTEE,
        PRIVILEGE,
        ADMIN_OPTION
    FROM _V_OBJECT_PRIVILEGE
    WHERE UPPER(OBJSCHEMA) = '$schemaname'
    ORDER BY OBJNAME, GRANTEE, PRIVILEGE
    LIMIT 50;" "Object Privileges (Top 50)"
    
    # Tables in this schema
    print_section "Tables/Views in Schema"
    execute_safe_sql "_V_TABLE" "
    SELECT 
        TABLENAME,
        OWNER,
        CREATEDATE,
        TABLETYPE
    FROM _V_TABLE
    WHERE UPPER(SCHEMA) = '$schemaname'
    ORDER BY TABLENAME;" "Tables in $schemaname"
    
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
    echo "5. Permission inheritance analysis"
    echo "6. Compliance report (comprehensive)"
    echo "7. Return to security menu"
    echo ""
    
    read -p "Choose an option (1-7): " choice
    
    case $choice in
        1) audit_excessive_privileges ;;
        2) audit_inactive_users ;;
        3) audit_admin_users ;;
        4) audit_cross_database_access ;;
        5) audit_permission_inheritance ;;
        6) generate_compliance_report ;;
        7) return ;;
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
        ADMIN_OPTION,
        RESOURCE_LIMIT,
        CONNECTION_LIMIT
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
    
    # Roles with extensive object privileges
    print_section "Roles with Extensive Object Privileges"
    execute_safe_sql "_V_OBJECT_PRIVILEGE" "
    SELECT 
        GRANTEE,
        COUNT(*) as PRIVILEGE_COUNT,
        COUNT(DISTINCT OBJDB) as DATABASE_COUNT,
        COUNT(DISTINCT OBJSCHEMA) as SCHEMA_COUNT
    FROM _V_OBJECT_PRIVILEGE
    GROUP BY GRANTEE
    HAVING COUNT(*) > 100
    ORDER BY PRIVILEGE_COUNT DESC
    LIMIT 20;" "Extensive Object Privileges"
    
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
            COUNT(CASE WHEN ADMIN_OPTION = 't' THEN 1 END) as ADMIN_USERS,
            COUNT(CASE WHEN USERTYPE = 'SYSTEM' THEN 1 END) as SYSTEM_USERS,
            COUNT(CASE WHEN USERTYPE = 'EXTERNAL' THEN 1 END) as EXTERNAL_USERS
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
        
        echo "3. ROLE SUMMARY"
        echo "---------------"
        $NZSQL_CMD -c "
        SELECT 
            COUNT(*) as TOTAL_ROLES,
            COUNT(CASE WHEN ROLETYPE = 'SYSTEM' THEN 1 END) as SYSTEM_ROLES,
            COUNT(CASE WHEN ADMIN_OPTION = 't' THEN 1 END) as ADMIN_ROLES
        FROM _V_ROLE;" 2>/dev/null || echo "Role information not available"
        echo ""
        
        echo "4. DATABASE ACCESS SUMMARY"
        echo "--------------------------"
        $NZSQL_CMD -c "
        SELECT 
            DATABASE,
            COUNT(DISTINCT GRANTEE) as PRIVILEGED_USERS_ROLES
        FROM _V_DATABASE_PRIVILEGE
        GROUP BY DATABASE
        ORDER BY DATABASE;" 2>/dev/null || echo "Database privilege information not available"
        echo ""
        
        echo "5. RECENT ACTIVITY (Last 7 Days)"
        echo "--------------------------------"
        $NZSQL_CMD -c "
        SELECT 
            QH_USER,
            COUNT(DISTINCT QH_DATABASE) as DATABASES_ACCESSED,
            COUNT(*) as TOTAL_QUERIES,
            MAX(QH_TSTART) as LAST_ACTIVITY
        FROM _V_QRYHIST
        WHERE QH_TSTART > NOW() - INTERVAL '7 DAYS'
        GROUP BY QH_USER
        ORDER BY TOTAL_QUERIES DESC
        LIMIT 20;" 2>/dev/null || echo "Query history not available"
        
    } > "$report_file"
    
    print_success "Compliance report generated: $report_file"
    
    echo ""
    echo "Report Summary:"
    head -30 "$report_file"
    
    echo ""
    read -p "Press Enter to continue..."
}

show_security_menu() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                   NETEZZA SECURITY & PERMISSIONS ANALYZER                   ║${NC}"
    echo -e "${PURPLE}║                              Version 1.0                                    ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Security Analysis Options:${NC}"
    echo "1. 🔍 Discover Security System Views (Run this first!)"
    echo "2. 👤 User Permissions Analysis"
    echo "3. 👥 AD Group/Role Permissions Analysis"
    echo "4. 🗄️  Database & Schema Access Analysis"
    echo "5. 🔐 Security Audit & Compliance"
    echo "6. ❓ Quick Permission Lookup"
    echo "7. 📊 Interactive Permission Report Generator"
    echo "8. ⚙️  Security Configuration"
    echo "9. 📋 View Security Log"
    echo "10. ↩️  Return to Main Menu"
    echo "11. 🚪 Exit"
    echo ""
    echo -e "${YELLOW}Current Settings:${NC}"
    echo "  - Host: ${NETEZZA_HOST:-'(local connection)'}"
    echo "  - Database: $NETEZZA_DB"
    echo "  - User: $NETEZZA_USER"
    echo "  - Security Log: $SECURITY_LOG_FILE"
    echo ""
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
    
    # Check object privileges
    echo ""
    echo "Checking object privileges..."
    execute_safe_sql "_V_OBJECT_PRIVILEGE" "
    SELECT 'DIRECT OBJECT ACCESS' as ACCESS_TYPE, OBJDB, OBJSCHEMA, OBJNAME, PRIVILEGE, GRANTOR
    FROM _V_OBJECT_PRIVILEGE
    WHERE UPPER(GRANTEE) = '$username'
    AND (UPPER(OBJNAME) = '$object_name' OR PRIVILEGE = '$permission');" "Direct Object Access"
    
    echo ""
    read -p "Press Enter to continue..."
}

interactive_report_generator() {
    print_security_header "INTERACTIVE PERMISSION REPORT GENERATOR"
    
    echo "Select the type of report you want to generate:"
    echo "1. User Access Report (specific user)"
    echo "2. Group Access Report (specific role/group)"
    echo "3. Database Access Report (specific database)"
    echo "4. Schema Access Report (specific schema)"
    echo "5. Cross-Reference Report (user vs database vs permissions)"
    echo "6. Security Summary Dashboard"
    echo "7. Return to security menu"
    echo ""
    
    read -p "Choose an option (1-7): " choice
    
    case $choice in
        1) generate_user_access_report ;;
        2) generate_group_access_report ;;
        3) generate_database_access_report ;;
        4) generate_schema_access_report ;;
        5) generate_cross_reference_report ;;
        6) generate_security_dashboard ;;
        7) return ;;
        *) print_error "Invalid option" ;;
    esac
}

generate_security_dashboard() {
    local dashboard_file="/tmp/netezza_security_dashboard_$(date +%Y%m%d_%H%M%S).html"
    
    print_section "Generating Security Dashboard"
    echo "Creating HTML dashboard: $dashboard_file"
    
    cat > "$dashboard_file" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Netezza Security Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #4CAF50; color: white; padding: 10px; text-align: center; }
        .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; }
        .warning { background-color: #fff3cd; border-color: #ffeaa7; }
        .success { background-color: #d4edda; border-color: #c3e6cb; }
        table { width: 100%; border-collapse: collapse; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🔐 Netezza Security Dashboard</h1>
        <p>Generated: $(date)</p>
    </div>
EOF
    
    # Add system statistics
    {
        echo '<div class="section">'
        echo '<h2>📊 System Statistics</h2>'
        echo '<table>'
        echo '<tr><th>Metric</th><th>Count</th></tr>'
        
        # Get user count
        user_count=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_USER;" 2>/dev/null | tr -d ' ')
        echo "<tr><td>Total Users</td><td>$user_count</td></tr>"
        
        # Get admin count
        admin_count=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_USER WHERE ADMIN_OPTION = 't';" 2>/dev/null | tr -d ' ')
        echo "<tr><td>Admin Users</td><td>$admin_count</td></tr>"
        
        # Get role count
        role_count=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_ROLE;" 2>/dev/null | tr -d ' ')
        echo "<tr><td>Total Roles</td><td>$role_count</td></tr>"
        
        # Get database count
        db_count=$($NZSQL_CMD -t -c "SELECT COUNT(*) FROM _V_DATABASE;" 2>/dev/null | tr -d ' ')
        echo "<tr><td>Total Databases</td><td>$db_count</td></tr>"
        
        echo '</table>'
        echo '</div>'
        
    } >> "$dashboard_file"
    
    # Add admin users section
    {
        echo '<div class="section warning">'
        echo '<h2>⚠️ Admin Users</h2>'
        echo '<table>'
        echo '<tr><th>Username</th><th>User Type</th><th>Created Date</th></tr>'
        
        $NZSQL_CMD -c "
        SELECT USERNAME, USERTYPE, CREATEDATE 
        FROM _V_USER 
        WHERE ADMIN_OPTION = 't' 
        ORDER BY CREATEDATE;" 2>/dev/null | tail -n +3 | head -n -2 | while IFS='|' read -r username usertype createdate; do
            echo "<tr><td>${username// /}</td><td>${usertype// /}</td><td>${createdate// /}</td></tr>"
        done
        
        echo '</table>'
        echo '</div>'
        
    } >> "$dashboard_file"
    
    echo '</body></html>' >> "$dashboard_file"
    
    print_success "Security dashboard generated: $dashboard_file"
    
    if command -v open &> /dev/null; then
        read -p "Open dashboard in browser? (y/n): " open_choice
        if [[ "$open_choice" =~ ^[Yy] ]]; then
            open "$dashboard_file"
        fi
    elif command -v xdg-open &> /dev/null; then
        read -p "Open dashboard in browser? (y/n): " open_choice
        if [[ "$open_choice" =~ ^[Yy] ]]; then
            xdg-open "$dashboard_file"
        fi
    fi
    
    echo ""
    read -p "Press Enter to continue..."
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
        read -p "Choose an option (1-11): " choice
        
        case $choice in
            1)
                discover_security_views
                ;;
            2)
                analyze_user_permissions
                read -p "Press Enter to continue..."
                ;;
            3)
                analyze_ad_group_permissions
                read -p "Press Enter to continue..."
                ;;
            4)
                analyze_database_schema_access
                read -p "Press Enter to continue..."
                ;;
            5)
                analyze_security_audit
                read -p "Press Enter to continue..."
                ;;
            6)
                quick_permission_lookup
                read -p "Press Enter to continue..."
                ;;
            7)
                interactive_report_generator
                read -p "Press Enter to continue..."
                ;;
            8)
                configure_settings
                ;;
            9)
                view_log_file
                ;;
            10)
                print_success "Returning to main menu..."
                return
                ;;
            11)
                print_success "Thank you for using Netezza Security Analyzer!"
                exit 0
                ;;
            *)
                print_error "Invalid option. Please choose 1-11."
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_security "$@"
fi