#!/bin/bash

# Linux环境优化脚本
# 作者: xiaoping 
# 版本: 1.1

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行，请使用sudo执行"
        exit 1
    fi
}

# 检测系统类型
detect_os() {
    if [ -f /etc/redhat-release ]; then
        OS="centos"
        PKG_MANAGER="yum"
    elif [ -f /etc/debian_version ]; then
        OS="ubuntu"
        PKG_MANAGER="apt"
    else
        log_error "不支持的操作系统"
        exit 1
    fi
    log_info "检测到系统类型: $OS"
}

# 1. 更换国内镜像源
change_mirror() {
    log_info "开始更换国内镜像源..."
    
    # 备份原始源文件
    if [ "$OS" = "ubuntu" ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%Y%m%d)
        
        # 获取Ubuntu版本
        UBUNTU_VERSION=$(lsb_release -cs)
        
        cat > /etc/apt/sources.list << EOF
# 阿里云镜像源
deb http://mirrors.aliyun.com/ubuntu/ $UBUNTU_VERSION main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $UBUNTU_VERSION-security main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $UBUNTU_VERSION-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $UBUNTU_VERSION-backports main restricted universe multiverse
EOF
        
        apt update
        
    elif [ "$OS" = "centos" ]; then
        # 备份原始repo文件
        mkdir -p /etc/yum.repos.d/backup
        mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/backup/
        
        # 下载阿里云repo文件
        wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
        
        # 清理缓存并重新生成
        yum clean all
        yum makecache
    fi
    
    log_info "镜像源更换完成"
}

# 2. 配置Python等常用环境镜像源
setup_python_mirror() {
    log_info "开始配置Python镜像源..."
    
    # 创建pip配置目录
    mkdir -p ~/.pip
    
    # 配置pip镜像源
    cat > ~/.pip/pip.conf << EOF
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn
EOF
    
    # 配置conda镜像源（如果存在conda）
    if command -v conda &> /dev/null; then
        conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main/
        conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/free/
        conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge/
        conda config --set show_channel_urls yes
        log_info "Conda镜像源配置完成"
    fi
    
    # 配置npm镜像源（如果存在npm）
    if command -v npm &> /dev/null; then
        npm config set registry https://registry.npm.taobao.org
        log_info "NPM镜像源配置完成"
    fi
    
    log_info "Python环境镜像源配置完成"
}

# 3. 清理系统垃圾
clean_system() {
    log_info "开始清理系统垃圾..."
    
    if [ "$OS" = "ubuntu" ]; then
        # 清理apt缓存
        apt autoremove -y
        apt autoclean
        apt clean
        
        # 清理日志文件
        journalctl --vacuum-time=7d
        
    elif [ "$OS" = "centos" ]; then
        # 清理yum缓存
        yum clean all
        
        # 清理日志文件
        journalctl --vacuum-time=7d
        
        # 清理临时文件
        find /tmp -type f -atime +7 -delete 2>/dev/null
    fi
    
    # 清理通用垃圾文件
    find /var/log -name "*.log" -type f -size +100M -exec truncate -s 0 {} \;
    find /home -name ".cache" -type d -exec rm -rf {} + 2>/dev/null
    
    log_info "系统垃圾清理完成"
}

# 4. 修改SSH默认端口
change_ssh_port() {
    log_info "开始修改SSH端口..."
    
    echo -n "请输入新的SSH端口号 (建议1024-65535): "
    read NEW_PORT
    
    # 验证端口号
    if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -lt 1024 ] || [ "$NEW_PORT" -gt 65535 ]; then
        log_error "无效的端口号"
        return 1
    fi
    
    # 备份SSH配置文件
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d)
    
    # 修改SSH端口
    sed -i "s/#Port 22/Port $NEW_PORT/g" /etc/ssh/sshd_config
    sed -i "s/Port 22/Port $NEW_PORT/g" /etc/ssh/sshd_config
    
    # 重启SSH服务
    systemctl restart sshd
    
    log_info "SSH端口已修改为: $NEW_PORT"
    log_warn "请确保防火墙已开放端口 $NEW_PORT，否则可能无法连接"
    
    # 添加防火墙规则
    if command -v ufw &> /dev/null; then
        ufw allow $NEW_PORT
        log_info "已添加UFW防火墙规则"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=$NEW_PORT/tcp
        firewall-cmd --reload
        log_info "已添加firewalld防火墙规则"
    fi
}

