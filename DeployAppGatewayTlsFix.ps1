param(
    [Parameter(Mandatory = $true, Position = 1)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true, Position = 2)]
    [String]$TrafficManagerProfileName,

    [Parameter(Mandatory = $false, Position = 3)]
    [ValidateSet("AzureUsGovernment", "AzureCloud")]
    [String]$Environment = "AzureUsGovernment"
)

$tm = Get-AzureRmTrafficManagerProfile -Name $TrafficManagerProfileName -ResourceGroupName $ResourceGroupName

foreach ($ep in $tm.Endpoints) 
{
    if ($ep.TargetResourceId.Contains("Microsoft.Web/sites")) {
        Write-Host "Web App Endpoint Found."
        Write-Host $ep.TargetResourceId 
    } else {
        Write-Host "Unknown endpoint type, skipping"
        $ep.TargetResourceId
    }

}
