# Interactive PPK to PEM Converter

## For this to work we need the fzf 

convert-ppk() {
    local ppk_dir="/mnt/c/Users/abhishek.t/Documents/PPK"
    local pem_dir="$HOME/.ssh/keys"

    # 1. Dependency and Directory Checks
    if ! command -v puttygen &> /dev/null; then
        echo "❌ Error: 'putty-tools' is not installed."
        return 1
    fi
    if [ ! -d "$ppk_dir" ]; then
        echo "❌ Error: Windows PPK directory not found: $ppk_dir"
        return 1
    fi

    # 2. Dynamically scan the Windows folder for .ppk files (removing the extension for a cleaner UI)
    local available_keys
    available_keys=$(find "$ppk_dir" -maxdepth 1 -type f -name "*.ppk" -exec basename {} .ppk \;)

    if [ -z "$available_keys" ]; then
        echo "❌ No .ppk files found in $ppk_dir"
        return 1
    fi

    # 3. Open the floating centered UI for the user to select a key
    local input_name
    input_name=$(echo "$available_keys" | fzf \
        --reverse \
        --height=100% \
        --margin=20%,25% \
        --border="rounded" \
        --padding=1 \
        --prompt="🔑 Select PPK to Convert: " \
        --pointer="▶" \
        --info=hidden)

    # 4. Exit gracefully if the user presses Esc/Ctrl-C
    if [ -z "$input_name" ]; then
        return 0
    fi

    # 5. Prompt for the output name (Defaults to the input name if left blank)
    echo -e "\nSelected: \e[1;36m$input_name.ppk\e[0m"
    read -p "Enter new PEM name (Leave blank to keep '$input_name'): " output_name
    
    # If output_name is blank, set it to the input_name
    output_name=${output_name:-$input_name}

    local source_file="$ppk_dir/$input_name.ppk"
    local dest_file="$pem_dir/$output_name.pem"

    # 6. Validate Destination: Does the Linux key already exist?
    if [ -f "$dest_file" ]; then
        echo -e "\n⚠️  Warning: The key '$output_name.pem' already exists!"
        read -p "Do you want to overwrite it? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "🛑 Operation aborted. Your existing key was kept safe."
            return 1
        fi
    fi

    # 7. Ensure secure directory exists
    mkdir -p "$pem_dir"
    chmod 700 "$pem_dir"

    # 8. Convert the file
    echo -e "\n⏳ Converting..."
    puttygen "$source_file" -O private-openssh -o "$dest_file"

    # 9. Verify success and apply final security measures
    if [ $? -eq 0 ]; then
        chmod 400 "$dest_file"
        echo "✅ Success! PEM securely saved to: $dest_file"
    else
        echo "❌ Error: Conversion failed."
    fi
}


