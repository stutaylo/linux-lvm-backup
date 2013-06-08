#/bin/sh

ENABLE_EMAIL_ALERTS=1
EMAIL_ALERT_ADDRESS=me@domain


bail()
{
  # Sends an email to alert the backup has failed, and exits.
  echo "-> FAILED: $1" 

  if [ $ENABLE_EMAIL_ALERTS -eq 1 ]; then
    echo "-> Sending alert email"
mail -s "Backup Problem On $(hostname)" $EMAIL_ALERT_ADDRESS<<EOF

**************************************************************
BACKUP PROBLEMS ON $(hostname). BACKUP SCRIPT SAID.....

$1

Human Intervention Necessary. Please see logfile for more info.

**************************************************************
-- 
The Backup Fairies.

EOF
  fi

  exit 1

}


validateSource()
{

  # Make sure the source is a mounted lvol.
  echo "-> Checking source lvol $source"
  if [ "$mountpoint" != "$source" ]; then
    return 1
  fi

  lvs $mountvol &> /dev/null 
  if [ $? -ne 0 ]; then
    return 1
  fi

  return 0

}


validateTarget()
{

  # Make sure we can ssh to the remote host and that the target dir is there
  echo "-> Checking SSH connectivity to $remote_host"
  ssh -q -o ConnectTimeout=4 -o StrictHostKeyChecking=no -o PasswordAuthentication=no $remote_host [ -d $remote_dir ]
  if [ $? -ne 0 ]; then
    return 1
  fi

  return 0

}


createSnapshot()
{

  # Create the LVM snapshot and mount it.
  free_pe=$(vgs --noheadings -o vg_free_count $volume_group)
  echo "-> VG $volume_group has$free_pe free physical extents"

  echo "-> Creating snapshot $snapshot_name"
  lvcreate -s -l $free_pe -n $snapshot_name $logical_volume &>/dev/null
  if [ $? -ne 0 ]; then
    return 1
  fi

  echo "-> Mounting $volume_group/$snapshot_name to $mountdir"
  mount $volume_group/$snapshot_name $mountdir
  if [ $? -ne 0 ]; then
    return 1
  fi

  return 0
}


doBackup()
{

  # Actually perform the backup.
  echo "-> Copying data to $remote_host:$remote_dir/$remote_file"
  olddir=$(pwd)
  cd $mountdir && tar zcf - . 2>/dev/null | ssh $remote_host "cat - > $remote_dir/$remote_file"
   
  if [ $? -ne 0 ]; then
    return 1
  fi

  cd $olddir
  return 0

}

cleanupBackup()
{
  # Cleanup after ourselves.
  echo "-> Unmounting $mountdir"
  umount -f $mountdir && rmdir $mountdir
  if [ $? -ne 0 ]; then
    return 1
  fi

  echo "-> Removing snapshot $snapshot_name"
  lvremove -f $volume_group/$snapshot_name &>/dev/null
  if [ $? -ne 0 ]; then
    return 1
  fi

  return 0

}


#
# Main script starts here.
#
if [ $# -ne 2 ]; then
  bail "Wrong number of parameters passed to script"
  exit 1
fi

source=$1
target=$2

echo "=========================================================="
echo "-> Starting backup on $(date)"

#
# Validate our source.
#
mountpoint=$(df -P $source 2>/dev/null | awk 'END{print $6}')
mountvol=$(df -P $source 2>/dev/null | awk 'END{print $1}')

validateSource
if [ $? -ne 0 ]; then
  bail "Source directory $source could not be validated. Is it an Lvol?"
fi


#
# Validate our target.
#
remote_host=$(echo $target | awk -F: '{print $1}')
remote_dir=$(echo $target | awk -F: '{print $2}')

validateTarget
if [ $? -ne 0 ]; then
  bail "Could not SSH to $remote_host, or remote dir $remote_dir does not exist"
fi


#
# Create the backup.
#
logical_volume=$(lvs --noheadings -o lv_path $mountvol)
volume_group=$(dirname $logical_volume)
snapshot_name="backupsnap$$"
mountdir=$(mktemp -d)
safesource=$(echo $source | sed -e 's/\//_/g')
remote_file="$(date +%d%m%y_%H%M).$(hostname).$safesource.tar.gz"

createSnapshot
if [ $? -ne 0 ]; then
  bail "Could not create/mountpoint $mountdir temporary LVM snapshot"
fi

doBackup
if [ $? -ne 0 ]; then 
  bail "Backup to remote server $remote_host failed"
fi

cleanupBackup

if [ $? -ne 0 ]; then
  bail "Could not unmount and remove snapshot $snapshot_name."
fi

echo "-> Backup Complete $(date)"
echo "=========================================================="
