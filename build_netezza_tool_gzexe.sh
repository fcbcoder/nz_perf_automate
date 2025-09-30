#!/bin/bash

#=============================================================================
# Alternative Builder using gzexe (built-in compression method)
#=============================================================================

print_header() {
    echo -e "\n=== $1 ==="
}

print_header "NETEZZA TOOL BUILDER (GZEXE METHOD)"

# Check if source exists
if [[ ! -f "perf_automate.sh" ]]; then
    echo "ERROR: perf_automate.sh not found"
    exit 1
fi

# Create build directory
mkdir -p "gzexe_build"
cp "perf_automate.sh" "gzexe_build/netezza_perf_tool"
cd "gzexe_build"

# Make executable
chmod +x netezza_perf_tool

# Compress and protect using gzexe
print_header "COMPRESSING WITH GZEXE"
gzexe netezza_perf_tool

# Clean up
rm -f netezza_perf_tool~

# Create package
cd ..
tar -czf "netezza_tool_gzexe_$(date +%Y%m%d).tar.gz" gzexe_build/

echo "Created: netezza_tool_gzexe_$(date +%Y%m%d).tar.gz"
echo "The script is compressed and harder to read, but not fully protected."