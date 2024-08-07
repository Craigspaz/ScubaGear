# The purpose of this test is to verify that some of the DeployUtils functions, used to publish ScubaGear, are working correctly.

# Suppress PSSA warnings here at the root of the test file.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
param()

BeforeAll {
  # Write-Warning $PSScriptRoot
  . $PSScriptRoot/../../utils/DeployUtils.ps1
}

Describe "Check ConfigureScubaGearModule" {
  It "The manifest file should be altered" {
    # Get contents of manifest file.
    $Location = Get-Location
    $ManifestFilePath = Join-Path -Path $Location -ChildPath "PowerShell/ScubaGear/ScubaGear.psd1"
    $OriginalContent = Get-Content -Path $ManifestFilePath
    # For debugging
    # ForEach ($Line in $OriginalContent) { Write-Warning $Line }
    # Setup input parameters.
    $ModuleFolderPath = Join-Path -Path $Location -ChildPath "/PowerShell/ScubaGear"
    $ModuleVersion = "9.9.9"
    $Tag = "help"
    ConfigureScubaGearModule -ModulePath $ModuleFolderPath -OverrideModuleVersion $ModuleVersion -PrereleaseTag $Tag
    # Get the new contents of the manifest file
    $ModifiedContent = Get-Content -Path $ManifestFilePath
    # For debugging
    # ForEach ($Line in $ModifiedContent) { Write-Warning $Line }
    # Diff the original with the modified
    $Diff = Compare-Object -ReferenceObject $OriginalContent -DifferenceObject $ModifiedContent
    # Look for changes for a new module version
    $ModuleVersionDiff = $Diff | Out-String | Select-String -Pattern $ModuleVersion
    # There should be only 1 match.
    ForEach ($Match in $ModuleVersionDiff.Matches) {
      $Match | Should -Be $ModuleVersion
    }
    # Look for changes for a new tag
    $TagDiff = $Diff | Out-String | Select-String -Pattern $Tag
    ForEach ($Match in $TagDiff.Matches) {
      $Match | Should -Be $Tag
    }
  }
}

Describe "Check CreateArrayOfFilePaths" {
  It "The array should have all the files in it" {
    # Pick any location, doesn't matter.  For now, get utils folder.
    $Location = Get-Location
    $UtilsFolderPath = Join-Path -Path $Location -ChildPath "utils"
    # For this location, get all the PS files.
    # This could be any type of file; it doesn't really matter.
    $Files = Get-ChildItem -Path $UtilsFolderPath -Filter "*.ps1"
    # Add the files to an array.
    $ArrayOfPowerShellFiles += $Files
    # For debugging
    Write-Warning "Length of input array is $($ArrayOfPowerShellFiles.Length)"
    # Create an array with the method
    $ArrayOfFilePaths = CreateArrayOfFilePaths -SourcePath $UtilsFolderPath -Extensions "*.ps1"
    # For debugging
    Write-Warning "Length of output array is $($ArrayOfFilePaths.Length)"
    # The resulting file should not be empty.
    $ArrayOfFilePaths | Should -Not -BeNullOrEmpty
    # It should have as many files as we sent to the function.
    $ArrayOfFilePaths.Length | Should -Be $ArrayOfPowerShellFiles.Length
  }
}

Describe "Check CreateFileList" {
  It "The list should have all the files in it" {
    # Pick any location, doesn't matter.  For now, get current location.
    $Location = Get-Location
    # For this location, get all the MarkDown files at the base of the repo.
    # This could be any type of file; it doesn't really matter.
    $Files = Get-ChildItem -Path $Location -Filter "*.md"
    # Add the files to an array.
    $ArrayOfMarkdownFiles += $Files
    # For debugging
    # Write-Warning "Length of array is $($ArrayOfMarkdownFiles.Length)"
    # Create a filelist with the function.
    $FileList = CreateFileList -FileNames $ArrayOfMarkdownFiles
    # Get the content in the filelist
    $Content = Get-Content -Path $FileList
    $MarkdownMatches = $Content | Select-String -Pattern '.md'
    # The resulting file should not be empty.
    $Content | Should -Not -BeNullOrEmpty
    # It should have as many files as we sent to the function.
    $MarkdownMatches.Length | Should -Be $ArrayOfMarkdownFiles.Length
  }
}

Context "Unit tests for Build-ScubaModule" {
  Describe -Name 'Return good build folder path' {
    BeforeAll {
      Mock ConfigureScubaGearModule { $true }
    }
    It 'Verify that a valid directory is returned' {
      $Location = Get-Location
      $ModuleFolderPath = Join-Path -Path $Location -ChildPath "/PowerShell/ScubaGear"
      Mock ConfigureScubaGearModule { $true }
      ($ModuleBuildFolderPath = Build-ScubaModule -ModulePath $ModuleFolderPath) | Should -Not -BeNullOrEmpty
      Test-Path -Path $ModuleBuildFolderPath -PathType Container | Should -BeTrue
    }
  }
  Describe -Name 'Publish error' {
    BeforeAll {
      Mock ConfigureScubaGearModule { $false } -Verifiable
      Mock -CommandName Write-Error {}
    }
    It 'Verify warning for config failed' {
      $Location = Get-Location
      $ModuleFolderPath = Join-Path -Path $Location -ChildPath "/PowerShell/ScubaGear"
      Build-ScubaModule -ModulePath $ModuleFolderPath
      Assert-MockCalled Write-Error -Times 1
    }
  }
}

