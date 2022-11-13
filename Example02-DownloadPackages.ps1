Import-Module -Name 'ALNuGetPackageManager.psm1' -Verbose

cd '02-NuGetDownload'

nuget search -Source azuredevops

nuget install fad4be71-bf29-4ff6-e4e1-18d3968ff689.Partner.Customer.extension
