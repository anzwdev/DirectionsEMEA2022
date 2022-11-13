function Download-ALDependenciesToSymbols {
    param(
        [string] $Path = '.',
        [string] $Version = 'latest',
        [string] $PackageSource
    )

    Write-Host "Loading app.json"

    $AppManifest = Read-ALAppManifest -Path $Path
    $AppManifestDependencies = Collect-ALAppManifestDependencies -AppManifest $AppManifest


    Write-Host "Removing downloaded packages"

    Clear-ALNuGetPackagesFolder -Path $Path

    Write-Host "Downloading packages"

    foreach ($AppDependency in $AppManifestDependencies.Values) {
        Write-Host ("Downloading packages for " + $AppDependency.Publisher + " - " + $AppDependency.Name)

        Download-ALDependencyPackage -Path $Path -Dependency $AppDependency -PackageSource $PackageSource -Version $Version
    }

    Write-Host "Updating symbols"

    Copy-ALAppsFromPackagesToSymbols -Path $Path
}

function New-ALNuGetPackage {
    param(
        [string] $Path = '.',
        [string] $FileName = 'app.nuspec',
        [string] $PreReleaseVersionSuffix = '',
        [switch] $OutputFileNamesWithoutVersion
    )

    $ManifestDetails = Update-ALNuGetPackageManifest -Path $Path -FileName $FileName -PreReleaseVersionSuffix $PreReleaseVersionSuffix

    $PackageManifestPath = Join-Path -Path $Path -ChildPath $FileName
    nuget pack $PackageManifestPath -OutputFileNamesWithoutVersion -OutputDirectory $Path

    if (-not $OutputFileNamesWithoutVersion) {
        $PackageNameWithoutVersion = $ManifestDetails.Id + ".nupkg"
        $PackageNameWithVersion = $ManifestDetails.Id + "." + $ManifestDetails.Version + ".nupkg"

        $PackagePathWithoutVersion = (Join-Path -Path $Path -ChildPath $PackageNameWithoutVersion)
        $PackagePathWithVersion = (Join-Path -Path $Path -ChildPath $PackageNameWithVersion)

        Move-Item -Path $PackagePathWithoutVersion -Destination $PackagePathWithVersion -Force

        Write-Output ("Package renamed to '" + $PackagePathWithVersion + "'")
    }
}

function New-ALNuGetPackageManifest {
    param(
        [string] $Path = '.',
        [string] $FileName = 'app.nuspec',
        [string] $PreReleaseVersionSuffix = ''
        )

    Remove-ALNuGetPackageManifest -Path $Path -FileName $FileName
    return Update-ALNuGetPackageManifest -Path $Path -FileName $FileName -PreReleaseVersionSuffix $PreReleaseVersionSuffix
}