# Interactive SSH Server Adder
add-server() {
    local name="" ip="" user="" key=""
    local config_file="$HOME/.ssh/config"
    local pem_dir="$HOME/.ssh/keys"


    if [[ "$#" -eq 0 ]]; then
        echo -e "\e[1;36m╭──────────────────────────────────────────╮\e[0m"
        echo -e "\e[1;36m│             Add New SSH Server           │\e[0m"
        echo -e "\e[1;36m╰──────────────────────────────────────────╯\e[0m"

        read -rp "Server Name (Alias) : " name
        [[ -z "$name" ]] && { echo "❌ Name is required. Aborted."; return 1; }

        read -rp "IP Address : " ip
        [[ -z "$ip" ]] && { echo "❌ IP is required. Aborted."; return 1; }

        read -rp "Username : (Press Enter for 'ec2-user') " user
        user=${user:-ec2-user} # Automatically defaults to ec2-user if left blank

        # KEY SELECTION (fzf)
        mkdir -p "$pem_dir"
        local available_keys
        available_keys=$(find "$pem_dir" -maxdepth 1 -type f -name "*.pem" -exec basename {} .pem 2>/dev/null)

        if command -v fzf &> /dev/null && [[ -n "$available_keys" ]]; then
            # Append an option to manually type a key
            local fzf_list="$available_keys\n[+] Type a new key manually..."
            
            echo -e " 🔑 Key File            : \e[90m(Opening menu...)\e[0m"
            key=$(echo -e "$fzf_list" | fzf \
                --reverse \
                --no-preview \
                --height=100% \
                --margin=20%,30% \
                --border="rounded" \
                --padding=1 \
                --prompt="🔑 Select Key: " \
                --pointer="▶" \
                --info=hidden)

            # If user pressed Esc, abort
            [[ -z "$key" ]] && { echo "❌ Aborted."; return 1; }

            # If they chose to type manually, prompt them
            if [[ "$key" == "[+] Type a new key manually..." ]]; then
                read -rp " 🔑 Enter Key Name (without .pem): " key
            fi
        else
            # Fallback if fzf is missing or no keys exist yet
            read -rp " 🔑 Key Name (without .pem): " key
        fi

        [[ -z "$key" ]] && { echo "❌ Key is required. Aborted."; return 1; }
        echo -e "\e[1;36m────────────────────────────────────────────\e[0m"

    else
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

        if [[ -z "$name" || -z "$ip" || -z "$user" || -z "$key" ]]; then
            echo "Usage: add-server -name <name> -ip <ip> -u <user> -key <key-name>"
            return 1
        fi
    fi

    local key_path="$pem_dir/$key.pem"

    # Smart Check: Warn if the key hasn't been converted yet
    if [[ ! -f "$key_path" ]]; then
        echo -e "⚠️  \e[1;33mWarning: The key '$key_path' does not exist yet.\e[0m"
        echo -e "   Make sure to run '\e[1;36mconvert-ppk $key\e[0m' before connecting."
    fi

    # Append the formatted block to the SSH config file
    {
        echo ""
        echo "Host $name"
        echo "    HostName $ip"
        echo "    User $user"
        echo "    IdentityFile $key_path"
    } >> "$config_file"

    # Ensure strict security permissions on the config file
    chmod 600 "$config_file"

    echo -e "✅ \e[1;32mSuccess! Server '$name' added to ~/.ssh/config.\e[0m"
    echo -e "🚀 You can now connect using: \e[1;36mssh $name\e[0m"
}

list-servers() {
# Interactive SSH Server Menu (Centered Modal UI)
    local config_file="$HOME/.ssh/config"

    if [[ ! -f "$config_file" ]]; then
        echo "❌ No servers found. The file $config_file does not exist."
        return 1
    fi

    # 1. Extract ONLY the Host names (ignoring wildcards like *)
    local server_list
    server_list=$(awk '/^Host / { 
        if ($2 != "" && $2 != "*") {
            print $2
        }
    }' "$config_file")

    # 2. Pipe into fzf with strict centering margins
    local target_host
    target_host=$(echo "$server_list" | fzf \
        --reverse \
        --no-preview \
        --height=100% \
        --margin=20%,30% \
        --border="rounded" \
        --padding=1 \
        --prompt="🔍 Search Server: " \
        --pointer="▶" \
        --info=hidden)

    # 3. Exit gracefully if the user presses Esc/Ctrl-C
    if [[ -z "$target_host" ]]; then
        return 0
    fi

    # 4. Connect
    echo "Connecting to $target_host..."
    ssh "$target_host"
}


