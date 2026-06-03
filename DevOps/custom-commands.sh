#!/bin/bash
# ~/.devops_functions.sh: Custom scripts and utilities

# Interactive PPK to PEM Converter
convert-ppk() {
    local ppk_dir="/mnt/c/Users/abhishek.t/Documents/PPK"
    local pem_dir="$HOME/.ssh/keys"

    if ! command -v puttygen &> /dev/null; then
        echo "❌ Error: 'putty-tools' is not installed."
        return 1
    fi
    if [ ! -d "$ppk_dir" ]; then
        echo "❌ Error: Windows PPK directory not found: $ppk_dir"
        return 1
    fi

    local available_keys
    available_keys=$(find "$ppk_dir" -maxdepth 1 -type f -name "*.ppk" -exec basename {} .ppk \;)

    if [ -z "$available_keys" ]; then
        echo "❌ No .ppk files found in $ppk_dir"
        return 1
    fi

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

    if [ -z "$input_name" ]; then
        return 0
    fi

    echo -e "\nSelected: \e[1;36m$input_name.ppk\e[0m"
    read -p "Enter new PEM name (Leave blank to keep '$input_name'): " output_name
    
    output_name=${output_name:-$input_name}

    local source_file="$ppk_dir/$input_name.ppk"
    local dest_file="$pem_dir/$output_name.pem"

    if [ -f "$dest_file" ]; then
        echo -e "\n⚠️  Warning: The key '$output_name.pem' already exists!"
        read -p "Do you want to overwrite it? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "🛑 Operation aborted. Your existing key was kept safe."
            return 1
        fi
    fi

    mkdir -p "$pem_dir"
    chmod 700 "$pem_dir"

    echo -e "\n⏳ Converting..."
    puttygen "$source_file" -O private-openssh -o "$dest_file"

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
        echo -e "\e[1;36m│              Add New SSH Server            │\e[0m"
        echo -e "\e[1;36m╰──────────────────────────────────────────╯\e[0m"

        read -rp "Server Name (Alias) : " name
        [[ -z "$name" ]] && { echo "❌ Name is required. Aborted."; return 1; }

        read -rp "IP Address : " ip
        [[ -z "$ip" ]] && { echo "❌ IP is required. Aborted."; return 1; }

        read -rp "Username : (Press Enter for 'ec2-user') " user
        user=${user:-ec2-user}

        mkdir -p "$pem_dir"
        local available_keys
        available_keys=$(find "$pem_dir" -maxdepth 1 -type f -name "*.pem" -exec basename {} .pem 2>/dev/null)

        if command -v fzf &> /dev/null && [[ -n "$available_keys" ]]; then
            local fzf_list="$available_keys\n[+] Type a new key manually..."
            
            echo -e " 🔑 Key File             : \e[90m(Opening menu...)\e[0m"
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

            [[ -z "$key" ]] && { echo "❌ Aborted."; return 1; }

            if [[ "$key" == "[+] Type a new key manually..." ]]; then
                read -rp " 🔑 Enter Key Name (without .pem): " key
            fi
        else
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

    if [[ ! -f "$key_path" ]]; then
        echo -e "⚠️  \e[1;33mWarning: The key '$key_path' does not exist yet.\e[0m"
        echo -e "   Make sure to run '\e[1;36mconvert-ppk $key\e[0m' before connecting."
    fi

    {
        echo ""
        echo "Host $name"
        echo "    HostName $ip"
        echo "    User $user"
        echo "    IdentityFile $key_path"
    } >> "$config_file"

    chmod 600 "$config_file"

    echo -e "✅ \e[1;32mSuccess! Server '$name' added to ~/.ssh/config.\e[0m"
    echo -e "🚀 You can now connect using: \e[1;36mssh $name\e[0m"
}

