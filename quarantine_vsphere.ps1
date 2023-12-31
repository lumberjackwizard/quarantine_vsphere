

#Get vCenter FQDN or IP:
$vcenter = Read-Host "Enter vCenter FQDN or IP"

#Get vCenter credentials
$Cred = Get-Credential -Title "$vcenter Credentials" -Message 'Enter vCenter administrator Username and Password'

Connect-VIServer -Server $vcenter -Credential $Cred | Out-Null

$target_vm = Read-Host "Enter VM name to be quarantined"

# logic to validate legit VM was entered

$target_vm = Get-VM $target_vm -ErrorAction SilentlyContinue
if ($target_vm) {
    Write-Host 'VM located...' 
} else {
    Write-Host 'No matching VM found. Exiting...'
    exit
} 

#Check VDS where target VM resides for 'Quarantine' dvpg. Create it if one does not exist. 

$vm_vds = Get-VDSwitch -VM $target_vm

$vdpgs = Get-VDPortgroup -vdswitch $vm_vds

$Q_dvpg_check = 1
foreach ($vdpg in $vdpgs){                
    if ($vdpg.Name -eq 'Quarantine'){ 
        $Q_dvpg_check = 0
        Write-Host "Quarantine Distributed Port Group located..."
        break
    }
}

if ($Q_dvpg_check){
    Write-Host "Quarantine Distributed Port Group does not exist. Creating Quarantine Port Group..."
    $Qtine_dvpg = $vm_vds | New-VDPortgroup -Name "Quarantine" 
    $Qtine_dvpg_teaming = Get-vdswitch $vm_vds | Get-VDPortgroup $Qtine_dvpg | Get-VDUplinkTeamingPolicy
    $Qtine_uplinks = $Qtine_dvpg_teaming.ActiveUplinkPort + $Qtine_dvpg_teaming.StandbyUplinkPort
    Get-vdswitch $vm_vds | Get-VDPortgroup $Qtine_dvpg | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -UnusedUplinkPort $Qtine_uplinks | Out-Null                          

}
    
#rename the target VM

Write-Host "Renaming $target_vm to QUARANTINE_$target_vm..."
$target_vm = Get-VM $target_vm | Set-VM -Name "QUARANTINE_$target_vm" -Confirm:$false

#move all VM NICs to the Quarantine dvpg

Write-Host "Moving $target_vm vNics to Quarantine Distributed Port Group..."
$Qtine_dvpg = Get-VDPortgroup -VDSwitch $vm_vds -Name Quarantine

$target_networking = Get-NetworkAdapter -VM $target_vm

foreach($nic in $target_networking){
    Set-NetworkAdapter -NetworkAdapter $nic -Portgroup $Qtine_dvpg -Confirm:$false | Out-Null
}


#Suspend the VM

Write-Host "Beginning VM suspension of $target_vm..."
Get-VM $target_vm | Suspend-VM -Confirm:$false | Out-Null


#Create Quaratine Resource Pool for suspended VM
#This will prevent the VM from being removed from suspension until it's removed from this Resource Pool
#If DRS is not enabled on the VM's cluster, this section will be skipped.

$target_cluster = Get-VM $target_vm | Get-Cluster

if ($target_cluster.DrsEnabled -eq "True"){
    Write-Host "Checking if QUARANTINE_RESOURCE_POOL already exists..."
    $qtine_pool = Get-ResourcePool -Name QUARANTINE_RESOURCE_POOL -Location $target_cluster -ErrorAction SilentlyContinue
    if ($qtine_pool){
        Write-Host "QUARANTINE_RESOURCE_POOL already exists. Moving $target_vm to this resource pool..."
        Move-VM -VM $target_vm -Destination $qtine_pool | Out-Null
    } else {
        Write-Host "QUARANTINE_RESOURCE_POOL does not exist. Creating..."
        $qtine_pool = New-ResourcePool -Location $target_cluster -MemLimitGB 0 -CpuLimitMhz 0  -Name QUARANTINE_RESOURCE_POOL
        Write-Host "Moving $target_vm to QUARANTINE_RESOURCE_POOL..."
        Move-VM -VM $target_vm -Destination $qtine_pool | Out-Null
    }

}


#Closing statement
Write-Host "$target_vm quarantined succesfully!"