function Update-ALNuGetPackageManifest {
    param(
        [string] $Path = '.',
        [string] $FileName = 'app.nuspec',
        [string] $PreReleaseVersionSuffix = ''
        )

    $AppManifest = Read-ALAppManifest -Path $Path
    $PackageManifest = Read-ALNuGetPackageManifest -Path $Path -FileName $FileName

    $NamespaceManager = [System.Xml.XmlNamespaceManager]::new($PackageManifest.NameTable)
    $NamespaceManager.AddNamespace("nuspec", "http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd")
    
    $Package = Get-ALNuSpecPackageNode -Document $PackageManifest -NamespaceManager $NamespaceManager
    $Metadata = GetOrCreate-ALNuSpecElement -Document $PackageManifest -NamespaceManager $NamespaceManager -Element $Package -Name "metadata"

    $NuGetExtensionId = Create-ALNuSpecExtensionId -Id $AppManifest.id -Publisher $AppManifest.publisher -Name $AppManifest.name
    $NuGetVersionNo = $appManifest.version
    if (-not [string]::IsNullOrWhiteSpace($PreReleaseVersionSuffix)) {   
        $NuGetVersionNo = $NuGetVersionNo + "-" + $PreReleaseVersionSuffix
    }    

    $NuGetExtensionDescription = $AppManifest.description
    if ([String]::IsNullOrWhiteSpace($NuGetExtensionDescription)) {
        $NuGetExtensionDescription = (Get-NotNullString -Value $AppManifest.publisher) + " - " + (Get-NotNullString -Value $AppManifest.name)
    }

    Update-ALNuSpecElement -Document $PackageManifest -NamespaceManager $NamespaceManager -Element $Metadata -Name "id" -Value $NuGetExtensionId
    Update-ALNuSpecElement -Document $PackageManifest -NamespaceManager $NamespaceManager -Element $Metadata -Name "version" -Value $NuGetVersionNo
    Update-ALNuSpecElement -Document $PackageManifest -NamespaceManager $NamespaceManager -Element $Metadata -Name "authors" -Value $AppManifest.publisher
    Update-ALNuSpecElement -Document $PackageManifest -NamespaceManager $NamespaceManager -Element $Metadata -Name "description" -Value $NuGetExtensionDescription
    Update-ALNuSpecElement -Document $PackageManifest -NamespaceManager $NamespaceManager -Element $Metadata -Name "title" -Value $AppManifest.name

    $Dependencies = GetOrCreate-ALNuSpecElement -Document $PackageManifest -NamespaceManager $NamespaceManager -Element $Metadata -Name "dependencies"
    $Dependencies.RemoveAll()
   
    foreach ($AppDependency in $appManifest.dependencies) {
        [string] $DependencyId = $AppDependency.id
        if ($DependencyId -eq $null) {
            $DependencyId = $AppDependency.appId
        }

        Create-ALNuSpecDependency -Document $PackageManifest -NamespaceManager $NamespaceManager -Element $Dependencies -Id $DependencyId -Publisher $AppDependency.publisher -Name $AppDependency.name -Version $AppDependency.version
    }
    
    $ALAppFileName = ($AppManifest.publisher + "_" + $AppManifest.name + "_" + $AppManifest.version + ".app")
    $ALAppFiles = [System.Xml.XmlElement](GetOrCreate-ALNuSpecElement -Document $PackageManifest -NamespaceManager $NamespaceManager -Element $Package -Name "files")
    $ALAppFileNodes = $ALAppFiles.SelectNodes("nuspec:file", $NamespaceManager)
    foreach ($ALAppFileNode in $ALAppFileNodes) {
        [string] $ALAppFileNodeName = $ALAppFileNode.GetAttribute("src")

        if ($ALAppFileNodeName.EndsWith(".app", [System.StringComparison]::InvariantCultureIgnoreCase)) {
            $ALAppFiles.RemoveChild($ALAppFileNode) > null
        }
    }

    Create-ALNuSpecFile -Document $PackageManifest -NamespaceManager $NamespaceManager -Element $ALAppFiles -FilePath $ALAppFileName

    Save-ALNuGetPackageManifest -Document $PackageManifest -Path $Path -FileName $FileName

    return [PSCustomObject]@{
        Id = $NuGetExtensionId
        Version = $NuGetVersionNo
    }
}

function Read-ALNuGetPackageManifest {
    param(
        [string] $Path,
        [string] $FileName
        )

    $PackageManifestPath = Join-Path -Path $Path -ChildPath $FileName

    [xml]$PackageManifest = [xml]::new()

    if (Test-Path -Path $PackageManifestPath -PathType Leaf) {
        $PackageManifest.Load($PackageManifestPath) 
    }

    return $PackageManifest
}

function Save-ALNuGetPackageManifest {
param(
    [xml] $Document,
    [string] $Path,
    [string] $FileName
    )

    $PackageManifestPath = Join-Path -Path $Path -ChildPath $FileName
    $Document.Save($PackageManifestPath)
}

