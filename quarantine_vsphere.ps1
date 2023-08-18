

#Get vCenter FQDN or IP:
$vcenter = Read-Host "Enter vCenter FQDN or IP"

#Get vCenter credentials
$Cred = Get-Credential -Title "$vcenter Credentials" -Message 'Enter vCenter administrator Username and Password'

Connect-VIServer -Server $vcenter -Credential $Cred

$target_vm = Read-Host "Enter VM name to be quarantined"

# logic to validate legit VM was entered

$check_target = Get-VM $target_vm -ErrorAction SilentlyContinue
if ($check_target) {
    Write-Host 'VM located' 
} else {
    Write-Host 'No matching VM found'
    exit
} 

#Check VDS where target VM resides for 'Quarantine' dvpg. Create it if one does not exist. 

$vm_vds = Get-VDSwitch -VM $target_vm

$vdpgs = Get-VDPortgroup -vdswitch $vm_vds

$Q_dvpg_check = 1
foreach ($vdpg in $vdpgs){                
    if ($vdpg.Name -eq 'Quarantine'){ 
        $Q_dvpg_check = 0
        Write-Host "Quarantine Distributed Port Group located"
        break
    }
}

if ($Q_dvpg_check){
    Write-Host "Quarantine Distributed Port Group does not exist. Creating Quarantine Port Group."
    $Qtine_dvpg = $vm_vds | New-VDPortgroup -Name "Quarantine" 
    $Qtine_dvpg_teaming = Get-vdswitch $vm_vds | Get-VDPortgroup $Qtine_dvpg | Get-VDUplinkTeamingPolicy
    $Qtine_uplinks = $Qtine_dvpg_teaming.ActiveUplinkPort + $Qtine_dvpg_teaming.StandbyUplinkPort
    $move_Qtine_uplinks = Get-vdswitch $vm_vds | Get-VDPortgroup $Qtine_dvpg | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -UnusedUplinkPort $Qtine_uplinks                             

}
    
    