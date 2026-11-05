$token = az account get-access-token --resource-type ms-graph --query accessToken --output tsv
$secureToken = ConvertTo-SecureString $token -AsPlainText -Force
Connect-MgGraph -AccessToken $secureToken
Get-MgContext