function Remove-ALNuGetPackageManifest {
param(
    [string] $Path,
    [string] $FileName
    )

    $PackageManifestPath = Join-Path -Path $Path -ChildPath $FileName

    if (Test-Path -Path $PackageManifestPath -PathType Leaf) {
        Remove-Item -Path $PackageManifestPath
    }
}


function Get-ALNuSpecPackageNode {
    param(
        [xml] $Document, 
        [System.Xml.XmlNamespaceManager] $NamespaceManager
    )

    [System.Xml.XmlElement] $ChildElement = $Document.SelectSingleNode("nuspec:package", $NamespaceManager)
    if ($ChildElement -eq $null) {
        $ChildElement = $Document.CreateElement("package", "http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd")
        $Document.AppendChild($ChildElement) > $null
    }

    return $ChildElement
}

function GetOrCreate-ALNuSpecElement {
    param(
        [xml] $Document, 
        [System.Xml.XmlNamespaceManager] $NamespaceManager, 
        [System.Xml.XmlElement] $Element, 
        [string] $Name
    )
    
    [System.Xml.XmlElement]$ChildElement = $Element.SelectSingleNode("nuspec:" + $name, $NamespaceManager)
    if ($ChildElement -eq $null) {
        $ChildElement = $Document.CreateElement($name, "http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd")
        $Element.AppendChild($ChildElement) > $null
    }

    return $ChildElement
}

function Update-ALNuSpecElement {
    param(
        [xml] $Document, 
        [System.Xml.XmlNamespaceManager] $NamespaceManager, 
        [System.Xml.XmlElement] $Element, 
        [string] $Name,
        [string] $Value
    )

    if ($Value -eq $null) {
        $Value = ""
    }

    [System.Xml.XmlElement] $ChildElement = GetOrCreate-ALNuSpecElement -Document $Document -NamespaceManager $NamespaceManager -Element $Element -Name $Name
    $ChildElement.InnerText = $Value
}

function Create-ALNuSpecDependency {
    param(
        [xml] $Document, 
        [System.Xml.XmlNamespaceManager] $NamespaceManager, 
        [System.Xml.XmlElement] $Element, 
        [string] $Id,
        [string] $Publisher,
        [string] $Name, 
        [string] $Version
    )

    [System.Xml.XmlElement] $ChildElement = $Document.CreateElement("dependency", "http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd")
    $NuSpecExtensionId = Create-ALNuSpecExtensionId -Id $Id -Publisher $Publisher -Name $Name
    $Version = Get-NotNullString -Value $Version
    
    $ChildElement.SetAttribute("id", $NuSpecExtensionId)
    $ChildElement.SetAttribute("version", $Version)

    $Element.AppendChild($ChildElement) > $null
}

function Create-ALNuSpecFile {
    param(
        [xml] $Document, 
        [System.Xml.XmlNamespaceManager] $NamespaceManager, 
        [System.Xml.XmlElement] $Element, 
        [string] $FilePath
    )

    [System.Xml.XmlElement] $ChildElement = $Document.CreateElement("file", "http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd")
   
    $ChildElement.SetAttribute("src", $FilePath)
    $ChildElement.SetAttribute("target", "content")

    $Element.AppendChild($ChildElement) > $null
}


function Create-ALNuSpecExtensionId {
    param(
        [string] $Id,
        [string] $Publisher,
        [string] $Name
    )

    $Id = Get-NotNullString -Value $Id
    $Publisher = Get-NotNullString -Value $Publisher
    $Name = Get-NotNullString -Value $Name
    $Publisher = $Publisher -replace "[^\w-]",""
    $NuSpecExtensionId = $Id + "." + $Publisher + "." + $Name
    $NuSpecExtensionId = $NuSpecExtensionId -replace "[^\w-]","."

    if ($NuSpecExtensionId.Length -gt 64) {
        $NuSpecExtensionId = $NuSpecExtensionId.Substring(0, 64)
    }

    while ($NuSpecExtensionId.EndsWith(".")) {
        $NuSpecExtensionId = $NuSpecExtensionId.Substring(0, $NuSpecExtensionId.Length)
    }

    return $NuSpecExtensionId
}

