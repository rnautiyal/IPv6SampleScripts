<#
.SYNOPSIS
    Creates a dualstack application gateway.
.DESCRIPTION
    Creates a dualstack application gateway that support ipv6 and ipv4 listeners
    with ipv4 backend pools.
.PARAMETER Subscription
    Customer subscription used to create the application gateway instance.
.PARAMETER Location
    Location where the resource group and resources will be generated.
.PARAMETER Prefix
    String used to prefix the resource group name and nested resources.
.PARAMETER Id
    Unique identifier that is used in concatenation with the prefix to generate resource names.
.PARAMETER VnetPrefix
    Prefix used for defining vnet ip ranges.
.PARAMETER AppGwSubnetPrefix
    Prefix used for defining application gateway subnet ip ranges.
.PARAMETER BackendSubnetPrefix
    Prefix used for defining backend pool subnet ip ranges.
.EXAMPLE
    ./appgw.ps1 -Subscription "aa67bbde-b8ce-4a5d-bcbf-9234156495cc" -Location "westcentralus" -Prefix "appgwipv6bb" -Id "12345678"
#>
param(
  [string] $Subscription = "aa67bbde-b8ce-4a5d-bcbf-9234156495cc", 
  [string] $Location = "westcentralus",
  [string] $Prefix = "appgwipv6bb",
  [string] $Id = -join (1..8 | ForEach-Object { [char]((97..122) + (48..57) | Get-Random) }),
  [string[]] $VnetPrefix = @("10.0.0.0/16", "ace:cab:deca::/48"),
  [string[]] $AppGwSubnetPrefix = @("10.0.0.0/24", "ace:cab:deca::/64"),
  [string[]] $BackendSubnetPrefix = @("10.0.1.0/24", "ace:cab:deca:10::/64")
)

$rgName = "$Prefix-$Id"
$vnetName = "$Prefix-$Id-vnet"
$appgwSubnetName = "$Prefix-$Id-appgw-subnet"
$backendSubnetName = "$Prefix-$Id-backend-subnet"
$fipv4Name = "$Prefix-$Id-fipv4"
$fipv6Name = "$Prefix-$Id-fipv6"
$appGWName = "$Prefix-$Id-appgw"

$ErrorActionPreference = "Stop"
$null = Update-AzConfig -DisplayBreakingChangeWarning $false -Scope Process

$null = Select-AzSubscription -Subscription $Subscription

# Create resource group
$rg = New-AzResourceGroup `
  -Name $RgName `
  -Location $Location `
  -Force

Write-Output "Created resource group $RgName at $Location in $Subscription" 

# Create the subnet
$appgwSubnet = New-AzVirtualNetworkSubnetConfig -Name $appgwSubnetName -AddressPrefix $AppGwSubnetPrefix
$backendSubnet = New-AzVirtualNetworkSubnetConfig -Name $backendSubnetName -AddressPrefix $BackendSubnetPrefix
Write-Output "Created appgw subnet $appgwSubnetName($AppGwSubnetPrefix) and backend subnet $backendSubnetName($BackendSubnetPrefix)" 

# Create the virtual network
$vnet = New-AzVirtualNetwork -Name $VnetName `
  -ResourceGroupName $RgName `
  -Location $Location `
  -AddressPrefix $VnetPrefix `
  -Subnet @($appgwSubnet, $backendSubnet) `
  -Force

Write-Output "Created vnet $VnetName in resource group $rgName with address prefix $VnetPrefix" 

# Add the frontend public ip addresses
$pipv4 = New-AzPublicIpAddress `
  -Name $fipv4Name `
  -ResourceGroupName $rgName `
  -Location $Location `
  -Sku 'Standard' `
  -AllocationMethod 'Static' `
  -IpAddressVersion 'IPv4' `
  -Force
$pipv6 = New-AzPublicIpAddress `
  -Name $fipv6Name `
  -ResourceGroupName $rgName `
  -Location $Location `
  -Sku 'Standard' `
  -AllocationMethod 'Static' `
  -IpAddressVersion 'IPv6' `
  -Force

