convert-ppk() {
    local input_name=""
    local output_name=""

    # 1. Check if at least the input filename is provided
    if [ -z "$1" ]; then
        echo "Usage: convert-ppk <ppk-filename> [-o <output-filename>]"
        return 1
    fi

    # The first argument is the source file
    input_name="$1"
    shift # Move to the next arguments

    # 2. Parse optional flags (like -o)
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -o) output_name="$2"; shift ;;
            *) echo "❌ Unknown parameter: $1"; return 1 ;;
        esac
        shift
    done

    # 3. If no output name is provided via -o, default to the input name
    if [ -z "$output_name" ]; then
        output_name="$input_name"
    fi

    # 4. Define precise paths
    local ppk_dir="/mnt/c/Users/abhishek.t/Documents/PPK"
    local pem_dir="$HOME/.ssh/keys"
    local source_file="$ppk_dir/$input_name.ppk"
    local dest_file="$pem_dir/$output_name.pem"

    # 5. Validate Source: Does the Windows file exist?
    if [ ! -f "$source_file" ]; then
        echo "❌ Error: Could not find $source_file"
        return 1
    fi

    # 6. Validate Destination: Does the Linux key already exist?
    if [ -f "$dest_file" ]; then
        echo "⚠️  Warning: The key '$dest_file' already exists!"
        read -p "Do you want to overwrite it? (y/n) " -n 1 -r
        echo # Print a new line
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "🛑 Operation aborted. Your existing key was kept safe."
            return 1
        fi
    fi

    # 7. Ensure secure directory exists
    mkdir -p "$pem_dir"
    chmod 700 "$pem_dir"

    # 8. Convert the file
    puttygen "$source_file" -O private-openssh -o "$dest_file"

    # 9. Verify success and apply final security measures
    if [ $? -eq 0 ]; then
        chmod 400 "$dest_file"
        echo "✅ Success! PEM securely saved to: $dest_file"
    else
        echo "❌ Error: Conversion failed."
    fi
}

# Add server command
add-server() {
    # 1. Initialize empty variables
    local name=""
    local ip=""
    local user=""
    local key=""

    # 2. Parse the command line arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -name) name="$2"; shift ;;
            -ip)   ip="$2"; shift ;;
            -u)    user="$2"; shift ;;
            -key)  key="$2"; shift ;;
            *)     echo "❌ Unknown parameter passed: $1"; return 1 ;;
        esac
        shift
    done

    # 3. Validate that all required fields were provided
    if [[ -z "$name" || -z "$ip" || -z "$user" || -z "$key" ]]; then
        echo "Usage: add-server -name <name> -ip <ip> -u <user> -key <key-name-without-extension>"
        return 1
    fi

    # 4. Define paths
    local config_file="$HOME/.ssh/config"
    local key_path="$HOME/.ssh/keys/$key.pem"

    # 5. Smart Check: Warn if the key hasn't been converted yet
    if [[ ! -f "$key_path" ]]; then
        echo "⚠️  Warning: The key '$key_path' does not exist yet."
        echo "    Make sure to run 'convert-ppk $key' before connecting."
    fi

    # 6. Append the formatted block to the SSH config file
    echo "" >> "$config_file"
    echo "Host $name" >> "$config_file"
    echo "    HostName $ip" >> "$config_file"
    echo "    User $user" >> "$config_file"
    echo "    IdentityFile $key_path" >> "$config_file"

    # 7. Ensure strict security permissions on the config file
    chmod 600 "$config_file"

    echo "✅ Success! Server '$name' added to ~/.ssh/config."
    echo "🚀 You can now connect using: ssh $name"
}

# List all the servers
list-servers() {
    local config_file="$HOME/.ssh/config"

    # 1. Check if the configuration file exists yet
    if [[ ! -f "$config_file" ]]; then
        echo "❌ No servers found. The file $config_file does not exist."
        return 1
    fi

    # 2. Print the table header
    echo "---------------------------------------------------------------------------------"
    printf "%-25s | %-20s | %-20s | %-25s\n" "SERVER NAME (Alias)" "IP ADDRESS" "USERNAME" "KEY FILE"
    echo "---------------------------------------------------------------------------------"

    # 3. Use AWK to parse the SSH config blocks into single lines
    awk '
    # When a new "Host" block starts, print the previous one and reset variables
    /^Host / { 
        if (host != "") {
            printf "%-25s | %-20s | %-20s | %-25s\n", host, ip, user, key
        }
        host=$2; ip="-"; user="-"; key="-"
    }
    # Capture the specific details for the current host
    /^ *HostName / { ip=$2 }
    /^ *User / { user=$2 }
    /^ *IdentityFile / { 
        # Split the path by "/" and grab only the actual filename to keep the table clean
        n = split($2, path_array, "/")
        key = path_array[n] 
    }
    # Print the very last host block when the file ends
    END {
        if (host != "") {
            printf "%-25s | %-20s | %-20s | %-25s\n", host, ip, user, key
        }
    }' "$config_file"

    # 4. Print the table footer
    echo "---------------------------------------------------------------------------------"

}

