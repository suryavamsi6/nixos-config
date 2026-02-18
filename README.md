# NixOS-Config

This repository contains my NixOS and macOS (nix-darwin) configuration files.

---

## NixOS (Linux)

### Pre-Requisites

Make sure NixOS is already installed..

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

---

## macOS (nix-darwin) — MacBook M4 Air

### Pre-Requisites

1. **Install Nix:**

    ```bash
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
    ```

2. **Clone the repository:**

    ```bash
    git clone https://github.com/suryavamsi6/nixos-config.git
    cd nixos-config
    ```

3. **First-time bootstrap** (builds and installs nix-darwin):

    ```bash
    nix run nix-darwin -- switch --flake .#macbook-air
    ```

4. **Subsequent rebuilds:**

    ```bash
    darwin-rebuild switch --flake .#macbook-air
    ```

