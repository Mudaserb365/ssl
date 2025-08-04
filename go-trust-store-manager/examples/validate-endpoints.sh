#!/bin/bash

# Website Certificate Trust Path Validator
# This script validates the certificate trust paths for multiple websites

# Colors for better UI
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if go is installed
if ! command -v go &> /dev/null; then
  echo -e "${RED}Error: Go is not installed.${NC}"
  echo "Please install Go to run the trust path validator."
  exit 1
fi

# Check if validator exists
VALIDATOR="$SCRIPT_DIR/trust-path-validator.go"
if [ ! -f "$VALIDATOR" ]; then
  echo -e "${RED}Error: Trust path validator not found at $VALIDATOR${NC}"
  exit 1
fi

# Setup temporary directory for certificates
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Usage information
function show_help() {
  echo "Website Certificate Trust Path Validator"
  echo ""
  echo "Usage: $0 [options] [domains...]"
  echo ""
  echo "Options:"
  echo "  -f, --file FILE    Read domains from FILE (one domain per line)"
  echo "  -o, --output DIR   Save reports to DIR (default: current directory)"
  echo "  -d, --days DAYS    Warn if certificate expires within DAYS days (default: 30)"
  echo "  -s, --summary      Only show summary results"
  echo "  -p, --port PORT    Port to connect on (default: 443)"
  echo "  -h, --help         Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0 example.com google.com"
  echo "  $0 --file domains.txt --output reports"
  echo "  $0 --summary --days 60 example.org"
}

# Parse command line arguments
DAYS=30
OUTPUT_DIR="."
SUMMARY_ONLY=false
PORT=443
DOMAINS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file)
      DOMAINS_FILE="$2"
      if [ ! -f "$DOMAINS_FILE" ]; then
        echo -e "${RED}Error: Domains file not found: $DOMAINS_FILE${NC}"
        exit 1
      fi
      # Read domains from file (ignoring empty lines and comments)
      while read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        DOMAINS+=("$line")
      done < "$DOMAINS_FILE"
      shift 2
      ;;
    -o|--output)
      OUTPUT_DIR="$2"
      # Create output directory if it doesn't exist
      mkdir -p "$OUTPUT_DIR"
      shift 2
      ;;
    -d|--days)
      DAYS="$2"
      shift 2
      ;;
    -s|--summary)
      SUMMARY_ONLY=true
      shift
      ;;
    -p|--port)
      PORT="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    -*)
      echo -e "${RED}Error: Unknown option: $1${NC}"
      show_help
      exit 1
      ;;
    *)
      DOMAINS+=("$1")
      shift
      ;;
  esac
done

# Check if we have domains to validate
if [ ${#DOMAINS[@]} -eq 0 ]; then
  echo -e "${RED}Error: No domains specified.${NC}"
  show_help
  exit 1
fi

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Website Certificate Validation Report${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "${YELLOW}Validating ${#DOMAINS[@]} domains...${NC}"
echo ""

# Initialize counters
VALID_COUNT=0
WARNING_COUNT=0
ERROR_COUNT=0

# Process each domain
for domain in "${DOMAINS[@]}"; do
  echo -e "${BLUE}Checking $domain:${NC}"
  
  # Get the certificate
  echo -e "  Retrieving certificate..."
  CERT_FILE="$TEMP_DIR/$domain.pem"
  if ! openssl s_client -connect "$domain:$PORT" -servername "$domain" </dev/null 2>/dev/null | openssl x509 -outform PEM > "$CERT_FILE"; then
    echo -e "  ${RED}Failed to retrieve certificate for $domain${NC}"
    ERROR_COUNT=$((ERROR_COUNT+1))
    continue
  fi
  
  # Run validation
  echo -e "  Validating trust path..."
  OUTPUT_FILE="$OUTPUT_DIR/$domain-validation.txt"
  
  if $SUMMARY_ONLY; then
    # Run validation with minimal output
    RESULT=$(go run "$VALIDATOR" -cert "$CERT_FILE" -days "$DAYS" 2>&1)
    SUCCESS=$?
    
    if [ $SUCCESS -eq 0 ]; then
      if echo "$RESULT" | grep -q "Warning"; then
        echo -e "  ${YELLOW}✓ Valid with warnings${NC}"
        WARNING_COUNT=$((WARNING_COUNT+1))
      else
        echo -e "  ${GREEN}✓ Valid${NC}"
        VALID_COUNT=$((VALID_COUNT+1))
      fi
    else
      echo -e "  ${RED}✗ Invalid${NC}"
      ERROR_COUNT=$((ERROR_COUNT+1))
    fi
  else
    # Run validation with full output
    if go run "$VALIDATOR" -cert "$CERT_FILE" -days "$DAYS" -v > "$OUTPUT_FILE" 2>&1; then
      if grep -q "Warning" "$OUTPUT_FILE"; then
        echo -e "  ${YELLOW}✓ Valid with warnings${NC}"
        WARNING_COUNT=$((WARNING_COUNT+1))
      else
        echo -e "  ${GREEN}✓ Valid${NC}"
        VALID_COUNT=$((VALID_COUNT+1))
      fi
      echo -e "  Full report saved to: $OUTPUT_FILE"
    else
      echo -e "  ${RED}✗ Invalid${NC}"
      ERROR_COUNT=$((ERROR_COUNT+1))
      echo -e "  Error details saved to: $OUTPUT_FILE"
    fi
  fi
  
  echo ""
done

# Print summary
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Summary${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Valid: $VALID_COUNT${NC}"
echo -e "${YELLOW}Warnings: $WARNING_COUNT${NC}"
echo -e "${RED}Errors: $ERROR_COUNT${NC}"
echo -e "Total: ${#DOMAINS[@]}"
echo ""

if [ $ERROR_COUNT -gt 0 ]; then
  echo -e "${RED}Some certificates failed validation!${NC}"
  exit 1
elif [ $WARNING_COUNT -gt 0 ]; then
  echo -e "${YELLOW}All certificates are valid, but some have warnings.${NC}"
  exit 0
else
  echo -e "${GREEN}All certificates are valid!${NC}"
  exit 0
fi 