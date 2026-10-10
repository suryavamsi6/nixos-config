# ComfyUI image generation for the primary desktop (RTX 5080).
{ lib, ... }:
{
  options.flake.modules.homeManager.comfyui = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      let
        modelName = "flux1-schnell-fp8.safetensors";
        modelSha256 = "ead426278b49030e9da5df862994f25ce94ab2ee4df38b556ddddb3db093bf72";
        modelRevision = "130698a84046a0e44105507a65949f62226a81f7";
        modelUrl = "https://huggingface.co/Comfy-Org/flux1-schnell/resolve/${modelRevision}/${modelName}";

        installFluxSchnell = pkgs.writeShellApplication {
          name = "comfyui-install-flux-schnell";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.curl
          ];
          text = ''
            model_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/comfyui/models/checkpoints"
            model="$model_dir/${modelName}"
            partial="$model.part"
            mkdir -p "$model_dir"

            if [[ -f "$model" ]] && printf '%s  %s\n' '${modelSha256}' "$model" | sha256sum --check --status; then
              echo "FLUX.1 Schnell FP8 is already installed: $model"
              exit 0
            fi

            if [[ -e "$model" ]]; then
              echo "Existing model failed SHA-256 verification; replacing it." >&2
              rm -f "$model"
            fi

            echo "Downloading the 17.2 GB FLUX.1 Schnell FP8 checkpoint..."
            echo "This is a one-time download; ensure you have at least 18 GB free in your home filesystem."
            curl --fail --location --retry 3 --retry-all-errors --continue-at - \
              '${modelUrl}' --output "$partial"

            if ! printf '%s  %s\n' '${modelSha256}' "$partial" | sha256sum --check --status; then
              echo "Downloaded checkpoint failed SHA-256 verification; removing the partial file." >&2
              rm -f "$partial"
              exit 1
            fi

            mv "$partial" "$model"
            echo "Installed $model"
            echo "Restarting ComfyUI so it discovers the checkpoint..."
            systemctl --user restart comfyui.service
          '';
        };

        launchComfyUI = pkgs.writeShellApplication {
          name = "comfyui-launch";
          runtimeInputs = [
            pkgs.systemd
            pkgs.xdg-utils
          ];
          text = ''
            systemctl --user start comfyui.service
            ${pkgs.coreutils}/bin/sleep 2
            xdg-open http://127.0.0.1:8188
          '';
        };

        comfyUI = pkgs.writeShellApplication {
          name = "comfyui-python";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.git
            pkgs.python3
            pkgs.uv
          ];
          text = ''
            state_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/comfyui"
            repo="$state_dir/ComfyUI"
            venv="$state_dir/venv"
            mkdir -p "$state_dir"

            if [[ ! -d "$repo/.git" ]]; then
              rm -rf "$repo"
              git clone https://github.com/comfyanonymous/ComfyUI.git "$repo"
            fi

            if [[ ! -x "$venv/bin/python" ]]; then
              python -m venv "$venv"
            fi

            if [[ ! -f "$venv/.dependencies-installed" || "$repo/requirements.txt" -nt "$venv/.dependencies-installed" ]]; then
              "$venv/bin/python" -m pip install --upgrade pip
              "$venv/bin/python" -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
              "$venv/bin/python" -m pip install -r "$repo/requirements.txt"
              touch "$venv/.dependencies-installed"
            fi
            if [[ ! -f "$venv/.manager-installed" ]]; then
              "$venv/bin/python" -m pip install --upgrade --pre comfyui-manager
              touch "$venv/.manager-installed"
            fi
            export PATH="$venv/bin:$PATH"
            rm -f "$venv/bin/uv"
            if ! "$venv/bin/uv" --version >/dev/null 2>&1; then
              "$venv/bin/python" -m pip install --upgrade uv
            fi
            export LD_LIBRARY_PATH="/run/opengl-driver/lib:${pkgs.stdenv.cc.cc.lib}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            exec "$venv/bin/python" "$repo/main.py" "$@"
          '';
        };

        desktopItem = pkgs.makeDesktopItem {
          name = "comfyui-local";
          desktopName = "ComfyUI (Local Image Generation)";
          comment = "Generate images locally with FLUX.1 Schnell on the RTX 5080";
          exec = "${launchComfyUI}/bin/comfyui-launch";
          icon = "applications-graphics";
          terminal = false;
          categories = [
            "Graphics"
            "ArtificialIntelligence"
          ];
        };
      in
      {
        home.packages = [
          installFluxSchnell
          launchComfyUI
          comfyUI
          desktopItem
        ];

        # Write the unit directly so it exists for manual starts without being
        # linked into default.target. The desktop launcher starts it on demand.
        xdg.configFile."systemd/user/comfyui.service".text = ''
          [Unit]
          Description=ComfyUI with the official CUDA PyTorch wheels
          After=default.target

          [Service]
          Type=simple
          ExecStart=${comfyUI}/bin/comfyui-python --base-directory %h/.local/share/comfyui --listen 127.0.0.1 --port 8188 --enable-cors-header --enable-manager
          Restart=on-failure
          RestartSec=5
        '';
      };
  };
}
