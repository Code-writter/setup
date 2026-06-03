
## The Tmux SSH Split Plugin

There is a specific community plugin designed to solve this exact problem. It looks at your active pane, checks if ssh is running, and if so, runs the exact same ssh command in the new split.

Add this to the ##### ───────── PLUGINS ───────── section of your ~/.tmux.conf:
Code snippet

```bash
set -g @plugin 'pschmitt/tmux-ssh-split'
```

# Configure the plugin to use your existing split keys
```
set-option -g @ssh-split-h-key "|"
set-option -g @ssh-split-v-key "-"
```

After adding this, remember to press Prefix + I (capital i) to install the plugin, and Prefix + r to reload. Now, pressing `Prefix + |` while SSH into a server will automatically open a new pane and start the SSH connection to the same server.

## Enable SSH Multiplexing (Crucial for Speed)

When the plugin opens that new pane, SSH will normally try to perform the whole handshake and authentication process again, which takes time.

You can bypass this by enabling SSH Multiplexing in your WSL ~/.ssh/config file. This tells SSH to use the first connection as a master tunnel. Any subsequent panes that connect to the same server will piggyback on that tunnel and connect instantly (in milliseconds) without asking for keys or passwords.

Open (or create) your ~/.ssh/config file in WSL and add these lines at the very top:
Code snippet
```bash
Host *
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%r@%h-%p
    ControlPersist 10m
```

(Note: You will need to create that sockets directory once by running mkdir -p ~/.ssh/sockets in your terminal).

With these two setups combined, when you hit your split key, Tmux will instantly duplicate your SSH session into the new pane with zero lag.
