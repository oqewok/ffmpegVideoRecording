Param (
    [Parameter (Mandatory=$true)][string]$cameraURI,
    [Parameter (Mandatory=$true)][string]$cameraName,
    [Parameter (Mandatory=$true)][timespan]$recordLength,
    [Parameter(Mandatory=$true)][timespan]$cameraPingInterval,
    [Parameter(Mandatory=$false)][bool]$passThru=$true,
    [Parameter(Mandatory=$false)][bool]$noNewWindow=$true,
    [Parameter(Mandatory=$false)][int]$recordSessionLimit=20
)

# cameraURI          - URI to camera with login and password
# cameraName         - Human readable camera alias/name
# recordLength       - Total recording time interval, when given all the videos will be the same specified length
# cameraPingInterval - When unavailable, the script will ping the camera (at IP taken from URI) with given interval
# passThru           - Return child's script results back here
# noNewWindow        - Create no windows while execution process
# recordSessionLimit - Specifies amount of videos recorded by the script in attempt to prevent endless execution

# Functions

# FFmpeg recording
function Invoke-Recording
{
    Write-Output("")
    Write-Output("Recording...")
    $startTime = Get-Date
    Write-Output("Start time " + $startTime)
    Write-Output("")

    $yearMonthDay = Get-Date -Format yyyyMMdd
    $fullTime = Get-Date -Format HH-mm-ss-ffff

    $saveFolder = "$PSScriptRoot\recorded\$cameraName\"

    if(!(Test-Path $saveFolder))
    {
        Write-Output("Directory " + $saveFolder + " does not exist")
        Write-Output("Creating directry...")
        mkdir -Path $saveFolder
        Write-Output("Directory created!")
    }
    else
    {
        Write-Output("Directory " + $saveFolder + " already exists")
    }

    $saveAs = $saveFolder + $yearMonthDay + "_" + $fullTime + "_" + $cameraName + ".ts"

    # uncomment this in case of real cameras and comment below otherwise
    $command = "`"$PSScriptRoot\ffmpeg.exe -rtsp_transport tcp -i `"$cameraURI`" -t $recordLength -vcodec copy -acodec copy $saveAs -y`""

    # .\ffmpeg.exe -rtsp_transport tcp -i rtsp://admin:admin123@172.23.11.123:554/ISAPI/Streaming/Channels/101 -t 01:00:00 -vcodec copy -acodec copy 30062020_CAM123.ts

    # comment this in case of real cameras and uncomment above otherwise
    #$command = "`"$PSScriptRoot\ffmpeg.exe -i `"$cameraURI`" -t $recordLength -vcodec copy -acodec copy $saveAs -y`""

    Write-Output("FFMPEG command:" + $command)
    Write-Output("Video from camera " + $cameraName + " will be saved to " + $saveAs)
    Write-Output("Recording video...")
    
    #вызов записи
    #Invoke-Expression $command
    if($passThru -and $noNewWindow)
    {
        Start-Process powershell -Wait -NoNewWindow -PassThru -ArgumentList $command
    }
    elseif ($passThru -and !$noNewWindow)
    {
        Start-Process powershell -Wait -PassThru -ArgumentList $command    
    }
    elseif($noNewWindow -and !$passThru)
    {
        Start-Process powershell -Wait -NoNewWindow -ArgumentList $command
    }
    else
    {
        Start-Process powershell -Wait -ArgumentList $command
    }

    $endTime = Get-Date
    $elapsed = $endTime - $startTime

    Write-Output("")
    Write-Output("Recording finished!")
    Write-Output("End time " + $endTime)
    Write-Output($saveAs + " recorded in " + $elapsed)
    Write-Output("")
}

# Creating ping folder
function Invoke-CreatePingFolder
{
    param([Parameter (Mandatory=$true)][string]$underPing)

    # Create ping .txt
    $pingFolder = $PSScriptRoot + "\pingOutput\" + $underPing
    Write-Output("Creating directory for ping folder: " + $pingFolder)

    if(!(Test-Path $pingFolder))
    {
        Write-Output("Directory " + $pingFolder + " does not exist")
        Write-Output("Creating directory...")
        mkdir -Path $pingFolder
        Write-Output("Directory created!")
    }

    return $pingFolder
}

function Invoke-Sleep
{
    Start-Sleep -Seconds 5
}

function Set-Title
{
    $now = Get-Date
    $Host.UI.RawUI.WindowTitle = "`"Recording video for camera `"$cameraName`", start time: `"$now`" `""
}

# Script start
$scriptStartTime = Get-Date 
$resultLogFile = "$PSScriptRoot\recordResultsLog.txt"

$sb = [System.Text.StringBuilder]::new()

