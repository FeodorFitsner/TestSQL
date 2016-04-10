$VerbosePreference = "Continue"

Import-Module C:\testsql\TestSQL.psm1 -Force

Write-Host "G1:"
Get-Command -Module TestSQL


$SQLServer = "localhost"
$AGListener = "localhost"

Describe "Query Tests For Invoke-SQLQuery" {
    Write-Host "G2:"
    Get-Command -Module TestSQL
    It "Direct-SQL-Query" {
        Write-Host "G3:"
        Get-Command -Module TestSQL

        $Query = "SELECT @@version AS Version"
        $Test = Invoke-SQLQuery -Instance $SQLServer -Database Master -Query $Query
        $Test.Version | Should Match "SQL"
    }
    It "Pipeline-SQL-Query" {
        $Query = "SELECT @@version AS Version"
        $Test = $Query | Invoke-SQLQuery -Instance $SQLServer -Database Master
        $Test.Version | Should Match "SQL"
    }
    <#
    It "AG-Listener-MultiSiteFailover-Switch" {
        $Query = "SELECT @@version AS Version"
        $Test = Invoke-SQLQuery -Instance $AGListener -Database Master -Query $Query
        $Test.Version | Should Match "SQL"
    }#>
    It "List-Databases" {
        $Test = Invoke-SQLQuery -Instance $SQLServer -ListDatabases | Where Name -eq "master"
        $Test.Name | Should Be "master"
    }
    It "NoInstance-Switch" {
        $Query = "SELECT @@version AS Version"
        $Test = Invoke-SQLQuery -Instance $SQLServer -Database Master -Query $Query -NoInstance
        $Test | Get-Member -Name Instance | Should BeNullOrEmpty
    }
    It "PrintToStdOut-Switch" {
        Invoke-SQLQuery -Instance $SQLServer -Database Master -Query "PRINT 'Print To StdOut'" -PrintToStdOut | Should Be "Print To StdOut"
    }
    It "ErrorAction-Stop" {
        $Query = "SELECTs @@version AS Version"
        { Invoke-SQLQuery -Instance $SQLServer -Database Master -Query $Query -ErrorAction Stop } | Should Throw
    }
}