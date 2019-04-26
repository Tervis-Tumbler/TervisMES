$ModulePath = if ($PSScriptRoot) {
	$PSScriptRoot
} else {
	(Get-Module -ListAvailable TervisMES).ModuleBase
}
. $ModulePath\Definition.ps1

Function Get-MESUsersWhoHaveLoggedOnIn3Months {
    param (
        [Parameter(Mandatory)]$DataSource,
        [Parameter(Mandatory)]$DataBase
    )
    $DateOf3MonthsAgo = $(get-date).AddMonths(-3)
    $QueryForMESUsersWhoHaveLoggedOnIn3Months = @"
SELECT [ID]
      ,[UserID]
      ,[Area]
      ,[Shift]
      ,[Cell]
      ,[Station]
      ,[LastLoginDate]
  FROM [MES].[dbo].[LastLogin] (Nolock)
  where LastLoginDate > '$($DateOf3MonthsAgo.Year)-$($DateOf3MonthsAgo.Month)-$($DateOf3MonthsAgo.Day)'
  order by LastLoginDate desc
"@

    $MESUsersWhoHaveLoggedOnInTheLast3Months = Invoke-SQL -dataSource $DataSource -database $DataBase -sqlCommand $QueryForMESUsersWhoHaveLoggedOnIn3Months
    $UserNames = $MESUsersWhoHaveLoggedOnInTheLast3Months | 
    select -ExpandProperty userid

    $UniqueUserNamesWithoutWhiteSpace = $UserNames | Remove-WhiteSpace | Sort-Object -Unique
    $UniqueUserNamesWithoutWhiteSpace
}

Function Remove-ADMESUsersWhoHaveNotLoggedOnIn3Months {
    [CmdletBinding()]
    param (
        [Switch]$WhatIf = $true
    )
    $MESUserNames = Get-MESUsersWhoHaveLoggedOnIn3Months -DataSource "MESSQL.production.$env:USERDNSDOMAIN" -DataBase MES
    $ADUsers = Get-MESOnlyUsers
    $ADUserSAMAccountNames = $ADUsers.samaccountName

    $Results = Compare-Object $MESUserNames $ADUserSAMAccountNames
    
    $ADMESUsersWhoHaventLoggedOnIn3Months = $Results | 
    where sideindicator -eq "=>" | 
    select -ExpandProperty InputObject

    $ADMESUsersWhoHaventLoggedOnIn3Months | Remove-ADUser -WhatIf:$WhatIf
}

function Get-MESOnlyUsers {
    $OU = Get-ADOrganizationalUnit -filter * | 
    where DistinguishedName -like "OU=Users,OU=Production Floor,OU=Operations*" | 
    select -ExpandProperty DistinguishedName

    Get-ADUser -SearchBase $OU -Filter { Enabled -eq $false }
}

function Get-ADUsersThatShouldntBeMESOnlyUsers {
    
}

#function Install-StoresRDSRemoteDesktopPrivilegeScheduledTasks {
#    param (
#        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$ComputerName
#    )
#    begin {
#        $ScheduledTaskCredential = New-Object System.Management.Automation.PSCredential (Get-PasswordstatePassword -AsCredential -ID 259)
#        $Execute = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
#        $Argument = '-Command Update-StoreManagerToStoresRdsPrivilege -NoProfile'
#    }
#    process {
#        Install-PowerShellApplicationScheduledTask -FunctionName 
#
#        $CimSession = New-CimSession -ComputerName $ComputerName
#        If (-NOT (Get-ScheduledTask -TaskName Update-Privilege_StoresRDS_RemoteDesktop -CimSession $CimSession -ErrorAction SilentlyContinue)) {
#            Install-TervisScheduledTask -Credential $ScheduledTaskCredential -TaskName Update-Privilege_StoresRDS_RemoteDesktop -Execute $Execute -Argument $Argument -RepetitionIntervalName EveryDayAt2am -ComputerName $ComputerName
#        }
#    }
#}

function Remove-HelixBatches {
    param (	
	    [Parameter(Mandatory, HelpMessage="Directory path to files to be deleted")]
	    $path,
	    [Parameter(Mandatory, HelpMessage="Number of days history to remain")]
	    $days
    )

    ## CALL POWERSHELL USING Argument:
    ## -command "& 'c:\scripts\DeleteFilesOlderThan.ps1' -path '\\tervis.prv\applications\MES\Helix\Helix Batches\Delta' -days 14"
	
    $limit = (Get-Date).AddDays(-1 * $days)

    # Delete files older than the $limit.
    Get-ChildItem -Path $path -Recurse -Force | 
    Where-Object { !$_.PSIsContainer -and $_.CreationTime -lt $limit } | 
    Remove-Item -Force

    # Delete any empty directories left behind after deleting the old files.
    Get-ChildItem -Path $path -Recurse -Force | 
    Where-Object { 
        $_.PSIsContainer -and (
            Get-ChildItem -Path $_.FullName -Recurse -Force | 
            Where-Object { !$_.PSIsContainer }
        ) -eq $null 
    } |
    Remove-Item -Force -Recurse
}

function Get-MESCustomyzerGraphicsBatchDetail {
    param (
        [Parameter(Mandatory)]$BatchID
    )
    #http://tfs2012:8080/tfs/DefaultCollection/MES/_versionControl#path=%24%2FMES%2FSource%2FMain%2FTervis.MES.SQL%2FTervis.MES.SQL%2FGraphics%2FStored%20Procedures%2FGetBatchDetails.sql&version=T&_a=contents
    Invoke-MSSQL -Server messql.production.tervis.prv -Database mes -SQLCommand @"
exec [Graphics].[GetBatchDetails] $BatchID
"@ -ConvertFromDataRow
}

function Invoke-MESSQL {
    param (
        [Parameter(Mandatory,ParameterSetName="SQLCommand")]$SQLCommand
	)
    Invoke-MSSQL -Server SQL -Database MES -sqlCommand $SQLCommand -ConvertFromDataRow
}

function Get-MESGraphicsGraphicsBatchRenderLog {
	param(
		[Parameter(ValueFromPipelineByPropertyName)]$GraphicsBatchHeaderID
	)
	process {
		$SQLCommand = New-SQLSelect -SchemaName Graphics -TableName GraphicsBatchRenderLog -Parameters $PSBoundParameters
        Invoke-MESSQL -SQLCommand $SQLCommand
        #  |
		# Add-Member -MemberType ScriptProperty -Name OrderDetail -Force -PassThru -Value {
		# 	$This | Add-Member -MemberType NoteProperty -Name OrderDetail -Force -Value $($This | Get-CustomyzerApprovalOrderDetail)
		# 	$This.OrderDetail
		# }
	}
}

function Set-MESGraphicsGraphicsBatchRenderLog {
	param (
		[Parameter(Mandatory,ValueFromPipelineByPropertyName)]$ID,
		$ProcessingFinish,
		$ProcessingStatus
	)
	process {
        $ValueParameters = $PSBoundParameters |
        ConvertFrom-PSBoundParameters -ExcludeProperty ID -AsHashTable

		$SQLCommand = New-SQLUpdate -SchemaName Graphics -TableName GraphicsBatchRenderLog -WhereParameters @{ID = $ID} -ValueParameters $ValueParameters
        Invoke-MESSQL -SQLCommand $SQLCommand
	}
}