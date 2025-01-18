#!/system/bin/sh
# Copyright 2023-2024, shadow3 (@shadow3aaa)
#
# This file is part of fas-rs.
#
# fas-rs is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
#
# fas-rs is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along
# with fas-rs. If not, see <https://www.gnu.org/licenses/>.

DIR=/sdcard/Android/fas-rs
CONF=$DIR/games.toml
soc_model=$(getprop ro.soc.model)
MERGE_FLAG=$DIR/.need_merge
LOCALE=$(getprop persist.sys.locale)
KERNEL_VERSION=$(uname -r | awk -F. '{
    if ($1 == 3) print "3.18";
    else if ($1 == 4) print "4.14"; 
    else if ($1 == 5 && ($2 <= 10)) print "5.10";
    else if ($1 == 5 && ($2 == 15)) print "5.15";
    else print "unsupported"
}')
WEBROOT_PATH="/data/adb/modules/cpufreq_clamping/webroot"
RECREAT_CPUFREQ_CLAMPING_CONF=1
CPUFREQ_CLAMPING_CONF="/data/cpufreq_clamping.conf"
DEFAULT_CPUFREQ_CLAMPING_CONF=$(cat <<EOF
interval_ms=40
boost_app_switch_ms=150
#cluster0
baseline_freq=1700
margin=300
boost_baseline_freq=2000
max_freq=9999
#cluster1
baseline_freq=1600
margin=300
boost_baseline_freq=2000
max_freq=9999
#cluster2
baseline_freq=1600
margin=300
boost_baseline_freq=2500
max_freq=9999
EOF
)

local_print() {
    if [ $LOCALE = zh-CN ]; then
        ui_print "$1"
    else
        ui_print "$2"
    fi
}

local_echo() {
    if [ $LOCALE = zh-CN ]; then
        echo "$1"
    else
        echo "$2"
    fi
}

creat_conf() {
    if [[ ! -f "$CPUFREQ_CLAMPING_CONF" ]]; then
        local_print "- 配置文件夹：/data/cpufreq_clamping.conf" "- Configuration folder: /data/cpufreq_clamping.conf"
        echo "$DEFAULT_CPUFREQ_CLAMPING_CONF" > "$CPUFREQ_CLAMPING_CONF"
    else
        local_print "- 配置文件夹：/data/cpufreq_clamping.conf" "- Configuration folder: /data/cpufreq_clamping.conf"
    fi
}

recreat_conf() {
    rm "$CPUFREQ_CLAMPING_CONF"
    echo "$DEFAULT_CPUFREQ_CLAMPING_CONF" > "$CPUFREQ_CLAMPING_CONF"
    if [[ -f "$CPUFREQ_CLAMPING_CONF" ]]; then
        local_print "- 配置文件夹：/data/cpufreq_clamping.conf" "- Configuration folder: /data/cpufreq_clamping.conf"
    else
        local_print "- 配置文件夹：/data/cpufreq_clamping.conf" "- Configuration folder: /data/cpufreq_clamping.conf"
    fi
}

# 音量键检测函数
key_check() {
    while true; do
        key_check=$(/system/bin/getevent -qlc 1 2>&1)
        if [ $? -ne 0 ]; then
            ui_print "getevent命令执行失败，请确保设备支持"
            return 1
        fi
        
        key_event=$(echo "$key_check" | awk '{ print $3 }' | grep 'KEY_')
        key_status=$(echo "$key_check" | awk '{ print $4 }')
        
        if [[ "$key_event" == *"KEY_VOLUMEUP"* && "$key_status" == "DOWN" ]]; then
            return 0
        elif [[ "$key_event" == *"KEY_VOLUMEDOWN"* && "$key_status" == "DOWN" ]]; then
            return 1
        fi
    done
}

if [ $ARCH != arm64 ]; then
    local_print "- 设备不支持, 非arm64设备！" "- Only for arm64 device!"
    abort
elif [ $API -le 30 ]; then
    local_print "- 系统版本过低, 需要安卓12及以上的系统版本版本！" "- Required A12+!"
    abort
fi

# 设置Zygisk环境变量
export ZYGISK_ENABLED=1
export ZYGISK_MODULE=$MODPATH/zygisk/fas-rs-u-c.so

# 加载Zygisk模块
/system/bin/app_process -Xzygote /system/bin --zygote --start-system-server &

if [ -f $CONF ]; then
    touch $MERGE_FLAG
else
    mkdir -p $DIR
    cp $MODPATH/games.toml $CONF
fi

cp -f $MODPATH/README_CN.md $DIR/doc_cn.md
cp -f $MODPATH/README_EN.md $DIR/doc_en.md

set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/fas-rs 0 0 0755

local_print "- 配置文件夹：/sdcard/Android/fas-rs" "Configuration folder: /sdcard/Android/fas-rs"
local_echo "updateJson=https://raw.githubusercontent.com/suiyuanlixin/fas-rs-usage-clamping/refs/heads/main/Update/update_zh.json" "updateJson=https://raw.githubusercontent.com/suiyuanlixin/fas-rs-usage-clamping/refs/heads/main/Update/update_en.json" >>$MODPATH/module.prop

resetprop fas-rs-installed true

# 内核版本兼容处理
if [ "$KERNEL_VERSION" = "unsupported" ]; then
    local_print "- 内核版本不支持，使用Zygisk模拟功能" "- Kernel version not supported, using Zygisk emulation"
    # 通过Zygisk实现类似功能
    export ZYGISK_EMULATE_CPUFREQ=1
    mkdir -p /data/adb/modules/fas-rs