update-key() {
    local server_name="" new_key=""
    local config_file="$HOME/.ssh/config"
    local ppk_dir="/mnt/c/Users/abhishek.t/Documents/PPK"
    local pem_dir="$HOME/.ssh/keys"

    if [[ "$#" -eq 0 ]]; then
        echo -e "\e[1;36m╭──────────────────────────────────────────╮\e[0m"
        echo -e "\e[1;36m│          🔄 Update / Rotate Key          │\e[0m"
        echo -e "\e[1;36m╰──────────────────────────────────────────╯\e[0m"

        if ! command -v fzf &> /dev/null; then
            echo "❌ 'fzf' is required for interactive mode."
            return 1
        fi

        # 1. Select the Server from existing config
        local server_list
        server_list=$(awk '/^Host / { if ($2 != "" && $2 != "*") print $2 }' "$config_file")
        
        if [[ -z "$server_list" ]]; then
            echo "❌ No servers found in ~/.ssh/config."
            return 1
        fi

        echo -e " 🏷️  Server Name : \e[90m(Opening menu...)\e[0m"
        server_name=$(echo "$server_list" | fzf \
            --reverse \
            --height=40% \
            --margin=10%,25% \
            --border="rounded" \
            --padding=1 \
            --prompt="🔍 Select Server to Update: " \
            --pointer="▶" \
            --info=hidden)

        [[ -z "$server_name" ]] && { echo "❌ Aborted."; return 1; }
        # Clear the "Opening menu..." text and show the selection
        echo -e "\e[1A\e[K 🏷️  Server Name : \e[1;32m$server_name\e[0m"

        # 2. Select the New Key from Windows folder
        local available_keys
        available_keys=$(find "$ppk_dir" -maxdepth 1 -type f -name "*.ppk" -exec basename {} .ppk 2>/dev/null)

        if [[ -z "$available_keys" ]]; then
            echo "❌ No .ppk files found in $ppk_dir"
            return 1
        fi

        echo -e " 🔑 New Key     : \e[90m(Opening menu...)\e[0m"
        new_key=$(echo "$available_keys" | fzf \
            --reverse \
            --no-preview \
            --height=100% \
            --margin=10%,25% \
            --border="rounded" \
            --padding=1 \
            --prompt="🔑 Select New PPK Key: " \
            --pointer="▶" \
            --info=hidden)

        [[ -z "$new_key" ]] && { echo "❌ Aborted."; return 1; }
        echo -e "\e[1A\e[K 🔑 New Key     : \e[1;32m$new_key.ppk\e[0m"
        echo -e "\e[1;36m────────────────────────────────────────────\e[0m"


    else
        while [[ "$#" -gt 0 ]]; do
            case $1 in
                -name) server_name="$2"; shift ;;
                -key)  new_key="$2"; shift ;;
                *)     echo "❌ Unknown parameter: $1"; return 1 ;;
            esac
            shift
        done

        if [[ -z "$server_name" || -z "$new_key" ]]; then
            echo "Usage: update-key -name <server-alias> -key <new-ppk-filename>"
            return 1
        fi
    fi


    if ! grep -q "^Host $server_name$" "$config_file"; then
        echo "❌ Error: Server '$server_name' not found in ~/.ssh/config."
        return 1
    fi

    local new_pem_path="$pem_dir/$new_key.pem"
    local source_ppk="$ppk_dir/$new_key.ppk"

    # 🔍 Identify the OLD key
    local old_pem_path
    old_pem_path=$(awk -v target="$server_name" '
        $1 == "Host" { current_host = $2 }
        $1 == "IdentityFile" && current_host == target { print $2 }
    ' "$config_file")

    echo -e "\n🔄 \e[1;34mPhase 1: Converting the new key...\e[0m"
    if [[ ! -f "$source_ppk" ]]; then
        echo "❌ Error: Source PPK not found at $source_ppk"
        return 1
    fi

    # Perform conversion inline for safety
    mkdir -p "$pem_dir" && chmod 700 "$pem_dir"
    puttygen "$source_ppk" -O private-openssh -o "$new_pem_path"

    if [ $? -ne 0 ]; then
        echo "❌ Error: Key conversion failed. Aborting rotation."
        return 1
    fi
    chmod 400 "$new_pem_path"

    echo -e "🔄 \e[1;34mPhase 2: Updating the SSH configuration...\e[0m"
    awk -v target="$server_name" -v new_path="    IdentityFile $new_pem_path" '
        $1 == "Host" { current_host = $2 }
        $1 == "IdentityFile" && current_host == target { $0 = new_path }
        { print }
    ' "$config_file" > "${config_file}.tmp"

    mv "${config_file}.tmp" "$config_file"
    chmod 600 "$config_file"

    echo -e "🔄 \e[1;34mPhase 3: Cleaning up old files...\e[0m"
    if [[ -n "$old_pem_path" && -f "$old_pem_path" ]]; then
        if [[ "$old_pem_path" != "$new_pem_path" ]]; then
            rm "$old_pem_path"
            echo "🗑️  Cleanup: Old key permanently deleted ($old_pem_path)"
        else
            echo "ℹ️  Notice: Old key and new key have the same name. No files deleted."
        fi
    else
        echo "ℹ️  Notice: No existing key found to clean up."
    fi

    echo -e "\n✅ \e[1;32mSuccess! Key rotation complete for '$server_name'.\e[0m"
}

