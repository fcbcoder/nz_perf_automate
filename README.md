🎯 Key Features Implemented
1. Netezza System State Analysis
  -  System version and health status
  -  Database sizes and skew information
  -  Disk usage across all hosts
  -  Key system configuration parameters
2. Linux OS Performance Monitoring
  -  Host CPU, memory, and swap usage
  -  Load averages (1, 5, 15 minutes)
  -  Top resource-intensive processes
  -  I/O performance statistics (similar to sar)
3. Active Sessions and SQL Analysis
  -  Long-running sessions (configurable threshold, default 2+ hours)
  -  Session state summary
  -  Currently executing queries with runtime
4. Query Performance Analysis
  -  Top queries by elapsed time (last 24 hours)
  -  CPU-intensive queries
  -  Current lock information
  -  Memory usage analysis
5. Interactive SQL Analysis ⭐
  -  Analyze SQL from active sessions
  -  Historical query analysis
  -  Custom SQL explain plan generation
  -  **Automated issue detection** including:
      -  Large table joins
      -  Missing WHERE clauses on big tables
      -  SELECT * usage
      -  ORDER BY without LIMIT
      - Nested subqueries
🚀 Usage Instructions
Run the script:
cd 
./perf_automate.sh
First-time setup:
  -  The script will test your connection
  -  Configure connection settings if needed (Option 7)
  -  Set your preferred thresholds
Environment Variables (Optional):
  - export NETEZZA_HOST="your_netezza_host"
  - export NETEZZA_DB="SYSTEM"  # or your preferred database
  - export NETEZZA_USER="ADMIN" # or your admin user
🔧 Configurable Settings
  -  Long Running Query Threshold: Default 2 hours (configurable)
  -  Top Sessions/Queries Limits: Default 10/20 (configurable)
  -  Connection Parameters: Host, database, username
  -  Output: Color-formatted text reports
  -  Logging: All SQL queries logged to timestamped files
📊 Interactive Features
  -  Main menu-driven interface
  -  Real-time explain plan generation
  -  SQL issue analysis with recommendations
  -  Configuration management
  -  Complete system check option
🔍 SQL Issue Detection
The tool automatically identifies:

  -  Big table joins (tables with _FACT, _LARGE, _BIG patterns)
  -  Full table scans on large tables without WHERE clauses  
  -  Performance anti-patterns (SELECT *, ORDER BY without LIMIT)
  -  Complex subqueries that could be optimized# nz_perf_automate
