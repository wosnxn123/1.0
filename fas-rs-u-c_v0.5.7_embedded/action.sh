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

MODDIR=${0%/*}
EXTENSIONS=/dev/fas_rs/extensions
DIR=/sdcard/Android/fas-rs
CONF=$DIR/games.toml
EXTENSION_NAME="fas_rs_extension_usage_clamping.lua"
EXTENSION_NAME2="fas_rs_extension_extra_policy.lua"
prop_des="$MODDIR/prop_des"
des_value=$(cat "$prop_des")
enable_value=$(cat "/sys/module/cpufreq_clamping/parameters/enable")
mod_value=$(cat "$MODDIR/tem_mod")

if [ "$mod_value" = "modify" ]; then
    sed -i '/\[powersave\]/,/^\[/ s/core_temp_thresh = [^ ]*/core_temp_thresh = 75000/' "$CONF"
    sed -i '/\[balance\]/,/^\[/ s/core_temp_thresh = [^ ]*/core_temp_thresh = 85000/' "$CONF"
    sed -i '/\[performance\]/,/^\[/ s/core_temp_thresh = [^ ]*/core_temp_thresh = 95000/' "$CONF"
    sed -i '/\[fast\]/,/^\[/ s/core_temp_thresh = [^ ]*/core_temp_thresh = "disabled"/' "$CONF"
elif [ "$mod_value" = "disable" ]; then
    sed -i 's/core_temp_thresh = [^ ]*/core_temp_thresh = "disabled"/g' "$CONF"
fi

if [ "$des_value" = "description" ]; then
    sed -i "/^description=/s/=.*$/=/" "$MODDIR/module.prop"
    if [ -f "$EXTENSIONS/$EXTENSION_NAME" ] && [ -f "$EXTENSIONS/$EXTENSION_NAME2" ]; then
        sed -i "/description=/s/$/[ Extensions loaded ] /" "$MODDIR/module.prop"
    elif [ -f "$EXTENSIONS/$EXTENSION_NAME" ] || [ -f "$EXTENSIONS/$EXTENSION_NAME2" ]; then
        sed -i "/description=/s/$/[ Extension loaded ] /" "$MODDIR/module.prop"
    else
        sed -i "/description=/s/$/[ Extension unloaded ] /" "$MODDIR/module.prop"
    fi
    if lsmod | grep -q "cpufreq_clamping"; then
        sed -i "/description=/s/$/[ Cpufreq_clamping loaded ] /" "$MODDIR/module.prop"
    else
        sed -i "/description=/s/$/[ Cpufreq_clamping unloaded ] /" "$MODDIR/module.prop"
    fi
    if [ "$enable_value" = "1" ]; then
        sed -i "/description=/s/$/[ Cpufreq_clamping enabled ] /" "$MODDIR/module.prop"
    else
        sed -i "/description=/s/$/[ Cpufreq_clamping disabled ] /" "$MODDIR/module.prop"
    fi
    if [ "$mod_value" = "modify" ]; then
        sed -i "/description=/s/$/[ Temperature control modified ] /" "$MODDIR/module.prop"
    elif [ "$mod_value" = "disable" ]; then
        sed -i "/description=/s/$/[ Temperature control disabled ] /" "$MODDIR/module.prop"
    fi
    > "$prop_des"
    echo "status" > "$prop_des"
elif [ "$des_value" = "status" ]; then
    sed -i "/^description=/s/=.*$/=/" "$MODDIR/module.prop"
    sed -i "/description=/s/$/Frame aware scheduling for android, work with cpufreq clamping. Requires 5.10 or 5.15 kernel and kernel ebpf support./" "$MODDIR/module.prop"
    > "$prop_des"
    echo "description" > "$prop_des"
fi
