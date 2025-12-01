#!/bin/bash

# =========================================================================================
# ☁️ Cortex Cloud - Azure Permissions & Configuration Checker
#
# Description:
#   This script provides a comprehensive tool for validating an Azure user's permissions
#   and environment configuration. It merges the functionality of a wildcard-based role
#   checker and a granular effective permissions checker.
#
# Features:
#   - Checks for Entra ID Global Administrator role.
#   - Validates broad, wildcard permissions (e.g., 'Microsoft.Compute/*') based on assigned roles.
#   - Verifies a specific list of granular, effective permissions against a target scope.
#   - Checks for and interactively prompts to register required Azure Resource Providers.
#   - Flexible scope targeting: Tenant Root, Management Group, Subscription, or a specific Resource ID.
#
# Usage:
#   ./unified_azure_checker.sh [options]
#
# Options:
#   --scope <SCOPE_ID>                 : Full Azure resource ID to check against.
#   -mg, --management-group <MG_NAME>  : Target a Management Group by its name or ID.
#   --tenant-root                      : Target the Tenant Root Management Group (auto-detected).
#   --check-all                        : (Default) Run all available checks.
#   --check-global-admin               : Run only the Entra Global Administrator check.
#   --check-wildcard                   : Run only the role-based wildcard permission checks.
#   --check-granular                   : Run only the granular effective permission checks.
#   --check-providers                  : Run only the Azure provider registration checks.
#   --non-interactive                  : Run without interactive prompts. Skips provider registration.
#   -h, --help                         : Display this help message.
#
# Dependencies:
#   - Azure CLI (must be logged in via `az login`)
#   - jq (a command-line JSON processor)
#
# Author:
#   - March Bichlmeier (@markbic & markbic-panw) (minor revisions by @adilio)
# =========================================================================================

# --- Script Configuration ---

# Exit on any error and treat unset variables as an error
set -o errexit
set -o nounset
set -o pipefail

# Colors for console output
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;36m'
readonly NC='\033[0m' # No Color

# An associative array mapping a category name to its required Azure permission wildcard.
declare -A WILDCARD_PERMISSIONS
WILDCARD_PERMISSIONS=(
  ["Compute"]="Microsoft.Compute/*"
  ["Storage"]="Microsoft.Storage/*"
  ["Networking"]="Microsoft.Network/*"
  ["Key Vault"]="Microsoft.KeyVault/*"
  ["Container Services"]="Microsoft.ContainerService/*"
  ["Container Registry"]="Microsoft.ContainerRegistry/*"
  ["Monitoring & Logs"]="Microsoft.Insights/*"
  ["IAM / Role Assignments"]="Microsoft.Authorization/roleAssignments/*"
  ["Cosmos DB"]="Microsoft.DocumentDB/*"
  ["App Services"]="Microsoft.Web/*"
  ["Policy Insights"]="Microsoft.PolicyInsights/*"
  ["Event Hubs"]="Microsoft.EventHub/*"
)

# A list of specific, granular Azure permissions required for certain operations.
readonly GRANULAR_PERMISSIONS=(
    "Microsoft.Resources/deploymentScripts/*"
    "Microsoft.Resources/subscriptions/resourceGroups/*"
    "Microsoft.Resources/deployments/validate/action"
    "Microsoft.Resources/deployments/read"
    "Microsoft.Resources/deployments/write"
    "Microsoft.Resources/deployments/delete"
    "Microsoft.Resources/deployments/whatIf/action"
    "Microsoft.Authorization/elevateAccess/action"
    "Microsoft.Authorization/roleAssignments/read"
    "Microsoft.Authorization/roleAssignments/write"
    "Microsoft.Authorization/roleAssignments/delete"
    "Microsoft.Authorization/roleDefinitions/read"
    "Microsoft.Authorization/roleDefinitions/write"
    "Microsoft.Authorization/roleDefinitions/delete"
    "Microsoft.Authorization/roleManagementPolicies/read"
    "Microsoft.Authorization/roleManagementPolicies/write"
    "Microsoft.PolicyInsights/remediations/read"
    "Microsoft.PolicyInsights/remediations/write"
    "Microsoft.PolicyInsights/remediations/delete"
    "Microsoft.aadiam/diagnosticsettings/read"
    "Microsoft.aadiam/diagnosticsettings/write"
    "Microsoft.aadiam/diagnosticsettings/delete"
    "Microsoft.aadiam/tenants/providers/Microsoft.Insights/diagnosticSettings/write"
)

