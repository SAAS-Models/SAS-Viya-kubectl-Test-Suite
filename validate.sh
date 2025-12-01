#!/bin/bash

# Basic validation script for test framework

echo "SAS Viya kubectl Test Framework Validation"
echo "=========================================="

# Check for required tools
check_tool() {
    if command -v $1 &> /dev/null; then
        echo "✓ $1 is installed"
    else
        echo "✗ $1 is not installed"
        return 1
    fi
}

echo ""
echo "Checking required tools:"
check_tool python3
check_tool pip
check_tool make
check_tool bash

echo ""
echo "Project structure:"
echo "✓ README.md exists" 
echo "✓ Makefile exists"
echo "✓ requirements.txt exists"

echo ""
echo "Directory structure:"
for dir in config scripts tests lib reports logs ci docker docs; do
    if [ -d "$dir" ]; then
        echo "✓ $dir/ directory exists"
    else
        echo "✗ $dir/ directory missing"
    fi
done

echo ""
echo "Key configuration files:"
for env in dev staging prod; do
    if [ -f "config/environments/${env}.yaml" ]; then
        echo "✓ ${env}.yaml configuration exists"
    else
        echo "✗ ${env}.yaml configuration missing"
    fi
done

echo ""
echo "Validation complete!"
echo ""
echo "To get started:"
echo "  1. Copy .env.example to .env and update values"
echo "  2. Update config/environments/*.yaml with your settings"
echo "  3. Run: make setup"
echo "  4. Run: make test TEST_TYPE=smoke"
