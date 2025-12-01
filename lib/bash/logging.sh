#!/bin/bash

# Logging functions for test output

# Source colors if not already sourced
if [ -z "${NC+x}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/colors.sh"
fi

# Log levels
export LOG_LEVEL_DEBUG=0
export LOG_LEVEL_INFO=1
export LOG_LEVEL_WARN=2
export LOG_LEVEL_ERROR=3
export LOG_LEVEL_FATAL=4

# Current log level (default: INFO)
export CURRENT_LOG_LEVEL=${CURRENT_LOG_LEVEL:-$LOG_LEVEL_INFO}

# Log file
export LOG_FILE=${LOG_FILE:-"./logs/test-$(date +%Y%m%d-%H%M%S).log"}

# Ensure log directory exists
mkdir -p "$(dirname "${LOG_FILE}")"

# Function to log with timestamp
log_with_timestamp() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Write to log file
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Debug log
log_debug() {
    if [[ ${CURRENT_LOG_LEVEL} -le ${LOG_LEVEL_DEBUG} ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $@"
        log_with_timestamp "DEBUG" "$@"
    fi
}

# Info log
log_info() {
    if [[ ${CURRENT_LOG_LEVEL} -le ${LOG_LEVEL_INFO} ]]; then
        echo -e "${BLUE}[INFO]${NC} $@"
        log_with_timestamp "INFO" "$@"
    fi
}

# Warning log
log_warn() {
    if [[ ${CURRENT_LOG_LEVEL} -le ${LOG_LEVEL_WARN} ]]; then
        echo -e "${YELLOW}${WARNING_SIGN} [WARN]${NC} $@"
        log_with_timestamp "WARN" "$@"
    fi
}

# Error log
log_error() {
    if [[ ${CURRENT_LOG_LEVEL} -le ${LOG_LEVEL_ERROR} ]]; then
        echo -e "${RED}${CROSS_MARK} [ERROR]${NC} $@"
        log_with_timestamp "ERROR" "$@"
    fi
}

# Fatal log
log_fatal() {
    echo -e "${BOLD_RED}${CROSS_MARK} [FATAL]${NC} $@"
    log_with_timestamp "FATAL" "$@"
    exit 1
}

# Success log
log_success() {
    echo -e "${GREEN}${CHECK_MARK} [SUCCESS]${NC} $@"
    log_with_timestamp "SUCCESS" "$@"
}

# Pass log for tests
log_pass() {
    echo -e "${GREEN}${CHECK_MARK} PASS:${NC} $@"
    log_with_timestamp "PASS" "$@"
}

# Fail log for tests
log_fail() {
    echo -e "${RED}${CROSS_MARK} FAIL:${NC} $@"
    log_with_timestamp "FAIL" "$@"
}

# Test log
log_test() {
    echo -e "\n${BOLD_CYAN}${ARROW} TEST:${NC} $@"
    log_with_timestamp "TEST" "$@"
}

# Header log
log_header() {
    local header="$@"
    local line=$(printf '=%.0s' {1..60})
    echo -e "\n${BOLD_WHITE}${line}${NC}"
    echo -e "${BOLD_WHITE}${header}${NC}"
    echo -e "${BOLD_WHITE}${line}${NC}"
    log_with_timestamp "HEADER" "${header}"
}

# Section log
log_section() {
    echo -e "\n${BOLD_CYAN}──────── $@ ────────${NC}"
    log_with_timestamp "SECTION" "$@"
}

# Export functions
export -f log_debug
export -f log_info
export -f log_warn
export -f log_error
export -f log_fatal
export -f log_success
export -f log_pass
export -f log_fail
export -f log_test
export -f log_header
export -f log_section
