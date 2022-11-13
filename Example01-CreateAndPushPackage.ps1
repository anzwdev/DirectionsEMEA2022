Import-Module -Name 'ALNuGetPackageManager.psm1' -Verbose

cd "01-Extensions\MainExtension"

Update-ALNuGetPackageManifest -Path '.'

New-ALNuGetPackage -Path '01-Extensions\MainExtension'

nuget push .\fad4be71-bf29-4ff6-e4e1-18d3968ff689.Partner.Customer.extension.1.2.0.0.nupkg -Source azuredevops -ApiKey <ApiKeyName>

nuget search -Source azuredevops
