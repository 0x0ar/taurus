#!/usr/bin/env bash

# bluez is already a required package; this step makes the adapter usable by
# enabling its system service when the user opts in during installation.

setup_bluetooth() {
    if [ "${OPT_BLUETOOTH:-true}" != true ]; then
        return 0
    fi

    local init_sys
    init_sys=$(detect_init_system)

    echo -e "\n\e[36m[ INFO ]\e[0m $(t "installer.deploy.configuring_bluetooth")"
    enable_system_service "bluetooth" "$init_sys"
    echo -e "  \e[32m$(t "installer.deploy.bluetooth_success")\e[0m"
}
