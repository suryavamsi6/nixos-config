# nixos-config

This repository contains my NixOS configuration files.

## Post Installation

Make sure NixOS is already installed and Nix flakes are enabled.

1. **Clone the repository:**

    ```bash
    git clone https://github.com/suryavamsi6/nixos-config.git
    cd nixos-config
    ```

2. **Enable Nix Flakes:**

    Add the following lines to your `/etc/nixos/configuration.nix`:

    ```nix
    {
      nix.extraOptions = ''
        experimental-features = nix-command flakes
      '';
    }
    ```

3. **Backup existing configuration (optional):**

    It is recommended to backup your existing NixOS configuration files before applying the new ones.

    ```bash
    sudo cp -r /etc/nixos /etc/nixos-backup
    ```

4. **Copy configuration files:**

    Copy the configuration files except `hardware-configuration.nix` from this repository to the `/etc/nixos` directory:


    ```bash
    sudo cp -r * /etc/nixos/
    ```

5. **Rebuild the system:**

    Rebuild your NixOS system with the new configuration:

    ```bash
    sudo nixos-rebuild switch
    ```

6. **Reboot the system:**

    Reboot your system to apply the new configuration:

    ```bash
    sudo reboot
    ```



## Pre Installation

1. **Clone the repository:**

    ```bash
    git clone https://github.com/suryavamsi6/nixos-config.git
    cd nixos-config
    ```

2. **Install NixOS:**

    Follow the official NixOS installation guide using Btrfs: [NixOS Installation Guide](https://nixos.wiki/wiki/Btrfs)

    Another great guide which helped me with Btrfs setup: [NixOS Btrfs Github](https://gist.github.com/giuseppe998e/629774863b149521e2efa855f7042418)


3. **Copy configuration files:**

    After following the steps and creating the volumes, copy the configuration files from this repository to the `/etc/nixos` directory:

    Remember to edit the configuration.nix with your user name. 

    ```bash
    sudo cp -r * /etc/nixos/
    ```

4. **Rebuild the system:**

    Install NixOS with this configuration:

    ```bash
    sudo nixos-install --no-root-passwd
    ```

5. **Reboot the system:**

    Reboot your system to apply the new configuration:

    ```bash
    sudo reboot
    ```
