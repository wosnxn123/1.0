#!/bin/bash

# 获取系统信息
get_system_info() {
    echo "+----------------------------+"
    echo "|      系统信息概览          |"
    echo "+----------------------------+"
    echo "| 操作系统: $(lsb_release -d | cut -f2)   |"
    echo "| 内核版本: $(uname -r)        |"
    echo "| 系统架构: $(uname -m)           |"
    echo "| 总内存: $(free -h | grep Mem | awk '{print $2}')                |"
    echo "| 已用内存: $(free -h | grep Mem | awk '{print $3}')             |"
    echo "| 可用内存: $(free -h | grep Mem | awk '{print $7}')              |"
    echo "| CPU 信息: $(lscpu | grep 'Model name' | awk -F: '{print $2}') |"
    echo "| 磁盘使用: $(df -h / | grep / | awk '{print $5}')               |"
    echo "| IP 地址: $(hostname -I | awk '{print $1}')                     |"
    echo "+----------------------------+"
}

# 检查 supervisord 是否安装
check_supervisord_installed() {
    if command -v supervisord &> /dev/null; then
        echo "| 已安装: 是                 |"
        return 0
    else
        echo "| 已安装: 否                 |"
        return 1
    fi
}

# 检查 supervisord 状态
check_supervisord_status() {
    if systemctl is-active --quiet supervisord; then
        echo "| 正在运行: 是               |"
    else
        echo "| 正在运行: 否               |"
    fi
    echo "+----------------------------+"
}

# 显示菜单
show_menu() {
    clear
    get_system_info
    echo "|   supervisord 状态         |"
    echo "+----------------------------+"
    check_supervisord_installed
    check_supervisord_status
    echo ""
    echo "请选择一个选项:"
    echo "1) 安装 supervisord"
    echo "2) 删除 supervisord"
    echo "3) 检查 supervisord 状态"
    echo "4) 重启 supervisord"
    echo "5) 退出"
}

# 安装 supervisord 并配置 systemctl 替代
install_supervisord() {
    echo "正在安装 supervisord..."
    sudo apt update
    sudo apt install -y supervisor

    echo "创建配置文件目录..."
    sudo mkdir -p /etc/supervisor/conf.d

    echo "生成默认配置文件..."
    echo_supervisord_conf | sudo tee /etc/supervisor/supervisord.conf

    echo "添加 include 配置..."
    sudo sed -i '/\[include\]/a files = /etc/supervisor/conf.d/*.conf' /etc/supervisor/supervisord.conf

    echo "创建 supervisord 服务文件..."
    sudo tee /etc/systemd/system/supervisord.service > /dev/null <<EOL
[Unit]
Description=Supervisor process control system
Documentation=http://supervisord.org
After=network.target

[Service]
ExecStart=/usr/bin/supervisord -c /etc/supervisor/supervisord.conf
ExecStop=/usr/bin/supervisorctl shutdown
ExecReload=/usr/bin/supervisorctl reload
KillMode=process
Restart=on-failure
RestartSec=42s

[Install]
WantedBy=multi-user.target
EOL

    echo "重新加载 systemd 配置..."
    sudo systemctl daemon-reload

    echo "启用并启动 supervisord 服务..."
    sudo systemctl enable supervisord
    sudo systemctl start supervisord

    echo "创建自定义 systemctl 脚本..."
    sudo tee /usr/local/bin/systemctl > /dev/null <<EOL
#!/bin/bash

case "\$1" in
    start)
        sudo supervisorctl start \$2
        ;;
    stop)
        sudo supervisorctl stop \$2
        ;;
    restart)
        sudo supervisorctl restart \$2
        ;;
    status)
        sudo supervisorctl status \$2
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status} <service>"
        exit 1
        ;;
esac
EOL

    echo "赋予自定义 systemctl 脚本执行权限..."
    sudo chmod +x /usr/local/bin/systemctl

    echo "安装和配置完成。"
}

# 删除 supervisord 和自定义 systemctl 脚本
remove_supervisord() {
    echo "正在删除 supervisord..."
    sudo systemctl stop supervisord
    sudo systemctl disable supervisord
    sudo rm /etc/systemd/system/supervisord.service
    sudo systemctl daemon-reload
    sudo apt remove -y supervisor
    sudo rm -rf /etc/supervisor
    sudo rm /usr/local/bin/systemctl
    echo "删除完成。"
}

# 检查 supervisord 状态
check_status() {
    echo "检查 supervisord 状态..."
    sudo supervisorctl status
}

# 重启 supervisord
restart_supervisord() {
    echo "重启 supervisord..."
    sudo systemctl restart supervisord
    echo "重启完成。"
}

# 主程序
while true; do
    show_menu
    read -p "输入选项 [1-5]: " choice
    case $choice in
        1)
            install_supervisord
            ;;
        2)
            remove_supervisord
            ;;
        3)
            check_status
            ;;
        4)
            restart_supervisord
            ;;
        5)
            echo "退出程序。"
            exit 0
            ;;
        *)
            echo "无效选项，请重新输入。"
            ;;
    esac
    read -p "按任意键返回菜单..."
done
