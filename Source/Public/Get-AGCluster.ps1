Function Get-AGCluster
{
    <#
    .SYNOPSIS
        Get very basic Availability Group cluster information

    .DESCRIPTION
        Script will give you some basic AG cluster information, such as what is the primary replica,
        what databases are in the AG, listener configuration, and health of the AG.

    .PARAMETER ComputerName
        Specify one node in the AG cluster

    .PARAMETER AGListener
        Specify the Availability Group you want to query by using the Listener DNS name.  

    .INPUTS
        None

    .OUTPUTS
        [PSCustomObject]
            Name                                   Name of the AG 
            PrimaryReplicaServerName               Server that is the primary in the AG
            AvailabilityReplicas                   Names of all the servers in the AG
            AvailabilityDatabases                  Names of all of the databases currently added to the AG
            HealthState                            Simple state information of the health of the AG
            Listeners                              IP addresses, Ports and networks monitored that the AG is configured for

    .EXAMPLE
        Import-Module PS.SQL
        Get-AGCluster -ComputerName SQL-AG-01

        Get basic information about all of the AG's on SQL-AG-01 cluster

        AvailabilityGroup        : ag1
        PrimaryReplicaServerName : SQL-AG-01
        AvailabilityReplicas     : {SQL-AG-01, SQL-AG-02, SQL-AG-03}
        AvailabilityDatabases    : {TestAGDatabase, TestAGDatabase10, TestAGDatabase70}
        Listeners                : {@{ip_address=192.168.4.50; port=1433; network_subnet_ip=192.168.4.0; network_subnet_ipv4_mask=255.255.255.0}, @{ip_address=192.168.6.50; port=1433; network_subnet_ip=192.168.6.0; network_subnet_ipv4_mask=255.255.255.0}}
        HealthState              : HEALTHY

    .NOTES
        Author:             Martin Pugh
        Date:               12/16/14
      
        Changelog:
            12/16/14        MLP - Initial Release
            12/20/16        MLP - Complete rewrite, now uses SQL queries.  Added AvailabilityGroup to query
            2/19/16         MLP - Added to PS.SQL
            3/15/16         MLP - Fixed position settings
    #>
    #requires -Version 3.0

    [CmdletBinding(DefaultParameterSetName="computer")]
    Param (
        [Parameter(Mandatory=$true,
            ParameterSetName="computer",
            Position=0)]
        [string]$ComputerName,

        [Parameter(ParameterSetName="ag",
            Position=0)]
        [string]$AGListener
    )

    Write-Verbose "$(Get-Date): Get-AGCluster started"

    Switch ($PsCmdlet.ParameterSetName)
    {
        "computer" {
            $Instance = $ComputerName 
            $AGs = Invoke-SQLQuery -Instance $Instance -Database Master -MultiSubnetFailover -Query "SELECT agc.name,ags.primary_replica FROM sys.availability_groups_cluster AS agc JOIN sys.dm_hadr_availability_group_states AS ags ON agc.group_id = ags.group_id"
            Break 
        }
        "ag" { 
            $Instance = $AGListener
            $AGs = Invoke-SQLQuery -Instance $Instance -Database Master -MultiSubnetFailover -Query "SELECT l.dns_name,agc.name FROM sys.availability_group_listeners AS l JOIN sys.availability_groups_cluster AS agc ON l.group_id = agc.group_id WHERE dns_name ='$AGListener'"
            $AGs | Add-Member -MemberType NoteProperty -Name primary_replica -Value $AGListener
            Break 
        }
    }

    If ($AGs)
    {
        ForEach ($AGName in $AGs)
        {
            Write-Verbose "$(Get-Date): Retrieving information for $($AGName.Name)..."
            $AG = Invoke-SQLQuery -Instance $AGName.primary_replica -Database Master -MultiSubnetFailover -Query "Select ag.name,ag.group_id,ag_state.primary_replica,ag_state.synchronization_health_desc From sys.availability_groups_cluster as ag Join sys.dm_hadr_availability_group_states as ag_state On ag.group_id = ag_state.group_id WHERE name = '$($AGName.Name)'" 
            [PSCustomObject]@{
                AvailabilityGroup = $AG.Name
                AvailabilityGroupID = $AG.group_id
                PrimaryReplicaServerName = $AG.Primary_replica
                AvailabilityReplicas = Invoke-SQLQuery -Instance $AGName.primary_replica -Database Master -MultiSubnetFailover -Query "Select replica_server_name from sys.availability_replicas Where group_id = '$($AG.group_id)'" | Select -ExpandProperty replica_server_name
                AvailabilityDatabases = Invoke-SQLQuery -Instance $AGName.primary_replica -Database Master -MultiSubnetFailover -Query "Select database_name from sys.availability_databases_cluster Where group_id = '$($AG.group_id)'" | Select -ExpandProperty database_name
                ListenerDNSName = Invoke-SQLQuery -Instance $AGName.primary_replica -Database Master -MultiSubnetFailover -Query "SELECT dns_name FROM sys.availability_group_listeners WHERE group_id ='$($AG.group_id)'" | Select -ExpandProperty dns_name
                Listeners = Invoke-SQLQuery -Instance $AGName.primary_replica -Database Master -MultiSubnetFailover -Query "Select list.port,list_detail.ip_address,list_detail.network_subnet_ip,list_detail.network_subnet_ipv4_mask From sys.availability_group_listeners as list Join sys.availability_group_listener_ip_addresses as list_detail On list.listener_id = list_detail.listener_id Where list.group_id ='$($AG.group_id)'" | Select ip_address,port,network_subnet_ip,network_subnet_ipv4_mask
                HealthState = $AG.synchronization_health_desc 
            }
        }
    }
    Else
    {
        Write-Error "Unable to locate Availability Group for $Instance because ""$($Error[0])"""
    }
    Write-Verbose "$(Get-Date): Get-AGCluster finished"
}


