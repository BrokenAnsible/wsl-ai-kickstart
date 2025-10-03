#!/bin/bash

# WSL Debian 13 AI Setup Script
# Run this after fresh WSL Debian installation
# Upgrades to Debian 13 (Trixie) and installs CUDA + UV + SDKMan for AI workflows
# Create a template post install to save bandwidth for internet limits.

set -e  # Exit on any error

echo "=== WSL Debian 13 AI Setup Script ==="
echo "This script will:"
echo "1. Configure default WSL user"
echo "2. Update system packages"
echo "3. Install CUDA 12.6 toolkit"
echo "4. Install UV (ultra-fast Python package manager)"
echo "5. Install SDKMAN (Java/JVM manager)"
echo "6. Configure WSL for optimal AI workflows"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

echo ""
echo "=== Step 1: Configure Default WSL User ==="
read -p "Enter your preferred Linux username (lowercase, no spaces): " WSL_USERNAME

# Check if user exists, create if not
if ! id "$WSL_USERNAME" &>/dev/null; then
    echo "Creating user: $WSL_USERNAME"
    useradd -m -s /bin/bash "$WSL_USERNAME"
    usermod -aG sudo "$WSL_USERNAME"
    echo "Please set password for $WSL_USERNAME:"
    passwd "$WSL_USERNAME"
else
    echo "User $WSL_USERNAME already exists"
fi

# Configure default user in wsl.conf
cat > /etc/wsl.conf << EOF
[user]
default=$WSL_USERNAME

[boot]
systemd=true

[automount]
enabled=true
root=/mnt/
options="metadata,umask=22,fmask=11"

[network]
generateHosts=true
generateResolvConf=true

[interop]
enabled=false
appendWindowsPath=false
EOF

echo "Default user configured: $WSL_USERNAME"
echo "WSL will use this user by default after restart"

echo ""
echo "=== Configure User Home Directory Startup ==="
# Ensure user starts in their home directory
echo 'cd ~' >> /home/$WSL_USERNAME/.bashrc
echo "Configured $WSL_USERNAME to start in home directory"

echo ""
echo "=== Step 2: System Update and Install Essential Tools ==="
apt update && apt upgrade -y

# Install curl first since we need it for other installations
if ! command -v curl &> /dev/null; then
    echo "Installing curl..."
    apt install -y curl
fi

# Install zip first since we need it for other installations
if ! command -v zip &> /dev/null; then
    echo "Installing zip..."
    apt install -y zip
fi

# Install unzip first since we need it for other installations
if ! command -v unzip &> /dev/null; then
    echo "Installing unzip..."
    apt install -y unzip
fi

echo ""
echo "=== Step 3: Install CUDA Repository ==="
# Check if CUDA keyring already installed
if ! dpkg -l | grep -q cuda-keyring; then
    echo "Installing CUDA keyring..."
    # Download and install NVIDIA CUDA keyring
    curl -L -o cuda-keyring_1.1-1_all.deb https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb
    dpkg -i cuda-keyring_1.1-1_all.deb
    rm cuda-keyring_1.1-1_all.deb
    
    apt update
else
    echo "CUDA keyring already installed"
fi

echo ""
echo "=== Step 3: Install CUDA Toolkit 12.6 ==="
# Check if CUDA toolkit already installed
if ! command -v nvcc &> /dev/null; then
    echo "Installing CUDA toolkit..."
    apt install -y \
        cuda-toolkit-12-6 \
        libcu++-dev \
        cuda-compiler-12-6 \
        cuda-libraries-dev-12-6 \
        cuda-driver-dev-12-6 \
        cuda-cudart-dev-12-6
else
    echo "CUDA toolkit already installed: $(nvcc --version | grep release)"
fi

echo ""
echo "=== Step 3: Configure CUDA Environment ==="
# Add CUDA to PATH permanently
USER_BASHRC="/home/$WSL_USERNAME/.bashrc"
if ! grep -q "/usr/local/cuda-12.6/bin" "$USER_BASHRC"; then
    echo "Configuring CUDA environment for user $WSL_USERNAME..."
    echo 'export PATH=/usr/local/cuda-12.6/bin:$PATH' >> "$USER_BASHRC"
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:$LD_LIBRARY_PATH' >> "$USER_BASHRC"
    # Also add to system-wide bashrc for good measure
    echo 'export PATH=/usr/local/cuda-12.6/bin:$PATH' >> /etc/bash.bashrc
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:$LD_LIBRARY_PATH' >> /etc/bash.bashrc
else
    echo "CUDA environment already configured"