Write-Output "Created public ip addresses $fipv4Name and $fipv6Name for resource group $rgName" 

$backendPool = New-AzApplicationGatewayBackendAddressPool `
  -Name "$Prefix-$Id-backend-pool" `
  -BackendFqdns @("bing.com")

$backendProbe = New-AzApplicationGatewayProbeConfig `
  -Name "$Prefix-$Id-backend-probe" `
  -Protocol Https `
  -Path '/' `
  -Interval 30 `
  -Timeout 30 `
  -UnhealthyThreshold 3 `
  -PickHostNameFromBackendHttpSettings

$backendSettings = New-AzApplicationGatewayBackendHttpSetting `
  -Name "$Prefix-$Id-backend-settings" `
  -Port 443 `
  -Protocol Https `
  -PickHostNameFromBackendAddress `
  -CookieBasedAffinity Disabled `
  -RequestTimeout 30 `
  -Probe $backendProbe

$vnet = Get-AzVirtualNetwork -Name $vnetName
$appgwSubnet = Get-AzVirtualNetworkSubnetConfig -Name $appgwSubnetName -VirtualNetwork $vnet

$gipconfig = New-AzApplicationGatewayIPConfiguration `
  -Name "$Prefix-$Id-ipconf" `
  -Subnet $appgwSubnet

$fipconfig = New-AzApplicationGatewayFrontendIPConfig `
  -Name "$Prefix-$Id-fipv4conf" `
  -PublicIPAddress $pipv4

$fipconfigv6 = New-AzApplicationGatewayFrontendIPConfig `
  -Name "$Prefix-$Id-fipv6conf" `
  -PublicIPAddress $pipv6

$frontendport = New-AzApplicationGatewayFrontendPort `
  -Name "$Prefix-$Id-port" `
  -Port 80

$listener = New-AzApplicationGatewayHttpListener `
  -Name "$Prefix-$Id-v4listener" `
  -Protocol Http `
  -FrontendIPConfiguration $fipconfig `
  -FrontendPort $frontendport

$listenerv6 = New-AzApplicationGatewayHttpListener `
  -Name "$Prefix-$Id-v6listener" `
  -Protocol Http `
  -FrontendIPConfiguration $fipconfigv6 `
  -FrontendPort $frontendport


$frontendRule = New-AzApplicationGatewayRequestRoutingRule `
  -Name "$Prefix-$Id-ipv4Route" `
  -RuleType Basic `
  -Priority 1 `
  -HttpListener $listener `
  -BackendAddressPool $backendPool `
  -BackendHttpSettings $backendSettings

$frontendRulev6 = New-AzApplicationGatewayRequestRoutingRule `
  -Name "$Prefix-$Id-ipv6Route"`
  -RuleType Basic `
  -Priority 2 `
  -HttpListener $listenerv6 `
  -BackendAddressPool $backendPool `
  -BackendHttpSettings $backendSettings

$sku = New-AzApplicationGatewaySku `
  -Name Standard_v2 `
  -Tier Standard_v2

$autoscale = New-AzApplicationGatewayAutoscaleConfiguration `
  -MinCapacity 0 `
  -MaxCapacity 2 

Write-Output "Creating Application Gateway $appGWName in resource group $rgName"

New-AzApplicationGateway `
  -Name $appGWName `
  -ResourceGroupName $rgName `
  -Location $Location `
  -BackendAddressPools $backendPool `
  -BackendHttpSettingsCollection $backendSettings `
  -FrontendIpConfigurations @($fipconfig, $fipconfigv6) `
  -GatewayIpConfigurations $gipconfig `
  -FrontendPorts $frontendport `
  -HttpListeners @($listener, $listenerv6) `
  -RequestRoutingRules @($frontendRule, $frontendRulev6) `
  -Probes $backendProbe `
  -Sku $sku `
  -Tag @{"DisableNetworkIsolation" = "True" } `
  -AutoscaleConfiguration $autoscale `
  -Force

Write-Output "Successfully created Application Gateway $appGWName in resource group $rgName at $Location in $Subscription"