# A list of Azure Resource Providers that should be in a 'Registered' state.
readonly REQUIRED_PROVIDERS=(
  "Microsoft.Compute"
  "Microsoft.Storage"
  "Microsoft.Network"
  "Microsoft.KeyVault"
  "Microsoft.ContainerService"
  "Microsoft.ContainerRegistry"
  "Microsoft.Insights"
  "Microsoft.Authorization"
  "Microsoft.DocumentDB"
  "Microsoft.Web"
  "Microsoft.PolicyInsights"
  "Microsoft.EventHub"
  "Microsoft.Security"
  "Microsoft.Aadiam"
  "Microsoft.Communication"
)


# --- Helper Functions ---

# Prints a formatted header to the console.
print_header() {
    echo -e "${BLUE}======================================================================${NC}"
    echo -e "${BLUE}# $1${NC}"
    echo -e "${BLUE}======================================================================${NC}"
}

# Checks if a required command-line tool is available in the system's PATH.
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Checks if a required permission is covered by a permission pattern (e.g., a wildcard).
# This function is case-insensitive.
is_covered() {
    local required lower_required
    required="$1"
    lower_required=$(echo "$required" | tr '[:upper:]' '[:lower:]')

    local pattern lower_pattern
    pattern="$2"
    lower_pattern=$(echo "$pattern" | tr '[:upper:]' '[:lower:]')

    if [[ "$lower_pattern" == "*" ]]; then
        return 0 # Granted by universal wildcard
    fi

    if [[ "$lower_pattern" == *"*"* ]]; then
        # Treat as a prefix match if wildcard is present
        local prefix="${lower_pattern%'\*'}"
        if [[ "$lower_required" == "$prefix"* ]]; then
            return 0 # Granted by prefix wildcard
        fi
    else
        # Perform an exact match
        if [[ "$lower_required" == "$lower_pattern" ]]; then
            return 0 # Granted by exact match
        fi
    fi

    return 1 # Not granted
}

# Displays the help message for the script.
show_help() {
    grep "^# " "$0" | cut -c 3-
    exit 0
}


# --- Core Checker Functions ---

# Script Header
print_header "☁️ Cortex Cloud - Azure Permissions & Configuration Checker"

# Verifies that all script dependencies are installed and the user is logged into Azure.
run_dependency_checks() {
    print_header "Running Pre-flight Checks"
    local has_error=false
    if ! command_exists az; then
        echo -e "❌ ${RED}Error: Azure CLI ('az') is not installed. Please install it to continue.${NC}"
        has_error=true
    fi
    if ! command_exists jq; then
        echo -e "❌ ${RED}Error: 'jq' is not installed. Please install it to continue.${NC}"
        has_error=true
    fi

    if [[ "$has_error" == true ]]; then
        exit 1
    fi
    echo "✅ Dependencies 'az' and 'jq' are installed."

    if ! az account show >/dev/null 2>&1; then
        echo -e "❌ ${RED}Error: You are not logged into Azure. Please run 'az login' first.${NC}"
        exit 1
    fi
    echo -e "✅ Logged into Azure successfully."
}

# Checks for updated version of bash
REQUIRED_MAJOR=4
REQUIRED_MINOR=0

CURRENT_MAJOR=${BASH_VERSINFO[0]}
CURRENT_MINOR=${BASH_VERSINFO[1]}

if (( CURRENT_MAJOR < REQUIRED_MAJOR )) || { (( CURRENT_MAJOR == REQUIRED_MAJOR )) && (( CURRENT_MINOR < REQUIRED_MINOR )); }; then
  echo -e "\033[0;31m❌ This script requires Bash ${REQUIRED_MAJOR}.${REQUIRED_MINOR} or higher. You are using ${CURRENT_MAJOR}.${CURRENT_MINOR}.\033[0m"
  echo -e "\033[0;33m👉 On macOS, the default Bash is outdated (3.2), due to licensing constraints. To upgrade:\033[0m"
  echo -e "\033[0;36m   brew install bash\033[0m"
  echo -e "\033[0;33mThen run this script using the new Bash:\033[0m"
  echo -e "\033[0;36m   /opt/homebrew/bin/bash $0\033[0m"
  exit 1
fi

