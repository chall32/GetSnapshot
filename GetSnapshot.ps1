#----------------------------------------------------------------------------------------------------
# GetSnapshot.ps1
# Chris Hall ('Top and tailed' from: http://communities.vmware.com/message/1290894#1290894)
#
# v1.0  - 31 Jul 2013 - Chris Hall - Initial Release
#
#
# Basic Snapshot test : Get-VM | Get-Snapshot | Select vm,name,@{N="SizeGB";E={[math]::round($_.SizeGB, 2)}}
#----------------------------------------------------------------------------------------------------
#
#--FUNCTIONS-----------------------------------------------------------------------------------------
#
function Get-SnapshotTree{  
     param($tree, $target)  
       
     $found = $null  
     foreach($elem in $tree){  
          if($elem.Snapshot.Value -eq $target.Value){  
               $found = $elem  
               continue  
          }  
     }  
     if($found -eq $null -and $elem.ChildSnapshotList -ne $null){  
          $found = Get-SnapshotTree $elem.ChildSnapshotList $target  
     }  
       
     return $found  
}  
  
function Get-SnapshotExtra ($snap){  
     #$daysBack = 5               # How many days back from now  
     $guestName = $snap.VM     # The name of the guest  
       
  
     $tasknumber = 999          # Windowsize of the Task collector  
       
     #$serviceInstance = get-view ServiceInstance  
     $taskMgr = Get-View TaskManager  
       
     # Create hash table. Each entry is a create snapshot task  
     $report = @{}  
       
     $filter = New-Object VMware.Vim.TaskFilterSpec  
     $filter.Time = New-Object VMware.Vim.TaskFilterSpecByTime  
     $filter.Time.beginTime = (($snap.Created).AddSeconds(-5))  
     $filter.Time.timeType = "startedTime"  
       
     $collectionImpl = Get-View ($taskMgr.CreateCollectorForTasks($filter))  
       
     $dummy = $collectionImpl.RewindCollector  
     $collection = $collectionImpl.ReadNextTasks($tasknumber)  
     while($collection -ne $null){  
          $collection | where {$_.DescriptionId -eq "VirtualMachine.createSnapshot" -and $_.State -eq "success" -and $_.EntityName -eq $guestName} | %{  
               $row = New-Object PsObject  
               $row | Add-Member -MemberType NoteProperty -Name User -Value $_.Reason.UserName  
               $vm = Get-View $_.Entity  
               $snapshot = Get-SnapshotTree $vm.Snapshot.RootSnapshotList $_.Result
	       $key = ""
	       if ($snapshot.CreateTime -ne $NULL){
               		$key = $_.EntityName + "&" + ($snapshot.CreateTime.ToString())  
	       }
               $report[$key] = $row  
          }  
          $collection = $collectionImpl.ReadNextTasks($tasknumber)  
     }  
     $collectionImpl.DestroyCollector()  
       
     # Get the guest's snapshots and add the user  
     $snapshotsExtra = $snap | % {  
	  $key = ""  
          $key = $_.vm.Name + "&" + ($_.Created.ToString())  
          if($report.ContainsKey($key)){  
               $_ | Add-Member -MemberType NoteProperty -Name Creator -Value $report[$key].User  
          }  
          $_  
     }  
     $snapshotsExtra  
}  

function LoadSnapin{
  param($PSSnapinName)
  if (!(Get-PSSnapin | where {$_.Name   -eq $PSSnapinName})){
    Add-pssnapin -name $PSSnapinName
  }
}
#
#--END FUNCTIONS-------------------------------------------------------------------------------------
#
LoadSnapin -PSSnapinName   "VMware.VimAutomation.Core"
cls

write-host "Chris' Snapshot Discovery and Attribution Tool (v1.0)"
write-host "-----------------------------------------------------"
write-host "                                  Chris Hall Jul 2013"
write-host ""
$VIname = read-host "Enter ESXi Host or vCenter Name/IP "
Connect-VIServer $VIname 
write-host ""
write-host "Enter minimum acceptable snapshot age in days. For example"
write-host "     2 = look for snapshots older than 2 days"
write-host "     0 = look for all snapshots"
$snapdays = read-host " "
write-host ""
$dismode = read-host "Output to [S]creen or [C]SV file? (Enter S or C) "
write-host ""
write-host ".... Running .... May take some time ...."
$Snapshots = Get-VM | Get-Snapshot # | Where {$_.Created -lt ((Get-Date).AddDays(-[int]$snapdays))}    
$mySnaps = @()  
foreach ($snap in $Snapshots){  
     $SnapshotInfo = Get-SnapshotExtra $snap  
     $mySnaps += $SnapshotInfo  
}  

if (($dismode -eq "C") -or ($dismode -eq "c")) {
	$filename = "C:\Scripts\Snapshot-Report-"+ $VIname + ".csv"
	$mySnaps | Select VM, Name, Creator, Description, Created, @{N="SizeGB";E={[math]::round($_.SizeGB, 2)}} | Export-Csv $filename -UseCulture -NoTypeInformation
	write-host ""
	write-host "Results saved to" $filename
}
else {
	$mySnaps | Select VM, Name, Creator, Description, Created, @{N="SizeGB";E={[math]::round($_.SizeGB, 2)}}  
}
Disconnect-VIServer -Confirm:$false