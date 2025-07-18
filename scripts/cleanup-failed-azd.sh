#!/bin/bash

# AKS Scale to Zero - Failed azd down cleanup script
# This script helps clean up Azure resources when 'azd down' fails
# Based on manual cleanup steps in README.md

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v azd &> /dev/null; then
        print_error "Azure Developer CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure login status
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    print_info "Prerequisites check passed."
}

# Get environment values
get_env_values() {
    print_info "Getting environment values..."
    
    AZURE_RESOURCE_GROUP=$(azd env get-values | grep "AZURE_RESOURCE_GROUP" | cut -d'=' -f2 | tr -d '"' || echo "")
    AZURE_KEY_VAULT_NAME=$(azd env get-values | grep "AZURE_KEY_VAULT_NAME" | cut -d'=' -f2 | tr -d '"' || echo "")
    AZURE_LOCATION=$(azd env get-values | grep "AZURE_LOCATION" | cut -d'=' -f2 | tr -d '"' || echo "")
    
    # If AZURE_RESOURCE_GROUP is empty, try to get resource group from environment name
    if [ -z "$AZURE_RESOURCE_GROUP" ]; then
        AZURE_ENV_NAME=$(azd env get-values | grep "AZURE_ENV_NAME" | cut -d'=' -f2 | tr -d '"' || echo "")
        if [ -n "$AZURE_ENV_NAME" ]; then
            # Common pattern for resource group naming
            AZURE_RESOURCE_GROUP="rg-aks-scale-to-zero-${AZURE_ENV_NAME}"
            print_warning "AZURE_RESOURCE_GROUP not found, using inferred name: $AZURE_RESOURCE_GROUP"
        else
            print_error "Could not find AZURE_RESOURCE_GROUP in environment values."
            print_info "Available environment values:"
            azd env get-values
            exit 1
        fi
    fi
    
    print_info "Resource Group: $AZURE_RESOURCE_GROUP"
    print_info "Key Vault Name: ${AZURE_KEY_VAULT_NAME:-Not found}"
    print_info "Location: ${AZURE_LOCATION:-Not found}"
}

# Delete resource group
delete_resource_group() {
    print_info "Checking if resource group exists..."
    
    if az group exists --name "$AZURE_RESOURCE_GROUP" 2>/dev/null | grep -qi "true"; then
        print_warning "Resource group '$AZURE_RESOURCE_GROUP' exists."
        echo -n "Do you want to delete it? (yes/no): "
        read -r response
        
        if [[ "$response" == "yes" ]]; then
            print_info "Deleting resource group '$AZURE_RESOURCE_GROUP'..."
            az group delete --name "$AZURE_RESOURCE_GROUP" --yes --no-wait
            print_info "Resource group deletion initiated (running in background)."
            
            # Wait and check deletion status
            print_info "Waiting for deletion to complete..."
            local count=0
            while [ $count -lt 30 ]; do
                sleep 10
                if ! az group exists --name "$AZURE_RESOURCE_GROUP" 2>/dev/null | grep -qi "true"; then
                    print_info "Resource group successfully deleted."
                    break
                fi
                count=$((count + 1))
                print_info "Still deleting... ($((count * 10)) seconds elapsed)"
            done
            
            if [ $count -eq 30 ]; then
                print_warning "Resource group deletion is taking longer than expected. It will continue in the background."
            fi
        else
            print_info "Skipping resource group deletion."
        fi
    else
        print_info "Resource group '$AZURE_RESOURCE_GROUP' does not exist or already deleted."
    fi
}

