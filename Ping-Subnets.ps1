﻿function Ping-SubNets(){
    [CmdletBinding()]
    param(
        [ValidatePattern("(([0-9]{1,3}(~[0-9]{1,3})?)\.){3}([0-9]{1,3}(~[0-9]{1,3})?)")]
        [parameter(Mandatory=$true, Position=1, ParameterSetName="Address")][String]$Address,
        [parameter(Mandatory=$true, Position=1, ParameterSetName="Tuples")][int[]]$A,
        [parameter(Mandatory=$true, Position=2, ParameterSetName="Tuples")][int[]]$B,
        [parameter(Mandatory=$true, Position=3, ParameterSetName="Tuples")][int[]]$C,
        [parameter(Mandatory=$true, Position=4, ParameterSetName="Tuples")][int[]]$D,
        [parameter(Mandatory=$false)]           [decimal]$Timeout=30,
        [parameter(Mandatory=$false)]           [decimal]$MaxJobs=12,
        [parameter(Mandatory=$false)]           [Switch] $Loud,
        [parameter(Mandatory=$false)]           [Switch] $Silence,
        [parameter(Mandatory=$false)]           [ScriptBlock] $Callback = $null
    )

    $startTime = Get-Date

    $liveIPs = @()
    $checkedIPs = @()
    $objectPool = @()

    $pingCall = {
        param(
            [parameter(Mandatory=$true,Position=1)]$ip,
            [parameter(Mandatory=$true,Position=2)]$Timeout,
            [parameter(Mandatory=$false,Position=3)]$Callback = $null
        )
        $startTime = Get-Date
        $ping = Get-WMIObject -Query "Select StatusCode,ResponseTime From Win32_PingStatus where Address='$ip' and Timeout=$Timeout"
        $result = @{ IP=$ip; Successful=($ping.StatusCode -eq 0); Status=$ping.StatusCode; ResponseTime=$ping.ResponseTime }
        if ($Callback) {
            $result.Callback = . $Callback $result
        }
        $endTime = Get-Date
        $result.Duration = ($endTime - $startTime).TotalMilliseconds

        return $result
    }

    $checkResults = {
        param(
            [parameter(Mandatory=$false)] [Switch]$Silence
        )
        $currentJobs = Get-Job | ? { $_.State -match "Completed|Failed|Stopped" } | sort -Property Name
        foreach($job in $currentJobs) {

            if ($job.HasMoreData) {
                $result = Receive-Job $job
                $checkedIPs += $result.IP
                if ($result.Successful) {
                    $liveIPs += $result.IP
                    if (!$Silence) {
                        Write-host ("{0,-16}   (~{1}ms latency, {2:n2}ms total)" -f $result.IP,$result.ResponseTime,$result.Duration) -ForegroundColor Green
                    }
                } elseif ($Loud -and !$Silence) {
                    Write-host "$($result.IP)`t ($($result.Status))" -ForegroundColor Red
                }
            }
            
            $job | Remove-Job
        }
    }

    if ($PSCmdlet.ParameterSetName -eq "Address") {
        $aStr, $bStr, $cStr, $dStr = $Address.split(".")
        
        foreach ($vName in "aStr", "bStr", "cStr", "dStr") {
            $v = Get-Variable $vName | % Value
            $s, $e = $v.split("~")
            
            if (!$e) {
                $e = $s
            }
            
            $r = ($s..$e)
            
            Set-Variable -Name $vName[0] -Value $r -Scope 0
        }
    }

    foreach ($abyte in $A) {
        foreach ($bbyte in $B) {
            foreach ($cbyte in $C) {
                foreach ($dbyte in $D) {
                    
                    Start-Sleep -Milliseconds 10

                    while ((Get-Job).Count -ge $MaxJobs) {
                        . $checkResults -Silence:$Silence
                    }
                    
                    $ip = "$abyte.$bbyte.$cbyte.$dbyte"
                    Start-Job -ScriptBlock $pingCall -ArgumentList $ip,$Timeout,$Callback | Out-Null
                }
            }
        }
    }

    while (Get-Job) {
        . $checkResults -Silence:$Silence
    }

    $endTime = Get-Date
    $duration = $endTime - $startTime
    if (!$Silence) {
        Write-host ("Ping sweep took {0} (~{1:n2}ms per address)." -f $duration, ($duration.TotalMilliseconds/$checkedIPs.Count)) -ForegroundColor Cyan
        write-host ""
    }
    
    return @{FoundIPs=$liveIPs; Duration=$duration; CheckedIPs = $checkedIPs; Settings=$PSBoundParameters}
}