# Checks if the signed-in user is a member of the "Global Administrator" directory role.
run_global_admin_check() {
    print_header "Checking Entra Global Administrator Role"
    if ! az rest --help >/dev/null 2>&1; then
      echo -e "⚠️  ${YELLOW}Skipping Global Admin check: 'az rest' is not available in this Azure CLI version.${NC}"
      return
    fi

    local role_id
    role_id=$(az rest --method GET \
        --url "https://graph.microsoft.com/v1.0/directoryRoles" \
        --query "value[?displayName=='Global Administrator'].id" -o tsv 2>/dev/null || true)

    if [[ -z "$role_id" ]]; then
        echo -e "ℹ️  The 'Global Administrator' role was not found. This can happen if it's inactive or if you lack permissions to query directory roles."
        return
    fi

    local member_ids
    member_ids=$(az rest --method GET \
      --url "https://graph.microsoft.com/v1.0/directoryRoles/${role_id}/members" \
      --query "value[].id" -o tsv 2>/dev/null)

    if echo "$member_ids" | grep -qF "$AZ_USER_ID"; then
      echo -e "✅ ${GREEN}User IS a Global Administrator in Entra ID.${NC}"
    else
      echo -e "❌ ${RED}User is NOT a Global Administrator in Entra ID.${NC}"
    fi
}

# Checks for broad, wildcard-based permissions by inspecting the definitions of roles assigned to the user.
run_wildcard_check() {
    print_header "Checking Role-Based Wildcard Permissions at Scope"
    echo -e "ℹ️  This check inspects the definitions of roles assigned to the user at the target scope."
    echo -e "ℹ️  Target Scope: ${YELLOW}${SCOPE}${NC}\n"

    # Get all role definition names assigned to the user at the specified scope
    local assigned_roles
    assigned_roles=$(az role assignment list --assignee "$AZ_USER_ID" --scope "$SCOPE" --query "[].roleDefinitionName" -o tsv 2>/dev/null || true)

    if [[ -z "$assigned_roles" ]]; then
        echo -e "❌ ${RED}User has no roles assigned at the specified scope.${NC}"
        return
    fi

    # Loop through each required wildcard permission and check if any assigned role grants it.
    for category in "${!WILDCARD_PERMISSIONS[@]}"; do
        local wildcard="${WILDCARD_PERMISSIONS[$category]}"
        local perm_status="❌ ${RED}No${NC}"

        while IFS= read -r role_name; do
            # Fetch the actions for the current role definition
            local actions
            actions=$(az role definition list --name "$role_name" --query "[].permissions[].actions[]" -o tsv 2>/dev/null || true)
            if echo "$actions" | grep -qE "(^\\*$)|(^${wildcard//\*/\\*}$)"; then
                perm_status="✅ ${GREEN}Yes${NC}"
                break
            fi
        done <<< "$assigned_roles"

        echo -e "🔐 ${category} → ${wildcard} : ${perm_status}"
    done
}

# Checks the user's calculated effective permissions against a granular list.
run_granular_check() {
    print_header "Checking Granular Effective Permissions at Scope"
    echo -e "ℹ️  This check resolves all roles to determine the user's effective permissions."
    echo -e "ℹ️  Target Scope: ${YELLOW}${SCOPE}${NC}\n"

    local perms_json
    perms_json=$(az rest --method get --uri "${SCOPE}/providers/Microsoft.Authorization/permissions?api-version=2022-04-01" -o json 2>/dev/null)

    if [[ -z "$perms_json" ]] || [[ "$(echo "$perms_json" | jq '.value | length')" == "0" ]]; then
        echo -e "❌ ${RED}Could not fetch effective permissions. The scope may be invalid or you lack permissions to read it.${NC}"
        return
    fi

    # Store actions and notActions in arrays
    local -a actions not_actions
    readarray -t actions < <(echo "$perms_json" | jq -r '.value[].actions[]')
    readarray -t not_actions < <(echo "$perms_json" | jq -r '.value[].notActions[]')

    # Check each required permission
    for perm in "${GRANULAR_PERMISSIONS[@]}"; do
        local is_granted=false
        local is_denied=false

        # Check if any action grants the permission
        for action in "${actions[@]}"; do
            if is_covered "$perm" "$action"; then
                is_granted=true
                break
            fi
        done

        # If granted, check if any NotAction denies it
        if $is_granted; then
            for not_action in "${not_actions[@]}"; do
                if is_covered "$perm" "$not_action"; then
                    is_denied=true
                    break
                fi
            done
        fi

        # Print the final result
        if $is_granted && ! $is_denied; then
            echo -e "${GREEN}[GRANTED]${NC}  $perm"
        else
            echo -e "${RED}[DENIED]${NC}   $perm"
        fi
    done
}