$sb.AppendLine()
$sb.AppendLine("Script start time: " + $scriptStartTime.ToString())
$sb.AppendLine("Camera URI: " + $cameraURI)
$sb.AppendLine("Camera name" + $cameraName.ToString())
$sb.AppendLine("Record length: " + $recordLength.ToString())
$sb.AppendLine("Ping camera availability interval: " + $cameraPingInterval.ToString())
$sb.AppendLine("Show FFmpeg output: " + $passThru)
$sb.AppendLine("Max recorded videos limit from the script start: " + $recordSessionLimit)

Write-Output($sb.ToString())
Write-Output($sb.ToString() >> "$resultLogFile")

$currentRecorded = 0
$recordLimitReached = $currentRecorded -lt $recordSessionLimit

$pingResult = $false
$ffmpegErrorFlag = $false
$recordingErrors = 0
$pingErrors = 0

Invoke-Sleep
Set-Title

while($true -and $recordLimitReached)
{
    # Get camera IP from camera stream URI
    $underPing = ($cameraURI | Select-String -Pattern "\d{1,3}(\.\d{1,3}){3}" -AllMatches).Matches.Value

    # If cannot parse any 192.168... look like => then URI is at "localhost"
    if(!$underPing)
    {
        $underPing = "localhost"
    }

    $pingFolder = (Invoke-CreatePingFolder($underPing+"_"+$cameraName))[-1]

    $pingDateTime = Get-Date -Format yyyy-MM-dd_HH-mm-ss
    $message = $pingDateTime.ToString() + ": pinging camera " + $cameraName + " @ " + $underPing;
    $pingResult = Test-Connection -Count 1 -Quiet $underPing
    $message = $message + ". Ping: " + $pingResult

    $pingFilename = (Get-Date -Format yyyy-MM-dd).ToString()+"_ping.txt"
    Write-Output($message)
    Write-Output("$pingFolder\$pingFilename")
    echo "$message" >> "$pingFolder\$pingFilename"
    
    if($pingResult)
    {
        $startTime = Get-Date
        
        Invoke-Recording

        $endTime = Get-Date
        $elapsed = $endTime - $startTime

        Write-Output("Elapsed Recording time: " + $elapsed)

        # If elapsed record time is twice less than expected => probably a ffmpeg mistake
        # The control based on elapsed time compared to actual video size
        # one want to record
        $ffmpegErrorFlag = $elapsed.TotalMinutes -le ($recordLength.TotalMinutes / 2)

        $elapsedTotalMin = $elapsed.TotalMinutes
        $recordLengthTotalMinDividedBy2 = $recordLength.TotalMinutes / 2
        Write-Output("FFmpeg error flag: `"$elapsedTotalMin`" <= `"$recordLengthTotalMinDividedBy2`" == `"$ffmpegErrorFlag`"")

        if($ffmpegErrorFlag)
        {
            Write-Output("Recording error. Sleeping for " + "$cameraPingInterval" + " ...")
            $recordingErrors++
            Start-Sleep -Seconds $cameraPingInterval.TotalSeconds
        }
        else
        {
            $currentRecorded++
            $recordLimitReached = $currentRecorded -lt $recordSessionLimit
        }
    }
    else
    {
        Write-Output("Ping failed. Sleeping for " + "$cameraPingInterval" + " ...")
        $pingErrors++;
        Start-Sleep -Seconds $cameraPingInterval.TotalSeconds
    }
}

$scriptEndTime = Get-Date
$recordLimitReached = $currentRecorded -le $recordSessionLimit
$elapsedTime = $scriptEndTime - $scriptStartTime

$sb.Clear()
$sb.AppendLine()
$sb.AppendLine()
$sb.AppendLine("Script finished!")
$sb.AppendLine("INFO:")
$sb.AppendLine("Camera URI: " + $cameraURI)
$sb.AppendLine("Videos recorded count: " + $currentRecorded)
$sb.AppendLine("Limit: " + $recordSessionLimit)
$sb.AppendLine("Max recorded videos limit reached: " + $recordLimitReached)
$sb.AppendLine("Script start time: " + $scriptStartTime.ToString())
$sb.AppendLine("Script finish time: " + $scriptEndTime.ToString())
$sb.AppendLine("Elapsed time: " + $elapsedTime.ToString())
$sb.AppendLine("Ping errors count: " + $pingErrors)
$sb.AppendLine("Recording errors count: " + $recordingErrors)
$sb.AppendLine("=============------------=============")

Write-Output($sb.ToString())

$resultLogFile = "$PSScriptRoot\recordResultsLog.txt"
Write-Output($sb.ToString() >> "$resultLogFile")