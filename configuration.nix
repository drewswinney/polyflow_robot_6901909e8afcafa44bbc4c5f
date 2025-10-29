{ config, pkgs, lib, webrtcPkg, pyEnv, webrtcEnv, ... }:

let
  user      = "admin";
  password  = "password";
  hostname  = "6901909e8afcafa44bbc4c5f";
  homeDir   = "/home/${user}";

  py  = pkgs.python3;   # pinned to 3.12 by flake overlay

  rosPkgs = pkgs.rosPackages.humble;
  ros2pkg = rosPkgs.ros2pkg;
  ros2cli = rosPkgs.ros2cli;
  ros2launch = rosPkgs.ros2launch;
  launch = rosPkgs.launch;
  launch-ros = rosPkgs.launch-ros;
  rclpy = rosPkgs.rclpy;
  ament-index-python = rosPkgs.ament-index-python;
  rosidl-parser = rosPkgs.rosidl-parser;
  rosidl-runtime-py = rosPkgs.rosidl-runtime-py;
  composition-interfaces = rosPkgs.composition-interfaces;
  osrf-pycommon = rosPkgs.osrf-pycommon;
  yaml = pkgs.python3Packages."pyyaml";
  empy = pkgs.python3Packages."empy";
  catkin-pkg = pkgs.python3Packages."catkin-pkg";

  webrtcLauncher = pkgs.writeShellApplication {
    name = "webrtc-launch";
    runtimeInputs = [
      ros2cli
      ros2launch
      launch
      launch-ros
      rclpy
      ament-index-python
      rosidl-parser
      rosidl-runtime-py
      composition-interfaces
      osrf-pycommon
      pyEnv
      webrtcEnv   # your poetry2nix env (websockets, pyyaml, etc.)
      webrtcPkg   # your ROS package
    ];
    text = ''
      set -eo pipefail

      # Guard PATH/PYTHONPATH before enabling nounset; systemd often runs with them unset.
      PATH="''${PATH-}"
      PYTHONPATH="''${PYTHONPATH-}"
      AMENT_PREFIX_PATH="''${AMENT_PREFIX_PATH-}"

      set -u
      shopt -s nullglob

      # If you want extra safety, you can still source local setups here,
      # but writeShellApplication already puts runtimeInputs on PATH/PYTHONPATH.

      # choose python (poetry env preferred)
      PYBIN="${webrtcEnv}/bin/python3"; [ -x "$PYBIN" ] || PYBIN="$(command -v python3)"

      # helper: add all python*/site-packages under a prefix
      add_sitepkgs() {
        local P="$1"

        # If the prefix doesn't exist or has no lib directory, log and exit quietly
        if [ ! -d "$P/lib" ]; then
          echo "[WARN] No 'lib' directory under: $P" >&2
          return 0
        fi

        local found=0
        for d in "$P"/lib/python*/site-packages; do
          if [ -d "$d" ]; then
            echo "[INFO] Adding site-packages: $d" >&2
            PYTHONPATH="$d''${PYTHONPATH:+:}''${PYTHONPATH}"
            found=1
          else
            echo "[DEBUG] Skipped missing: $d" >&2
          fi
        done

        if [ $found -eq 0 ]; then
          echo "[WARN] No site-packages found under $P/lib" >&2
        fi
      }

      add_prefix() {
        local P="$1"

        if [ -d "$P/share/ament_index/resource_index/packages" ]; then
          echo "[INFO] Adding ament prefix: $P" >&2
          AMENT_PREFIX_PATH="$P''${AMENT_PREFIX_PATH:+:}''${AMENT_PREFIX_PATH}"
        fi
      }

      # add ROS packages first
      add_sitepkgs "${ros2pkg}"
      add_sitepkgs "${ros2cli}"
      add_sitepkgs "${ros2launch}"
      add_sitepkgs "${launch}"
      add_sitepkgs "${launch-ros}"
      add_sitepkgs "${rclpy}"
      add_sitepkgs "${ament-index-python}"
      add_sitepkgs "${rosidl-runtime-py}"
      add_sitepkgs "${rosidl-parser}"
      add_sitepkgs "${composition-interfaces}"
      add_sitepkgs "${osrf-pycommon}"
      add_sitepkgs "${yaml}"
      add_sitepkgs "${webrtcPkg}"

      # then add your poetry env (websockets, pyyaml, etc.)
      add_sitepkgs "${webrtcEnv}"
      export PYTHONPATH
      add_prefix "${ros2pkg}"
      add_prefix "${ros2cli}"
      add_prefix "${ros2launch}"
      add_prefix "${launch}"
      add_prefix "${launch-ros}"
      add_prefix "${rclpy}"
      add_prefix "${ament-index-python}"
      add_prefix "${rosidl-runtime-py}"
      add_prefix "${rosidl-parser}"
      add_prefix "${composition-interfaces}"
      add_prefix "${osrf-pycommon}"
      add_prefix "${webrtcPkg}"
      export AMENT_PREFIX_PATH

      exec ros2 launch webrtc webrtc.launch.py
    '';
  };
