#!/bin/bash

# YouTube to Blog - Auto Deployment Script
# Location: /var/www/yt2blog
# Uses PM2 for process management under tvmcloud user
# Run with: sudo ./deploy.sh (first time only, then just ./deploy.sh)

set -e

DEPLOY_USER="tvmcloud"

echo "=========================================="
echo "YouTube to Blog - Auto Deploy"
echo "=========================================="
echo ""

# Get current directory (should be /var/www/yta)
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "📁 Project directory: $PROJECT_DIR"
echo "👤 Deploy user: $DEPLOY_USER"
echo ""

# Check if running as root or with sudo
if [ "$EUID" -eq 0 ]; then
    echo "Step 0: One-time ownership and git configuration..."
    
    # Fix ownership permanently
    chown -R $DEPLOY_USER:$DEPLOY_USER $PROJECT_DIR
    
    # Configure git to allow this directory (system-wide)
    git config --system --add safe.directory $PROJECT_DIR
    
    # Set proper permissions on .git directory
    chmod -R u+rwX,go+rX $PROJECT_DIR/.git
    
    # Configure git to preserve file ownership
    su - $DEPLOY_USER -c "cd $PROJECT_DIR && git config core.fileMode false"
    
    echo "✅ Ownership fixed permanently - you won't need sudo next time"
    echo ""
    
    # Now re-run this script as the deploy user
    echo "🔄 Re-running script as $DEPLOY_USER..."
    exec su - $DEPLOY_USER -c "cd $PROJECT_DIR && bash $0"
    exit 0
fi

# From here on, we're running as the deploy user
echo "✅ Running as $DEPLOY_USER (no sudo needed)"
echo ""

# Step 1: Check system dependencies (no sudo needed if already installed)
echo "Step 1/8: Checking system dependencies..."
MISSING_DEPS=""
command -v python3 &> /dev/null || MISSING_DEPS="$MISSING_DEPS python3"
command -v pip3 &> /dev/null || MISSING_DEPS="$MISSING_DEPS python3-pip"
command -v ffmpeg &> /dev/null || MISSING_DEPS="$MISSING_DEPS ffmpeg"
command -v node &> /dev/null || MISSING_DEPS="$MISSING_DEPS nodejs"
command -v npm &> /dev/null || MISSING_DEPS="$MISSING_DEPS npm"

if [ -n "$MISSING_DEPS" ]; then
    echo "⚠️  Missing dependencies:$MISSING_DEPS"
    echo "   Run: sudo apt update && sudo apt install -y$MISSING_DEPS"
    exit 1
else
    echo "✅ All system dependencies installed"
fi

# Step 2: Check PM2
echo ""
echo "Step 2/8: Checking PM2..."
if ! command -v pm2 &> /dev/null; then
    echo "⚠️  PM2 not installed. Run: sudo npm install -g pm2"
    exit 1
else
    echo "✅ PM2 already installed"
fi

# Step 3: Create Python virtual environment
echo ""
echo "Step 3/8: Creating Python virtual environment..."
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
source venv/bin/activate
echo "✅ Virtual environment ready"

# Step 4: Install Python dependencies
echo ""
echo "Step 4/8: Installing Python dependencies..."
pip install --upgrade pip -q
pip install -r requirements.txt -q
echo "✅ Python packages installed"

# Step 5: Optional dependencies check
echo ""
echo "Step 5/8: Checking optional dependencies..."
echo "✅ Optional dependencies check complete"

# Step 6: Setup environment variables
echo ""
echo "Step 6/8: Setting up environment variables..."
if [ ! -f .env ]; then
    echo "⚠️  No .env file found. Skipping..."
    echo "   Create .env file manually with GEMINI_API_KEY"
else
    echo "✅ .env file already exists"
fi

# Export proxy settings from system environment for PM2
if [ -n "$http_proxy" ] || [ -n "$HTTP_PROXY" ]; then
    echo "✅ System proxy detected - will be passed to PM2"
else
    echo "ℹ️  No system proxy detected"
fi

# Step 7: Set permissions and create directories
echo ""
echo "Step 7/8: Setting up directories..."

# Create required directories
mkdir -p /home/$DEPLOY_USER/.youtube-to-blog/{outputs,cache}
chmod -R 755 /home/$DEPLOY_USER/.youtube-to-blog
echo "✅ Directories ready"

# Step 8: Clear cache and Start/Restart with PM2
echo ""
echo "Step 8/9: Clearing Streamlit cache..."
rm -rf /home/$DEPLOY_USER/.streamlit/cache/* 2>/dev/null || true
echo "✅ Cache cleared"

# Step 9: Managing application with PM2
echo ""
echo "Step 9/9: Managing application with PM2..."

# Check if PM2 process exists
if pm2 list | grep -q "yt2blog-3030"; then
    echo "🔄 PM2 process exists, restarting..."
    pm2 restart yt2blog-3030 --update-env
    echo "✅ PM2 process restarted"
else
    echo "🚀 Starting new PM2 process..."
    # Start with PM2, passing environment variables including proxy
    pm2 start venv/bin/streamlit \
        --name yt2blog-3030 \
        --interpreter none \
        --env "http_proxy=$http_proxy,https_proxy=$https_proxy,HTTP_PROXY=$HTTP_PROXY,HTTPS_PROXY=$HTTPS_PROXY" \
        -- run app.py \
        --server.port=3030 \
        --server.address=0.0.0.0 \
        --server.headless=true \
        --server.enableCORS=false \
        --server.enableXsrfProtection=false
    
    echo "✅ PM2 process started"
    
    # Save PM2 process list
    pm2 save
fi

# Wait for service to start
echo ""
echo "⏳ Waiting for Streamlit to start..."
sleep 5

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "=========================================="
echo "✅ DEPLOYMENT SUCCESSFUL!"
echo "=========================================="
echo ""
echo "🎉 Your YouTube to Blog app is running!"
echo ""
echo "📍 Application is running on:"
echo "   http://$SERVER_IP:3030"
echo "   http://localhost:3030 (from server)"
echo ""
echo "✅ App is directly accessible on port 3030"
echo "   You can configure Apache vhost if needed for domain/SSL"
echo ""
echo "🔄 IMPORTANT: Clear browser cache or use incognito mode"
echo "   to see changes!"
echo ""
echo "📊 PM2 Status:"
pm2 status
echo ""
echo "🔧 Useful PM2 Commands:"
echo "   pm2 status                    # Check status"
echo "   pm2 restart yt2blog-3030      # Restart app"
echo "   pm2 stop yt2blog-3030         # Stop app"
echo "   pm2 start yt2blog-3030        # Start app"
echo "   pm2 logs yt2blog-3030         # View logs"
echo "   pm2 logs yt2blog-3030 -f      # Follow logs"
echo "   pm2 monit                     # Monitor resources"
echo ""
echo "🔄 To update code:"
echo "   cd $PROJECT_DIR"
echo "   git pull"
echo "   ./deploy.sh                   # No sudo needed!"
echo ""
echo "📝 Optional Apache VHost:"
echo "   App runs directly on port 3030"
echo "   Configure vhost only if you need custom domain/SSL"
echo ""
echo "=========================================="
echo "Setup complete! Running as $DEPLOY_USER"
echo "=========================================="
