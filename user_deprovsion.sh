#!/bin/bash

# Script to delete a user and their data

# Get the username from the user (or use a default)
if [ -z "$1" ]; then
    read -p "Enter the username to delete: " username
else
    username="$1"
fi

# Check if the user exists
if ! id "$username" &>/dev/null; then
    echo "User '$username' does not exist."
    exit 1
fi

# Restricted usernames (add more as needed)
restricted_users=("ubuntu" "krishan.singh")  # Add users you don't want deleted

# Check if the user is restricted
for restricted_user in "${restricted_users[@]}"; do
    if [[ "$username" == "$restricted_user" ]]; then
        echo "User '$username' is restricted and cannot be deleted by this script."
        exit 1
    fi
done

# Backup directory (adjust as needed)
backup_dir="/home/backups"  # Or any other suitable location
mkdir -p "$backup_dir"       # Create the backup directory if it doesn't exist

# Create a timestamped backup filename
timestamp=$(date +%Y%m%d%H%M%S)
backup_file="$backup_dir/$username-$timestamp.tar.gz"

# Confirm deletion (important safety measure)
read -p "Are you sure you want to delete user '$username' and ALL their data? (yes/no): " confirmation

if [[ "$confirmation" != "yes" ]]; then
    echo "Deletion cancelled."
    exit 1
fi

# Kill any running processes owned by the user (important!)
pkill -u "$username"

# Create the backup (tar.gz)
sudo tar -czvf "$backup_file" /home/"$username"

# Delete the user and their home directory
sudo userdel -r "$username"

# Check for and delete the user's group if it's their primary group (optional, use with caution)
primary_group=$(id -gn "$username") # Get the primary group before the user is deleted
if [[ "$primary_group" != "" ]]; then #Check if primary group exists before deletion
    user_count_in_group=$(groups "$primary_group" | cut -d ':' -f 2 | tr ' ' '\n' | grep -c "$username") #Count users in the group
    if [[ "$user_count_in_group" -eq 1 ]]; then #If the user is the only member of the group
        read -p "User '$username' was the only member of group '$primary_group'. Delete the group? (yes/no): " group_confirmation
        if [[ "$group_confirmation" == "yes" ]]; then
            sudo groupdel "$primary_group"
            echo "Group '$primary_group' deleted."
        fi
    fi
fi



echo "User '$username' and their data have been deleted."
echo "Data backed up to: $backup_file"

# Optional: Clean up any other user-related files or directories (add as needed)
# Example: Remove user's files from /tmp
# sudo find /tmp -user "$username" -delete

exit 0
