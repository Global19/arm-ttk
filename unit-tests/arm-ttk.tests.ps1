﻿<#
.Synopsis
    arm-ttk Pester tests
.Description
    Pesters tests for the Azure Resource Manager Template Toolkit (arm-ttk).

    These tests make sure arm-ttk is working properly, and are not to be confused with the validation within arm-ttk.
.Notes

    The majority of tests are implemented in a parallel directory structure to the validation in arm-tttk.
    
    That is, for each test file in deploymentTemplate, a test directory should exist beneath this location.

    For example, given the arm-ttk validation rule in:

        deploymentTemplate\adminUsername-Should-Not-Be-A-Literal.test.ps1

    There should be a test data directory:
        
        adminUsername-Should-Not-Be-A-Literal

    
    This will map to a describe block named deploymentTemplate\adminUsername-Should-Not-Be-A-Literal

    This directory should contain two subfolders:

    * Pass
    * Fail

    ### The Pass Folder 
    The Pass folder can contain one or more JSON files.  Running these rules on these files should produce no errors.
    
    The Pass folder may also contain one or more .path.txt files.  These will contain a relative path to a JSON file that should produce no errors.

    ### The Fail Folder

    The Fail folder may also contain one or more JSON files.  These JSON files are expected to produce errors.

    Each JSON file may have a corresponding .should.be.ps1 or .should.be.txt

    If the corresponding .should.be file is a text file (.txt), 
    the error message or ID should match the contents of the file.

    If the corresponding .should.be file is a script (.ps1),
    the error will be passed to the .ps1, which should throw if the error was unexpected. 

    

# Top Level folder matching test name
# Subfolders named pass\fail
# Subfolders for each test beneath that
# Must be human readable 
# Must be logically related to test purpose
# _should not be ErrorID_
# File in a folder _should_ exercise as many scenarios as possible
# ErrorIDs from failures will be reconciled with code to give a coverage metric (though we can also use Pester)
# -This runs thru Pester- (for code coverage)
    

    
#>


if (-not (Get-Module arm-ttk)) { 
    Write-Error "arm-ttk not loaded"
    return
}

# We'll need a few functions to get started:
# Get-TTKPesterInput ( this gets the right input file, given the criteria above)
function Get-TTKPesterTestInput {
    param(
    [Parameter(Mandatory)]
    [string]
    $Path
    )
    Push-Location $path  # Push into the path so relative paths work as expected.
    foreach ($item in Get-ChildItem -Path $Path) {
        
        if ($item.Extension -eq '.json') {
            $item
        }
        elseif ($item.Name -match '\.path\.txt$') {
            foreach ($line in [IO.File]::ReadAllLines($item.Fullname)) {
                Get-Item -Path $line -ErrorAction SilentlyContinue
            }
        }
        elseif ($item -is [IO.DirectoryInfo]) {
            $item
        }
    }
    Pop-Location
}

#Test-TTKPass is called for each directory of pass files, and contains the "it" block
function Test-TTKPass {
    param(
    [Parameter(Mandatory)]
    [string]
    $Name,

    [Parameter(Mandatory)]
    [string]
    $Path
    )
    $testFiles = Get-TTKPesterTestInput -Path $path 
    foreach ($testFile in $testFiles) {
        $fileName = $testFile.Name.Substring(0, $testFile.Name.Length - $testFile.Extension.Length)
        $ttkParams = @{Test = $Name}
        if ($testFile -isnot [IO.DirectoryInfo]) {
            $ttkParams.File = $testfile.Name
        }
        it "Validates $fileName is correct" {
            
            $ttkResults = Get-Item -Path $testFile.Fullname | 
                Test-AzTemplate @ttkParams
            if (-not $ttkResults) { throw "No Test Results" }
            if ($ttkResults | Where-Object { -not $_.Passed}) {
                throw "$($ttkResults.Errors | Out-String)"
            }
        }
    }

}

function Test-TTKFail {
    param(
    [Parameter(Mandatory)]
    [string]
    $Name,

    [Parameter(Mandatory)]
    [string]
    $Path
    )

    $testFiles = Get-TTKPesterTestInput -Path $Path
    foreach ($testFile in $testFiles) {
        $fileName = $testFile.Name.Substring(0, $testFile.Name.Length - $testFile.Extension.Length)
        $targetTextPath  = Join-Path $path "$fileName.should.be.txt"
        $targetScriptPath = Join-Path $path "$fileName.should.be.ps1"
        it "Validates $fileName is flagged" {
            $ttkParams = @{Test = $Name}
            if ($testFile -isnot [IO.DirectoryInfo]) {
                $ttkParams.File = $testfile.Name
            }
            $ttkResults = Get-Item -Path $testFile.Fullname | 
                Test-AzTemplate @ttkParams 
            if (-not $ttkResults) { throw "No Test Results" }
            if (Test-Path $targetTextPath) { # If we have a .should.be.txt
                $targetText = [IO.File]::ReadAllText($targetTextPath) # read it
                foreach ($ttkResult in $ttkResults) {
                    foreach ($ttkError in $ttkResult.Errors) {
                        if ($ttkError.Message -ne $targetText -and $ttkError.FullyQualifiedErrorID -notlike "$targetText,*") {
                            throw "Unexpected Error:
Expected '$($targetText)', got $($ttkError.Message)
$(if ($ttkError.FullyQualifiedErrorID -notlike 'Microsoft.PowerShell*') {
    'ErrorID [' + $ttkError.FullyQualifiedErrorID.Split(',')[0] + ']'
})"
                        }
                    }   
                }
            }
            if (Test-Path $targetScriptPath) {
                
                & "$targetScriptPath" $ttkResults
            }
        }
    }
}


# Get a list of a directories beneath this file location
$MyRoot = $MyInvocation.MyCommand.ScriptBlock.File | Split-Path
$testDirectories = $MyRoot | 
    Get-ChildItem -Directory

foreach ($td in $testDirectories) {
    if ('Pass','Fail','CommonPass','CommonFail' -contains $td.Name ) { continue } # skip some well-known names
    Push-Location $td.FullName
    
    describe "$($td.Name)" {
        $passDirectory = Get-ChildItem -Filter Pass -ErrorAction Ignore
        if ($passDirectory) { # If the pass directory is present, run pass
            context 'Pass' {
                Test-TTKPass -Name $td.Name -Path $passdirectory.FullName
                
            }
        }

        $failDirectory = Get-ChildItem -Filter Fail -ErrorAction Ignore

        if ($failDirectory) { # If the fail directory is present, run fail
            context 'Fail' { 
                Test-TTKFail -Name $td.Name -Path $failDirectory.FullName
            }
        }
    }

    Pop-Location
}