#!/system/bin/sh

# 获取内核版本
KERNEL_VERSION=$(uname -r | cut -d. -f1-2)

# 检查内核版本
if [ $(echo "$KERNEL_VERSION < 5.10" | bc) -eq 1 ]; then
    # 5.10以下内核的特殊处理
    echo "Detected kernel version $KERNEL_VERSION (< 5.10)"
    
    # 检查并加载cpufreq_clamping模块
    if ! lsmod | grep -q cpufreq_clamping; then
        # 根据内核版本选择正确的模块
        if [ -f "/system/lib/modules/5.4/cpufreq_clamping.ko" ]; then
            insmod /system/lib/modules/5.4/cpufreq_clamping.ko
        elif [ -f "/system/lib/modules/5.9/cpufreq_clamping.ko" ]; then
            insmod /system/lib/modules/5.9/cpufreq_clamping.ko
        else
            echo "No compatible cpufreq_clamping module found"
            exit 1
        fi
    fi
fi

# 加载Zygisk模块
export ZYGISK_ENABLED=1
export ZYGISK_MODULE=/system/lib64/zygisk/fas-rs-u-c.so

# 启动模块
/system/bin/app_process -Djava.class.path=/system/framework/zygisk.jar &