# 5. 安装宝塔面板
install_bt_panel() {
    log_info "开始安装宝塔面板..."
    
    if [ "$OS" = "ubuntu" ]; then
        wget -O install.sh http://download.bt.cn/install/install-ubuntu_6.0.sh
    elif [ "$OS" = "centos" ]; then
        wget -O install.sh http://download.bt.cn/install/install_6.0.sh
    fi
    
    if [ -f install.sh ]; then
        bash install.sh
        rm -f install.sh
        log_info "宝塔面板安装完成"
        log_info "请访问 http://你的服务器IP:8888 进行初始化配置"
    else
        log_error "宝塔面板安装脚本下载失败"
    fi
}

# 6. 一键关闭防火墙
disable_firewall() {
    log_info "开始关闭防火墙..."
    
    log_warn "警告：关闭防火墙会降低系统安全性，请确认是否继续？"
    echo -n "输入 'yes' 确认关闭防火墙: "
    read CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        log_info "操作已取消"
        return 0
    fi
    
    # 检测并关闭不同的防火墙服务
    if command -v ufw &> /dev/null; then
        # Ubuntu UFW防火墙
        log_info "检测到UFW防火墙，正在关闭..."
        ufw --force disable
        systemctl stop ufw
        systemctl disable ufw
        log_info "UFW防火墙已关闭并禁用开机启动"
        
    elif command -v firewall-cmd &> /dev/null; then
        # CentOS/RHEL firewalld防火墙
        log_info "检测到firewalld防火墙，正在关闭..."
        systemctl stop firewalld
        systemctl disable firewalld
        log_info "firewalld防火墙已关闭并禁用开机启动"
        
    elif command -v iptables &> /dev/null; then
        # iptables防火墙
        log_info "检测到iptables防火墙，正在清空规则..."
        iptables -F
        iptables -X
        iptables -t nat -F
        iptables -t nat -X
        iptables -t mangle -F
        iptables -t mangle -X
        iptables -P INPUT ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT ACCEPT
        
        # 保存iptables规则（如果有iptables-save命令）
        if command -v iptables-save &> /dev/null; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
        
        log_info "iptables防火墙规则已清空"
    else
        log_warn "未检测到常见的防火墙服务"
    fi
    
    # 检查SELinux状态（如果存在）
    if command -v getenforce &> /dev/null; then
        SELINUX_STATUS=$(getenforce)
        if [ "$SELINUX_STATUS" != "Disabled" ]; then
            log_info "检测到SELinux状态: $SELINUX_STATUS"
            echo -n "是否同时关闭SELinux？(yes/no): "
            read SELINUX_CONFIRM
            
            if [ "$SELINUX_CONFIRM" = "yes" ]; then
                setenforce 0
                sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
                sed -i 's/SELINUX=permissive/SELINUX=disabled/g' /etc/selinux/config
                log_info "SELinux已设置为disabled，重启后生效"
            fi
        fi
    fi
    
    log_info "防火墙关闭操作完成"
    log_warn "请注意：防火墙已关闭，系统安全性降低，建议仅在测试环境使用"
}

# 显示菜单
show_menu() {
    clear
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}    Linux 环境优化脚本 v1.1    ${NC}"
    echo -e "${BLUE}================================${NC}"
    echo
    echo "请选择要执行的操作:"
    echo
    echo "1. 更换国内镜像源"
    echo "2. 配置Python等环境镜像源"
    echo "3. 清理系统垃圾"
    echo "4. 修改SSH默认端口"
    echo "5. 安装宝塔面板"
    echo "6. 一键关闭防火墙"
    echo "7. 执行全部优化 (1-5)"
    echo "0. 退出脚本"
    echo
    echo -n "请输入选项 [0-7]: "
}

# 执行全部优化
run_all() {
    log_info "开始执行全部优化..."
    change_mirror
    setup_python_mirror
    clean_system
    change_ssh_port
    install_bt_panel
    log_info "全部优化完成！"
}

# 主函数
main() {
    check_root
    detect_os
    
    while true; do
        show_menu
        read choice
        
        case $choice in
            1)
                change_mirror
                ;;
            2)
                setup_python_mirror
                ;;
            3)
                clean_system
                ;;
            4)
                change_ssh_port
                ;;
            5)
                install_bt_panel
                ;;
            6)
                disable_firewall
                ;;
            7)
                run_all
                ;;
            0)
                log_info "退出脚本"
                exit 0
                ;;
            *)
                log_error "无效选项，请重新选择"
                ;;
        esac
        
        echo
        echo "按任意键继续..."
        read -n 1
    done
}

# 脚本入口
main "$@"
