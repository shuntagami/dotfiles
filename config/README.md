# Dotfiles Configuration

This directory contains configuration files that allow you to customize your dotfiles setup without modifying the core scripts.

## Configuration Files

### `dotfiles.conf`
Main configuration file containing:
- Repository URLs and installation paths
- macOS-specific settings (computer name, dock size)
- Network settings (VPN, WiFi networks)
- Package manager options
- Debug settings

### `paths.conf`
Common directory aliases used across zsh configurations:
- Development directories (`alias_d`, `alias_p`, `alias_g`)
- Application and system directories
- Language environment paths

## Customization

To customize your setup:

1. **Copy the configuration files** (optional, they work with defaults):
   ```bash
   cp config/dotfiles.conf config/dotfiles.local.conf
   cp config/paths.conf config/paths.local.conf
   ```

2. **Edit the local versions** with your specific settings:
   ```bash
   # Example customizations in dotfiles.local.conf
   MACOS_COMPUTER_NAME="Your-MacBook-Name"
   VPN_SERVICE_NAME="Your-VPN-Service"
   WIFI_NETWORK_HOME="Your-Home-WiFi"
   WIFI_NETWORK_OFFICE="Your-Office-WiFi"
   WSL_USER_NAME="your-windows-username"
   ```

3. **The scripts will automatically use local configurations** if they exist, falling back to defaults.

## Environment Variables

You can also override any setting using environment variables:
```bash
export MACOS_COMPUTER_NAME="Custom-Name"
export DEBUG=1  # Enable debug logging
```

## Security Note

- Never commit sensitive information (passwords, API keys) to these configuration files
- Use environment variables or external configuration for sensitive data
- The `*.local.conf` files are gitignored for your security