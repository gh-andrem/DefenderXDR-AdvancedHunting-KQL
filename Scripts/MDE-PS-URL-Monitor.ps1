<#
.SYNOPSIS
Monitors the availability of specified Microsoft Defender for Endpoint URLs (streamlined connectivity URLs only!).

.DESCRIPTION
Periodically tests DNS resolution and HTTPS connectivity for the configured URLs. All test results are written to a timestamped CSV file. Only failed tests are written to the PowerShell output.

A test is considered failed when DNS resolution fails, no HTTP response is received, or the returned HTTP status code is not 200.

.PARAMETER IntervalSeconds
Delay between completed test rounds. Default: 60 seconds.

.PARAMETER DurationMinutes
Total monitoring duration. Default: 1440 minutes.

.PARAMETER TimeoutSeconds
Maximum time allowed for each individual HTTPS request. Default: 120 seconds.

.PARAMETER OutputDirectory
Directory for the timestamped CSV file.
Default: C:\Temp\MDEUrlMonitor

.EXAMPLE
.\Test-MDEUrlAvailability.ps1

.EXAMPLE
.\Test-MDEUrlAvailability.ps1 `
    -IntervalSeconds 60 `
    -DurationMinutes 1440 `
    -TimeoutSeconds 120
#>

param(
    [ValidateRange(1, 86400)]
    [int]$IntervalSeconds = 60,

    [ValidateRange(1, 525600)]
    [int]$DurationMinutes = 1440,

    [ValidateRange(1, 300)]
    [int]$TimeoutSeconds = 120,

    [string]$OutputDirectory = "C:\Temp\MDEUrlMonitor"
)

$Urls = @(
    "https://edr-neu3.eu.endpoint.security.microsoft.com/edr/commands/test",
    "https://edr-weu.eu.endpoint.security.microsoft.com/edr/commands/test",
    "https://edr-neu.eu.endpoint.security.microsoft.com/edr/commands/test",
    "https://edr-weu3.eu.endpoint.security.microsoft.com/edr/commands/test",
    "https://eu-v20.events.endpoint.security.microsoft.com/ping"
)

# Create the output directory if it does not exist.
New-Item `
    -Path $OutputDirectory `
    -ItemType Directory `
    -Force `
    -ErrorAction Stop |
    Out-Null

$StartTime = Get-Date
$EndTime = $StartTime.AddMinutes($DurationMinutes)

$CsvPath = Join-Path `
    -Path $OutputDirectory `
    -ChildPath (
        "MDE-UrlMonitor_{0}.csv" -f
        $StartTime.ToString("yyyyMMdd_HHmmss")
    )

while ((Get-Date) -lt $EndTime) {

    foreach ($Url in $Urls) {

        $TimestampUtc = (Get-Date).ToUniversalTime()
        $Uri = [System.Uri]$Url

        $DnsSuccess = $false
        $IpAddresses = $null
        $HttpReceived = $false
        $StatusCode = $null
        $ResponseMs = $null
        $ErrorType = $null
        $ErrorMessage = $null

        # Test DNS resolution.
        try {
            $Addresses = [System.Net.Dns]::GetHostAddresses(
                $Uri.Host
            )

            $IpAddresses = (
                $Addresses |
                ForEach-Object {
                    $_.IPAddressToString
                }
            ) -join ";"

            $DnsSuccess = $true
        }
        catch {
            $ErrorType = "DNS"
            $ErrorMessage = (
                $_.Exception.GetBaseException().Message
            )
        }

        # Test HTTPS connectivity only if DNS resolution succeeded.
        if ($DnsSuccess) {

            $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                $Response = Invoke-WebRequest `
                    -Uri $Uri.AbsoluteUri `
                    -Method Get `
                    -UseBasicParsing `
                    -TimeoutSec $TimeoutSeconds `
                    -ErrorAction Stop

                $Stopwatch.Stop()

                $HttpReceived = $true
                $StatusCode = [int]$Response.StatusCode
                $ResponseMs = $Stopwatch.ElapsedMilliseconds

                if ($StatusCode -ne 200) {
                    $ErrorType = "HTTPStatus"
                    $ErrorMessage = (
                        "Unexpected HTTP status code: {0}" -f
                        $StatusCode
                    )
                }
            }
            catch [System.Net.WebException] {
                $Stopwatch.Stop()

                $ResponseMs = $Stopwatch.ElapsedMilliseconds
                $WebResponse = $_.Exception.Response

                if ($null -ne $WebResponse) {
                    # An HTTP response was received, but its status
                    # code was not accepted.
                    $HttpReceived = $true
                    $StatusCode = [int]$WebResponse.StatusCode
                    $ErrorType = "HTTPStatus"

                    if ($WebResponse.StatusDescription) {
                        $ErrorMessage = (
                            "HTTP {0} - {1}" -f
                            $StatusCode,
                            $WebResponse.StatusDescription
                        )
                    }
                    else {
                        $ErrorMessage = (
                            "Unexpected HTTP status code: {0}" -f
                            $StatusCode
                        )
                    }
                }
                else {
                    # No HTTP response was received.
                    $HttpReceived = $false
                    $ErrorType = "Connection"
                    $ErrorMessage = (
                        $_.Exception.GetBaseException().Message
                    )
                }
            }
            catch {
                $Stopwatch.Stop()

                $ResponseMs = $Stopwatch.ElapsedMilliseconds
                $HttpReceived = $false
                $ErrorType = "Connection"
                $ErrorMessage = (
                    $_.Exception.GetBaseException().Message
                )
            }
        }

        $IsError = (
            -not $DnsSuccess -or
            -not $HttpReceived -or
            $StatusCode -ne 200
        )

        if ($IsError) {
            if (-not $ErrorType) {
                $ErrorType = "Unknown"
            }

            if (-not $ErrorMessage) {
                $ErrorMessage = (
                    "Request failed without a detailed error message."
                )
            }
        }

        $Result = [pscustomobject]@{
            TimeGeneratedUtc = $TimestampUtc.ToString("o")
            Computer         = $env:COMPUTERNAME
            Url              = $Url
            Hostname         = $Uri.Host
            DnsSuccess       = $DnsSuccess
            IpAddresses      = $IpAddresses
            HttpReceived     = $HttpReceived
            StatusCode       = $StatusCode
            ResponseMs       = $ResponseMs
            IsError          = $IsError
            ErrorType        = $ErrorType
            ErrorMessage     = $ErrorMessage
        }

        # Write successful and failed tests to the CSV file.
        $Result |
            Export-Csv `
                -Path $CsvPath `
                -Append `
                -NoTypeInformation `
                -Encoding UTF8

        # Write only failed tests to stdout.
        if ($IsError) {
            $Result
        }
    }

    # The interval starts after the complete test round.
    if ((Get-Date) -lt $EndTime) {
        Start-Sleep -Seconds $IntervalSeconds
    }
}