function Read-ALAppManifest {
    param(
        [string] $Path = '.'
        )

    $AppManifestPath = Join-Path -Path $Path -ChildPath 'app.json'
    $AppManifest = Get-Content -Raw -Path $AppManifestPath | ConvertFrom-Json
    return $AppManifest
}

function Collect-ALAppManifestDependencies {
    param($AppManifest)
    $AppManifestDependencies = @{}

    if ($AppManifest.dependencies -ne $null) {
        foreach ($AppDependency in $AppManifest.dependencies) {
            [string] $Id = $AppDependency.id
            if ($Id -eq $null) {
                $Id = $AppDependency.appId
            }
            Add-ALAppManifestDependencyToHashtable -AppManifestDependencies $AppManifestDependencies -Id $Id -Publisher $AppDependency.publisher -Name $AppDependency.name -Version $AppDependency.version
        }
    }

    #add system applications
    if ($AppManifest.application -ne $null) {
        #Id="c1335042-3002-4257-bf8a-75c898ccb1b8" Name="Application" Publisher="Microsoft"
        #    Id="63ca2fa4-4f03-4f2b-a480-172fef340d3f" Name="System Application" Publisher="Microsoft" 
        #    Id="437dbf0e-84ff-417a-965d-ed2bb9650972" Name="Base Application" Publisher="Microsoft"
        #Id="8874ed3a-0643-4247-9ced-7a7002f7135d" Name="System" Publisher="Microsoft"

        Add-ALAppManifestDependencyToHashtable -AppManifestDependencies $AppManifestDependencies -Id "c1335042-3002-4257-bf8a-75c898ccb1b8" -Publisher "Microsoft" -Name "Application" -Version $AppManifest.application
        Add-ALAppManifestDependencyToHashtable -AppManifestDependencies $AppManifestDependencies -Id "63ca2fa4-4f03-4f2b-a480-172fef340d3f" -Publisher "Microsoft" -Name "System Application" -Version $AppManifest.application
        Add-ALAppManifestDependencyToHashtable -AppManifestDependencies $AppManifestDependencies -Id "437dbf0e-84ff-417a-965d-ed2bb9650972" -Publisher "Microsoft" -Name "Base Application" -Version $AppManifest.application       
        Add-ALAppManifestDependencyToHashtable -AppManifestDependencies $AppManifestDependencies -Id "8874ed3a-0643-4247-9ced-7a7002f7135d" -Publisher "Microsoft" -Name "System" -Version $AppManifest.application
    }    

    return $AppManifestDependencies
}

function Add-ALAppManifestDependencyToHashtable {
    param(
        [hashtable] $AppManifestDependencies,
        [string] $Id,
        [string] $Publisher,
        [string] $Name,
        [string] $Version
    )
    
    #if application exists, use highest version
    if ($AppManifestDependencies.ContainsKey($Id)) {

        $ExistingVersion = $AppManifestDependencies[$Id].Version
        $NewVersionObject = [System.Version]::Parse($Version)       
        $ExistingVersionObject = [System.Version]::Parse($ExistingVersion)

        if ($NewVersionObject -gt $ExistingVersionObject) {
            $AppManifestDependencies[$Id].Version = $Version
        }

    } else {
        $Dependency = [PSCustomObject]@{
            Id = $Id
            Publisher = $Publisher
            Name = $Name
            Version = $Version
        }
        $AppManifestDependencies.Add($Id, $Dependency) > null
    }
}

function Get-NotNullString {
    param([string] $Value)

    if ($Value -eq $null) {
        return ""
    }
    return $Value
}

