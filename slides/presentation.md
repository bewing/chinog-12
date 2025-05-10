class: center, middle

<div class="my-header"><img src="assets/imc-logo.png" style="float: left; width:250px"></div>

.image-30[![placeholder](assets/ansible-puzzle-router.png)]
# Agnostic automation with Network Resource Modules
Brandon Ewing<br />
CHI-NOG 12, May 2025<br />
[www.github.com/bewing/chinog-12](https://www.github.com/bewing/chinog-12/)

???
* Thank the PC
* intro self

---
class: center
.image-70[![placeholder](assets/introvert.png)]

---
class: middle, inverse
<div class="my-header"><h1>Setup</h1></div>
<br />

.big[
* Brownfield Network

* No automated config management

* Multiple Vendors

* Desire to start partial config control

* Existing Ansible Infrastructure
]

---
class: middle, inverse
<div class="my-header"><h1>Inventory</h1></div>
.big[
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
]

---
<div class="my-header"><h1>Take One</h1></div>
<br />

.biggish[
```yaml
- hosts: all
  gather_facts: false
  tasks:
  - name: Set NTP servers
    ios_commands:
      commands:
      - configure terminal
      - ntp server 1.2.3.4
      - ntp server 4.3.2.1
```
]

--

.huge[.green[That works great!]]

```terminal
$ ansible-playbook playbooks/take-one/take-one.yml -i inventory.yml -l clab-chinog-iol

PLAY [all] *******************************************************************

TASK [Set NTP servers] *******************************************************
ok: [clab-chinog-iol]

PLAY RECAP *******************************************************************
clab-chinog-iol            : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

.huge[.red[but...]]

---
<div class="my-header"><h1>Take One</h1></div>
<br />
<br />

.big[.red[Problems]]

.big[* Change feedback?]

.biggish[
```terminal
          changed=0
```
]

--

* .big[What about removals?]

.biggish[
```yaml
ntp_servers:
- 4.3.2.1
- 9.8.7.6
```
]

---
<div class="my-header"><h1>Take Two</h1></div>
<br />
<br />
<br />

.big[
* Let's dig deeper
]

--

<br />
.big[
* Manually get config/parse (TextFSM)
* Determine lines to add/remove (Jinja2 filters)
* Push changes to device (Jinja2 template)
]

---
class: middle,inverse
<div class="my-header"><h1>Take Two</h1></div>
<br />

.biggish[
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
  - name: Set NTP servers
    vars:
      to_add: "{{ ntp_servers | difference(current_ntp_servers | map(attribute='Host')) }}"
      to_delete: "{{ current_ntp_servers | map(attribute='Host') | difference(ntp_servers) }}"
    ios_config:
      src: "templates/config/ntp.j2"
```
]

---
<div class="my-header"><h1>Take Two</h1></div>
<br />
<br />
<br />

```textfsm
# ntp.fsm
Value Required Host (\S+)

Start
  ^ntp server $Host -> Record
```
 <br />

 ```jinja2
{# ntp.j2 #}
{% for h in to_add %}
ntp server {{ h }}
{% endfor %}
{% for h in to_delete %}
no ntp server {{ h }}
{% endfor %}
 ```

---
<div class="my-header"><h1>Take Two</h1></div>
<br />

.huge[.green[That works great!]]

