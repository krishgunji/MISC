#!/bin/bash

# Array of users and their public key files
declare -A users=(
    ["nishanthini_r"]='/home/ubuntu/root-workspace/auth-keys/nishanthini_r.pub'
    ["lavanya_kumar"]='/home/ubuntu/root-workspace/auth-keys/lavanya_kumar.pub'  # Add more users here
)

# Common initial password (CHANGE THIS IMMEDIATELY AFTER RUNNING THE SCRIPT!)
initial_password="deeptector@198"  # ***CRITICAL: Change this!***

# Loop through the users
for username in "${!users[@]}"; do
    publicKeyFile="${users[$username]}"

    # Check if the user already exists (improved check)
    if id "$username" &>/dev/null; then
        echo "User '$username' already exists. Skipping."
        continue
    fi

    echo "Creating user '$username'..."

    # Create the user (no password, login disabled initially)
    sudo useradd -m -s /bin/bash "$username"
    sudo chown "$username":"$username" /home/"$username"
    sudo usermod -aG sudo "$username"

    # Set the initial password (and immediately expire it)
    sudo chpasswd <<<"$username:$initial_password"
    sudo passwd -e "$username"

    # Create .ssh directory and authorized_keys file as the target user (improved)
    sudo -u "$username" mkdir -p /home/"$username"/.ssh
    sudo chown "$username":"$username" /home/"$username"/.ssh  # Set ownership immediately
    sudo chmod 700 /home/"$username"/.ssh                 # Set permissions immediately

    sudo -u "$username" touch /home/"$username"/.ssh/authorized_keys
    sudo chown "$username":"$username" /home/"$username"/.ssh/authorized_keys # Set ownership immediately
    sudo chmod 600 /home/"$username"/.ssh/authorized_keys # Set permissions immediately


    # Copy the public key into authorized_keys (more robust)
    if [ -f "$publicKeyFile" ]; then
        sudo cat "$publicKeyFile" | sudo -u "$username" tee -a /home/"$username"/.ssh/authorized_keys > /dev/null # Append, redirect stdout
        echo "Public key added to authorized_keys."
    else
        echo "Error: Public key file '$publicKeyFile' not found for user '$username'. Skipping."
        continue  # Skip to the next user if the key file is missing
    fi

    echo "User '$username' created successfully with SSH key authentication and added to sudo group."
    echo "Initial password set. User MUST change it on first login." # More emphatic message

done