else
    rmmod cpufreq_clamping 2>/dev/null
    insmod $MODPATH/kernelobject/$KERNEL_VERSION/cpufreq_clamping.ko 2>&1
    
    if [ $? -ne 0 ]; then
        local_print "- 载入 cpufreq_clamping.ko 失败，使用Zygisk模拟功能" "- Failed to load cpufreq_clamping.ko, using Zygisk emulation"
        export ZYGISK_EMULATE_CPUFREQ=1
        mkdir -p /data/adb/modules/fas-rs
    fi
fi

[[ $RECREAT_CPUFREQ_CLAMPING_CONF -eq 1 ]] && recreat_conf || creat_conf

if [ -f "$WEBROOT_PATH/index.html" ]; then
    rm -rf $WEBROOT_PATH/*
    cp -r $MODPATH/webroot/* $WEBROOT_PATH/
fi

sh $MODPATH/vtools/init_vtools.sh $(realpath $MODPATH/module.prop)
/data/powercfg.sh $(cat /data/cur_powermode.txt)

if [ -f "$MODPATH/prop_des" ]; then
    > "$MODPATH/prop_des"
fi

if [ -f "$MODPATH/tem_mod" ]; then
    > "$MODPATH/tem_mod"
fi

echo "description" > "$MODPATH/prop_des"

# 小核频率控制选项
ui_print "- 是否关闭fas对小核集群的频率控制？"
ui_print "- 音量+：是"
ui_print "- 音量-：否"
if key_check; then
    if [ "$soc_model" = "SM7675" -o "$soc_model" = "SM8550" ]; then
        sed -i '/log_info("\[extra_policy\] fas-rs load_fas, set extra_policy")/a\    log_info("\[extra_policy\] fas-rs load_fas, set ignore_policy")' "$MODPATH/extension/kalama_extra.lua"
        sed -i "s/set_extra_policy_rel(0, 3, -50000, 0)/set_ignore_policy(0, true)/" "$MODPATH/extension/kalama_extra.lua"
        sed -i '/log_info("\[extra_policy\] fas-rs unload_fas, remove extra_policy")/a\    log_info("\[extra_policy\] fas-rs unload_fas, remove ignore_policy")' "$MODPATH/extension/kalama_extra.lua"
        sed -i "s/remove_extra_policy(0)/set_ignore_policy(0, false)/" "$MODPATH/extension/kalama_extra.lua"
    elif [ "$soc_model" = "MT6886"* ]; then
        sed -i 's/log_info("\[extra_policy\] fas-rs load_fas, set extra_policy")/log_info("\[extra_policy\] fas-rs load_fas, set ignore_policy")/' "$MODPATH/extension/sun_extra.lua"
        sed -i "s/set_extra_policy_rel(0, 6, -150000, -100000)/set_ignore_policy(0, true)/" "$MODPATH/extension/sun_extra.lua"
        sed -i 's/log_info("\[extra_policy\] fas-rs unload_fas, remove extra_policy")/log_info("\[extra_policy\] fas-rs unload_fas, remove ignore_policy")/' "$MODPATH/extension/sun_extra.lua"
        sed -i "s/remove_extra_policy(0)/set_ignore_policy(0, false)/" "$MODPATH/extension/sun_extra.lua"
    else
        sed -i '/log_info("\[extra_policy\] fas-rs load_fas, set extra_policy")/a\    log_info("\[extra_policy\] fas-rs load_fas, set ignore_policy")' "$MODPATH/extension/taro_extra.lua"
        sed -i "s/set_extra_policy_rel(0, 4, -50000, 0)/set_ignore_policy(0, true)/" "$MODPATH/extension/taro_extra.lua"
        sed -i '/log_info("\[extra_policy\] fas-rs unload_fas, remove extra_policy")/a\    log_info("\[extra_policy\] fas-rs unload_fas, remove ignore_policy")' "$MODPATH/extension/taro_extra.lua"
        sed -i "s/remove_extra_policy(0)/set_ignore_policy(0, false)/" "$MODPATH/extension/taro_extra.lua"
    fi
fi

# 温控设置选项
ui_print "- 是否关闭或修改fas-rs核心温控？"
ui_print "- 音量+：是"
ui_print "- 音量-：否"
if key_check; then
    ui_print "- 请选择操作"
    ui_print "- 音量+：修改fas-rs核心温控"
    ui_print "- 音量-：关闭fas-rs核心温控"
    if key_check; then
        sed -i '/\[powersave\]/,/^\[/ s/core_temp_thresh = [^ ]*/core_temp_thresh = 75000/' "$CONF"
        sed -i '/\[balance\]/,/^\[/ s/core_temp_thresh = [^ ]*/core_temp_thresh = 85000/' "$CONF"
        sed -i '/\[performance\]/,/^\[/ s/core_temp_thresh = [^ ]*/core_temp_thresh = 95000/' "$CONF"
        sed -i '/\[fast\]/,/^\[/ s/core_temp_thresh = [^ ]*/core_temp_thresh = "disabled"/' "$CONF"
        echo "modify" > "$MODPATH/tem_mod"
    else
        sed -i 's/core_temp_thresh = [^ ]*/core_temp_thresh = "disabled"/g' "$CONF"
        echo "disable" > "$MODPATH/tem_mod"
    fi
fi
