function Set-Title
{
    $now = Get-Date -Format dd-MM-yyyy_HH:mm:ss
    $Host.UI.RawUI.WindowTitle = "`"Camera monitoring utility. Start time: `"$now`"`""
}

function Invoke-CreateDefaultFoldersAndFilesIfNotExists
{
    param(
        [Parameter (Mandatory=$true)][string]$rootFolder,
        [Parameter (Mandatory=$true)][string]$outputFolder,
        [Parameter (Mandatory=$true)][string]$csvPath
    )

    if(!(Test-Path "$rootFolder"))
    {
        Write-Output("Creating utility folder: " + "$rootFolder")
        mkdir -Path "$rootFolder"
    }

    if(!(Test-Path $outputFolder))
    {
        Write-Output("Creating output folder: " + $outputFolder)
        mkdir -Path $outputFolder
    }

    if(!(Test-Path $csvPath))
    {
        Write-Output("Creating .csv template file: " + $csvPath)

        Add-Content -Path $csvPath -Value 'URI,Name,PingInterval'
        $values = @(
            '192.168.10.115,Camera 1,00:10:00',
            '10.192.64.126,Camera 2,00:10:00'
        )
        $values | ForEach-Object { Add-Content -Path $csvPath -Value $_}
    }
}

$utilityFolder = "$PSScriptRoot\monitoringUtility"
$outputFolder = "$utilityFolder\output"
$watchListPath = "$utilityFolder\watchList.csv"

$cameras = Import-Csv -Path $watchListPath

$Throttle = $cameras.Length
$SessionState = [system.management.automation.runspaces.initialsessionstate]::CreateDefault()
$runspacepool = [runspacefactory]::CreateRunspacePool(1, $Throttle, $SessionState, $Host)
$RunspacePool.Open()

$now = Get-Date
Set-Title

Write-Output("Monitoring is active for...")

Invoke-CreateDefaultFoldersAndFilesIfNotExists -rootFolder $utilityFolder -outputFolder $outputFolder -csvPath $watchListPath