```terminal
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
<div class="my-header"><h1>Take Two</h1></div>
<br />

.big[.red[Problems]]

* .biggish[Different OSes]?

```terminal
TASK [Set NTP servers] ****************************************************************************
fatal: [clab-chinog-ceos]: FAILED! => {"changed": false, "msg": "Connection type
ansible.netcommon.httpapi is not valid for this module"}
ok: [clab-chinog-iol]

PLAY RECAP ****************************************************************************************
clab-chinog-ceos           : ok=2    changed=0    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0
clab-chinog-iol            : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

--
* Complex configurations?
  * Do you authenticate your NTP?
  * How complex did your templates just get?

---
class: inverse
<div class="my-header"><h1>Complexity</h1></div>
<br />

```jinja2
{% if change_route_maps %}
{%  for route_map in change_route_maps %}
no route-map {{ route_map }}
{%   for index,term in target_route_maps[route_map].items()|sort %}
route-map {{ route_map }} {{ term['action'] }} {{ index }}
{%    for cmd in term['cmds'] %}
   {{ cmd }}
{%    endfor %}
{%   endfor %}
{%  endfor %}
{% endif %}

```

```yaml
- name: Set route maps to change
  ansible.builtin.set_fact:
    change_route_maps: |-
      {%- set route_maps = {} %}
      {%- for route_map in current_route_maps.keys() | intersect(target_route_maps.keys()) %}
      {%-    set changes = [] %}
      {%-    for seq, current_details in current_route_maps[route_map].items() %}
      {%-       set target_details = target_route_maps[route_map].get(seq, None) %}
      {%-       if target_details is none %}
      {%-          set _ = changes.append("--route-map " ~ route_map ~ " permit " ~ seq) %}
      {%-          for cmd in current_details.cmds %}
      {%-             set _ = changes.append("--   " ~ cmd) %}
      {%-          endfor %}
      {%-          set _ = changes.append("--!") %}
      {%-       else %}
      {%-          for i in range(current_details.cmds | length) %}
      {%-             if current_details.cmds[i] != target_details.cmds[i] %}
      {%-                if i == 0 or current_details.cmds[i-1] == target_details.cmds[i-1] %}
      {%-                   set _ = changes.append("route-map " ~ route_map ~ " permit " ~ seq) %}
      {%-                endif %}
      {%-                set _ = changes.append("--   " ~ current_details.cmds[i]) %}
      {%-                set _ = changes.append("++   " ~ target_details.cmds[i]) %}
      {%-             endif %}
      {%-          endfor %}
      {%-          for i in range(current_details.cmds | length, target_details.cmds | length) %}
      {%-             set _ = changes.append("++   " ~ target_details.cmds[i]) %}
      {%-          endfor %}
      {%-       endif %}
      {%-    endfor %}
      {%-    for seq, target_d

```

---
<div class="my-header"><h1>Complexity</h1></div>
<br />
<br />
<br />

.big[.underline[.red[Ansible, Jinja, FSM, etc are Domain Specific Languages]]]

--

<br />
<br />
<br />

.big[.purple[Let's move the complexity into a .strong[programming language!]]]

---

.image-40[![placeholder](assets/python-logo-only.svg)]

---
class: inverse
<div class="my-header"><h1>Complexity</h1></div>
<br />
.big[
* Who's going to write all that code?!?!

  * Configuration modeling

  * CLI parsers

  * REST/RPC support?!?!
]
--
.big[
* .strong[AND] it all has to work within Ansible?
]

--

<br />
.big[.orange[Red Hat Ansible team already did it!]]

---
class: middle
<div class="my-header"><h1>Ansible Network Modules</h1></div>
.biggish[

* A set of vendor-specific Galaxy collections

* Written and supported by the Red Hat Ansible Network Team
  * with full documentation!

* Provide the networking framework

* Handles device fact collection (natively!) and config *section* management

]

---
<div class="my-header"><h1>Ansible Network Modules</h1></div>
<br />
<br />

```yaml
- hosts: all
  gather_facts: false
  tasks:
  - name: Configure NTP
    register: return_value
    cisco.ios.ios_ntp_global:
      state: replaced
      config:
        authenticate: true
        authentication_keys:
        - algorithm: md5
          id: 2
          key: supersecret
          encryption: 7
        servers:
        - server: 1.2.3.4
          version: 2
          prefer: true
          key: 2
        - server: 4.3.2.1
          version: 2
          key: 2
  - ansible.builtin.debug:
      var: return_value

```

---
<div class="my-header"><h1>Ansible Network Modules</h1></div>

```terminal
$ ansible-playbook playbooks/ios-ntp/ios-ntp.yml -i inventory.yml -l clab-chinog-iol

PLAY [all] *******************************************************************

TASK [Configure NTP] *********************************************************
changed: [clab-chinog-iol]

TASK [ansible.builtin.debug] *************************************************
ok: [clab-chinog-iol] =>
    return_value:
        after:
            authenticate: true
            authentication_keys:
            -   algorithm: md5
                encryption: 7
                id: 2
                key: VALUE_SPECIFIED_IN_NO_LOG_PARAMETER
            servers:
            -   key_id: 2
                prefer: true
                server: 1.2.3.4
                version: 2
            -   key_id: 2
                server: 4.3.2.1
                version: 2
        before: {}
        changed: true
        commands:
        - ntp authenticate
        - ntp authentication-key 2 md5 ******** 22
        - ntp server 1.2.3.4 key 2 prefer version 2
        - ntp server 4.3.2.1 key 2 version 2
        failed: false

PLAY RECAP *******************************************************************
clab-chinog-iol            : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

---
<div class="my-header"><h1>Ansible Network Modules</h1></div>
```terminal
$ ansible-playbook playbooks/ios-ntp/ios-ntp.yml -i inventory.yml -l clab-chinog-iol

PLAY [all] *******************************************************************

TASK [Configure NTP] *********************************************************
ok: [clab-chinog-iol]

TASK [ansible.builtin.debug] *************************************************
ok: [clab-chinog-iol] =>
    return_value:
        before:
            authenticate: true
            authentication_keys:
            -   algorithm: md5
                encryption: 7
                id: 2
                key: VALUE_SPECIFIED_IN_NO_LOG_PARAMETER
            servers:
            -   key_id: 2
                prefer: true
                server: 1.2.3.4
                version: 2
            -   key_id: 2
                server: 4.3.2.1
                version: 2
        changed: false
        commands: []
        failed: false

PLAY RECAP *******************************************************************
clab-chinog-iol            : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0

```

---
<div class="my-header"><h1>So what's actually going on</h1></div>
<br />
<br />

.biggish[
Ansible Network Modules contain:
* An *argspec* covering the model of the config (usually the **want** part)
* A *facts* module that handles populating the **have** argspec from the device
* A *config* module that can compare want/have and generate a list of commands
* For CLI devices, an *rm_templates* module that handles parsing and assists with configuration generation
]

---
<div class="my-header"><h1>argspec</h1></div>
<br />
<br />

Arguments passed to the module.

* the **state** directive

  * Controls module behavior

--
<br />

* **config** dictionary contains the model for this module

  * *similar* between OS/collections but NOT IDENTICAL

--

* **EXTREMELY** well-documented, with extensive examples

---
<div class="my-header"><h1>argspec</h1></div>
<br />
<br />

## states
* merged
* replaced
* overridden
* deleted
* gathered
* rendered

---
<div class="my-header"><h1>argspec</h1></div>
<br />
<br />
<h2>state: merged</h2>
.col-9[
* Usually the safest

* Will ADD your config to the existing config

* and keep what is already present

* Will merge down into individual ACL entries

* So if you have seq 10 20 30, and merge in 15 and 20

  * 15 is added
  * 20 is replaced
]
.col-3[
##  merged
### replaced
### overridden
### deleted
### gathered
### rendered
]

---
<div class="my-header"><h1>argspec</h1></div>
<br />
<br />

<h2>state: replaced</h2>
.col-9[Replace a subsection (usually) of the config section on the device
<br />

* Used to replace the configured subsection with the provided config

* Differs per module
 * NTP will behave like `overidden`
 * But ACL may only replace a single ACL

* Please read the docs and perform testing when using this in plays/roles
]
.col-3[
###  merged
## replaced
### overridden
### deleted
### gathered
### rendered
]

---
<div class="my-header"><h1>argspec</h1></div>
<br />
<br />

<h2>state: overridden</h2>
.col-9[
Override the entire section on the device

* In some cases, same behavior as `replaced` (NTP, etc)

* In others, may remove config! (ACL, prefix list, etc)

* As usual, test when possible
]
.col-3[
###  merged
### replaced
## overridden
### deleted
### gathered
### rendered
]

---
<div class="my-header"><h1>argspec</h1></div>
<br />
<br />

<h2>state: deleted</h2>

.col-9[
&nbsp;
]
.col-3[
###  merged
### replaced
### overridden
## deleted
### gathered
### rendered
]

---
class: inverse
<div class="my-header"><h1>argspec</h1></div>
<br />
<br />

<h2>state: deleted</h2>

.col-9[
<br />
<br />
.biggish[.red[REMOVES THE SECTION FROM THE DEVICES]]

<br />
.small[.orange[use with care]]
]
.col-3[
###  merged
### replaced
### overridden
## deleted
### gathered
### rendered
]

---

<div class="my-header"><h1>argspec</h1></div>
<br />
<br />

<h2>state: gathered</h2>

.col-8[
* Special state, only gathers **have**
  * returns as `gathered`

```terminal
$ ansible-playbook playbooks/gather/gather.yml -i inventory.yml -l clab-chinog-iol
TASK [Gather NTP config] *****************************************************
ok: [clab-chinog-iol]

TASK [ansible.builtin.debug] *************************************************
ok: [clab-chinog-iol] =>
    return_value:
        changed: false
        failed: false
        gathered:
            authenticate: true
            authentication_keys:
            -   algorithm: md5
                encryption: 7
                id: 2
                key: VALUE_SPECIFIED_IN_NO_LOG_PARAMETER
            servers:
            -   key_id: 2
                prefer: true
                server: 1.2.3.4
                version: 2
PLAY RECAP *******************************************************************
clab-chinog-iol: ok=2 changed=0 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0
```
]
.col-1[
&nbsp;
]
.col-3[
###  merged
### replaced
### overridden
### deleted
## gathered
### rendered
]

---
<div class="my-header"><h1>argspec</h1></div>
<br />
<br />

<h2>state: rendered</h2>

.col-8[
Inverts `gathered`, takes your `argspec.config`/.strong[want] and turns it into a configuration

**NB**: Does *NOT* connect to device / collect config

```terminal
    return_value:
        changed: false
        failed: false
        rendered:
        - ntp authenticate
        - ntp authentication-key 2 md5 ******** 7
        - ntp server 1.2.3.4 key 2 prefer version 2
        - ntp server 4.3.2.1 key 2 version 2
```
]
.col-1[
&nbsp;
]
.col-3[
###  merged
### replaced
### overridden
### deleted
### gathered
## rendered
]

---
<div class="my-header"><h1>argspec</h1></div>
<br />
<br />

.big[
* Well documented
* Examples for *EVERY* state in every module
* Similar, but not *identical* config specs between vendors
* Highly advise testing prior to deployment
]

--
.big[
* See playbooks/states in Github for an example with the IOS ACL module
]

---
<div class="my-header"><h1>facts</h1></div>
<br />
<br />

???
Stop and talk about how every module does fact collection internally

and also provides external ansible_facts

--

.big[.strong[gather_facts: false]]

---
<div class="my-header"><h1>facts</h1></div>
<br />
<br />

.big[.strong[gather_facts: .red[<s>false</s>]]]

<br />

.big[.strong[gather_facts: .green[it_depends]]]

---
<div class="my-header"><h1>facts</h1></div>
<br />
<br />

## Device fact modules

* You can call individual OS fact modules as tasks

```yaml
- hosts: all
  gather_facts: false
  tasks:
  - cisco.ios.ios_facts:
      gather_subset:
      - interfaces
      gather_network_resources:
      - ntp_global
  - ansible.builtin.debug:
      var: ansible_facts.keys()
  - ansible.builtin.debug:
      var: ansible_facts.network_resources.keys()
```

---
class: inverse
<div class="my-header"><h1>facts</h1></div>
<br />

```terminal
$ ansible-playbook playbooks/facts/facts.yml -i inventory.yml -l clab-chinog-iol

PLAY [all] *******************************************************************

TASK [cisco.ios.ios_facts] ***************************************************
ok: [clab-chinog-iol]

TASK [ansible.builtin.debug] *************************************************
ok: [clab-chinog-iol] =>
    ansible_facts.keys():
    - network_resources
    - net_gather_network_resources
    - net_gather_subset
    - net_system
    - net_image
    - net_version
    - net_hostname
    - net_api
    - net_python_version
    - net_iostype
    - net_operatingmode
    - net_serialnum
    - net_all_ipv4_addresses
    - net_all_ipv6_addresses
    - net_neighbors
    - net_interfaces

TASK [ansible.builtin.debug] *************************************************
ok: [clab-chinog-iol] =>
    ansible_facts.network_resources.keys():
    - ntp_global

PLAY RECAP *******************************************************************
clab-chinog-iol            : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

---
<div class="my-header"><h1>facts</h1></div>
<br />
<br />
<br />

.biggish[
* `gather_facts` is a play-level keyword
* so is `gather_subset`!
]

--

.biggish[
* `gather_network_resources` is not :(
]

.big[
```terminal
ERROR! 'gather_network_resources' is not a valid attribute for a Play
```
]

---
<div class="my-header"><h1>facts</h1></div>
<br />

**HOWEVER**

`gather_facts` at the play-level is just calling `ansible.builtin.gather_facts`

--

`module_defaults` to the rescue!

```yaml
- hosts: all
  module_defaults:
    ansible_builtin.gather_facts:
      gather_subset:
      - interfaces
      gather_network_resources:
      - ntp_global
  gather_facts: true
  tasks:
  - ansible.builtin.debug:
    var: ansible_facts
```

```terminal
TASK [ansible.builtin.debug] *************************************************
ok: [clab-chinog-iol] =>
    ansible_facts:
        net_all_ipv4_addresses:
        - 172.20.20.3
        net_all_ipv6_addresses:
        - 3FFF:172:20:20::3
```

---
class: inverse
<div class="my-header"><h1>.red[Problems]</h1></div>
<br />
<br />

* .biggish[Different OSes]?


```terminal
TASK [Set NTP servers] ****************************************************************************
fatal: [clab-chinog-ceos]: FAILED! => {"changed": false, "msg": "Connection type
ansible.netcommon.httpapi is not valid for this module"}
ok: [clab-chinog-iol]

PLAY RECAP ****************************************************************************************
clab-chinog-ceos           : ok=2    changed=0    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0
clab-chinog-iol            : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

---
<div class="my-header"><h1>Interoperability</h1></div>
<br />
<br />
<br />
<br />

```yaml
- hosts: all
  gather_facts: false
  tasks:
  - name: Configure NTP
    cisco.ios.ios_ntp_global:
      state: replaced
      config:
      ...
```

--

```yaml
- hosts: all
  gather_facts: false
  tasks:
  - name: Configure NTP
    ansible.netcommon.network_resource:
      name: ntp_global
      state: replaced
      config:
      ...

```

---
<div class="my-header"><h1>Interoperability</h1></div>
<br />
<br />

```terminal
$ ansible-playbook playbooks/agnostic-ntp/agnostic-ntp.yml -i inventory.yml

PLAY [all] *******************************************************************

TASK [Configure NTP] *********************************************************
changed: [clab-chinog-ceos]
ok: [clab-chinog-iol]

TASK [ansible.builtin.debug] *************************************************
ok: [clab-chinog-ceos] =>
    mod_out:
        after:
            authentication_keys:
            -   algorithm: md5
                encryption: 7
                id: 2
                key: VALUE_SPECIFIED_IN_NO_LOG_PARAMETER
            servers:
            -   key_id: 2
                prefer: true
                server: 1.2.3.4
                version: 2
            -   key_id: 2
                server: 4.3.2.1
                version: 2
        ansible_connection: ansible.netcommon.httpapi
        ansible_network_os: arista.eos.eos
<snip>
PLAY RECAP *******************************************************************
clab-chinog-ceos           : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
clab-chinog-iol            : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```
---
<div class="my-header"><h1>Interoperability</h1></div>
<br />
<br />

.huge[.green[That works great!]]
<br />
<br />

.huge[.red[but...]]

---
<div class="my-header"><h1>argspec</h1></div>
<br />
<br />
<br />
<br />
Arguments passed to the module.

* the **state** directive

  * Controls module behavior

* **config** dictionary contains the model for this module

  * .red[.strong[*similar* between OS/collections but NOT IDENTICAL]]

---
<div class="my-header"><h1>Interoperability</h1></div>
<br />
<br />

.strong[arista.eos.ntp_global]

.image-80[![placeholder](assets/arista-ntp-local-interface.png)]
<br />
<br />
.strong[cisco.ios.ntp_global]
.image-80[![placeholder](assets/cisco-ntp-source.png)]

---
<div class="my-header"><h1>Interoperability</h1></div>
<br />
<br />

.image-80[![placeholder](assets/jackie-chan-why.webp)]


---
<div class="my-header"><h1>Interoperability</h1></div>
<br />
<br />

.big[
```yaml
- name: Configure Cisco NTP
  when: ansible_network_os == "cisco.ios.ios"
  ansible.netcommon.network_resource:
    name: ntp_global
    config:
      local_interface: Loopback0
...
- name: Configure Arista NTP
  when: ansible_network_os == "arista.eos.eos"
  ansible.netcommon.network_resource:
    name: ntp_global
    config:
      source: Loopback0

```
]

---
<div class="my-header"><h1>Interoperability</h1></div>
<br />
<br />

.strong[HostVars]

.biggish[
```yaml
network:
  hosts:
    clab-chinog-ceos:
      ntp_config:
        local_interface: Ethernet1
        servers:
        - server: 1.2.3.4
          server: 4.3.2.1
```

```yaml
tasks:
- name: Push NTP config
  ansible.netcommon.network_resource
    name: ntp_global
    state: overridden
    config: "{{ ntp_config }}""

```
]

---
<div class="my-header"><h1>Interoperability</h1></div>
<br />
<br />

* Resource modules commit, but do not save!

* Define handlers in your plays to write startup-config if device has one

```yaml
handlers:
- name: Save IOS config
  listen: Save config
  when: not ansible_check_mode and ansible_network_os == "cisco.ios.ios"
  ansible.netcommon.cli_command:
     command: copy running-config startup-config
     prompt: Destination
     answer: '\r'

- name: Save EOS config
  listen: Save config
  when: not ansible_check_mode and ansible_network_os == "arista.eos.eos"
  arista.eos.eos_command: # cli_command doesn't support httpapi
    commands:
    - copy running-config startup-config

```

---
<div class="my-header"><h1>Demo</h1></div>
<br />
<br />
