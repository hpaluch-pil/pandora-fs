# Automated Pandora FMS setup

Automated Pandora FMS setup for Rocky Linux 8.

This script basically autoamtes tasks from: https://pandorafms.com/manual/!current/en/documentation/pandorafms/technical_annexes/31_pfms_install_latest_rocky_linux


Requirements:
- Rocky Linux 8

Setup:
- runs as regular user with sudo privileges:

```shell
./setup_pandora_fms.sh
```


WARNING!
- unlike official guide we use random passwords for MySQL root user and MySQL pandora user
- after setup is run you can find MySQL passwords under `~/.config/pandorafs/secrets/mysql_root_pwd.txt`
  and `~/.config/pandorafs/secrets/mysql_pandora_pwd.txt`


Resources:
- https://pandorafms.com/manual/!current/en/documentation/pandorafms/technical_annexes/31_pfms_install_latest_rocky_linux

