#!/bin/bash
set -e

# Configuration
GPG_PUBLIC_KEY_URL="https://raw.githubusercontent.com/johnverbiest/crypto-identity/refs/heads/master/gpg/john-verbiest-public.asc"
GPG_FINGERPRINT="E3FF2C5FE713C7DCA36C900993DE6C09D1FDC17C"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Updating authorized_keys from GitHub repository...${NC}"

# Import GPG public key if not already present
if ! gpg --list-keys "$GPG_FINGERPRINT" &>/dev/null; then
    echo "Importing GPG public key..."
    curl -fsSL "$GPG_PUBLIC_KEY_URL" | gpg --import 2>/dev/null || {
        echo -e "${RED}Error: Failed to import GPG public key${NC}"
        exit 1
    }
    
    # Verify the imported key matches the expected fingerprint
    if ! gpg --list-keys "$GPG_FINGERPRINT" &>/dev/null; then
        echo -e "${RED}Error: Imported key does not match expected fingerprint${NC}"
        echo -e "${RED}Expected: $GPG_FINGERPRINT${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ GPG public key imported and verified${NC}"
    
    # Trust the key ultimately
    echo "Setting trust level for GPG key..."
    echo -e "5\ny\n" | gpg --command-fd 0 --expert --edit-key "$GPG_FINGERPRINT" trust quit &>/dev/null || {
        echo -e "${YELLOW}Warning: Failed to set trust level automatically${NC}"
    }
    echo -e "${GREEN}✓ GPG public key trusted${NC}"
else
    echo -e "${GREEN}✓ GPG public key already present${NC}"
fi