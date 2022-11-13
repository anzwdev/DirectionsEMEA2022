Import-Module -Name 'ALNuGetPackageManager.psm1' -Verbose

cd  '01-Extensions\MainExtension'

Download-ALDependenciesToSymbols -Path '.' -Version 'lowest' -PackageSource '<MyFeedName>'

Download-ALDependenciesToSymbols -Path '.' -Version 'latest' -PackageSource '<MyFeedName>'
