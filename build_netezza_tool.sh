#!/bin/bash

#=============================================================================
# Netezza Performance Tool Builder
# Creates protected executable from source script
#=============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}================================================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ ERROR: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ WARNING: $1${NC}"
}

print_header "NETEZZA PERFORMANCE TOOL BUILDER"

# Check if shc is installed
if ! command -v shc &> /dev/null; then
    print_error "shc (Shell Script Compiler) is not installed"
    echo ""
    echo "Install shc using:"
    echo "  macOS: brew install shc"
    echo "  Linux: sudo apt-get install shc  (Ubuntu/Debian)"
    echo "         sudo yum install shc      (RHEL/CentOS)"
    echo ""
    exit 1
fi

# Check if source script exists
SOURCE_SCRIPT="perf_automate.sh"
if [[ ! -f "$SOURCE_SCRIPT" ]]; then
    print_error "Source script '$SOURCE_SCRIPT' not found in current directory"
    exit 1
fi

print_success "Found source script: $SOURCE_SCRIPT"
print_success "shc compiler available"

# Create build directory
BUILD_DIR="netezza_tool_build"
if [[ -d "$BUILD_DIR" ]]; then
    print_warning "Build directory exists, cleaning up..."
    rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"
print_success "Created build directory: $BUILD_DIR"

# Copy source to build directory
cp "$SOURCE_SCRIPT" "$BUILD_DIR/"
cd "$BUILD_DIR"

# Compile the script
print_header "COMPILING SCRIPT"
echo "Compiling $SOURCE_SCRIPT to binary executable..."

# shc options:
# -f: source script file
# -o: output executable name
# -r: relax security (required for some systems)
# -v: verbose mode
if shc -f "$SOURCE_SCRIPT" -o "netezza_perf_tool" -r -v; then
    print_success "Script compiled successfully!"
else
    print_error "Compilation failed"
    exit 1
fi

# Clean up intermediate files
rm -f "$SOURCE_SCRIPT.x.c" "$SOURCE_SCRIPT"

# Create distribution package
print_header "CREATING DISTRIBUTION PACKAGE"

# Create README for end users
cat > README.txt << 'EOF'
NETEZZA PERFORMANCE AUTOMATION TOOL
====================================

INSTALLATION:
1. Extract all files to a directory on your Netezza system
2. Make the executable file executable: chmod +x netezza_perf_tool
3. Run the tool: ./netezza_perf_tool

REQUIREMENTS:
- Access to Netezza system with nzsql command
- Appropriate database permissions
- Linux/Unix environment

USAGE:
- The tool provides an interactive menu system
- Start with option 1 to discover available system views
- Configure connection settings in option 9 if needed

FEATURES:
- System state analysis
- Performance monitoring
- Session analysis with nzsession utility
- Lock analysis with nz_show_locks utility  
- SQL explain plan analysis with nz_plan utility
- Interactive session termination capabilities

SUPPORT:
- All activities are logged to /tmp/netezza_perf_*.log
- Use the log files for troubleshooting

For questions or issues, contact your database administrator.
EOF

print_success "Created README.txt"

# Create installation script
cat > install.sh << 'EOF'
#!/bin/bash

echo "Netezza Performance Tool Installer"
echo "=================================="

# Make executable
chmod +x netezza_perf_tool

# Check for nzsql
if command -v nzsql &> /dev/null; then
    echo "✓ nzsql found at: $(which nzsql)"
else
    echo "⚠ WARNING: nzsql not found in PATH"
    echo "  Please ensure Netezza client tools are installed"
fi

# Check for utilities
echo ""
echo "Checking for optional Netezza utilities:"

for util in nzsession nz_show_locks nz_plan nzkill; do
    if command -v $util &> /dev/null; then
        echo "✓ $util found at: $(which $util)"
    else
        echo "- $util not found (optional)"
    fi
done

echo ""
echo "Installation complete!"
echo "Run the tool with: ./netezza_perf_tool"
EOF

chmod +x install.sh
print_success "Created install.sh"

# Create version info
cat > version.txt << EOF
Netezza Performance Automation Tool
Build Date: $(date)
Version: 1.0
Platform: $(uname -s) $(uname -m)
Built with: shc $(shc -v 2>&1 | head -1 | awk '{print $3}')
EOF

print_success "Created version.txt"

# Create distribution archive
cd ..
DIST_NAME="netezza_perf_tool_v1.0_$(date +%Y%m%d)"

print_header "CREATING DISTRIBUTION ARCHIVE"

if tar -czf "${DIST_NAME}.tar.gz" "$BUILD_DIR"; then
    print_success "Created distribution archive: ${DIST_NAME}.tar.gz"
else
    print_error "Failed to create archive"
    exit 1
fi

# Create zip alternative
if command -v zip &> /dev/null; then
    if zip -r "${DIST_NAME}.zip" "$BUILD_DIR" >/dev/null; then
        print_success "Created distribution zip: ${DIST_NAME}.zip"
    fi
fi

print_header "BUILD SUMMARY"

echo "Distribution files created:"
echo "  📦 ${DIST_NAME}.tar.gz (recommended)"
if [[ -f "${DIST_NAME}.zip" ]]; then
    echo "  📦 ${DIST_NAME}.zip (alternative)"
fi

echo ""
echo "Distribution contents:"
echo "  🔧 netezza_perf_tool (compiled executable)"
echo "  📖 README.txt (user documentation)"  
echo "  ⚙️ install.sh (installation script)"
echo "  📋 version.txt (build information)"

echo ""
echo "Deployment instructions:"
echo "1. Copy the .tar.gz file to target Netezza system"
echo "2. Extract: tar -xzf ${DIST_NAME}.tar.gz"
echo "3. Enter directory: cd ${BUILD_DIR}"
echo "4. Run installer: ./install.sh"
echo "5. Execute tool: ./netezza_perf_tool"

print_success "Build completed successfully!"