# Check and purge Key Vault
purge_key_vault() {
    if [ -z "$AZURE_KEY_VAULT_NAME" ]; then
        print_warning "Key Vault name not found in environment. Searching for soft-deleted Key Vaults..."
        
        # Search for soft-deleted Key Vaults with the common prefix
        local deleted_vaults=$(az keyvault list-deleted --query "[?contains(name, 'kv-aks-s2z')].{Name:name, Location:properties.location}" -o tsv)
        
        if [ -n "$deleted_vaults" ]; then
            print_info "Found soft-deleted Key Vaults:"
            echo "$deleted_vaults"
            
            echo -n "Do you want to purge all found Key Vaults? (yes/no): "
            read -r response
            
            if [[ "$response" == "yes" ]]; then
                while IFS=$'\t' read -r name location; do
                    print_info "Purging Key Vault '$name' in location '$location'..."
                    az keyvault purge --name "$name" --location "$location"
                    print_info "Key Vault '$name' purged successfully."
                done <<< "$deleted_vaults"
            else
                print_info "Skipping Key Vault purge."
            fi
        else
            print_info "No soft-deleted Key Vaults found."
        fi
    else
        print_info "Checking for soft-deleted Key Vault '$AZURE_KEY_VAULT_NAME'..."
        
        if az keyvault list-deleted --query "[?name=='$AZURE_KEY_VAULT_NAME']" -o tsv | grep -q "$AZURE_KEY_VAULT_NAME"; then
            print_warning "Key Vault '$AZURE_KEY_VAULT_NAME' is in soft-deleted state."
            echo -n "Do you want to purge it? (yes/no): "
            read -r response
            
            if [[ "$response" == "yes" ]]; then
                local location=${AZURE_LOCATION:-$(az keyvault list-deleted --query "[?name=='$AZURE_KEY_VAULT_NAME'].properties.location" -o tsv)}
                print_info "Purging Key Vault '$AZURE_KEY_VAULT_NAME' in location '$location'..."
                az keyvault purge --name "$AZURE_KEY_VAULT_NAME" --location "$location"
                print_info "Key Vault purged successfully."
            else
                print_info "Skipping Key Vault purge."
            fi
        else
            print_info "Key Vault '$AZURE_KEY_VAULT_NAME' not found in soft-deleted state."
        fi
    fi
}

# Verify cleanup
verify_cleanup() {
    print_info "Verifying cleanup..."
    
    local has_issues=false
    
    # Check resource groups
    local remaining_rgs=$(az group list --query "[?contains(name, 'aks-scale-to-zero')].name" -o tsv)
    if [ -n "$remaining_rgs" ]; then
        print_warning "Found remaining resource groups:"
        echo "$remaining_rgs"
        has_issues=true
    else
        print_info "No resource groups found containing 'aks-scale-to-zero'."
    fi
    
    # Check soft-deleted Key Vaults
    local remaining_kvs=$(az keyvault list-deleted --query "[?contains(name, 'kv-aks-s2z')].name" -o tsv)
    if [ -n "$remaining_kvs" ]; then
        print_warning "Found remaining soft-deleted Key Vaults:"
        echo "$remaining_kvs"
        has_issues=true
    else
        print_info "No soft-deleted Key Vaults found containing 'kv-aks-s2z'."
    fi
    
    if [ "$has_issues" = false ]; then
        print_info "Cleanup completed successfully!"
    else
        print_warning "Some resources may still exist. Please check manually."
    fi
}

# Reset local environment
reset_local_env() {
    echo -n "Do you want to reset the local azd environment? (yes/no): "
    read -r response
    
    if [[ "$response" == "yes" ]]; then
        print_info "Resetting local azd environment..."
        azd env refresh
        print_info "Local environment reset completed."
    else
        print_info "Skipping local environment reset."
    fi
}

# Main execution
main() {
    echo "=== AKS Scale to Zero - Cleanup Script ==="
    echo "This script will help clean up Azure resources when 'azd down' fails."
    echo "Known issue: https://github.com/Azure/azure-dev/issues/4805"
    echo
    
    check_prerequisites
    get_env_values
    
    echo
    print_warning "This will permanently delete Azure resources!"
    echo -n "Do you want to continue? (yes/no): "
    read -r response
    
    if [[ "$response" != "yes" ]]; then
        print_info "Cleanup cancelled."
        exit 0
    fi
    
    delete_resource_group
    purge_key_vault
    verify_cleanup
    reset_local_env
    
    echo
    print_info "Cleanup process completed."
}

# Run main function
main