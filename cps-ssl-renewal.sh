#!/bin/bash

# Define the path to the directory where certificates are stored
CERT_PATH="/etc/letsencrypt/live"
DOMAIN_NAME1="cps-india.com"
DOMAIN_NAME2="flexus.in"

# Define the current date in ISO format (YYYY-MM-DD)
CURRENT_DATE=$(date -I)

# Define the server mappings (domain -> list of servers)
declare -A SERVER_MAPPING=(
    ["cps-india.com"]="user1@server1:/path/to/certs user2@server2:/path/to/certs user3@server3:/path/to/certs"
    ["flexus.in"]="user1@server4:/path/to/certs user2@server5:/path/to/certs"
)

# Define the server-specific commands (domain@server -> commands)
declare -A SERVER_COMMANDS=(
    ["cps-india.com@server1"]="sudo systemctl reload nginx"
    ["cps-india.com@server2"]="sudo systemctl restart apache2 && sudo systemctl status apache2"
    ["cps-india.com@server3"]="sudo systemctl restart nginx"
    ["flexus.in@server4"]="sudo systemctl reload httpd"
    ["flexus.in@server5"]="sudo systemctl restart apache2 && echo 'Apache restarted successfully'"
)

# Loop through each certificate directory
for cert_dir in "$CERT_PATH"/*; do
    # Check if it is a directory
    if [ -d "$cert_dir" ]; then
        # Extract the domain name from the directory
        domain=$(basename "$cert_dir")

        # Read the expiry date from the certbot certificate
        expiry_date=$(openssl x509 -enddate -noout -in "$cert_dir/cert.pem" | sed 's/notAfter=//')

        # Convert expiry date to ISO format
        expiry_date_iso=$(date -I -d "$expiry_date")

        # Check if the certificate is expired
        if [[ "$CURRENT_DATE" > "$expiry_date_iso" ]]; then
            echo "Certificate for $domain is expired (Expiry: $expiry_date_iso). Renewing..."
            
            # Renew the certificate
            certbot renew --cert-name "$domain" --quiet

            # Check if renewal succeeded
            if [ $? -eq 0 ]; then
                echo "Renewal succeeded for $domain."

                # Check if the domain has a server list
                if [ -n "${SERVER_MAPPING[$domain]}" ]; then
                    # Loop through each server in the list
                    for server_details in ${SERVER_MAPPING[$domain]}; do
                        # Parse the server details
                        remote_user_host=$(echo "$server_details" | cut -d: -f1)
                        remote_path=$(echo "$server_details" | cut -d: -f2)

                        # Transfer the certificate files
                        echo "Transferring certificate files for $domain to $remote_user_host..."
                        scp "$cert_dir/fullchain.pem" "$cert_dir/privkey.pem" "$remote_user_host:$remote_path/$domain/"
                        
                        # Check if transfer succeeded
                        if [ $? -eq 0 ]; then
                            echo "Certificate files for $domain transferred successfully to $remote_user_host."

                            # Run server-specific commands
                            domain_server_key="$domain@${remote_user_host#*@}"
                            if [ -n "${SERVER_COMMANDS[$domain_server_key]}" ]; then
                                commands="${SERVER_COMMANDS[$domain_server_key]}"
                                echo "Executing server-level commands for $domain on $remote_user_host..."
                                ssh "$remote_user_host" "$commands"

                                # Check if commands succeeded
                                if [ $? -eq 0 ]; then
                                    echo "Server-level commands executed successfully for $domain on $remote_user_host."
                                else
                                    echo "Failed to execute server-level commands for $domain on $remote_user_host."
                                fi
                            fi
                        else
                            echo "Failed to transfer certificate files for $domain to $remote_user_host."
                        fi
                    done
                else
                    echo "No server mapping found for $domain. Skipping file transfer."
                fi
            else
                echo "Renewal failed for $domain."
            fi
        else
            echo "Certificate for $domain is still valid (Expiry: $expiry_date_iso)."
        fi
    fi
done