# Update the key file after rotation
update-key() {
    local server_name=""
    local new_key=""

    # 1. Parse the command line arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -name) server_name="$2"; shift ;;
            -key)  new_key="$2"; shift ;;
            *)     echo "❌ Unknown parameter: $1"; return 1 ;;
        esac
        shift
    done

    # 2. Validate that inputs were provided
    if [[ -z "$server_name" || -z "$new_key" ]]; then
        echo "Usage: update-key -name <server-alias> -key <new-ppk-filename>"
        return 1
    fi

    local config_file="$HOME/.ssh/config"
    local new_pem_path="$HOME/.ssh/keys/$new_key.pem"

    # 3. Check if the server actually exists in the config file
    if ! grep -q "^Host $server_name$" "$config_file"; then
        echo "❌ Error: Server '$server_name' not found in ~/.ssh/config."
        return 1
    fi

    # ---------------------------------------------------------
    # 🔍 NEW LOGIC: Identify the OLD key before making changes
    # ---------------------------------------------------------
    local old_pem_path=$(awk -v target="$server_name" '
        $1 == "Host" { current_host = $2 }
        $1 == "IdentityFile" && current_host == target { print $2 }
    ' "$config_file")

    echo "🔄 Phase 1: Converting the new key..."
    # 4. Convert the new key using your existing command
    convert-ppk "$new_key"

    if [ $? -ne 0 ]; then
        echo "❌ Error: Key conversion failed. Aborting rotation."
        return 1
    fi

    echo "🔄 Phase 2: Updating the SSH configuration..."
    # 5. Replace the IdentityFile path for the target host
    awk -v target="$server_name" -v new_path="    IdentityFile $new_pem_path" '
    $1 == "Host" { current_host = $2 }
    $1 == "IdentityFile" && current_host == target { $0 = new_path }
    { print }
    ' "$config_file" > "${config_file}.tmp"

    mv "${config_file}.tmp" "$config_file"
    chmod 600 "$config_file"

    # ---------------------------------------------------------
    # 🗑️ NEW LOGIC: Safely delete the OLD key
    # ---------------------------------------------------------
    echo "🔄 Phase 3: Cleaning up old files..."
    if [[ -n "$old_pem_path" && -f "$old_pem_path" ]]; then
        # Safety Check: Ensure the old path is not the exact same as the new path
        if [[ "$old_pem_path" != "$new_pem_path" ]]; then
            rm "$old_pem_path"
            echo "🗑️  Cleanup: Old key permanently deleted ($old_pem_path)"
        else
            echo "ℹ️  Notice: Old key and new key have the same name. No files deleted."
        fi
    else
        echo "ℹ️  Notice: No existing key found to clean up."
    fi

    echo "✅ Success! Key rotation complete for '$server_name'."
}

devops-help() {
    echo "=========================================================="
    echo "              🚀 DEVOPS SSH TOOLS HELP 🚀                 "
    echo "=========================================================="
    echo ""
    echo "1. convert-ppk"
    echo "   Usage: convert-ppk <filename> [-o <output-name>]"
    echo "   Desc:  Converts a .ppk file from Windows to a .pem file in WSL."
    echo ""
    echo "2. add-server"
    echo "   Usage: add-server -name <alias> -ip <ip> -u <user> -key <keyname>"
    echo "   Desc:  Adds a new server configuration to ~/.ssh/config."
    echo ""
    echo "3. list-servers"
    echo "   Usage: list-servers"
    echo "   Desc:  Displays a formatted table of all configured SSH servers."
    echo ""
    echo "4. update-key"
    echo "   Usage: update-key -name <alias> -key <new-keyname>"
    echo "   Desc:  Rotates the key for an existing server and cleans up the old key."
    echo ""
    echo "=========================================================="
}

_convert_ppk_complete() {
    # Get the current word being typed
    local current_word="${COMP_WORDS[COMP_CWORD]}"
    # Updated to match the actual path in your convert-ppk command
    local ppk_dir="/mnt/c/Users/abhishek.t/Documents/PPK"

    # Read the directory, find .ppk files, and remove the .ppk extension for the suggestion
    local available_files=$(ls "$ppk_dir" 2>/dev/null | grep '\.ppk$' | sed 's/\.ppk$//')

    # Generate the autocomplete suggestions based on what the user has typed so far
    COMPREPLY=( $(compgen -W "$available_files" -- "$current_word") )
}
# Attach this logic to the 'convert-ppk' command
complete -F _convert_ppk_complete convert-ppk

_ssh_custom_complete() {
    local current_word="${COMP_WORDS[COMP_CWORD]}"
    local config_file="$HOME/.ssh/config"

    # Use AWK to grab all the 'Host' names from your config file
    local available_hosts=$(awk '/^Host / {print $2}' "$config_file" 2>/dev/null)

    # Generate the autocomplete suggestions
    COMPREPLY=( $(compgen -W "$available_hosts" -- "$current_word") )
}
# Attach this logic to the standard 'ssh' command
complete -F _ssh_custom_complete ssh
