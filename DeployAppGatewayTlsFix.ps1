<# 
.SYNOPSIS
PowerScript for installing Application Gatways in front of all Web App Endpoints associated with a Traffic Manager

.DESCRIPTION
The purpose of this script is to disable the TLS 1.0 on a multi region web app loadbalanced by a traffic manager. 

This script will loop through all registered endpoints of a Traffic Manager. For the end points associated with an
Azure Web App, it will install an Application Gateway in front of the Web App and point the Traffic Manager to the 
Gateway instead. The Gateway will only have TLS 1.1 and above enabled and traffic to the web app will be restricted
such that only traffic from the gateway is allowed. 

.EXAMPLE
.\DeployAppGatewayTlsFix.ps1 -ResourceGroupName <RESOURCE GROUP> -TrafficManagerProfileName <TM NAME> `
-CertificatePath <PATH TO PFX> -Environment AzureUsGovernment

.NOTES
    Author: Michael Hansen (mihansen@microsoft.com)
    Date:   November 30, 2017  
#> 

param(

    # Resource Group Containing Traffic Manager
    [Parameter(Mandatory = $true, Position = 1)]
    [string]$ResourceGroupName,

    # The Traffic Manager used to DNS loadbalance the site
    [Parameter(Mandatory = $true, Position = 2)]
    [String]$TrafficManagerProfileName,

    # Path to SSL (*.pfx) file to be used on the Application Gateways
    [Parameter(Mandatory = $true, Position = 3)]
    [String]$CertificatePath,

    # Password for SSL cert file
    [Parameter(Mandatory = $true, Position = 4)]
    [SecureString]$CertificatePassword,

    # Application Gateway SKU
    [Parameter(Mandatory = $false, Position = 5)]
    [ValidateSet("Standard_Small", "Standard_Medium", "Standard_Large")]
    [String]$ApplicationGatewaySku = "Standard_Small",    

    # Number of Application Gateway Instances
    [Parameter(Mandatory = $false, Position = 6)]
    [Int]$ApplicationGatewayInstances = 2,    

    # Azure Environment (Commercial or Gov)
    [Parameter(Mandatory = $false, Position = 7)]
    [ValidateSet("AzureUsGovernment", "AzureCloud")]
    [String]$Environment = "AzureUsGovernment"
)

$azcontext = Get-AzureRmContext
if ([string]::IsNullOrEmpty($azcontext.Account) -or
    !($azcontext.Environment.Name -eq $Environment)) {
    Login-AzureRmAccount -Environment $Environment        
}
$azcontext = Get-AzureRmContext

$tm = Get-AzureRmTrafficManagerProfile -Name $TrafficManagerProfileName -ResourceGroupName $ResourceGroupName

foreach ($ep in $tm.Endpoints) 
{
    if ($ep.TargetResourceId.Contains("Microsoft.Web/sites")) {
        Write-Host "Web App Endpoint Found."

        $trg = $ep.ResourceGroupName
        $tloc = $ep.Location
        $app = Get-AzureRmResource -ResourceId $ep.TargetResourceId
        $gwName = $app.ResourceName + "-gw"
        $gwVnetName = $app.ResourceName + "-gwvnet"
        $gwPublicIpName = $app.ResourceName + "-gwip"
        $gwIpConfigName = $app.ResourceName + "-gwipconf"

        $vnet = Get-AzureRmVirtualNetwork -Name $gwVnetName -ResourceGroupName $trg -ErrorVariable NotPresent -ErrorAction 0

        if ($NotPresent) {
            # subnet for AG
            $subnet = New-AzureRmVirtualNetworkSubnetConfig -Name subnet01 -AddressPrefix 10.0.0.0/24

            # vnet for AG
            $vnet = New-AzureRmVirtualNetwork -Name  $gwVnetName -ResourceGroupName $trg -Location $tloc -AddressPrefix 10.0.0.0/16 -Subnet $subnet
        }

        # Retrieve the subnet object for AG config
        $subnet=$vnet.Subnets[0]

        $publicip = Get-AzureRmPublicIpAddress -Name $gwPublicIpName -ResourceGroupName $trg -ErrorVariable NotPresent -ErrorAction 0

        if ($NotPresent) {
            # Create a public IP address
            $publicip = New-AzureRmPublicIpAddress -ResourceGroupName $trg -name $gwPublicIpName -location $tloc -AllocationMethod Dynamic
        }

        # Create a new IP configuration
        $gipconfig = New-AzureRmApplicationGatewayIPConfiguration -Name $gwIpConfigName -Subnet $subnet

        #Grab only the original URL for the app
        $hostnames = $app.Properties.hostNames -like "*azurewebsites*"

        # Create a backend pool with the hostname of the web app
        $pool = New-AzureRmApplicationGatewayBackendAddressPool -Name appGatewayBackendPool -BackendFqdns $hostnames

        # Define the status codes to match for the probe
        $match = New-AzureRmApplicationGatewayProbeHealthResponseMatch -StatusCode 200-399

        # Create a probe with the PickHostNameFromBackendHttpSettings switch for web apps
        $probeconfig = New-AzureRmApplicationGatewayProbeConfig -name webappprobe -Protocol Https -Path / -Interval 30 -Timeout 120 -UnhealthyThreshold 3 -PickHostNameFromBackendHttpSettings -Match $match

        # Define the backend http settings
        $poolSetting = New-AzureRmApplicationGatewayBackendHttpSettings -Name appGatewayBackendHttpSettings -Port 443 -Protocol Https -CookieBasedAffinity Disabled -RequestTimeout 120 -PickHostNameFromBackendAddress -Probe $probeconfig

        # Create a new front-end port
        $fp = New-AzureRmApplicationGatewayFrontendPort -Name frontendport01  -Port 443

        # Create a new front end IP configuration
        $fipconfig = New-AzureRmApplicationGatewayFrontendIPConfig -Name fipconfig01 -PublicIPAddress $publicip

        $cert = New-AzureRmApplicationGatewaySSLCertificate -Name cert01 -CertificateFile $CertificatePath -Password (New-Object PSCredential "user",$CertificatePassword).GetNetworkCredential().Password
        
        # Create a new listener using the front-end ip configuration and port created earlier
        $listener = New-AzureRmApplicationGatewayHttpListener -Name listener01 -Protocol Https -FrontendIPConfiguration $fipconfig -FrontendPort $fp -SslCertificate $cert

        # Create a new rule
        $rule = New-AzureRmApplicationGatewayRequestRoutingRule -Name rule01 -RuleType Basic -BackendHttpSettings $poolSetting -HttpListener $listener -BackendAddressPool $pool 

        # Define the application gateway SKU to use
        $sku = New-AzureRmApplicationGatewaySku -Name $ApplicationGatewaySku -Tier Standard -Capacity $ApplicationGatewayInstances

        #$sslpolicy = New-AzureRmApplicationGatewaySSLPolicy -PolicyType Custom -MinProtocolVersion TLSv1_2 -CipherSuite "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256", "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384", "TLS_RSA_WITH_AES_128_GCM_SHA256"
        
        #Predefined policy with min TLS 1.1
        $sslpolicy = New-AzureRmApplicationGatewaySslPolicy -PolicyType Predefined -PolicyName AppGwSslPolicy20170401
        
        $appgw =  Get-AzureRmApplicationGateway -Name $gwName -ResourceGroupName $trg -ErrorVariable NotPresent -ErrorAction 0

        if ($NotPresent) {
            # Create the application gateway
            $appgw = New-AzureRmApplicationGateway -Name $gwName -ResourceGroupName $trg -Location $tloc `
            -BackendAddressPools $pool -BackendHttpSettingsCollection $poolSetting -Probes $probeconfig `
            -FrontendIpConfigurations $fipconfig  -GatewayIpConfigurations $gipconfig `
            -FrontendPorts $fp -HttpListeners $listener -RequestRoutingRules $rule -Sku $sku `
            -SslPolicy $sslpolicy -SSLCertificates $cert
        }

        #Making sure we have updated IP info.
        $publicip = Get-AzureRmPublicIpAddress -Name $gwPublicIpName -ResourceGroupName $trg
        
        $ep.Target = $publicip.DnsSettings.Fqdn
        $ep.TargetResourceId = $publicip.Id
        
        Set-AzureRmTrafficManagerEndpoint -TrafficManagerEndpoint $ep

        #Now make sure the web app can only be contacted from the AG
        $appName = $app.Name
        $r = Get-AzureRmResource -ResourceGroupName $trg -ResourceType Microsoft.Web/sites/config -ResourceName "$appName/web" -ApiVersion 2016-08-01
        $p = $r.Properties
        $p.ipSecurityRestrictions = @()
        $restriction = @{}
        $restriction.Add("ipAddress", $publicip.IpAddress)
        $restriction.Add("subnetMask","255.255.255.255")
        $p.ipSecurityRestrictions+= $restriction
        Set-AzureRmResource -ResourceGroupName  $trg -ResourceType Microsoft.Web/sites/config -ResourceName "$appName/web" -ApiVersion 2016-08-01 -PropertyObject $p -Force     

    } else {
        Write-Host "Unknown endpoint type, skipping"
        $ep.TargetResourceId
    }
}
