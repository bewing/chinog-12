class: center, middle

<div class="my-header"><img src="assets/imc-logo.png" style="float: left; width:250px"></div>

.image-40[![placeholder](assets/ansible-puzzle-router.png)]
# Agnostic automation with Network Resource Modules
Brandon Ewing<br />
CHI-NOG 12, May 2025<br />
[www.github.com/bewing/chinog-12](https://www.github.com/bewing/chinog-12/)

???
* Thank the PC
* intro self

---
class: middle
<div class="my-header"><h1>Setup</h1></div>
<br />

.big[
* Brownfield Network

* Multiple Vendors

* No automated config management
]

--

.big[
  * Manage the easy stuff
]

---
class: middle
<div class="my-header"><h1>Inventory</h1></div>
```yaml
network:
  vars:
    ansible_user: admin
    ansible_password: admin
  hosts:
    clab-chinog-ceos:
      ansible_network_os: arista.eos.eos
      ansible_connection: ansible.netcommon.httpapi
      ansible_httpapi_use_ssl: yes
      ansible_httpapi_validate_certs: no
    clab-chinog-iol:
      ansible_network_os: cisco.ios.ios
      ansible_connection: ansible.netcommon.network_cli
```

---
class: middle
<div class="my-header"><h1>The old way</h1></div>
<br />

* Manually get config
* Determine lines to add/remove
* Push changes to device


---
class: middle
<div class="my-header"><h1>First Try</h1></div>
<br />

```yaml
- hosts: all
  gather_facts: no
  vars:
    ntp_servers:
    - 1.2.3.4
    - 4.3.2.1
  tasks:
  - name: Parse NTP config
    ansible.utils.cli_parse:
      command: show running-config
      parser:
        name: ansible.utils.textfsm
        template_path: "templates/fsm/ntp.fsm"
      set_fact:
        current_ntp_servers
  - name: Debug
    ansible.builtin.debug:
      msg: "{{ current_ntp_servers | map(attribute='Host') }}"
  - name: Set NTP servers
    vars:
      to_add: "{{ ntp_servers | difference(current_ntp_servers | map(attribute='Host')) }}"
      to_delete: "{{ current_ntp_servers | map(attribute='Host') | difference(ntp_servers) }}"
    ios_config:
      src: "templates/config/ntp.j2"
```

---
<div class="my-header"><h1>First Try</h1></div>
<br />

.huge[.green[That works great!]]

```shell
$ ansible-playbook playbooks/getting-started/getting-started.yml -i inventory.yml --limit clab-chinog-iol
TASK [Set NTP servers] *************************************************************************************
[WARNING]: To ensure idempotency and correct diff the input configuration lines should be similar to how
they appear if present in the running configuration on device including the indentation
changed: [clab-chinog-iol]

PLAY RECAP ************************************************************************************************
clab-chinog-iol            : ok=3    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```


--

<br />
<br />

.huge[.red[but...]]

---
<div class="my-header"><h1>First Try</h1></div>
<br />

.big[.red[Problems]]

* .bigish[Different OSes]?

--

```shell
TASK [Set NTP servers] ****************************************************************************
fatal: [clab-chinog-ceos]: FAILED! => {"changed": false, "msg": "Connection type
ansible.netcommon.httpapi is not valid for this module"}
ok: [clab-chinog-iol]

PLAY RECAP ****************************************************************************************
clab-chinog-ceos           : ok=2    changed=0    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0
clab-chinog-iol            : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

* .bigish[Different NTP servers?]
  * If in EMEA, use 9.8.7.6

--

* .bigish[Complex configurations?]
  * Do you authenticate your NTP?
  * How complex did your templates just get?