# script block to ping a camera and check it's stream via ffmpeg
$TestScriptBlock = {
    Param (
        [Parameter (Mandatory=$true)][string]$CameraURI,
        [Parameter (Mandatory=$true)][string]$Name,
        [Parameter (Mandatory=$true)][timespan]$PingInterval,
        [Parameter (Mandatory=$true)][string]$OutputFolder
    )

    $maxNonRecordingTime = New-TimeSpan -Minutes 30

    $unavailableCount = 0
    
    while($true)
    {
        # Get camera IP from camera stream URI
        $underPing = ($cameraURI | Select-String -Pattern "\d{1,3}(\.\d{1,3}){3}" -AllMatches).Matches.Value
         
        # If cannot parse any 192.168... look like => then URI is at "localhost"
        if(!$underPing)
        {
            $underPing = "localhost"
        }

        $pingFolder = "$OutputFolder\$Name"+"_$underPing"
        
        if(!(Test-Path $pingFolder))
        {
            mkdir -Path $pingFolder
        }
        
        $pingDateTime = Get-Date -Format HH:mm:ss
        $message = $pingDateTime.ToString() + "," + $Name + "," + $underPing;
        
        $pingResult = Test-Connection -Count 1 -Quiet $underPing
        #$pingResult = $false

        $message = $message + "," + $pingResult

        $pingFilename = (Get-Date -Format yyyy-MM-dd).ToString()+"_ping.txt"

        if($pingResult)
        {
            $hasStream = $false

            for ($i = 0; $i -lt 8 -and -not $hasStream; $i++)
            {

                $command = ".\ffprobe.exe -v quiet -print_format json -select_streams v:0 -show_entries stream=avg_frame_rate,r_frame_rate,time_base,bits_per_raw_sample -of default=noprint_wrappers=1:nokey=1 -rtsp_transport tcp -i `"$CameraURI`""
                
                # $command = ".\ffprobe.exe -v quiet -print_format json -select_streams v:0 -show_entries stream=avg_frame_rate,r_frame_rate,time_base,bits_per_raw_sample -of default=noprint_wrappers=1:nokey=1 -rtsp_transport tcp -stimeout 1000 -i `"$CameraURI`""
                # $command = ".\ffprobe.exe -v quiet -print_format json -select_streams v:0 -show_entries stream=avg_frame_rate,r_frame_rate,time_base,bits_per_raw_sample -of  default=noprint_wrappers=1:nokey=0 -i D:\Data\20200715_17-19-20-3530_Conv2_Cam123.ts"
                $ffprobeResult = Invoke-Expression $command

                $hasAnyResult = $false
                $hasAnyResult = ([Object[]]$ffprobeResult).Length -ge 1

                if($hasAnyResult)
                {
                    $avg_frame_rate = $ffprobeResult[0]
                    $r_frame_rate =  $ffprobeResult[1]
                    $time_base =  $ffprobeResult[2]
                    $bits_per_raw_sample =  $ffprobeResult[3]

                    $Avg = $avg_frame_rate -ne "0/0" -and $avg_frame_rate -ne "N/A"
                    $R = $r_frame_rate -ne "0/0" -and $r_frame_rate -ne "N/A"
                    $Base = $time_base -ne "0/0" -and $time_base -ne "N/A"
                    $Bps = $bits_per_raw_sample -ne "0/0" -and $bits_per_raw_sample -ne "N/A"

                    $hasStream = $Avg -or $R -or $Base -or $Bps
                }
            }

            $message += ","+$hasStream

            if($hasStream)
            {
                $unavailableCount = 0
            }
            else
            {
                $unavailableCount++   
            }

            if(($unavailableCount * $PingInterval.TotalHours)  -ge $maxNonRecordingTime.TotalHours)
            {
                $message += ", === Camera pings but doesn't give any frames for more than " + $maxNonRecordingTime
            }

            echo "$message" >> "$pingFolder\$pingFilename"
            Start-Sleep -Seconds $PingInterval.TotalSeconds
        }
        else
        {
            # Ping at IP address result can be False due to security/network reasons, but RTSP stream is up
            # So that strings below are wrong in general case, but suitable for some security/network settings

            # Say "no ping => no stream"
            $message += ",False"
            $unavailableCount++  

            # If more than one maxNonRecordingTime$maxNonRecordingTime we 
            if(($unavailableCount * $PingInterval.TotalHours)  -ge $maxNonRecordingTime.TotalHours){
                $message += ", === Camera doesn't ping and unavailable for more than " + $maxNonRecordingTime
                echo "$message" >> "$pingFolder\$pingFilename"
            }

            echo "$message" >> "$pingFolder\$pingFilename"
            $unavailableCount++

            Start-Sleep -Seconds $PingInterval.TotalSeconds
        }
    }


    $out = "End Monitoring for: URI = {0}, Name = {1}, Interval = {2}" -f $CameraURI, $Name, $PingInterval

    Return New-Object PSObject -Property @{
        Msg = $out
    }
 }

$Jobs = @()

$cameras | Format-Table Name, URI, PingInterval -AutoSize

$cameras | ForEach-Object {
    $Job = [powershell]::Create().AddScript($TestScriptBlock).AddArgument($_.URI).AddArgument($_.Name).AddArgument([timespan]$_.PingInterval).AddArgument($outputFolder)
    $Job.RunspacePool = $RunspacePool
    $Jobs += New-Object PSObject -Property @{
        RunNum = $_
        Pipe = $Job
        Result = $Job.BeginInvoke()
   }
}

$Results = @()

ForEach ($Job in $Jobs) {
    $Results += $Job.Pipe.EndInvoke($Job.Result)
}

#$Results | Select-Object Msg| Out-GridView -Title "Results"
$Results | Format-Table Msg -AutoSize