fi

# Create convenient symlink if it doesn't exist
if [ ! -L /usr/local/cuda ]; then
    ln -sf /usr/local/cuda-12.6 /usr/local/cuda
fi

echo ""
echo "=== Step 3: Install Additional Development Tools ==="
apt install -y \
    python3-dev \
    build-essential \
    git \
    ca-certificates \
    gnupg \
    lsb-release

echo ""
echo "=== Step 4: Install UV (Python Package Manager) ==="
# Check if UV already installed
if ! command -v uv &> /dev/null; then
    # Install UV - ultra-fast Python package manager
    # UV Installation - run as user
    echo "Installing UV for user $WSL_USERNAME..."
    su - "$WSL_USERNAME" -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'

     # Add UV to user's PATH
    if ! grep -q "/.cargo/bin" /etc/bash.bashrc; then
        echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> /home/$WSL_USERNAME/.bashrc
    fi

    # Test UV installation
    if command -v uv &> /dev/null; then
        echo "UV successfully installed: $(uv --version)"
    else
        echo "Warning: UV installation may have failed"
    fi
else
    echo "UV already installed: $(uv --version)"
fi

echo ""
echo "=== Step 5: Install SDKMAN (Java/JVM Manager) ==="
# Check if SDKMAN already installed
if [ ! -d "/home/$WSL_USERNAME/.sdkman" ]; then
    echo "Installing SDKMAN for user: $WSL_USERNAME..."
    # Install SDKMAN for the configured user
    su - "$WSL_USERNAME" -c 'curl -s "https://get.sdkman.io" | bash' || true
    echo "SDKMAN installed for user: $WSL_USERNAME"
else
    echo "SDKMAN already installed for user: $WSL_USERNAME"
fi
echo "After restart, use: sdk list java, sdk install java 21.0.2-tem, etc."

echo ""
echo "=== Step 6: Add User to CUDA/Graphics Groups ==="
# Check if user already in video group
if ! groups "$WSL_USERNAME" | grep -q video; then
    echo "Adding $WSL_USERNAME to video group..."
    usermod -aG video "$WSL_USERNAME"
else
    echo "$WSL_USERNAME already in video group"
fi

# Check if user already in render group (if it exists)
if getent group render > /dev/null 2>&1; then
    if ! groups "$WSL_USERNAME" | grep -q render; then
        echo "Adding $WSL_USERNAME to render group..."
        usermod -aG render "$WSL_USERNAME"
    else
        echo "$WSL_USERNAME already in render group"
    fi
else
    echo "Render group does not exist (this is normal)"
fi

echo "GPU access groups configured for $WSL_USERNAME"

echo ""
echo "=== Step 7: Final Cleanup ==="
apt autoremove -y
apt autoclean

echo ""
echo "=== Installation Complete! ==="
echo ""
echo "Installed components:"
echo "- Update System - Debian 13 (Trixie) supported"
echo "- CUDA Toolkit 12.6"
echo "- UV (ultra-fast Python package manager)"
echo "- SDKMAN (Java/JVM manager)"
echo "- Development tools"
echo "- Default user: $WSL_USERNAME"
echo ""
echo "IMPORTANT: You must restart WSL for user settings to take effect!"
echo ""
echo "Next steps:"
echo "1. Exit WSL: exit"
echo "2. Restart WSL: wsl --shutdown && wsl -d YourDistroName"
echo "3. Log in as $WSL_USERNAME and test installations:"
echo "   - nvcc --version"
echo "   - nvidia-smi" 
echo "   - uv --version"
echo "   - sdk version (SDKMAN)"
echo ""
echo "Ready to export as AI template!"
echo "Perfect for Hugging Face models, LLaMA, and local AI development!"
echo ""
echo "=== Setup Complete ==="
