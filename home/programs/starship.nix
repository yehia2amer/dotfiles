# Starship prompt — stable config, rarely edited
{ config, pkgs, ... }:
{
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    enableFishIntegration = true;
    enableNushellIntegration = true;

    settings = {
      character = {
        success_symbol = "[❯](bold green) ";
        error_symbol = "[✗](bold red) ";
      };

      directory = {
        truncation_length = 8;
        truncation_symbol = "…/";
        format = "\\[[$symbol($path)]($style)\\]";
      };

      cmd_duration = {
        min_time = 1;
        format = "\\[[⏱ $duration]($style)\\]";
        show_milliseconds = true;
      };

      git_branch.format = "\\[[$symbol$branch]($style)\\]";
      git_status.format = "([\\[$all_status$ahead_behind\\]]($style))";

      docker_context = {
        format = "\\[[$symbol$context]($style)\\]";
        disabled = false;
      };

      kubernetes = {
        format = "\\[[$symbol($context) - ($namespace)]($style)\\]";
        disabled = false;
      };

      memory_usage = {
        format = "\\[$symbol[$ram( | $swap)]($style)\\]";
        disabled = false;
        threshold = -1;
      };

      time = {
        format = "\\[[$time]($style)\\]";
        use_12hr = true;
        disabled = false;
      };

      username = {
        format = "\\[[$user]($style)\\]";
        disabled = false;
      };

      nix_shell = {
        format = "\\[[$symbol$state( \\($name\\))]($style)\\]";
        disabled = false;
      };

      battery = {
        full_symbol = " 󰂄 ";
        charging_symbol = " ⚡️ ";
        discharging_symbol = " 💀 ";
        display = [
          { threshold = 100; style = "#5EE78D"; }
          { threshold = 30; style = "red"; discharging_symbol = ""; }
        ];
      };

      shell = {
        fish_indicator = " ";
        nu_indicator = " nu _";
        powershell_indicator = " _";
        unknown_indicator = "mystery shell";
        style = "#07A7FF";
        disabled = false;
      };

      container.format = "[$symbol \\[$name\\]]($style) ";

      # Language formatters
      aws.format = "\\[[$symbol($profile)(\\($region\\))(\\[$duration\\])]($style)\\]";
      bun.format = "\\[[$symbol($version)]($style)\\]";
      c.format = "\\[[$symbol($version(-$name))]($style)\\]";
      cmake.format = "\\[[$symbol($version)]($style)\\]";
      golang.format = "\\[[$symbol($version)]($style)\\]";
      java.format = "\\[[$symbol($version)]($style)\\]";
      kotlin.format = "\\[[$symbol($version)]($style)\\]";
      lua.format = "\\[[$symbol($version)]($style)\\]";
      nodejs.format = "\\[[$symbol($version)]($style)\\]";
      python.format = "\\[[\${symbol}\${pyenv_prefix}(\${version})(\\($virtualenv\\))]($style)\\]";
      rust.format = "\\[[$symbol($version)]($style)\\]";
      swift.format = "\\[[$symbol($version)]($style)\\]";
      terraform.format = "\\[[$symbol$workspace]($style)\\]";
      helm.format = "\\[[$symbol($version)]($style)\\]";
      package.format = "\\[[$symbol$version]($style)\\]";
      pulumi.format = "\\[[$symbol$stack]($style)\\]";
      deno.format = "\\[[$symbol($version)]($style)\\]";
      dart.format = "\\[[$symbol($version)]($style)\\]";
      dotnet.format = "\\[[$symbol($version)(🎯 $tfm)]($style)\\]";
      gcloud.format = "\\[[$symbol$account(@$domain)(\\($region\\))]($style)\\]";
      ruby.format = "\\[[$symbol($version)]($style)\\]";
      scala.format = "\\[[$symbol($version)]($style)\\]";
      zig.format = "\\[[$symbol($version)]($style)\\]";
      solidity.format = "\\[[$symbol($version)]($style)\\]";
    };
  };
}
