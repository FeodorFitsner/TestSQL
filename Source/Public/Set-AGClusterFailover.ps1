Function Set-AGClusterFailover
{
    <#
    .SYNOPSIS
        Trigger a manual failover of an AlwaysOn Availability Group

    .DESCRIPTION
        The purpose of this script is to allow you to failover to a different node in an AlwaysOn Availability Group.

        Failover to synchronous nodes does not require any extra actions and can be done anytime.

        Failover to asynchronous nodes requires the use of the -Force parameter.  Data loss is possible and the script will
        prompt you to make sure you want to do this.

        Failover to asynchronous nodes in a DR situation, when synchronous nodes and the file share witness--essentially you've
        lost quorum--can also be done with this script.  Use -Force and -FixQuorum to trigger this.  Data loss is possible and the
        script will prompt you to make sure you want to do this.

        *** WARNING ***
        Do not do this unless you absolutely must. -Force and -FixQuorum should never be used in normal operations.
        *** WARNING ***

    .PARAMETER ComputerName
        Designate the node in the Availability Group cluster you want to failover to.

    .PARAMETER Force
        When failing over to an asynchronous node, you must use this switch to verify that you want to do this type of failover
        and that you understand data loss is possible.  This switch is also required when doing a DR failover after loss of
        quorum.

    .PARAMETER FixQuorum
        Only use in case of full DR failover and loss of quorum.  Switch instructs the script (along with the -Force parameter) 
        to force quorum to the asynchronous node and trigger a failover.

    .EXAMPLE
        Import-Module PS.SQL
        Set-AGClusterFailover -ComputerName SQL-AG-01b

        Triggers a failover to SQL-AG-01b, no action will occur if SQL-AG-01b is already the primary.

    .EXAMPLE
        Import-Module PS.SQL
        Set-AGClusterFailover -ComputerName SQL-AG-01c -Force

        Triggers a failover to the asynchronous node, SQL-AG-01c.  

    .NOTES
        Author:             Martin Pugh
        Date:               12/16/14
      
        Changelog:
            12/14/14        MLP - Initial Release
            10/9/15         MLP - reworked to require Get-AGCluster, and to use SQL queries instead of the SQL provider
            1/6/16          MLP - Added the moving of the "Cluster Group" Windows cluster group name using Move-RemoteClusterGroup function
            2/19/16         MLP - Updated help and added to PS.SQL
            3/15/16         MLP - Added ValidateAGClusterObject function
    #>
    #requires -Version 3.0
    [CmdletBinding()]
    Param (
        [Parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [Parameter(Mandatory)]
        [string]$ComputerName,
        [switch]$Force,
        [switch]$FixQuorum
    )
    BEGIN {
        Write-Verbose "$(Get-Date): Beginning failovers to $ComputerName..." -Verbose
        Write-Verbose "$(Get-Date):     Force: $Force"
        Write-Verbose "$(Get-Date): FixQuorum: $FixQuorum"
    }

    PROCESS {
        #Validate Cluster object
        $InputObject | ValidateAGClusterObject

        Write-Verbose "$(Get-Date): Failing over [$($InputObject.AvailabilityGroup)] to $ComputerName..." -Verbose
        If ($InputObject.AvailabilityReplicas -contains $ComputerName)
        {
            If ($ComputerName -ne $InputObject.PrimaryReplicaServerName)
            {
                $AGRState = $InputObject | Get-AGReplicaState | Where Server -eq $ComputerName
                Switch ($true)
                {
                    { $AGRState.SynchronizationState -ne "Healthy" -or (-not $InputObject.ListenerDNSName) -and (-not $Force) } {
                        Write-Warning "$(Get-Date): Availability Group [$($InputObject.AvailabilityGroup)] is in an unhealthy state or does not have DNS Listener's properly configured, unable to failover until this is resolved.  If you are in a DR situation rerun this script with the -Force and -FixQuorum switches"
                        Write-Warning "$(Get-Date): HealthState: $($AGRState.SynchronizationState)"
                        Write-Warning "$(Get-Date):    Listener: $($InputObject.ListenerDNSName)"
                        Break
                    }
                    { $AGRState.AvailabilityMode -eq "ASYNCHRONOUS_COMMIT" -and (-not $Force) } {
                        Write-Warning "$(Get-Date): $ComputerName is the ASynchronous node for [$($InputObject.AvailabilityGroup)] and cannot be failed over to without data loss.  If this is OK, use the -Force switch"
                        Break
                    }
                    { $AGRState.AvailabilityMode -eq "ASYNCHRONOUS_COMMIT" -and $Force -and (-not $FixQuorum) } {
                        If ($AGRState.SynchronizationState -ne "Healthy")
                        {
                            Write-Warning "$(Get-Date): Availability Group [$($InputObject.AvailabilityGroup)] is in an unhealthy state, aborting failover.  Fix the replication state, or if this is a DR situation use the -Force and -FixQuorum switches"
                        }
                        Else
                        {
                            Invoke-SQLQuery -Instance $ComputerName -Database Master -Query "ALTER AVAILABILITY GROUP [$($InputObject.AvailabilityGroup)] FORCE_FAILOVER_ALLOW_DATA_LOSS"
                            Start-Sleep -Seconds 10
                            $InputObject | Resume-AGReplication
                            Move-RemoteClusterGroup -Cluster $ComputerName -Node $ComputerName -Verbose
                        }
                        Break
                    }
                    { $AGRState.AvailabilityMode -eq "ASYNCHRONOUS_COMMIT" -and $Force -and $FixQuorum } {
                        Write-Warning "You have specified a DR failover to the asynchronous node. This is a drastic step and should only be performed if absolutely required."
                        $Answer = Read-Host "Are you sure you wish to proceed with a DR failover?  This action will change quorum settings, and there is a potential loss of data!`n[Y]es/[N]o (default is ""N"")"
                        If ($Answer.ToUpper() -eq "Y")
                        {
                            #Failover the cluster
                            Invoke-Command -Session $ComputerName -ScriptBlock {
                                Import-Module FailoverClusters
                                Stop-ClusterNode -Name $Using:ComputerName
                                Start-ClusterNode -Name $Using:ComputerName -FixQuorum
                                Start-Sleep -Seconds 3

                                #Set Node Weight
                                (Get-ClusterNode -Name $Using:ComputerName).NodeWeight = 1
                                ForEach ($Node in (Get-ClusterNode | Where Name -ne $Using:ComputerName))
                                {
                                    Start-Sleep -Milliseconds 500
                                    $Node.NodeWeight = 0
                                }
                            }
                            Invoke-SQLQuery -Instance $ComputerName -Database Master -Query "ALTER AVAILABILITY GROUP [$($InputObject.AvailabilityGroup)] FORCE_FAILOVER_ALLOW_DATA_LOSS"
                            Start-Sleep -Seconds 2

                            $InputObject | Resume-AGReplication
                            Break
                        }
                    }
                    DEFAULT {
                        Invoke-SQLQuery -Instance $ComputerName -Database Master -Query "ALTER AVAILABILITY GROUP [$($InputObject.AvailabilityGroup)] FAILOVER"
                        Start-Sleep -Seconds 10
                        $InputObject | Resume-AGReplication
                        Move-RemoteClusterGroup -Cluster $ComputerName -Node $ComputerName -Verbose
                    }
                }
            }
            Else
            {
                Write-Verbose "$(Get-Date): $ComputerName is already the primary replica for [$($InputObject.AvailabilityGroup)]" -Verbose
            }
        }
        Else
        {
            Write-Warning "$(Get-Date): $ComputerName is not a valid replica server for [$($InputObject.AvailabilityGroup)].  Skipping."
        }
    }

    END {
        Write-Verbose "$(Get-Date): Failover's completed." -Verbose
    }
}

