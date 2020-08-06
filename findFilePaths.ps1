# Generate full paths to the files with the given alias in thier full path
# Takes all files in a given $origin folder, the result file is placed to $destRoot\$fileAlias_filesFound.Count_Get-Date.txt
# Exclude directory is $excludeFolder

Param (
    [Parameter (Mandatory=$true)][string]$origin,
    [Parameter (Mandatory=$true)][string]$fileAlias,
    [Parameter (Mandatory=$true)][string]$destRoot,
    [Parameter (Mandatory=$true)][string]$excludeFolder
)

function Find-File {
    Param (
        [Parameter (Mandatory=$true)][string]$Path,
        [Parameter (Mandatory=$true)][string]$Alias,
        [Parameter (Mandatory=$true)][string]$DestRoot,
        [Parameter (Mandatory=$true)][string]$ExcludeFolder
    )

    if(!(Test-Path $DestRoot)){
        mkdir $DestRoot
    }   
    
    $stopWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $stopWatch.Start()

    $files = Get-ChildItem $Path -Recurse -File -Exclude $ExcludeFolder
    [string[]]$foundFilePaths = @()

    $searchPattern = "*_{0}.*" -f $Alias
    
    $files | ForEach-Object{
        if($_.Name -like $searchPattern){
            $foundFilePaths += $_
        }
    }

    if($foundFilePaths.Count -ne 0){
        $dt = Get-Date -Format yyyy-MM-dd_HH-mm-ss
        $resultLogFile = "{0}\{1}_count_{2}_{3}.txt" -f $DestRoot, $Alias, ($foundFilePaths.Count), $dt
        Write-Output($foundFilePaths >> "$resultLogFile")
    }
    else{
        Write-Output("Unfortunately no files were found")
    }
  

    $stopWatch.Stop()
    $elapsed = $stopWatch.Elapsed
    
    Write-Output("Elapsed time: `"$elapsed`"")
}

$title    = "Full file names for a given camera will be generated..."
$question = @"
Camera name: `"$fileAlias`"
Proceed?
"@

$choices  = "&Yes", "&No"

$decision = $Host.UI.PromptForChoice($title, $question, $choices, 1)
if ($decision -eq 0) {
    Write-Host "Confirmed"
    Find-File $origin $fileAlias $destRoot $excludeFolder
} else {
    Write-Host "Cancelled"
}

Read-Host "Press Enter..."