Context "Unit Test for ConfigureScubaGearModule" {
  Describe -Name 'Update manifest' {
    BeforeAll {
      $Location = Get-Location
      $ModuleFolderPath = Join-Path -Path $Location -ChildPath "/PowerShell/ScubaGear"
      if (Test-Path -Path "$env:TEMP\ScubaGear") {
        Remove-Item -Force -Recurse "$env:TEMP\ScubaGear"
      }
      Copy-Item -Recurse -Path $ModuleFolderPath -Destination $env:TEMP -Force
      ConfigureScubaGearModule -ModulePath "$env:TEMP\ScubaGear" | Should -BeTrue
      Import-LocalizedData -BaseDirectory "$env:TEMP\ScubaGear" -FileName ScubaGear.psd1 -BindingVariable UpdatedManifest
    }
    It 'Validate Private Data <Name>' -ForEach @(
      @{Name = "ProjectUri"; Field = "ProjectUri"; Expected = "https://github.com/cisagov/ScubaGear" },
      @{Name = "LicenseUri"; Field = "LicenseUri"; Expected = "https://github.com/cisagov/ScubaGear/blob/main/LICENSE" }
    ) {
      $UpdatedManifest.PrivateData.PSData.$Field | Should -BeExactly $Expected
    }
    It 'Validate Manifest Tags' {
      $UpdatedManifest.PrivateData.PSData.Tags | Should -Contain "CISA"
    }
    It 'Validate Manifest ModuleVersion' {
      $Version = [version]$UpdatedManifest.ModuleVersion
      $Version.Major -Match '[0-9]+' | Should -BeTrue
      $Version.Minor -Match '[0-9]+' | Should -BeTrue
      $Version.Build -Match '[0-9]+' | Should -BeTrue
      $Version.Revision -Match '[0-9]+' | Should -BeTrue
    }
  }
  Describe -Name 'Update manifest with version override' {
    BeforeAll {
      $Location = Get-Location
      $ModuleFolderPath = Join-Path -Path $Location -ChildPath "/PowerShell/ScubaGear"
      if (Test-Path -Path "$env:TEMP\ScubaGear") {
        Remove-Item -Force -Recurse "$env:TEMP\ScubaGear"
      }
      Copy-Item -Recurse -Path $ModuleFolderPath -Destination $env:TEMP -Force
      ConfigureScubaGearModule -ModulePath "$env:TEMP\ScubaGear" -OverrideModuleVersion "3.0.1"
      Import-LocalizedData -BaseDirectory "$env:TEMP\ScubaGear" -FileName ScubaGear.psd1 -BindingVariable UpdatedManifest
    }
    It 'Validate Manifest ModuleVersion' {
      $Version = [version]$UpdatedManifest.ModuleVersion
      $Version.Major | Should -BeExactly 3
      $Version.Minor | Should -BeExactly 0
      $Version.Build | Should -BeExactly 1
      $Version.Revision | Should -BeExactly -1
      $Version | Should -BeExactly "3.0.1"
    }
  }

  Describe -Name 'Update manifest with prerelease' {
    BeforeAll {
      $Location = Get-Location
      $ModuleFolderPath = Join-Path -Path $Location -ChildPath "/PowerShell/ScubaGear"
      if (Test-Path -Path "$env:TEMP\ScubaGear") {
        Remove-Item -Force -Recurse "$env:TEMP\ScubaGear"
      }
      Copy-Item -Recurse -Path $ModuleFolderPath -Destination $env:TEMP -Force
      ConfigureScubaGearModule -ModulePath "$env:TEMP\ScubaGear" -OverrideModuleVersion "3.0.1" -PrereleaseTag 'Alpha'
      Import-LocalizedData -BaseDirectory "$env:TEMP\ScubaGear" -FileName ScubaGear.psd1 -BindingVariable UpdatedManifest
    }
    It 'Validate Manifest version info with prerelease' {
      $Version = [version]$UpdatedManifest.ModuleVersion
      $Version.Major | Should -BeExactly 3
      $Version.Minor | Should -BeExactly 0
      $Version.Build | Should -BeExactly 1
      $Version.Revision | Should -BeExactly -1
      $Version | Should -BeExactly "3.0.1"
      $UpdatedManifest.PrivateData.PSData.Prerelease | Should -BeExactly 'Alpha'
    }
  }
  Describe -Name 'Update manifest with an invalid version' {
    BeforeAll {
      $Location = Get-Location
      $ModuleFolderPath = Join-Path -Path $Location -ChildPath "/PowerShell/ScubaGear"
      if (Test-Path -Path "$env:TEMP\ScubaGear") {
        Remove-Item -Force -Recurse "$env:TEMP\ScubaGear"
      }
      Copy-Item -Recurse -Path $ModuleFolderPath -Destination $env:TEMP -Force
      $ManifestPath = Join-Path -Path $env:TEMP -ChildPath 'ScubaGear\ScubaGear.psd1' -Resolve
      # 99.1 is an intentionally invalid number
      Get-Content "$ModuleFolderPath\ScubaGear.psd1" | ForEach-Object { $_ -replace '5.1', '99.1' } | Set-Content $ManifestPath
    }
    It 'Validate ConfigureScubaGearModule fails with bad Manifest' {
      # This function should throw an error.
      ConfigureScubaGearModule -ModulePath "$env:TEMP\ScubaGear"
      $Error.Count | Should -BeGreaterThan 0
    }
  }
}