in
{
  ##############################################################################
  # Hardware / boot
  ##############################################################################
  nixpkgs.overlays = [
    (final: super: {
      makeModulesClosure = x:
        super.makeModulesClosure (x // { allowMissing = true; });
    })
  ];

  imports = [
    "${builtins.fetchGit {
      url = "https://github.com/NixOS/nixos-hardware.git";
      rev = "26ed7a0d4b8741fe1ef1ee6fa64453ca056ce113";
    }}/raspberry-pi/4"
  ];

  boot = {
    # Default kernel is fine; swap if you need rpi4-specific later.
    initrd.availableKernelModules = [ "xhci_pci" "usbhid" "usb_storage" ];
    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
    options = [ "noatime" ];
  };

  ##############################################################################
  # System basics
  ##############################################################################
  system.autoUpgrade.flags = [ "--max-jobs" "1" "--cores" "1" ];

  networking = {
    hostName = hostname;
    networkmanager.enable = true;
    nftables.enable = true;
  };

  services.openssh.enable = true;
  services.timesyncd.enable = true;
  services.timesyncd.servers = [ "pool.ntp.org" ];
  systemd.additionalUpstreamSystemUnits = [ "systemd-time-wait-sync.service" ];
  systemd.services.systemd-time-wait-sync.wantedBy = [ "multi-user.target" ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  hardware.enableRedistributableFirmware = true;
  system.stateVersion = "23.11";

  # Optional: keep a copy of this file on the device
  environment.etc."nixos/configuration.nix" = {
    source = ./configuration.nix;
    mode = "0644";
  };

  ##############################################################################
  # Users
  ##############################################################################
  users.mutableUsers = false;
  users.users.${user} = {
    isNormalUser = true;
    password = password;
    extraGroups = [ "wheel" ];
    home = homeDir;
  };
  security.sudo.wheelNeedsPassword = false;

  ##############################################################################
  # Packages
  ##############################################################################
  environment.systemPackages =
    (with pkgs; [ git python3 ]) ++
    (with rosPkgs; [ ros2cli ros2launch ros2pkg launch launch-ros ament-index-python ros-base ]) ++
    [ webrtcPkg pyEnv ];

  ##############################################################################
  # Services
  ##############################################################################
  systemd.services.polyflow-webrtc = {
    description = "Run Polyflow WebRTC launch with ros2 launch";
    wantedBy = [ "multi-user.target" ];
    after    = [ "network-online.target" ];
    wants    = [ "network-online.target" ];

    environment = {
      ROS_DOMAIN_ID = "0";
      LANG = "en_US.UTF-8";
      LC_ALL = "en_US.UTF-8";
    };

    serviceConfig = {
      User             = user;
      Group            = "users";
      WorkingDirectory = homeDir;
      StateDirectory   = "polyflow";
      StandardOutput   = "journal";
      StandardError    = "journal";
      Restart          = "always";
      RestartSec       = "3s";
      ExecStart        = "${webrtcLauncher}/bin/webrtc-launch";
    };
  };
}