# SSH Menu and Copier
servers() {
    local config_file="$HOME/.ssh/config"

    if [[ ! -f "$config_file" ]]; then
        echo "❌ No servers found. The file $config_file does not exist."
        return 1
    fi

    local server_list
    server_list=$(awk '/^Host / { if ($2 != "" && $2 != "*") print $2 }' "$config_file")

    local result
    result=$(echo "$server_list" | fzf \
        --height=80% \
        --margin=10%,20% \
        --border="rounded" \
        --border-label=" 🌐 SSH Servers " \
        --border-label-pos="2" \
        --header=" ↵ Connect | Ctrl-Y Copy IP | Ctrl-P Copy Key " \
        --preview="awk -v target='{}' '\$1==\"Host\"{p=(\$2==target)} p{print}' ~/.ssh/config | batcat --color=always --language='ssh_config' --style=plain" \
        --preview-window="right:50%:border-left" \
        --expect=ctrl-y,ctrl-p)

    local key_pressed=$(echo "$result" | head -n1)
    local target_host=$(echo "$result" | tail -n+2)

    if [[ -z "$target_host" ]]; then
        return 0
    fi

    if [[ "$key_pressed" == "ctrl-y" ]]; then
        local ip=$(awk -v target="$target_host" '$1=="Host"{p=($2==target)} p && $1=="HostName"{print $2}' "$config_file")
        echo -n "$ip" | clip.exe
        echo -e "✅ \e[1;34m$target_host\e[0m IP (\e[1;32m$ip\e[0m) securely copied to clipboard!"
        return 0

    elif [[ "$key_pressed" == "ctrl-p" ]]; then
        local pem_file=$(awk -v target="$target_host" '$1=="Host"{p=($2==target)} p && $1=="IdentityFile"{print $2}' "$config_file")
        if [[ -f "$pem_file" ]]; then
            cat "$pem_file" | clip.exe
            echo -e "✅ \e[1;34m$target_host\e[0m Key (\e[1;32m$pem_file\e[0m) securely copied to clipboard!"
        else
            echo -e "❌ \e[1;31mError: Key file not found at $pem_file\e[0m"
        fi
        return 0
    fi

    echo "Connecting to $target_host..."
    ssh "$target_host"
}

# Bind Alt+s to open the servers menu
bind '"\es": "\C-e\C-uservers\n"'

# Update SSH Keys
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
        echo -e "\e[1A\e[K 🏷️  Server Name : \e[1;32m$server_name\e[0m"

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
    if ! command -v fzf &> /dev/null; then
        echo -e "\e[1;36m╭──────────────────────────────────────────────────────────╮\e[0m"
        echo -e "\e[1;36m│                🚀 DEVOPS SSH TOOLS HELP                  │\e[0m"
        echo -e "\e[1;36m╰──────────────────────────────────────────────────────────╯\e[0m"
        echo -e " \e[1;32m1. convert-ppk\e[0m   : Convert Windows .ppk to WSL .pem"
        echo -e " \e[1;32m2. add-server\e[0m    : Add a new server to ~/.ssh/config"
        echo -e " \e[1;32m3. servers\e[0m  : Interactive menu to connect to servers"
        echo -e " \e[1;32m4. update-key\e[0m    : Rotate keys for an existing server"
        echo -e "\e[1;36m────────────────────────────────────────────────────────────\e[0m"
        return 0
    fi

    local menu_options="🚀 servers : Connect to a server (Interactive)
➕ add-server      : Add a new server config
🔄 update-key      : Rotate keys for a server
🔑 convert-ppk     : Convert a single key
📖 help            : Read detailed command usage"

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

    [[ -z "$selection" ]] && return 0

    local cmd
    cmd=$(echo "$selection" | awk '{print $2}')

    if [[ "$cmd" == "help" ]]; then
        echo -e "\e[1;36m╭──────────────────────────────────────────────────────────╮\e[0m"
        echo -e "\e[1;36m│                    📖 DETAILED USAGE                     │\e[0m"
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

zen() {
    query="$*"
    "/mnt/c/Program Files/Zen Browser/zen.exe" "https://www.google.com/search?q=${query// /+}"
}