function Download-ALDependencyPackage {
    param(
        [string] $Path = '.',
        [string] $Version = 'latest',
        [string] $PackageSource,
        $Dependency
    )

    [string] $PackagesFolder = Get-ALNuGetPackagesFolderPath -Path $Path
    [string] $DependencyId = Create-ALNuSpecExtensionId -Id $Dependency.Id -Publisher $Dependency.Publisher -Name $Dependency.Name    

    try {
        $AllVersions = Find-Package -Name $DependencyId -Source $PackageSource -MinimumVersion $Dependency.Version -AllVersions -ErrorAction Stop
        if ($AllVersions.Count -gt 0) {
            [string] $ReqVersion = ""
            if ($Version -eq 'lowest') {
                $ReqVersion = $AllVersions[$AllVersions.Count - 1].Version
            } else {
                $ReqVersion = $AllVersions[0].Version
            }
            Install-Package -Name $DependencyId -RequiredVersion $ReqVersion -Source $PackageSource -Destination $PackagesFolder 
            Write-Host ("Version " + $ReqVersion + " of package " + $Dependency.Publisher + " - " + $Dependency.Name + " downloaded ") -ForegroundColor Green
        }
    }
    catch {
        Write-Host ("Package " + $Dependency.Publisher + " - " + $Dependency.Name + " not found ") -ForegroundColor Red
    }
}

function Clear-ALNuGetPackagesFolder {
    param([string] $Path = '.')

    $PackagesFolder = Get-ALNuGetPackagesFolderPath -Path $Path
    $PackagesPath = Join-Path -Path $PackagesFolder -ChildPath "*"

    Remove-Item $PackagesPath -Recurse -Force
}

function Get-ALNuGetPackagesFolderPath {
    param([string] $Path = '.')
    return Join-Path -Path $Path -ChildPath ".nugetpackages"
}

function Get-ALSymbolsFolderPath {
    param([string] $Path = '.')
    return Join-Path -Path $Path -ChildPath ".alpackages"
}

function Get-ALAppFiles {
    param([string] $Path)

    $AppInfosList = [System.Collections.ArrayList]::new()

    $AppFilesList = Get-ChildItem -Path $Path -Filter "*.app" -Recurse
    foreach ($AppFile in $AppFilesList) {
        [string] $AppName = $AppFile.Name
        [int] $Pos = $AppName.LastIndexOf(".")
        $AppName = $AppName.Substring(0, $Pos)
        $Pos = $AppName.LastIndexOf("_")
        $AppVersion = $AppName.Substring($Pos + 1)
        $AppName = $AppName.Substring(0, $Pos)

        $AppInfo = [PSCustomObject]@{
            AppName = $AppName.ToLower()
            AppVersion = $AppVersion
            FileName = $AppFile.Name
            FilePath = $AppFile.FullName
            FileItem = $AppFile
        }

        $AppInfosList.Add($AppInfo) > null
    }

    return $AppInfosList
}

function Copy-ALAppsFromPackagesToSymbols {
    param([string] $Path = '.')

    $PackagesFolder = Get-ALNuGetPackagesFolderPath -Path $Path
    $SymbolsFolder = Get-ALSymbolsFolderPath -Path $Path

    $SymbolsAppsList = Get-ALAppFiles -Path $SymbolsFolder
    $PackagesAppsList = Get-ALAppFiles -Path $PackagesFolder

    foreach ($PackageApp in $PackagesAppsList) {
        foreach ($SymbolApp in $SymbolsAppsList) {
            if ($SymbolApp.AppName -eq $PackageApp.AppName) {
                Remove-Item -Path $SymbolApp.FilePath -ErrorAction Ignore
            }
        }
        $DestAppPath = Join-Path -Path $SymbolsFolder -ChildPath $PackageApp.FileName
        Copy-Item -Path $PackageApp.FilePath -Destination $DestAppPath
    }

}

function Copy-SingleALAppToSymbols{
    param(
        [string] $SymbolsFolder,
        [string] $AppFile
    )
}

Export-ModuleMember -Function New-ALNuGetPackage, New-ALNuGetPackageManifest, Update-ALNuGetPackageManifest, Download-ALDependenciesToSymbols