# DevOps Master Dashboard & Help Menu
devops-help() {
    # 1. Check for fzf
    if ! command -v fzf &> /dev/null; then
        # Fallback to a cleaner text version if fzf isn't installed
        echo -e "\e[1;36m╭──────────────────────────────────────────────────────────╮\e[0m"
        echo -e "\e[1;36m│                🚀 DEVOPS SSH TOOLS HELP                  │\e[0m"
        echo -e "\e[1;36m╰──────────────────────────────────────────────────────────╯\e[0m"
        echo -e " \e[1;32m1. convert-ppk\e[0m   : Convert Windows .ppk to WSL .pem"
        echo -e " \e[1;32m2. add-server\e[0m    : Add a new server to ~/.ssh/config"
        echo -e " \e[1;32m3. list-servers\e[0m  : Interactive menu to connect to servers"
        echo -e " \e[1;32m4. update-key\e[0m    : Rotate keys for an existing server"
        echo -e "\e[1;36m────────────────────────────────────────────────────────────\e[0m"
        return 0
    fi

    # 2. Define the interactive menu options
    local menu_options="🚀 list-servers   : Connect to a server (Interactive)
➕ add-server     : Add a new server config
🔄 update-key     : Rotate keys for a server
🔑 convert-ppk    : Convert a single key
📖 help           : Read detailed command usage"

    # 3. Launch the fzf dashboard
    local selection
    selection=$(echo -e "$menu_options" | fzf \
        --reverse \
        --no-preview \
        --height=100% \
        --margin=20%,30% \
        --border="rounded" \
        --padding=1 \
        --prompt="🛠️ Select a tool to run: " \
        --pointer="▶" \
        --info=hidden)

    # Exit if user presses Esc
    [[ -z "$selection" ]] && return 0

    # 4. Extract the command name (the second word, since the first is an emoji)
    local cmd
    cmd=$(echo "$selection" | awk '{print $2}')

    # 5. Execute the selected tool or show the detailed help text
    if [[ "$cmd" == "help" ]]; then
        echo -e "\e[1;36m╭──────────────────────────────────────────────────────────╮\e[0m"
        echo -e "\e[1;36m│                   📖 DETAILED USAGE                      │\e[0m"
        echo -e "\e[1;36m╰──────────────────────────────────────────────────────────╯\e[0m"
        echo -e "\e[1;33mInteractive Usage:\e[0m Just type the command name and press Enter."
        echo ""
        echo -e "\e[1;34mManual CLI Flags:\e[0m"
        echo -e "  \e[1;32mconvert-ppk\e[0m  <filename> [-o <output-name>]"
        echo -e "  \e[1;32madd-server\e[0m   -name <alias> -ip <ip> -u <user> -key <key>"
        echo -e "  \e[1;32mupdate-key\e[0m   -name <alias> -key <new-key>"
        echo -e "\e[1;36m────────────────────────────────────────────────────────────\e[0m"
    else
        $cmd
    fi
}

source /usr/share/doc/fzf/examples/key-bindings.bash

[ -f /usr/share/bash-completion/completions/fzf ] && \
source /usr/share/bash-completion/completions/fzf

alias bat='batcat'
alias fd='fdfind'

export FZF_DEFAULT_COMMAND='fdfind --hidden --exclude node_modules --exclude .git --exclude .venv --exclude __pycache__ --exclude .mypy_cache --exclude .pytest_cache --exclude .vscode --exclude .idea --exclude .DS_Store --exclude *.pyc --exclude *.pyo --exclude *.log --exclude *.tmp --exclude .tmux --exclude .vscode-server'

alias fzf='fzf --preview "batcat --style=numbers --color=always {}"'

alias cat='batcat'
