# Move files from the record directory
# Takes a file and place it according to the following pattern:
# yyyyMMdd folder -> Camera name -> yyyy-MM-dd_CameraName_Time and so on here

Param (
    [Parameter (Mandatory=$true)][string]$origin,
    [Parameter (Mandatory=$true)][string]$destRoot,
    [Parameter (Mandatory=$false)][bool]$moveItems = $true
)

function Copy-File {
    Param (
        [Parameter (Mandatory=$true)][string]$Path,
        [Parameter (Mandatory=$true)][string]$DestinationRoot,
        [Parameter (Mandatory=$false)][bool]$MoveItems = $false
    )

    Import-Module BitsTransfer
    
    $dtFormat = "yyyyMMdd"
    $stopWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $stopWatch.Start()

    $files = Get-ChildItem $Path -Recurse -File
    [string[]]$copyFullNames = @()

    $files | ForEach-Object{
        $splittedName = $_.BaseName -split "_"

        $dateString = $splittedName[0]
        $cameraName = $splittedName[2]

        $yyyyMMdd = [datetime]::ParseExact($dateString,  $dtFormat, $null)
        $yyyy_MM_dd = $yyyyMMdd.ToString("yyyy-MM-dd")

        $copyDateFolder = "$($DestinationRoot)\$($yyyy_MM_dd)\$($cameraName)"

        if(!(Test-Path $copyDateFolder)){
            mkdir $copyDateFolder
        }    

        $outFile = "$($copyDateFolder)\$($_.Name)"
        $copyFullNames += $outFile
    }

    # Copy and store old files, shows progress
    if(-not($MoveItems)){
        for ($i = 0; $i -lt $files.Length; $i++){
            $from = $files[$i].Directory.FullName
            $to = $copyFullNames[$i]
            $overall = "{0}/{1}" -f ($i+1), $files.Length
            $description = @"
Recorded video relocation:
Current
   From: `"$from`"
     To: `"$to`"
Overall: `"$overall`"
"@
            $displayName = "Relocation in progress " + $overall
            Write-Output($description)
            Write-Output("")
            
            Start-BitsTransfer -Source $files[$i].FullName -Destination $copyFullNames[$i] -Description $description -DisplayName $displayName -RetryInterval 60 -RetryTimeout 125
            
            # Removes a copied file
            # Remove-Item -Path $files[$i].FullName
        }
    }
    # Or move from one folder to another without copy
    else {
        for ($i = 0; $i -lt $files.Length; $i++){
            $from = $files[$i].Directory.FullName
            $to = $copyFullNames[$i]
            $overall = "{0}/{1}" -f ($i+1), $files.Length
            $description = @"
Recorded video relocation:
Current
   From: `"$from`"
     To: `"$to`"
Overall: `"$overall`"
"@

            Write-Output($description)
            Write-Output("")

            Move-Item -Path $files[$i].FullName -Destination $copyFullNames[$i]
        }

        # Remove only empty directories
        Get-ChildItem $Path -Recurse -Force -Directory |
        Sort-Object -Property FullName -Descending |
        Where-Object { $($_ | Get-ChildItem -Force | Select-Object -First 1).Count -eq 0 } |
        Remove-Item
    }

    $stopWatch.Stop()
    $elapsed = $stopWatch.Elapsed
    
    Write-Output("")
    Write-Output("")
    $notRelocated = Get-ChildItem $Path -Recurse -File

    if($notRelocated.Length -ne 0){
        Write-Output("Files which are not relocated")
        Write-Output($notRelocated.FullName)
        Write-Output("")
    }
    else {
        Write-Output("All files are relocated!")
    }

    Write-Output("File transfer elapsed time: `"$elapsed`"")
}

$title    = "Please, check all given paths with respect"
$question = @"
You are transferring files from [Origin] / to [Destination] locations
[Origin]:      `"$origin`"
[Destination]: `"$destRoot`"
Transfered files will be moved (paths will be replaced, not copied) and empty folders will be removed from [Origin]: `"$moveItems`"

Check careful! Proceed?
"@

$choices  = "&Yes", "&No"

$decision = $Host.UI.PromptForChoice($title, $question, $choices, 1)
if ($decision -eq 0) {
    Write-Host "Confirmed"
    Copy-File $origin $destRoot $moveItems
} else {
    Write-Host "Cancelled"
}

Read-Host "Press Enter..."