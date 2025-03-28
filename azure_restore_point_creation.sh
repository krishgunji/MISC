#!/bin/bash

#Set Variables
subscription="SID"
resourceGroup="RGNAME"
vmName="VMANEM"
restorePointCollectionName="CollectionRP"
restorePointName="restorepoint3"
region="REGION"

# Error function
error_exit() {
    echo "Error: $1" >&2
    exit 1
 }

# Log into azure & check already logged or not.
if ! az account show > /dev/null 2>&1; then
    echo "Not logged in azure account.  Loggin in..."
    az login || error_exit "Failed to login into Azure."
fi

# Set Subsription
az account set --subscription "$subscription" || error_exit "Failed to set the subscription '$subscription'."

# Function to check the OS disk managed status
check_managed_disk() {
  os_disk_managed=$(az vm show --resource-group "$resourceGroup" --name "$vmName" --query "storageProfile.osDisk.managedDisk.id" -o tsv)

  if [ -z "$os_disk_managed" ]; then
    error_exit "The OS disk for VM '$vmName' is not a managed disk. Restore points are only supported for managed disks."
  fi
}

# Function to create a restore point collection
create_restore_point_collection() {
  echo "Creating restore point collection '$restorePointCollectionName'..."
  source_id="/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.Compute/virtualMachines/$vmName"
  az restore-point collection create \
    --resource-group "$resourceGroup" \
    --collection-name "$restorePointCollectionName" \
    --source-id "$source_id" \
    --location "$region" || error_exit "Failed to create restore point collection '$restorePointCollectionName'."
}

# Function to create a restore point
create_restore_point() {
  echo "Creating restore point '$restorePointName' for VM '$vmName'..."
  az restore-point create \
    --resource-group "$resourceGroup" \
    --name "$restorePointName" \
    --collection-name "$restorePointCollectionName" \
#    --consistency-mode 'ApplicationConsistent' || error_exit "Failed to create restore point '$restorePointName'."
}

# Function to check the provisioning state of the restore point
check_restore_point_provisioning_state() {
  echo "Checking provisioning state of restore point '$restorePointName'..."
  provisioning_state=$(az restore-point show --resource-group "$resourceGroup" --collection-name "$restorePointCollectionName" --name "$restorePointName" --query "provisioningState" -o tsv)

  if [ "$provisioning_state" != "Succeeded" ]; then
    echo "Warning: Restore point creation may have failed. Provisioning state: $provisioning_state"
  else
    echo "Restore point provisioning state: $provisioning_state"
  fi
}


# Check if the VM exists
if ! az vm show --resource-group "$resourceGroup" --name "$vmName" > /dev/null 2>&1; then
  error_exit "VM '$vmName' not found in resource group '$resourceGroup'."
fi

# Check managed disk status
check_managed_disk

# Check if the restore point collection exists, and create if it doesn't
if ! az restore-point collection show --resource-group "$resourceGroup" --collection-name "$restorePointCollectionName" > /dev/null 2>&1; then
  create_restore_point_collection
else
  echo "Restore point collection '$restorePointCollectionName' already exists."
fi

# Create the restore point
create_restore_point

# Check the provisioning state of the restore point
check_restore_point_provisioning_state

echo "Script completed."
