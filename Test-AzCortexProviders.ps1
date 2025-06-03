function Test-AzCortexProviders {
    <#
    .SYNOPSIS
    Ensures all required Azure resource providers are registered for Cortex Cloud Runtime Security.

    .DESCRIPTION
    This function checks if specific Azure resource providers are registered for the current subscription.
    If any are not registered, it prompts the user for confirmation before attempting to register them. Supports -WhatIf for dry-run.

    .EXAMPLE
    Test-AzCortexProviders

    .NOTES
    Author: Your Friendly PowerShell Platform Engineer 🏗️
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    param ()

    $EmojiCheck = "✅"
    $EmojiWarn  = "⚠️"
    $EmojiBuild = "🏗️"

    Write-Host "$EmojiBuild Checking Azure Resource Providers..." -ForegroundColor Cyan

    $results = @()
    $unregistered = @()

    $providers = @(
        "Microsoft.Compute",
        "Microsoft.Storage",
        "Microsoft.Network",
        "Microsoft.KeyVault",
        "Microsoft.ContainerService",
        "Microsoft.ContainerRegistry",
        "Microsoft.Insights",
        "Microsoft.Authorization",
        "Microsoft.DocumentDB",
        "Microsoft.Web",
        "Microsoft.PolicyInsights",
        "Microsoft.EventHub",
        "Microsoft.Security",
        "Microsoft.Aadiam",
        "Microsoft.Communication",
        "Microsoft.Datadog"
    )

    foreach ($provider in $providers) {
        try {
            $state = az provider show --namespace $provider --query "registrationState" -o tsv 2>$null

            if (-not $state) {
                Write-Warning "$EmojiWarn Unable to get registration state for: $provider"
                $results += [PSCustomObject]@{ Provider = $provider; State = "Unknown"; Action = "Error" }
                continue
            }

            if ($state -ne "Registered") {
                $unregistered += $provider
            }
        } catch {
            Write-Warning ("{0} Could not process provider '{1}': {2}" -f $EmojiWarn, $provider, $_.Exception.Message)
            $results += [PSCustomObject]@{ Provider = $provider; State = "Error"; Action = "Exception" }
        }
    }

    if ($unregistered.Count -eq 0) {
        Write-Host "✅ All required providers are already registered." -ForegroundColor Green
        return
    }

    Write-Host "📝 The following providers are not registered:" -ForegroundColor Yellow
    $unregistered | ForEach-Object { Write-Host " - $_" }

    $confirmation = Read-Host "❓ Do you want to proceed with registering these providers? (y/n)"
    if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
        Write-Host "⏹️ Operation cancelled by user." -ForegroundColor Yellow
        return
    }

    foreach ($provider in $unregistered) {
        try {
            if ($PSCmdlet.ShouldProcess($provider, "Register")) {
                Write-Host "📦 Registering: $provider..." -ForegroundColor Yellow
                $null = az provider register --namespace $provider
                Write-Host "$EmojiCheck Registered: $provider" -ForegroundColor Green
                $results += [PSCustomObject]@{ Provider = $provider; State = "Registered"; Action = "Updated" }
            }
        } catch {
            Write-Warning ("{0} Could not register provider '{1}': {2}" -f $EmojiWarn, $provider, $_.Exception.Message)
            $results += [PSCustomObject]@{ Provider = $provider; State = "Error"; Action = "Exception" }
        }
    }

    return $results
}

# Call the function
Test-AzCortexProviders
