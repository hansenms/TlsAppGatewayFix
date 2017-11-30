param(
    [Parameter(Mandatory = $true, Position = 1)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true, Position = 2)]
    [String]$Fqdn,
    
    [Parameter(Mandatory = $true, Position = 3)]
    [String]$CertificatePath,

    [Parameter(Mandatory = $true, Position = 4)]
    [SecureString]$CertificatePassword,

    [Parameter(Mandatory = $true, Position = 5)]
    [String[]]$Locations,

    [Parameter(Mandatory = $false, Position = 6)]
    [String]$AppNamePrefix,

    [Parameter(Mandatory = $false, Position = 7)]
    [ValidateSet("AzureUsGovernment", "AzureCloud")]
    [String]$Environment = "AzureUsGovernment"
)

$timeStamp = get-date -uformat %Y%m%d%H%M%S

if ([string]::IsNullOrEmpty($AppNamePrefix)) {
    $AppNamePrefix = "TlsDemo$timeStamp"
}

$azcontext = Get-AzureRmContext
if ([string]::IsNullOrEmpty($azcontext.Account) -or
    !($azcontext.Environment.Name -eq $Environment)) {
    Login-AzureRmAccount -Environment $Environment        
}
$azcontext = Get-AzureRmContext

$grp = Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorVariable NotPresent -ErrorAction 0

if ($NotPresent) {
    $grp = New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Locations[0]
}

$tm = Get-AzureRmTrafficManagerProfile -Name "trafman" -ResourceGroupName $ResourceGroupName -ErrorVariable NotPresent -ErrorAction 0

if ($NotPresent) { 
    $tm = New-AzureRmTrafficManagerProfile -Name "trafman" -ResourceGroupName $ResourceGroupName `
        -RelativeDnsName $AppNamePrefix -MonitorProtocol HTTPS `
        -MonitorPort 443 -TrafficRoutingMethod Performance `
        -Ttl 300 -PathForMonitor "/"
}

$trafManDns = $tm.RelativeDnsName + ".usgovtrafficmanager.net"
if ($Environment -eq "AzureCloud") {
    $trafManDns = $tm.RelativeDnsName + ".trafficmanager.net"    
}

Write-Host "Please ad a DNS CNAME entry from $Fqdn to $trafManDns"
Read-Host "Hit enter when completed."

foreach ($l in $Locations) {
    Write-Host "Creating web app for location: $l"

    $aspName = "$ResourceGroupName-asp-$l"
    $webAppName = "$ResourceGroupName-$l"

    $asp = Get-AzureRmAppServicePlan -Name $aspName -ResourceGroupName $ResourceGroupName -ErrorVariable NotPresent -ErrorAction 0
    if ($NotPresent) {
        $asp = New-AzureRmAppServicePlan -Name $aspName -ResourceGroupName $ResourceGroupName -Location $l -Tier Standard
    }

    $app = Get-AzureRmWebApp -Name $webAppName -ResourceGroupName $ResourceGroupName -ErrorVariable NotPresent -ErrorAction 0
    if ($NotPresent) {
        $app = New-AzureRmWebApp -Name $webAppName -ResourceGroupName $ResourceGroupName -Location $l -TrafficManagerProfileId $tm.Id -AppServicePlan $asp.Id
    }
 
    $tmep = Get-AzureRmTrafficManagerEndpoint -Name $webAppName -ResourceGroupName $ResourceGroupName -ProfileName "trafman" -Type "AzureEndpoints" -ErrorVariable NotPresent -ErrorAction 0
    if ($NotPresent) {
        $tmep = New-AzureRmTrafficManagerEndpoint -Name $webAppName -ProfileName "trafman" `
            -ResourceGroupName $ResourceGroupName -TargetResourceId $app.Id -EndpointLocation $l `
            -EndpointStatus "Enabled" -Type "AzureEndpoints"
    }

    $binding = Get-AzureRmWebAppSSLBinding -Name $Fqdn -ResourceGroupName $ResourceGroupName -WebAppName $webAppName

    if ([string]::IsNullOrEmpty($binding)) {

        $hosts = $app.HostNames
        if (!$hosts.Contains($Fqdn)) {
            $hosts.Add($Fqdn)
            Set-AzureRmWebApp -Name $app.Name -ResourceGroupName $ResourceGroupName -HostNames $hosts
        }

        $binding = New-AzureRmWebAppSSLBinding `
            -WebAppName $webAppName `
            -ResourceGroupName $ResourceGroupName `
            -Name $Fqdn `
            -CertificateFilePath $CertificatePath `
            -CertificatePassword (New-Object PSCredential "user",$CertificatePassword).GetNetworkCredential().Password `
            -SslState SniEnabled
    }
}

