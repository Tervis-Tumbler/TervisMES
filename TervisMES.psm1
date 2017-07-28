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