# Checks the registration status of required Azure Resource Providers.
run_provider_check() {
    print_header "Checking Azure Resource Provider Registrations"
    for provider in "${REQUIRED_PROVIDERS[@]}"; do
        local state
        state=$(az provider show --namespace "$provider" --query "registrationState" -o tsv 2>/dev/null || echo "Unknown")

        if [[ "$state" == "Registered" ]]; then
            echo -e "✅ ${provider} → ${GREEN}${state}${NC}"
        else
            echo -e "⚠️  ${provider} → ${YELLOW}${state}${NC}"
            if [[ "$IS_INTERACTIVE" == true ]]; then
                read -r -p "   ❓ Register this provider? [y/N]: " confirm
                if [[ "$confirm" =~ ^[yY]$ ]]; then
                    echo "      🔧 Registering ${provider}..."
                    if az provider register --namespace "$provider" --wait >/dev/null 2>&1; then
                        echo -e "      ✅ ${GREEN}Successfully registered ${provider}.${NC}"
                    else
                        echo -e "      ❌ ${RED}Failed to register ${provider}. You may lack the required permissions.${NC}"
                    fi
                fi
            fi
        fi
    done
}


# --- Main Execution ---

# Default values for flags
SCOPE=""
RUN_GLOBAL_ADMIN=false
RUN_WILDCARD=false
RUN_GRANULAR=false
RUN_PROVIDERS=false
IS_INTERACTIVE=true

# If no arguments are provided, run all checks
if [[ $# -eq 0 ]]; then
    RUN_GLOBAL_ADMIN=true
    RUN_WILDCARD=true
    RUN_GRANULAR=true
    RUN_PROVIDERS=true
fi

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        --scope)
            SCOPE="$2"
            shift 2
            ;;
        -mg|--management-group)
            SCOPE="/providers/Microsoft.Management/managementGroups/$2"
            shift 2
            ;;
        --tenant-root)
            # Auto-detect tenant root MG
            TENANT_ROOT_ID=$(az account management-group list --query "[?properties.parent==null].name | [0]" -o tsv)
            if [[ -z "$TENANT_ROOT_ID" ]]; then
                 echo -e "❌ ${RED}Error: Could not auto-detect the Tenant Root Management Group.${NC}"
                 exit 1
            fi
            SCOPE="/providers/Microsoft.Management/managementGroups/${TENANT_ROOT_ID}"
            shift
            ;;
        --check-all)
            RUN_GLOBAL_ADMIN=true; RUN_WILDCARD=true; RUN_GRANULAR=true; RUN_PROVIDERS=true; shift ;;
        --check-global-admin)
            RUN_GLOBAL_ADMIN=true; shift ;;
        --check-wildcard)
            RUN_WILDCARD=true; shift ;;
        --check-granular)
            RUN_GRANULAR=true; shift ;;
        --check-providers)
            RUN_PROVIDERS=true; shift ;;
        --non-interactive)
            IS_INTERACTIVE=false; shift ;;
        *)
            echo -e "${RED}Error: Unknown option '$1'${NC}"
            show_help
            ;;
    esac
done

# Run pre-flight dependency and login checks
run_dependency_checks

# Set the scope to the current subscription if it was not specified
if [[ -z "$SCOPE" ]]; then
    CURRENT_SUB_ID=$(az account show --query "id" -o tsv)
    SCOPE="/subscriptions/${CURRENT_SUB_ID}"
    echo -e "\n${YELLOW}Note: No scope was specified. Defaulting to the current subscription.${NC}"
fi

# Gather user and tenant context
print_header "Gathering User and Tenant Context"
AZ_USER_UPN=$(az ad signed-in-user show --query "userPrincipalName" -o tsv)
AZ_USER_ID=$(az ad signed-in-user show --query "id" -o tsv)
AZ_TENANT_ID=$(az account show --query "tenantId" -o tsv)
echo "👤 User Principal Name: ${AZ_USER_UPN}"
echo "🆔 User Object ID:      ${AZ_USER_ID}"
echo "🏢 Tenant ID:           ${AZ_TENANT_ID}"
echo "🎯 Target Scope:        ${SCOPE}"

# Execute the selected checks
if [[ "$RUN_GLOBAL_ADMIN" == true ]]; then
    run_global_admin_check
fi
if [[ "$RUN_WILDCARD" == true ]]; then
    run_wildcard_check
fi
if [[ "$RUN_GRANULAR" == true ]]; then
    run_granular_check
fi
if [[ "$RUN_PROVIDERS" == true ]]; then
    run_provider_check
fi

echo -e "\n${GREEN}All required permission checks complete.${NC}"
echo -e "\n${GREEN}Please verify passing status above, and proceed with Cortex Cloud onboarding.${NC}"